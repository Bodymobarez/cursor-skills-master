---
name: surge-dynamic-pricing
description: >-
  Staff-level fare & dynamic pricing for ride-hailing: the fare model (base + per-km +
  per-min + fees + tolls), zone/time surge multiplier from the supply/demand ratio, upfront
  vs metered pricing, fairness caps & transparency, fare estimate→final reconciliation,
  idempotent fare capture, and the money ledger (defers to payments-master). Real TypeScript
  + SQL with minor-unit money and integer math.
---

# Surge & Dynamic Pricing — Money in Integers, Quotes That Hold, Surge That's Fair

**Fares are money: compute in integer minor units, quote a price that holds, capture it idempotently, and make surge explainable — or you get rounding bugs, double charges, and a regulator's attention.** Two principal rules sit above everything: **(1) money is never a float** (fils/cents as `bigint`), and **(2) an upfront quote is a promise** — once the rider accepts, you honor it barring a material route change. Surge is just a multiplier derived from the supply/demand ratio per zone-time — powerful, abusable, and the thing riders hate most, so cap it and show it.

---

## 1. Mandate

- **Integer minor units, everywhere.** Fares, fees, surge are computed and stored as `bigint` minor units; never floats.
- **Upfront quote is binding.** Quote → rider accepts → that's the fare (recompute only on material route change, transparently).
- **Surge = demand/supply, capped and shown.** Derive the multiplier from the DSR per zone-time, cap it, round it, and tell the rider *why*.
- **Capture idempotently; the ledger is the truth.** Fare capture is keyed by trip + attempt; money movement defers to `payments-master` and its double-entry ledger.

## 2. When to use / when NOT

**Use when:** building fare estimation, the surge engine, upfront-vs-metered logic, fare reconciliation, or the trip→money handoff. Consumes the supply/demand heatmap from `realtime-matching-dispatch` and distance/duration from `routing-navigation-eta`; hands the captured fare to `payments-master`.

**Skip / go elsewhere when:** actual charge/capture/payout *mechanics*, PSPs, wallets, 3DS, refunds → `payments-master` (this skill computes *what* to charge; that one *moves* the money). Driver↔rider matching → `realtime-matching-dispatch`.

## 3. Mental model — quote → lock → ride → reconcile → capture

```
estimate (distance+duration from routing) × surge(zone,time)
   ─▶ QUOTE {amount, surge, expires_at}  ─▶ rider accepts  ─▶ LOCK quote on the trip
   ─▶ ride happens (actual distance/duration/wait/tolls)
   ─▶ RECONCILE: upfront → honor quote (route-change delta only) ; metered → compute from actuals
   ─▶ idempotent CAPTURE → payments-master ledger (fare split: platform fee, driver earnings, tax)
```

## 4. The fare model (integer math)

```ts
// All amounts are minor units (fils for AED, cents). NEVER float money.
type Minor = bigint;
interface FareConfig {
  baseFare: Minor;       // flag-down
  perKm: Minor;          // per km
  perMin: Minor;         // per minute (moving + sometimes waiting)
  minFare: Minor;        // floor
  bookingFee: Minor;     // platform/service fee
  cancellationFee: Minor;
}

interface RideActuals { distanceM: number; durationS: number; waitS: number; tollsMinor: Minor; }

function computeFare(cfg: FareConfig, a: RideActuals, surge: number): Minor {
  const km = a.distanceM / 1000;
  const min = a.durationS / 60;
  // Round each component to integer minor units; surge applies to the variable + base, not fees/tolls.
  const distance = BigInt(Math.round(Number(cfg.perKm) * km));
  const time     = BigInt(Math.round(Number(cfg.perMin) * min));
  const surged   = applySurge(cfg.baseFare + distance + time, surge);   // see §5 for capping/rounding
  const subtotal = bigMax(surged, cfg.minFare);
  return subtotal + cfg.bookingFee + a.tollsMinor;                       // tolls (Salik/Darb) pass-through
}

function applySurge(amount: Minor, mult: number): Minor {
  return BigInt(Math.round(Number(amount) * mult));   // multiply in number-space ONCE, round back to int
}
const bigMax = (a: Minor, b: Minor) => (a > b ? a : b);
```

