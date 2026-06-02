---
name: realtime-matching-dispatch
description: >-
  Staff-level driver↔rider matching & dispatch: H3 ring candidate search, ranking by
  ETA + acceptance-probability + rating (not nearest), batched vs greedy assignment,
  offer/accept with timeout + re-offer, atomic double-accept prevention, anti-starvation
  fairness, and supply/demand heatmaps. Real TypeScript + Redis + SQL. Pairs with
  ride-hailing-architecture (trip FSM) and routing-navigation-eta (ETA).
---

# Real-Time Matching & Dispatch — Nearest Is the Bug

**The closest driver is almost never the right driver.** A driver 200 m away across a divided highway with a U-turn loses to one 600 m away on a clear approach. Dispatch is a real-time **assignment problem weighted by predicted ETA and acceptance probability**, not a `ORDER BY distance LIMIT 1`. H3 makes the candidate search microsecond-fast; ETA-weighted scoring makes the pick *good*; atomic claims make it *correct* under concurrency.

---

## 1. Mandate

- **H3 narrows, ETA decides.** Hex ring gives a tiny candidate set in microseconds; the final pick uses road-network ETA + business signals, never straight-line distance.
- **Batch, don't greedy.** Buffer requests ~150–300 ms and solve the driver×rider assignment globally; greedy per-request assignment is the classic suboptimality.
- **Claim atomically.** One offer → one driver via an atomic Redis claim; the trip FSM guard is the second line of defense against double-accept.
- **Be fair on purpose.** Anti-starvation for drivers (idle-time boost) and riders (aging) — fairness is a designed term in the score, not an afterthought.

## 2. When to use / when NOT

**Use when:** building the dispatch service — candidate search, scoring, offer/accept, reassignment, supply/demand balancing. Sits on top of `ride-hailing-architecture` (it consumes `trip.requested`, emits `DRIVER_ACCEPTED` for the FSM) and calls `routing-navigation-eta` for ETAs.

