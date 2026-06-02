---
name: supplier-api-integration
description: >-
  Integrate and normalize travel supplier APIs at staff/principal depth. Connect GDS (Amadeus
  Self-Service/Enterprise, Sabre, Travelport), NDC 21.3 airline content, and hotel bed banks
  (Hotelbeds APItude, TBO, Expedia EAN/Rapid, WebBeds, GRN) plus transfers/activities/car behind
  ONE canonical model. Ships a real TypeScript SupplierAdapter interface, a Hotelbeds adapter
  (X-Signature auth, availability→CheckRates→booking), resilient fan-out (timeout/retry/circuit
  breaker), token/session pooling, rate-limit & look-to-book governance, and sandbox/cert fixtures.
---

# Supplier / GDS / NDC / Bed-bank Integration

**Mandate: a supplier's wire format must die at the adapter boundary.** Core code only ever sees the
canonical model from `travel-tech-architecture`. The recheck step is mandatory and non-negotiable. Every
outbound call has a timeout, a circuit breaker, and respects the supplier's look-to-book ceiling — because
the fastest way to lose a supplier contract is an uncapped search crawler.

## When to use this skill
- Wiring any external supply source: GDS, NDC airline, bed bank, transfer/activity/car/rail provider.
- Building the adapter layer, search fan-out, recheck, or supplier resilience/rate-limiting.
- **Not** for orchestrating the multi-step booking *saga* (that's `booking-orchestration`) or for
  *distributing* your own inventory to OTAs (that's `channel-manager-system`).

## The adapter pattern (the entire architecture)

```
            ┌──────────────────────────────────────────────┐
  core ───► │  SupplierAdapter (interface, canonical I/O)    │ ◄─── registry: supplierId → adapter
            └──────────────────────────────────────────────┘
   Amadeus   Sabre   NDC(Duffel)   Hotelbeds   EAN/Rapid   TBO   WebBeds   GRN   ...
   (each adapter owns: auth, wire format, retries, rate-limit, mapping → canonical)
```

```ts
export interface SearchCriteria {
  product: "hotel" | "flight";
  // hotel: destination, checkIn, checkOut, occupancies[]; flight: origin/dest/dates/pax
  [k: string]: unknown;
}

export interface SupplierAdapter {
  readonly id: string;
  search(c: SearchCriteria, signal: AbortSignal): Promise<HotelOffer[] | FlightOffer[]>;
  recheck(rateKeyOrOfferId: string, signal: AbortSignal): Promise<RatePlan | FlightOffer>; // fresh price/avail
  book(req: BookRequest): Promise<{ supplierRef: string; status: BookingStatus; raw: unknown }>;
  cancel(supplierRef: string): Promise<{ refund: Money; penalty: Money; raw: unknown }>;
  retrieve(supplierRef: string): Promise<Booking>;
}

export interface BookRequest {
  rateKeyOrOfferId: string;
  pax: Pax[];
  idempotencyKey: string;     // YOUR key — survives retries, prevents double-book (see booking-orchestration)
  clientRef: string;
}
```

## DECISION MATRIX — protocol & flow per supplier

| Supplier | Protocol (2026) | Search → recheck → book | Auth | Settlement |
|----------|-----------------|-------------------------|------|------------|
| **Amadeus Self-Service** | REST/JSON | Flight Offers Search → **Flight Offers Price** → Flight Create Orders | OAuth2 bearer | BSP / consolidator |
| **Amadeus Enterprise (1A)** | SOAP/XML | Air shopping → pricing → PNR (full GDS) | session + SOAP WSSE | BSP |
| **Sabre** | REST **and** SOAP | **Bargain Finder Max** → **Revalidate Itinerary** → **Create PNR** | OAuth2 (REST) / session | BSP / ARC |
| **NDC airline / Duffel** | XML (IATA 21.3) / JSON | AirShopping → **OfferPrice** → OrderCreate → OrderView | per-airline key | airline / agg |
| **Hotelbeds APItude** | REST/JSON | `/hotels` → **`/checkrates`** (if `rateType:RECHECK`) → `/bookings` | API key + **X-Signature** | VCC / credit |
| **Expedia Rapid (EAN) v3** | REST/JSON | Shopping → **Price Check** (tokenized link) → Booking (+ Hold/Resume) | API key (HMAC) | EPS collect / card |
| **TBO Holidays v7** | SOAP/XML (+ newer REST) | HotelSearch → **AvailabilityAndPricing** → HotelBook | creds in SOAP header | credit line |

> The recheck column is mandatory in every row. Names differ (CheckRates / Flight Offers Price / Price Check
> / Revalidate / AvailabilityAndPricing) but the role is identical: **the price you charge comes from here.**

## Reference adapter — Hotelbeds APItude (copy-paste quality)

Auth is `X-Signature = SHA256(apiKey + secret + unixSeconds)` in hex, sent with `Api-key`. The booking flow
is availability → (CheckRates only when the rate is flagged `RECHECK`) → booking, carrying the opaque
`rateKey` forward unparsed.

```ts
import { createHash } from "node:crypto";

const HB_BASE = process.env.HB_ENV === "prod"
  ? "https://api.hotelbeds.com/hotel-api/1.0"
  : "https://api.test.hotelbeds.com/hotel-api/1.0"; // identical servers, no real charges

function hotelbedsHeaders(apiKey: string, secret: string): HeadersInit {
  const sig = createHash("sha256")
    .update(apiKey + secret + Math.floor(Date.now() / 1000))
    .digest("hex");
  return { "Api-key": apiKey, "X-Signature": sig, Accept: "application/json",
           "Accept-Encoding": "gzip", "Content-Type": "application/json" };
}

export class HotelbedsAdapter implements SupplierAdapter {
  readonly id = "hotelbeds";
  constructor(private apiKey = process.env.HB_KEY!, private secret = process.env.HB_SECRET!) {}

  async search(c: SearchCriteria, signal: AbortSignal): Promise<HotelOffer[]> {
    const res = await fetch(`${HB_BASE}/hotels`, {
      method: "POST", signal, headers: hotelbedsHeaders(this.apiKey, this.secret),
      body: JSON.stringify({
        stay: { checkIn: c.checkIn, checkOut: c.checkOut },
        occupancies: c.occupancies,           // [{ rooms, adults, children, paxes:[{type,age}] }]
        destination: { code: c.destinationCode },
      }),
    });
    if (!res.ok) throw new SupplierError("hotelbeds", res.status, await res.text());
    const data = await res.json();
    return (data.hotels?.hotels ?? []).map(toCanonicalHotel); // map INTO canonical here, nowhere else
  }

  // CheckRates: ONLY needed when a rate carries rateType === "RECHECK". Returns the bookable rate + price.
  async recheck(rateKey: string, signal: AbortSignal): Promise<RatePlan> {
    const res = await fetch(`${HB_BASE}/checkrates`, {
      method: "POST", signal, headers: hotelbedsHeaders(this.apiKey, this.secret),
      body: JSON.stringify({ rooms: [{ rateKey }] }),
    });
    if (!res.ok) throw new SupplierError("hotelbeds", res.status, await res.text());
    return toCanonicalRatePlan((await res.json()).hotel.rooms[0].rates[0]);
  }

  async book(req: BookRequest) {
    const res = await fetch(`${HB_BASE}/bookings`, {
      method: "POST", headers: hotelbedsHeaders(this.apiKey, this.secret),
      body: JSON.stringify({
        holder: { name: req.pax[0].firstName, surname: req.pax[0].lastName },
        rooms: [{ rateKey: req.rateKeyOrOfferId, paxes: toHbPaxes(req.pax) }],
        clientReference: req.clientRef,        // idempotency anchor on the supplier side
      }),
    });
    if (!res.ok) throw new SupplierError("hotelbeds", res.status, await res.text());
    const b = (await res.json()).booking;
    return { supplierRef: b.reference, status: "CONFIRMED" as const, raw: b };
  }

  async cancel(ref: string) { /* DELETE /bookings/{ref} → read penalty from response */ return null as never; }
  async retrieve(ref: string) { /* GET /bookings/{ref} */ return null as never; }
}
```

> **Opaque (packaged) rates** from bed banks are sellable *only* when bundled with another product
> (flight/transfer/car) — never expose them as a standalone hotel price. Flag `opaque` on the `RatePlan`
> and enforce at the pricing/display layer.

## Resilience wrapper (suppliers ARE flaky — wrap every adapter)

```ts
// Per-supplier circuit breaker + timeout + retry (idempotent reads only). One breaker per credential set.
export function resilient(adapter: SupplierAdapter, breaker: CircuitBreaker, limiter: RateLimiter): SupplierAdapter {
  const guard = async <T>(op: () => Promise<T>, retries = 0): Promise<T> => {
    if (breaker.isOpen()) throw new SupplierUnavailable(adapter.id);
    await limiter.acquire();                 // respects concurrency + look-to-book budget
    try { const r = await op(); breaker.success(); return r; }
    catch (e) {
      breaker.failure();
      if (retries < 2 && isTransient(e)) {   // retry NETWORK/5xx on reads, NEVER on book()
        await sleep(150 * 2 ** retries + jitter());
        return guard(op, retries + 1);
      }
      throw e;
    } finally { limiter.release(); }
  };
  return {
    ...adapter,
    search: (c, s) => guard(() => adapter.search(c, withTimeout(s, 7000))),   // partial-result deadline
    recheck: (k, s) => guard(() => adapter.recheck(k, withTimeout(s, 8000))),
    book: (req) => adapter.book(req),        // NO auto-retry — let the saga decide via idempotencyKey
    cancel: adapter.cancel, retrieve: adapter.retrieve,
  };
}
```

**Never auto-retry `book()`.** A network timeout on book doesn't mean the booking failed — it may have
succeeded server-side. Resolve via the idempotency key + a `retrieve()` reconcile in `booking-orchestration`.

## Search fan-out (fast, partial, bounded)

```ts
export async function fanOutSearch(adapters: SupplierAdapter[], c: SearchCriteria): Promise<HotelOffer[]> {
  const ac = new AbortController();
  const deadline = setTimeout(() => ac.abort(), 9000); // hard wall: never wait for the slowest supplier
  const settled = await Promise.allSettled(adapters.map(a => a.search(c, ac.signal)));
  clearTimeout(deadline);
  const offers = settled.flatMap(s => (s.status === "fulfilled" ? s.value : (logSupplierMiss(s.reason), [])));
  return offers; // hand to mapping-system to dedupe, then pricing to mark up
}
```

One supplier down ≠ search fails. Return what you have; record the miss for observability and breaker state.

## Edge cases that bite in production
- **Price/availability drift:** the search price is a hint; recheck is the truth. Surface a clear "price
  updated" UX, never silently charge the new price.
- **`rateType: RECHECK` vs instant:** only CheckRates the rates that demand it — calling it on every rate
  wastes your look-to-book budget.
- **Currency:** suppliers quote in *their* net currency. Convert to sell currency with the FX pinned at quote
  time; never assume the supplier currency == display currency.
- **Cancellation policy timezones:** "free until" is in the *property's* timezone — resolve to UTC before
  comparing, or you'll mis-charge penalties around midnight.
- **On-request / pending:** bed banks may return `ON_REQUEST` (human confirms later) — model it as a real
  booking state, queue it in mid-office; don't treat as confirmed.
- **Air ticketing time limits:** Amadeus/Sabre PNRs must be paid/ticketed within ~24h (Sabre negotiable to
  48h) — persist `lastTicketingDate` and queue auto-cancel/ticket.

## Performance, scale & look-to-book governance
- **Search cache:** short TTL (minutes) keyed by canonical criteria; serves ranking/UX, never the booking price.
- **Concurrency caps + token bucket per credential set**; bed banks/GDS enforce hard **look-to-book** ratios
  — exceed them and you get throttled, billed, or suspended. Track L2B per supplier as a first-class metric.
- **Session/token pooling:** GDS sessions and OAuth tokens are scarce/expensive — pool, refresh proactively
  before expiry, and bound the pool to the supplier's session limit.
- **Async + partial results**; stream/append late suppliers if the UX supports it.

## Security
- Raw PANs never touch your servers — tokenize via PSP; pay suppliers with **VCC** to limit card exposure.
- Passport/DOB/loyalty are PII — encrypt at rest, **mask in logs** (`****1234`), short retention.
- Log raw request/response for disputes **redacted**; carry a correlation id end-to-end (NDC mandates one).
- Secrets per supplier × environment in a vault; rotate; never in code or client bundles.

## Testing
- Use sandbox/cert endpoints (Amadeus test, Hotelbeds `api.test.hotelbeds.com`, Sabre CERT) — identical
  servers, no real charges.
- **Record real responses as fixtures**; replay them in contract tests so a supplier schema change fails CI.
- Track **certification status per supplier** — many require passing a cert suite (avail/checkrates/booking,
  cancellation, multi-room) before production access.

## Observability (per supplier)
- Look-to-book ratio, search latency p50/p95/p99, timeout rate, circuit state, recheck price-drift %,
  book success/fail/on-request, token-pool saturation. Alert on L2B approaching the contractual cap.

## i18n / RTL & currency
- Pass language to suppliers that support it; render Arabic/Hebrew content RTL (pair `ui-master`).
- Convert net→sell with pinned FX; display localized currency formatting; never mix net/sell currencies.

## Anti-patterns
- Leaking supplier shapes into core/business logic — map at the boundary, always.
- Booking on a cached/search price without recheck → failed books and price disputes.
- Auto-retrying `book()` → duplicate PNRs/reservations. Resolve via idempotency + retrieve instead.
- Serial supplier calls / no circuit breaker → one slow supplier stalls everything.
- Ignoring look-to-book caps → throttling or credential suspension.
- Storing raw card/passport data; logging unredacted payloads.

## Checklist
```
- [ ] SupplierAdapter interface + registry; core sees only the canonical model
- [ ] Map board/room/cancellation/fare codes → enums; unmapped → review queue
- [ ] Async fan-out + per-supplier timeout + short-TTL search cache + partial results
- [ ] Mandatory recheck (CheckRates/Offer Price/Price Check/Revalidate) before book
- [ ] Resilience wrapper: timeout, circuit breaker, retry reads only, NEVER retry book()
- [ ] Idempotency key on book; persist supplierRef + redacted raw payload
- [ ] Rate-limit + look-to-book governance + token/session pooling per credential set
- [ ] Sandbox/cert endpoints, recorded fixtures, per-supplier cert tracking
```

## References (2026-current)
- Amadeus Self-Service (Flight Offers Search/Price, Create Orders): https://developers.amadeus.com/self-service
- Hotelbeds APItude getting-started (X-Signature, /hotels, /checkrates, /bookings): https://developer.hotelbeds.com
- Expedia Group Rapid (Shopping, Price Check, Booking, Hold & Resume): https://developers.expediagroup.com/rapid
- Sabre Dev Studio (Bargain Finder Max, Revalidate, Create PNR): https://developer.sabre.com
- IATA NDC 21.3 (AirShopping/OfferPrice/OrderCreate): https://guides.developer.iata.org

## Related
`travel-tech-architecture`, `booking-orchestration`, `mapping-system`, `b2b-b2c-booking-platform`;
pairs with `backend-api-master` (integrations-pro, resilience), `devops-master` (secrets/rate-limits).