**Why integers:** floating fares accumulate rounding error and produce off-by-a-fil disputes at scale. Compute components, round each to minor units, sum as `bigint`. Surge multiplies base+distance+time; **fees and tolls are not surged** (and never surge taxes).

## 5. Surge from supply/demand (zone × time)

```ts
// DSR (demand/supply ratio) per H3 zone from the dispatch heatmap (realtime-matching-dispatch §8).
// Map DSR → a capped, smoothed, rider-friendly multiplier.
function surgeMultiplier(dsr: number, cfg: { cap: number; step: number }): number {
  if (!isFinite(dsr) || dsr <= 1) return 1.0;                 // supply ≥ demand → no surge
  const raw = 1 + (dsr - 1) * 0.8;                            // gentle slope, not linear panic
  const capped = Math.min(raw, cfg.cap);                      // hard cap (e.g., 3.0) — fairness + regulation
  return Math.round(capped / cfg.step) * cfg.step;            // round to clean steps (1.0,1.2,1.5,2.0...)
}
```

```sql
-- Persist active surge per zone with a short validity so quotes reference a stable value.
CREATE TABLE surge_zones (
  city_id    int  NOT NULL,
  h3_cell    text NOT NULL,
  multiplier numeric(4,2) NOT NULL,
  dsr        numeric(6,2) NOT NULL,
  valid_from timestamptz NOT NULL DEFAULT now(),
  valid_to   timestamptz NOT NULL,
  PRIMARY KEY (city_id, h3_cell, valid_from)
);
CREATE INDEX surge_active ON surge_zones (city_id, h3_cell) WHERE valid_to > now();
```

**Smooth and cap on purpose:** raw DSR spikes (one cell, three requests, zero drivers → DSR=∞) must not produce 9× surge. Slope gently, hard-cap (regulators in several MENA markets cap or scrutinize multipliers), round to clean steps so riders see "1.5×" not "1.473×".

## 6. DECISION MATRIX — upfront vs metered

| Model | Rider sees | Risk holder | Best for | Notes |
|-------|-----------|-------------|----------|-------|
| **Upfront** ⭐ | exact price before booking | platform (eats route variance) | most ride-hailing (Uber/Careem) | quote binds; recompute only on material change |
| **Metered** | meter ticks; final at dropoff | rider (pays actuals) | regulated taxis, airport, some MENA cities | transparent, but no certainty |
| **Hybrid (upfront + cap)** | price with "won't exceed" cap | shared | new markets, volatile traffic | upfront feel with a safety ceiling |

**Verdict:** upfront is the modern default (certainty wins riders) — but it means **you** absorb the difference when traffic makes the trip longer than estimated, so your ETA/distance prediction quality (`routing-navigation-eta`) directly drives margin. Use metered where regulation requires it (some taxi integrations). Many MENA markets mix both by product.

## 7. Quote → reconcile (the binding promise)

```ts
interface Quote { tripId: string; amount: Minor; surge: number; estDistanceM: number; estDurationS: number; expiresAt: number; }

// Reconcile the locked upfront quote against reality. Honor it unless route MATERIALLY changed.
function reconcileUpfront(quote: Quote, actual: RideActuals, cfg: FareConfig): { final: Minor; adjusted: boolean; reason?: string } {
  const distDeltaPct = Math.abs(actual.distanceM - quote.estDistanceM) / Math.max(1, quote.estDistanceM);
  const materialChange = distDeltaPct > 0.20;                 // e.g., rider changed destination / big detour
  if (!materialChange) return { final: quote.amount, adjusted: false };  // promise held
  const recomputed = computeFare(cfg, actual, quote.surge);   // re-quote at the SAME surge (don't re-surge)
  return { final: recomputed, adjusted: true, reason: "route_changed" };
}
```

The discipline: **don't silently re-surge or re-rate** because traffic was bad — that's the platform's risk in upfront pricing. Only adjust for rider-caused material changes (destination edit, added stop), and **tell the rider why**. Quotes carry `expiresAt`; an expired quote re-quotes *before* acceptance, never after.

## 8. Idempotent fare capture (defers to payments-master)