**Skip / go elsewhere when:** courier *delivery* batching with prep-time and stacking → `marketplace-master/delivery-logistics-dispatch` (sibling; same H3+assignment spine, different constraints — don't duplicate it). Pure presence/GPS plumbing → `live-location-tracking`.

## 3. Mental model — the dispatch loop

```
trip.requested ─▶ H3 candidate set (online + idle + product-eligible, ring-expand till N)
   ─▶ ETA matrix (drivers → pickup, traffic-aware)  ─▶ score = f(ETA, p(accept), rating, fairness)
   ─▶ BATCH ASSIGN (min-cost bipartite over the window)  ─▶ OFFER (atomic claim, timeout)
   ─▶ accepted? → emit DRIVER_ACCEPTED  | declined/timeout? → re-enter next batch (penalize)
```

The candidate set must be **small** (10–30) before you spend money on ETAs — H3 is the cheap filter, the Routes/Matrix API or ML ETA is the expensive scorer you protect.

## 4. Candidate search via H3 ring

```ts
import { latLngToCell, gridDisk } from "h3-js"; // v4.4.x (v4 names: latLngToCell, gridDisk)

const RES = 8; // res-8 ≈ 531m edge → metro dispatch; res-9 (~174m) for dense cores

// Drivers publish location → indexed by H3 cell in Redis. Move = SREM old cell, SADD new.
async function indexDriver(d: { id: string; lat: number; lng: number; product: string }) {
  const cell = latLngToCell(d.lat, d.lng, RES);
  const prev = await redis.hget(`driver:cell`, d.id);
  if (prev && prev !== cell) await redis.srem(`disp:${prev}:${d.product}`, d.id);
  await redis.sadd(`disp:${cell}:${d.product}`, d.id);
  await redis.hset(`driver:cell`, d.id, cell);
  await redis.set(`driver:online:${d.id}`, "1", "EX", 30); // presence TTL — see live-location-tracking
}

// Expand rings until we have enough ONLINE, IDLE, eligible candidates.
async function candidates(pickup: LatLng, product: string, need = 20): Promise<string[]> {
  const center = latLngToCell(pickup.lat, pickup.lng, RES);
  const out = new Set<string>();
  for (let k = 0; k <= 5 && out.size < need; k++) {
    for (const cell of gridDisk(center, k)) {
      const ids = await redis.smembers(`disp:${cell}:${product}`);
      for (const id of ids) {
        if (await redis.exists(`driver:online:${id}`)) out.add(id); // skip stale/offline
      }
    }
  }
  return [...out];
}
```

H3 (hexagons) beats geohash here: near-equal cell areas and uniform neighbor distance, so ring expansion is honest in every direction. **H3 is the filter, not the answer.**

## 5. DECISION MATRIX — assignment strategy

| Strategy | Latency | Match quality | Complexity | Use |
|----------|---------|---------------|------------|-----|
| **Greedy nearest** | lowest | poor (ignores traffic, thrash) | trivial | prototypes only |
| **Greedy ETA-ranked** | low | decent | low | low-density markets, MVP |
| **Batched bipartite (Hungarian/auction)** ⭐ | +150–300 ms | best (global optimum over window) | medium | dense metros (Uber/Careem default) |
| **ML dispatch (value/marketplace-aware)** | low (model) | best + future-aware | high (training, features) | mature platforms, marketplace optimization |

**Verdict:** start greedy-ETA-ranked, graduate to **batched bipartite** the moment density makes greedy visibly suboptimal (driver thrash, riders matched to far drivers). The buffer window trades a fraction of a second of wait for materially better assignments.

## 6. Scoring & batched assignment (production)

```ts
// Lower score = better. ETA dominates; acceptance & fairness shape it.
function score(c: Candidate, r: RideReq, now: number): number {
  const etaPenalty   = c.etaToPickupS;                        // seconds to pickup (the spine)
  const acceptBoost  = (1 - c.pAccept) * 120;                 // unlikely-to-accept → +up to 120s
  const ratingBoost  = (5 - c.rating) * 15;                   // nudge toward better-rated
  const idleFairness = -Math.min(c.idleSec, 600) * 0.05;      // idle longer → favored (anti-starvation)
  const dirPenalty   = c.headingAwayFromPickup ? 60 : 0;      // pointed wrong way
  return etaPenalty + acceptBoost + ratingBoost + idleFairness + dirPenalty;
}

// Buffer requests, then solve the whole batch as min-cost assignment (not greedy).
class DispatchBatcher {
  private pending: RideReq[] = [];
  constructor(private windowMs = 200) { setInterval(() => this.flush().catch(log.error), windowMs); }
  add(r: RideReq) { this.pending.push(r); }

  private async flush() {
    if (!this.pending.length) return;
    const batch = this.pending.splice(0);
    const cands = await this.candidatesForBatch(batch);                 // H3 per request, deduped
    const eta   = await etaMatrix(cands, batch.map((b) => b.pickup));   // routing-navigation-eta
    const cost  = buildCostMatrix(batch, cands, eta, score);           // rows=requests, cols=drivers
    const assign = hungarian(cost);                                     // global min-cost bipartite
    for (const a of assign) {
      if (a.cost < Infinity) await this.offer(a.request, a.driver, eta.get(a.driver, a.request));
      else await this.requeueWithSurge(a.request);                      // no driver → widen/surge next window
    }
  }
}
```

`hungarian()` (or a faster auction algorithm at high N) minimizes **total** ETA across the batch — the two-rider/two-driver swap that greedy gets wrong. Cap candidates per request (you already did via H3) so the matrix stays small and the Matrix API bill stays sane.

## 7. Offer/accept — atomic claim, timeout, re-offer

```ts
const OFFER_TTL = 12; // seconds a driver has to accept

// Send offer; the offer key is the lock. First ACCEPT to claim wins.
async function offer(req: RideReq, driverId: string, etaS: number) {
  const offerId = ulid();
  await redis.set(`offer:${offerId}`, JSON.stringify({ tripId: req.tripId, driverId }),
                  "EX", OFFER_TTL, "NX");
  await redis.set(`trip:offering:${req.tripId}`, offerId, "EX", OFFER_TTL);
  push.toDriver(driverId, { type: "RIDE_OFFER", offerId, etaS, fare: req.fareQuote, ttl: OFFER_TTL });
  scheduleTimeout(offerId, req.tripId, OFFER_TTL); // on expiry → requeue + penalize non-response
}

// Driver taps Accept. Atomic claim: only the FIRST acceptor for this trip succeeds.
async function accept(offerId: string, driverId: string): Promise<"won" | "taken"> {
  const raw = await redis.get(`offer:${offerId}`);
  if (!raw) return "taken";                                   // expired/reassigned
  const { tripId, driverId: target } = JSON.parse(raw);
  if (target !== driverId) return "taken";
  // Atomically claim the TRIP (not just the offer): SET NX is the single source of truth.
  const claimed = await redis.set(`trip:driver:${tripId}`, driverId, "NX", "EX", 3600);
  if (!claimed) return "taken";                               // someone already claimed → double-accept blocked
  await tripService.applyEvent(tripId, { type: "DRIVER_ACCEPTED", driverId, offerId }); // FSM guard = 2nd defense
  await redis.del(`offer:${offerId}`, `trip:offering:${tripId}`);
  return "won";
}
```

**Two layers stop double-accept:** the atomic Redis claim (`SET NX` on `trip:driver:{tripId}`) and the trip FSM guard in `ride-hailing-architecture` (`assignedDriverId` check). Never rely on UI debouncing. **Broadcast-to-all offers are an anti-pattern** at scale — they create thundering-herd accepts and races; prefer scored, targeted, possibly sequential offers (top candidate first, fall through on timeout).

## 8. Supply/demand heatmap (the surge signal)

```sql
-- Aggregate open requests vs available drivers per H3 cell over a short window.
-- Feeds the surge engine (surge-dynamic-pricing) and the ops console.
SELECT h3_cell,
       count(*) FILTER (WHERE kind='request') AS demand,
       count(*) FILTER (WHERE kind='driver')  AS supply,
       (count(*) FILTER (WHERE kind='request')::numeric
         / NULLIF(count(*) FILTER (WHERE kind='driver'),0)) AS dsr  -- demand/supply ratio
FROM dispatch_signals
WHERE city_id = $1 AND at > now() - interval '3 minutes'
GROUP BY h3_cell;
```

DSR > 1 in a cell = undersupplied → surge incentive + driver "go here" nudges. This is the bridge from dispatch to pricing.

## 9. Edge cases & gotchas

- **Double-accept** → atomic `SET NX` trip claim + FSM guard (§7). Solved by construction.
- **Decline / timeout / no-response** → offer expires, request re-enters the next batch; track and penalize chronic decliners in `pAccept` (don't keep offering to a driver who never accepts).
- **No driver available** → requeue with backoff, widen H3 rings, raise surge incentive, notify rider of wait; auto-cancel + refund past SLA.
- **Acceptance-rate gaming** → drivers who accept then immediately cancel to keep stats. Measure *completed* not *accepted*; penalize accept-then-cancel.
- **Destination cherry-picking** → if you reveal dropoff pre-accept, drivers skim long fares. Reveal destination *after* accept (or use upfront earnings) unless local regulation requires showing it.
- **Stale candidate** → driver went offline between index and offer. Re-check presence at offer time (TTL key); the offer itself has a TTL.
- **Airport / venue queues** → FIFO virtual queue overrides nearest-ETA; first-in-lot gets the next ride. Model as a separate dispatch policy per geofence.
- **Thundering herd on surge** → many drivers converge on one hot cell, over-correcting. Smooth incentives; cap concurrent nudges per cell.

## 10. Performance & scale

- **H3 lookups are O(1)** and shard evenly (cell IDs distribute) → the live driver index scales horizontally; run expensive ETA/assignment only on the tiny candidate set.
- **Matrix calls cost money & latency** — cap candidates (H3 first), cache ETAs for a few seconds, batch one Matrix call per dispatch window, and consider self-hosted OSRM/Valhalla or an ML ETA at volume (`routing-navigation-eta`).
- **Shard the batcher by city** — each metro runs its own dispatch loop; no global lock, no cross-city contention.
- **WebSocket/MQTT fan-out** for offers: target the chosen driver(s), not a broadcast channel — fan-out cost scales with offers sent, so targeted offers keep it linear.
- **Auction over Hungarian** when batch sizes get large (Hungarian is O(n³)); auction algorithms approximate the optimum far faster.

## 11. Security & abuse

- **GPS spoofing** (fake-location apps to teleport to surge zones / airport queue) → cross-check speed/teleport jumps, sensor consistency, device attestation (Play Integrity / DeviceCheck); flag impossible movement.
- **Offer/accept replay** → offers are single-use TTL'd tokens (ULID), claims are atomic; a replayed accept hits "taken".
- **Driver location privacy** → dispatch sees driver coordinates server-side; riders never see unassigned-driver exact positions (only assigned driver after match — `live-location-tracking`).
- **Collusion** (driver+rider fake trips for incentives) → anomaly detection on trip shape, repeated pairs, GPS plausibility; feed trust & safety.

## 12. Testing — simulated drivers & replay

- **Driver simulator:** spawn N virtual drivers that move along real road geometry (decode a Directions polyline, step along it), publish GPS at realistic cadence, accept/decline by a policy. Run a whole city in a load test without a single real phone.
- **Replay traces:** record `dispatch_signals` + offers from production, replay against a candidate algorithm change, diff match rate / ETA / fairness. This is how you ship a scoring change safely.
- **Property tests:** no trip ever gets two `DRIVER_ACCEPTED`; every requeued request is eventually offered or cancelled; assignment cost never exceeds greedy (regression guard).
- **Chaos:** kill the batcher mid-window → pending requests must not be lost (persisted/requeued); drop ETAs → fall back to haversine with a flag.

## 13. Observability

- **Match rate** (% requests matched), **accept rate**, **completed rate** (the honest one) — per city/product.
- **Dispatch latency:** request → offer, offer → accept, request → accepted (p50/p95/p99).
- **ETA error** of pickup ETA (predicted vs actual arrival) — drives scoring quality.
- **Fairness:** driver idle-time distribution (no starving drivers), rider wait-time tail (no starving requests).
- **Reassignment rate**, decline rate by driver, no-driver rate by cell, surge frequency per cell.

## 14. Accessibility & i18n / RTL (MENA)

- **Offer UX in Arabic/RTL:** the driver's offer card (ETA, fare, pickup landmark) renders RTL with Arabic numerals option; pickup shown as **landmark + pin**, not a street address (`geocoding-places-addressing`).
- **Cash (COD) trips** affect dispatch: some drivers prefer/avoid cash — model as a driver preference and a request attribute; common across MENA (`payments-master`).
- **Demand shapes:** Ramadan iftar drop then surge, prayer-time lulls, Thursday-night peaks — surge/anti-starvation tuning must use locale-aware baselines, not US curves.
- **Women-driver / women-rider products** (e.g., Careem) — model as a product filter in candidate eligibility.

## 15. Anti-patterns

- **Greedy nearest-driver** (straight-line) → wrong driver, thrash, broken ETAs. Batch + ETA-weighted.
- **Broadcasting offers to all nearby drivers** → race storms, double-accepts, bad UX. Targeted scored offers.
- **No atomic claim** ("the FSM will catch it") → double-dispatch under load. Claim with `SET NX`.
- **Optimizing accept rate** instead of completed rate → rewards accept-then-cancel gaming.
- **Revealing destination pre-accept** (where avoidable) → cherry-picking, long-fare starvation.
- **Unbounded candidate sets** → Matrix API bill explosion + latency. H3-cap first.
- **One global dispatch loop** → cross-city contention. Shard by city.

## 16. Agent checklist

```
- [ ] H3 ring candidate search in Redis (online+idle+product-eligible), presence TTL re-check
- [ ] ETA matrix on the SMALL candidate set (traffic-aware); cache briefly
- [ ] Score = ETA + p(accept) + rating + idle-fairness + direction (lower=better)
- [ ] Batched bipartite assignment (Hungarian/auction), not greedy nearest
- [ ] Offer with TTL; ATOMIC trip claim (SET NX) + FSM guard = double-accept proof
- [ ] Re-offer on decline/timeout; penalize chronic decliners via p(accept)
- [ ] Reveal destination post-accept (unless regulated); airport FIFO queue policy
- [ ] Supply/demand DSR heatmap per H3 cell → surge signal + ops console
- [ ] Anti-starvation (driver idle boost, rider aging); shard batcher by city
- [ ] GPS-spoof / device-attestation checks; offers single-use; collusion detection
- [ ] Driver simulator + replay-trace harness; property test: never two accepts
- [ ] Metrics: match/accept/completed rate, dispatch latency, ETA error, fairness tails
```

## 17. References (verify current — 2026)

- Uber H3 (gridDisk, latLngToCell — v4 names): https://h3geo.org/docs/api/traversal · https://github.com/uber/h3-js
- Google Routes — Compute Route Matrix: https://developers.google.com/maps/documentation/routes/compute_route_matrix
- Redis sets / SET NX semantics: https://redis.io/docs/latest/commands/set/
- Hungarian/assignment background: https://en.wikipedia.org/wiki/Hungarian_algorithm · auction algorithm (Bertsekas)
- Uber Marketplace/dispatch engineering: https://www.uber.com/blog/engineering/ (dispatch, DeepETA, H3)

## 18. Related

`ride-hailing-architecture` (trip FSM + one-writer rule this feeds), `live-location-tracking` (presence/GPS the index relies on), `routing-navigation-eta` (the ETA matrix), `surge-dynamic-pricing` (consumes the DSR heatmap) · cross-master: `marketplace-master/delivery-logistics-dispatch` (courier sibling — reference, don't duplicate), `backend-api-master` (PostGIS/Redis), `ai-mcp-master` (ETA/acceptance models)
