---
name: ride-hailing-architecture
description: >-
  Staff-level architecture for Uber/Careem-style ride-hailing: service decomposition
  (rider/driver/trip/dispatch/pricing/location), the trip STATE MACHINE with guarded
  transitions, the real-time backbone (WebSocket vs MQTT), geo-indexing (H3 vs S2 vs
  PostGIS), idempotent trip creation, the core SQL data model, and multi-city/tenant
  geo-sharding. Start here before matching, tracking, routing, or pricing.
---

# Ride-Hailing Architecture — The Trip Is a State Machine, Not a Row

**A ride is a long-lived, money-bearing distributed transaction across six services and two phones over a flaky cellular link — model it as a guarded state machine with idempotent transitions, or it will corrupt.** The single most common failure of junior ride-hailing builds is treating a trip as a CRUD row that everyone mutates. The principal insight: there is exactly **one writer of trip state** (the trip service), every transition is **guarded + idempotent**, and everything else (location, dispatch, pricing) is a satellite that *reads* trip state and *proposes* events.

---

## 1. Mandate

- **One trip-state writer, guarded transitions, idempotent everything.** Every mutating trip op carries a client-generated idempotency key; replays return the same result, never a second trip or a double charge.
- **Index space with H3, store truth in PostGIS.** Hex cells for O(1) "who's near"; PostGIS geography for authoritative polygons (zones, airports, geofences).
- **Separate the hot path from the system of record.** Live location lives in Redis (ephemeral, TTL'd); trips/fares/payouts live in Postgres (durable, audited). Never put 10 Hz GPS in your primary DB.
- **Shard by city, not by user.** A ride is local: rider, driver, dispatch, surge are all within one metro. City is your natural shard key and blast-radius boundary.

## 2. When to use / when NOT

**Use when:** designing a ride-hailing / on-demand mobility / taxi-dispatch backend, choosing the real-time transport, defining the trip lifecycle, or planning multi-city scale. This is the **anchor skill** — read it before `realtime-matching-dispatch`, `live-location-tracking`, `routing-navigation-eta`, or `surge-dynamic-pricing`.

**Skip / go elsewhere when:** building courier *delivery* dispatch (food/parcels) → `marketplace-master/delivery-logistics-dispatch` (it shares H3 + batched assignment but has prep-time, stacking, COD that rides don't). Pure map *UI* → `maps-rendering-design`. The rider/driver *apps* themselves → `cross-platform-apps-master`. Money movement (fares, payouts, wallet) → `payments-master`.

## 3. Mental model — services & the one-writer rule

```
                    ┌─────────────┐   trip events (Kafka/NATS)   ┌──────────────┐
  rider app  ──WS──▶│   Trip svc  │◀────────────────────────────│ Pricing svc  │ fare quote/final
                    │ (state owner)│                              └──────────────┘
 driver app ──MQTT─▶│  idempotent │   ┌──────────────┐
       │            │  FSM writer │◀──│ Dispatch svc │ match → offer → assign
       │            └──────┬──────┘   └──────┬───────┘
       │  GPS 4s                  │ reads     │ reads candidates
       ▼                          ▼           ▼
 ┌──────────────┐         ┌──────────────┐  ┌──────────────┐
 │ Location svc │────────▶│  Redis (geo, │  │  PostGIS     │ zones, geofences, audit
 │ (ingest+fan) │ presence│  presence,   │  │ (system of   │
 └──────────────┘         │  TTL)        │  │  record)     │
                          └──────────────┘  └──────────────┘
```

| Service | Owns | Hot store | Durable store |
|---------|------|-----------|---------------|
| **Rider** | rider identity, payment method ref, saved places | — | Postgres |
| **Driver** | driver profile, vehicle, KYC, online/availability | Redis (online set) | Postgres |
| **Trip** ⭐ | **trip state machine** (the only state writer) | Redis (active-trip cache) | Postgres (trips ledger) |
| **Dispatch** | candidate search, scoring, offer/accept | Redis (H3 index, offers) | Postgres (offer log) |
| **Location** | GPS ingest, smoothing, presence, fan-out | Redis (geo + TTL) | cold storage (trail archive) |
| **Pricing** | fare estimate, surge, final fare, reconciliation | Redis (surge multipliers) | Postgres (fares) |

The rule that saves you: **Dispatch never writes `trips.status`. Pricing never writes `trips.status`. Only Trip does**, in response to commands, after guard checks, inside one transaction. Other services emit *events* ("driver accepted offer X") that Trip consumes and validates.

## 4. The trip state machine (guarded transitions)

This is the heart of the system. Model it explicitly — not as scattered `if (status === ...)` checks.

```
requested ─▶ matching ─▶ accepted ─▶ arriving ─▶ arrived ─▶ in_progress ─▶ completed
    │           │           │           │          │            │
    └──────────┴───────────┴───────────┴──────────┴────────────┴─▶ cancelled
                                                                 (terminal, with reason+actor)
```

```ts
// trip-fsm.ts — explicit transition table with guards. The whole platform's integrity is here.
export type TripState =
  | "requested" | "matching" | "accepted" | "arriving"
  | "arrived" | "in_progress" | "completed" | "cancelled";

export type TripEvent =
  | { type: "MATCH_STARTED" }
  | { type: "DRIVER_ACCEPTED"; driverId: string; offerId: string }
  | { type: "DRIVER_ARRIVED" }
  | { type: "TRIP_STARTED"; startOdometer?: number }    // often gated by OTP / rider-present
  | { type: "TRIP_COMPLETED"; dropoff: LatLng; distanceM: number; durationS: number }
  | { type: "CANCELLED"; by: "rider" | "driver" | "system"; reason: string };

// Allowed transitions ONLY. Anything not listed throws — no silent illegal jumps.
const TABLE: Record<TripState, Partial<Record<TripEvent["type"], TripState>>> = {
  requested:   { MATCH_STARTED: "matching", CANCELLED: "cancelled" },
  matching:    { DRIVER_ACCEPTED: "accepted", CANCELLED: "cancelled" },
  accepted:    { DRIVER_ARRIVED: "arrived", CANCELLED: "cancelled" }, // 'arriving' folded via sub-status; keep explicit if you split
  arriving:    { DRIVER_ARRIVED: "arrived", CANCELLED: "cancelled" },
  arrived:     { TRIP_STARTED: "in_progress", CANCELLED: "cancelled" },
  in_progress: { TRIP_COMPLETED: "completed", CANCELLED: "cancelled" }, // cancel here is rare → partial fare
  completed:   {},   // terminal
  cancelled:   {},   // terminal
};

export class IllegalTransition extends Error {}

export function nextState(cur: TripState, ev: TripEvent): TripState {
  const to = TABLE[cur]?.[ev.type];
  if (!to) throw new IllegalTransition(`No transition: ${cur} --${ev.type}-->`);
  return to;
}

// Business guards layered on top of structural legality.
export function assertGuards(cur: TripState, ev: TripEvent, ctx: TripContext) {
  if (ev.type === "TRIP_STARTED" && ctx.requiresOtp && !ctx.otpVerified)
    throw new IllegalTransition("Cannot start trip before rider OTP verified");
  if (ev.type === "DRIVER_ACCEPTED" && ctx.assignedDriverId && ctx.assignedDriverId !== ev.driverId)
    throw new IllegalTransition("Trip already claimed by another driver"); // double-accept guard
}
```

**Why a table, not a switch:** the table is testable, diffable in PRs, and impossible to "forget a case". Cancellation is reachable from every non-terminal state and **must record `by` + `reason`** (it drives cancellation fees, driver penalties, and rider trust). Note `arriving` vs `arrived`: many systems collapse "en-route to pickup" into `accepted` with a sub-status; keep them separate only if you bill/measure them separately.

## 5. Idempotent trip creation (no double-trips, ever)

A rider double-taps "Confirm" on a 3G connection. Without idempotency you create two trips, dispatch two drivers, and charge twice.

```sql
-- One trip per idempotency key. The unique index is the enforcement, not app logic.
CREATE TABLE trips (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  city_id       int  NOT NULL,                       -- shard key
  rider_id      uuid NOT NULL,
  driver_id     uuid,
  status        text NOT NULL DEFAULT 'requested',
  pickup        geography(Point,4326) NOT NULL,
  dropoff       geography(Point,4326),
  product       text NOT NULL,                        -- economy / xl / etc.
  fare_quote    bigint,                               -- minor units (fils/cents); see surge skill
  surge_mult    numeric(4,2) DEFAULT 1.0,
  idempotency_key text NOT NULL,
  requested_at  timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  version       int NOT NULL DEFAULT 0                -- optimistic concurrency
);
CREATE UNIQUE INDEX trips_idem ON trips (rider_id, idempotency_key);
CREATE INDEX trips_city_status ON trips (city_id, status) WHERE status NOT IN ('completed','cancelled');
```

```ts
// createTrip — safe under retries. Returns existing trip on key collision.
async function createTrip(req: CreateTripReq): Promise<Trip> {
  try {
    const { rows } = await db.query(
      `INSERT INTO trips (city_id, rider_id, status, pickup, product, idempotency_key)
       VALUES ($1,$2,'requested', ST_Point($3,$4)::geography, $5, $6)
       RETURNING *`,
      [req.cityId, req.riderId, req.pickupLng, req.pickupLat, req.product, req.idempotencyKey],
    );
    await bus.publish("trip.requested", { tripId: rows[0].id, cityId: req.cityId });
    return rows[0];
  } catch (e: any) {
    if (e.code === "23505") {                          // unique_violation → it's a retry
      const { rows } = await db.query(
        `SELECT * FROM trips WHERE rider_id=$1 AND idempotency_key=$2`,
        [req.riderId, req.idempotencyKey]);
      return rows[0];                                   // same trip, no second dispatch
    }
    throw e;
  }
}

// Applying an event: optimistic-locked, single transaction, one writer.
async function applyEvent(tripId: string, ev: TripEvent): Promise<Trip> {
  return db.tx(async (t) => {
    const trip = await t.one(`SELECT * FROM trips WHERE id=$1 FOR UPDATE`, [tripId]);
    assertGuards(trip.status, ev, toCtx(trip));
    const to = nextState(trip.status, ev);             // throws IllegalTransition if illegal
    const updated = await t.one(
      `UPDATE trips SET status=$2, driver_id=COALESCE($3,driver_id),
              version=version+1, updated_at=now() WHERE id=$1 AND version=$4 RETURNING *`,
      [tripId, to, (ev as any).driverId ?? null, trip.version]);
    await t.none(`INSERT INTO trip_events (trip_id, type, payload, at) VALUES ($1,$2,$3,now())`,
      [tripId, ev.type, ev]);                          // append-only audit = replayable history
    await bus.publish(`trip.${to}`, { tripId, cityId: trip.city_id });
    return updated;
  });
}
```

`FOR UPDATE` + `version` check = no lost updates when dispatch and a rider-cancel race. The `trip_events` append-only log is your audit trail, your debugging time-machine, and the source for replay tests (§10).

## 6. DECISION MATRIX — real-time backbone (WS vs MQTT vs SSE)

| Transport | Best for | Pros | Cons | Verdict |
|-----------|----------|------|------|---------|
| **WebSocket** | rider↔backend, driver↔backend app comms | bi-directional, ubiquitous, easy behind ALB/Envoy, JSON | you build reconnect/backpressure/heartbeat | ⭐ Default for app↔backend |
| **MQTT** (EMQX/HiveMQ) | driver GPS ingest at fleet scale, device telemetry | QoS 0/1/2, retained msgs, last-will (auto-offline on disconnect), tiny frames, topic fan-out | extra broker to run; overkill for a few thousand clients | ⭐ Driver location firehose / 100k+ devices |
| **SSE** | one-way rider trip updates | trivial, HTTP/2, auto-reconnect built in | server→client only | Good for rider status if no client→server needed |
| **gRPC streams** | service↔service, some native apps | typed, multiplexed, efficient | browsers need grpc-web; ops heavier | Internal + native-only edges |

**Principal pattern at scale (Uber/Careem-shape):** driver app publishes GPS over **MQTT** (last-will → instant offline detection, QoS 1, topic `drivers/{cityId}/{driverId}/loc`); both apps receive trip/dispatch updates over **WebSocket** (or SSE for pure rider updates). Don't dogmatically pick one — **MQTT for the telemetry firehose, WS for interactive app state.** Start with WS-only; introduce MQTT when the GPS ingest volume or battery cost forces it.

## 7. DECISION MATRIX — geo-index (H3 vs S2 vs PostGIS)

| Index | Shape | Killer feature | Weakness | Use for |
|-------|-------|----------------|----------|---------|
| **H3** (Uber, v4) | hexagons | uniform neighbor distance → honest k-ring expansion; no corner ambiguity | not a strict containment hierarchy (children approximate) | ⭐ "drivers near me", dispatch candidate sets, surge zones |
| **S2** (Google) | spherical squares | true hierarchy + cell coverings; great for region indexing | 4 edge + 4 corner neighbors (non-uniform); steeper learning curve | strict hierarchical geofence trees, planet-scale coverings |
| **PostGIS** | exact geometry | authoritative polygons, `ST_Covers`, `ST_DWithin`, GiST | not a microsecond in-memory ring lookup | ⭐ zones/airports/geofences = system of record |

**The pairing you actually ship:** H3 cells in Redis for the *hot* "who's near" lookup (`latLngToCell` → `gridDisk` ring expansion), PostGIS for the *authoritative* polygon truth (zone fee, airport queue, restricted area). Polyfill PostGIS polygons to H3 cells (`polygonToCells`) and cache them so a live ping becomes an O(1) "is this cell in the zone set?" check. (Full dispatch use: `realtime-matching-dispatch`.)

```ts
import { latLngToCell, gridDisk, polygonToCells } from "h3-js"; // v4.4.x — note v4 names
const DISPATCH_RES = 8;   // res-8 ≈ 0.74 km², edge ~531m → good metro dispatch granularity
// res-9 (~174m edge) for dense cores (Dubai Marina, Cairo downtown); res-7 (~1.4km) for sparse.
const cell = latLngToCell(25.2048, 55.2708, DISPATCH_RES); // Dubai. (lat, lng, res) — order matters
```

## 8. Edge cases & gotchas

- **Double-accept:** two drivers tap Accept on the same offer in the same 200 ms. The FSM guard (`assignedDriverId` check) + atomic claim in dispatch (`SET offer:{id} driverX NX`) makes the first win and the second get "trip taken". Never rely on UI timing.
- **Rider cancels while driver is accepting:** the `FOR UPDATE` + version guard serializes them; whoever commits first wins, the loser sees `IllegalTransition` and reconciles. Decide policy: late cancel after accept → cancellation fee.
- **Driver app crashes mid-trip:** trip stays `in_progress`; location goes stale. Use MQTT last-will + a stale-trip sweeper (no location > N min on an active trip → alert ops, attempt re-auth, allow rider SOS).
- **GPS drift / tunnels:** pickup point jumps 300 m or vanishes in an underpass. Smooth + snap-to-road (`live-location-tracking`); never auto-`DRIVER_ARRIVED` purely on a single noisy fix.
- **Stale fare quote:** rider gets a quote, sits for 10 min, surge changes. Quotes carry `expires_at`; on expiry re-quote before `accepted`. Honor the quote once accepted (`surge-dynamic-pricing`).
- **Clock skew between phone and server:** never trust device timestamps for billing/ordering; stamp on ingest server-side, keep device time only as a hint.
- **Network partition during `TRIP_COMPLETED`:** completion + fare capture must be idempotent (event id dedupe) so a retry doesn't double-charge.

## 9. Performance

- **Keep the hot path out of Postgres.** Active-trip lookups and presence go to Redis; Postgres handles state transitions (low QPS, high value) and the audit log. A metro at peak is thousands of transitions/sec, not millions — Postgres handles it; what kills you is 10 Hz GPS in the same DB.
- **Partial indexes** on `(city_id, status)` filtered to active trips keep the dispatcher's "open trips in this city" query tiny even with a billion completed rows.
- **Event bus, not synchronous fan-out.** Trip publishes `trip.accepted`; pricing, notifications, analytics consume independently. Synchronous chains couple latency and failure.
- **Cache trip context** (the small read model dispatch/pricing need) in Redis keyed by tripId with the version; invalidate on transition.

## 10. Scale & reliability

- **Shard by city.** `city_id` is the partition key for trips, the routing key for dispatch, and the failure boundary. A city's outage shouldn't touch another. Cross-city is rare (intercity rides) and handled as an explicit product.
- **Geo-shard the location tier by city/H3** so Redis presence sets stay bounded and a hot metro can scale independently.
- **Idempotent everything** (creation §5, event apply §5, fare capture) so retries during failover are safe.
- **Backpressure** at ingest: if the location pipeline lags, shed by dropping intermediate fixes (keep latest), never block the driver app.
- **Outbox pattern** for trip events: write the event in the same tx as the state change, relay to the bus async — no "state changed but event lost" gaps.

## 11. Observability

- **Funnel:** request → match → accept → arrive → start → complete, with drop-off rates and p50/p95 latency per stage. Match rate and accept rate are your supply-health vitals.
- **Dispatch latency:** `trip.requested` → `DRIVER_ACCEPTED` (p50/p95/p99) per city/product.
- **ETA error:** predicted pickup ETA vs actual; predicted trip ETA vs actual. (Methodology in `routing-navigation-eta`.)
- **State-machine health:** count of `IllegalTransition` (should be ~0 in steady state; spikes = a client or race bug), cancellations by actor/reason, double-accept rejections.
- **Per-city dashboards** (it's the shard) + active trips, online drivers, surge zones live.

## 12. Accessibility & i18n / RTL (MENA)

- **Bilingual from the data layer up:** store/emit names and statuses with locale; the apps render Arabic (RTL) and English. Don't hardcode LTR assumptions in status strings or push templates (`cross-platform-apps-master`, `communications-master`).
- **MENA addressing reality:** pickup is a **pin-drop + landmark**, not a street address. The trip's `pickup` is lat/lng-primary; landmark text is a hint for the driver. Support Makani (Dubai), KSA National Address, what3words — see `geocoding-places-addressing`.
- **COD / cash trips** are first-class in MENA: trip completion may settle in cash; model `payment_method = cash` and reconcile (`payments-master`).
- **Demand curves differ:** Ramadan iftar lulls then surges, prayer-time dips, late-night peaks — your capacity/observability baselines must be locale-aware, not US-curve defaults.

## 13. Anti-patterns

- **Many services writing `trips.status`** → corruption, races, "how did this trip get here?" One writer, guarded transitions, period.
- **Trip as a CRUD row** with no FSM → illegal states (completed-then-accepted), unauditable. Use the transition table.
- **No idempotency key on create/complete** → double trips, double charges on retry. Non-negotiable.
- **Live GPS in the primary OLTP DB** → write amplification meltdown. Redis hot, Postgres durable, cold storage for trails.
- **Sharding by user/region instead of city** → cross-shard trips everywhere; city is the natural locality.
- **Synchronous service chains** (trip → pricing → notify in one request) → cascading latency/failure. Events + outbox.
- **Trusting device timestamps** for billing/order → exploitable + skewed. Server-stamp on ingest.

## 14. Agent checklist

```
- [ ] Six services delimited; ONLY Trip writes trip.status (one-writer rule)
- [ ] Trip state machine as an explicit transition table + business guards (double-accept, OTP)
- [ ] Idempotency key unique index on trip create; FOR UPDATE + version on event apply
- [ ] Append-only trip_events log (audit + replay)
- [ ] Real-time backbone chosen: WS for app state (+ MQTT for GPS firehose at scale)
- [ ] H3 (Redis, hot) + PostGIS (truth, polygons) geo-index; polyfill zones to cells
- [ ] city_id as shard key, partition key, and failure boundary
- [ ] Hot path in Redis, durable in Postgres, trails in cold storage; outbox for events
- [ ] Edge cases handled: double-accept, race-cancel, driver crash, GPS drift, stale quote
- [ ] Observability: stage funnel, dispatch latency, ETA error, IllegalTransition count
- [ ] MENA: bilingual/RTL, pin-drop+landmark pickup, COD trips, locale demand curves
```

## 15. References (verify current — 2026)

- Uber H3 spatial index (v4 API, function renames): https://h3geo.org/docs · https://github.com/uber/h3-js
- Google S2 geometry: https://s2geometry.io
- PostGIS geography & spatial predicates: https://postgis.net/docs/ST_DWithin.html · https://postgis.net/docs/ST_Covers.html
- MQTT 5 / EMQX broker: https://www.emqx.io/docs/en/latest/ · MQTT spec: https://mqtt.org
- Transactional outbox pattern: https://microservices.io/patterns/data/transactional-outbox.html

## 16. Related

`realtime-matching-dispatch` (the dispatch service in depth), `live-location-tracking` (the location service), `routing-navigation-eta` (ETA), `surge-dynamic-pricing` (the pricing service) · cross-master: `cross-platform-apps-master` (rider/driver apps), `payments-master` (fares/payouts/wallet), `backend-api-master` (PostGIS/GIS, GPS ingest), `marketplace-master` (delivery-logistics-dispatch — courier sibling, don't duplicate)