```ts
// The fare is computed here; the MONEY MOVES in payments-master. Capture is idempotent.
async function captureFare(tripId: string, finalAmount: Minor, currency: string) {
  const idemKey = `fare:${tripId}`;                            // one capture per trip, ever
  return db.tx(async (t) => {
    const exists = await t.oneOrNone(`SELECT 1 FROM fare_captures WHERE trip_id=$1`, [tripId]);
    if (exists) return;                                         // already captured → no double charge
    await t.none(
      `INSERT INTO fare_captures (trip_id, amount, currency, captured_at) VALUES ($1,$2,$3,now())`,
      [tripId, finalAmount, currency]);
    // Hand to payments-master: charge rider (card/wallet) OR record COD; split fee/earnings/tax in the ledger.
    await payments.capture({ idemKey, tripId, amount: finalAmount, currency, method: await methodFor(tripId) });
    await bus.publish("fare.captured", { tripId, amount: finalAmount.toString(), currency });
  });
}
```

The **ledger note**: this skill produces a single authoritative `final` amount and the split intent (platform commission, driver earnings, VAT). The double-entry ledger, payout, COD reconciliation, refunds, and PSP/3DS mechanics all live in **`payments-master`** — do not reimplement money movement here.

## 9. Edge cases & gotchas

- **Float money** → rounding disputes at scale. `bigint` minor units, round per component.
- **Surge changed between quote and accept** → honor the *quoted* surge once accepted; re-quote only if the quote expired (§7).
- **Infinite/▲ DSR** (zero supply) → cap + smooth; never surface raw spikes (§5).
- **Rider edits destination mid-trip** → material change → transparent re-quote at the same surge.
- **Trip cancelled after match** → cancellation fee per policy (free-cancel window, then `cancellationFee`); idempotent.
- **Wait time at pickup** → bill per policy after a grace period; don't punish for the driver being early.
- **Tolls (Salik/Darb)** → pass-through, not surged, itemized on the receipt.
- **Currency & rounding rules** differ (AED fils to 2dp; some currencies round to nearest 5/25) — encode per-currency rounding.
- **Promo/discount + surge** → define order of operations (surge then discount, floor at minFare) and make it deterministic + auditable.

## 10. Performance & scale

- **Surge precomputed per zone** on a short cadence (the dispatch heatmap job), cached in Redis keyed by H3 cell; quotes read the cached multiplier, never recompute DSR per request.
- **Quotes are cheap** (read config + cached surge + a routing estimate) — cache the routing estimate per OD for the quote's lifetime.
- **Capture is low-QPS, high-value** — it lives in Postgres with the idempotency guard; the hot path (quotes) stays in cache.
- **Shard by city** like everything else; surge is inherently local.

## 11. Security & abuse

- **Quote tampering** → sign quotes server-side (HMAC over {tripId, amount, surge, expiresAt}); the client can display but never set the price. Verify on accept.
- **Surge gaming by drivers** (mass logoff to spike DSR, then return) → detect coordinated supply manipulation; smoothing + caps blunt the payoff.
- **Promo abuse** → one-time/per-user caps, server-side validation, fraud checks (`payments-master`).
- **Money PII & audit** → fare changes are append-only and audited; never mutate a captured fare (issue an adjustment/refund instead).
- **Regulatory caps** → encode market-specific surge ceilings and price transparency requirements as config, not code.

## 12. Testing

- **Golden fares:** fixed (distance, duration, surge) → exact expected minor-unit fare; guards rounding.
- **Idempotency:** call `captureFare` twice → one charge. Property test: no trip ever double-captures.
- **Quote-holds test:** traffic worse than estimate (no rider change) → final == quote (platform eats it).
- **Surge math:** DSR sweep including ∞ → multiplier stays ≤ cap, on clean steps.
- **Currency rounding:** per-currency fixtures (AED, EGP, PKR) round correctly.
- **Reconciliation:** destination-change → transparent adjusted fare at same surge.

## 13. Observability

- **Surge:** active multiplier distribution per city, % trips surged, max multiplier hit, DSR vs multiplier correlation.
- **Quote quality:** estimate-vs-actual distance/duration error (drives upfront margin) — ties to `routing-navigation-eta` ETA error.
- **Margin:** upfront variance absorbed (quoted − actual cost), per city/product.
- **Money integrity:** capture success rate, double-capture attempts blocked (should be the idempotency guard firing), adjustment/refund rate, COD reconciliation diffs (with `payments-master`).
- **Fairness:** rider price complaints vs surge level; cap-hit frequency.

## 14. Accessibility & i18n / RTL (MENA)

- **Surge transparency in Arabic:** show "1.5× أسعار مرتفعة" with a plain-language reason; never hide surge — trust is fragile and regulators care.
- **COD is huge in MENA:** the fare model must produce a clean cash amount (rounded to payable denominations) and hand COD reconciliation to `payments-master`.
- **Currency formatting & numerals:** AED/SAR/EGP/PKR with correct symbol placement, Arabic numerals option, RTL receipts.
- **Ramadan/holiday pricing:** demand curves and any promotional pricing differ; encode locale-aware surge baselines (not US curves).
- **Regulatory caps by market** (e.g., surge ceilings) → per-city config.

## 15. Anti-patterns

- **Float money** → rounding bugs, disputes. Integer minor units.
- **Re-surging/re-rating an accepted upfront quote because of traffic** → broken promise, churn, regulatory risk. Platform eats variance.
- **Uncapped/unsmoothed surge** → 9× spikes, outrage, bans. Cap + smooth + clean steps.
- **Client-set or unsigned prices** → tampering. Sign quotes server-side.
- **Reimplementing money movement here** → diverges from the ledger. Defer to `payments-master`.
- **Non-idempotent capture** → double charges on retry. Key by trip.
- **Hidden surge / no reason** → trust collapse. Always show multiplier + why.
- **Surging fees/tolls/taxes** → incorrect + non-compliant. Surge only base+distance+time.

## 16. Agent checklist

```
- [ ] All money in integer minor units (bigint); per-component rounding; per-currency rules
- [ ] Fare = base + perKm + perMin (+ minFare floor) ×surge, + bookingFee + tolls (fees/tolls NOT surged)
- [ ] Surge = capped, smoothed, step-rounded function of DSR per H3 zone; cached, short validity
- [ ] Upfront quote binds on accept; reconcile only material rider-caused changes at same surge
- [ ] Quotes signed (HMAC) + expiresAt; re-quote before accept on expiry, never after
- [ ] Idempotent fare capture (key=trip); hand money movement + split to payments-master
- [ ] Edge cases: cancellation fee, wait grace, tolls pass-through, promo×surge order, COD cash rounding
- [ ] Surge precomputed/cached; capture in Postgres; shard by city
- [ ] Anti-abuse: signed quotes, supply-manipulation detection, regulatory surge caps as config
- [ ] Transparency: show multiplier + reason (Arabic/English); never hide surge
- [ ] Tests: golden fares, idempotency, quote-holds, surge sweep incl ∞, currency rounding
- [ ] Metrics: % surged, estimate-vs-actual error, absorbed variance, double-capture blocks, COD diffs
```

## 17. References (verify current — 2026)

- H3 spatial zones for surge: https://h3geo.org/docs
- Money handling (minor units, never float): https://martinfowler.com/eaaCatalog/money.html
- VAT/e-invoicing (UAE/KSA) affecting fare tax lines: https://zatca.gov.sa · https://tax.gov.ae
- Idempotency keys for charges (pattern): https://stripe.com/docs/api/idempotent_requests
- Salik (Dubai toll): https://www.salik.ae · Darb (Abu Dhabi): https://darb.itc.gov.ae

## 18. Related

`realtime-matching-dispatch` (supply/demand DSR heatmap → surge), `routing-navigation-eta` (distance/duration → fare; ETA error → upfront margin), `ride-hailing-architecture` (trip carries fare_quote/surge_mult) · cross-master: `payments-master` (charge/capture/payout, double-entry ledger, COD reconciliation, refunds — money MOVES there), `business-master` (VAT/ZATCA e-invoicing of fares), `marketplace-master/marketplace-payments-payouts` (split-payment sibling)
