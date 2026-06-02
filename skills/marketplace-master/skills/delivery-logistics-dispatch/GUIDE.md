---
name: delivery-logistics-dispatch
description: >-
  Build last-mile delivery + courier dispatch at staff depth — Talabat/Uber-Eats-style
  on-demand: H3 hexagonal proximity index, DISCO-style batched bipartite assignment
  weighted by ETA (not nearest), Google Routes computeRouteMatrix ETAs, PostGIS+H3
  delivery zones, throttled GPS live tracking, batching/stacking, courier & ops apps,
  proof of delivery + COD cash handling. Plus carrier/shipping integration for products.
---

# Delivery, Logistics & Dispatch — The 30-Minute Physics Problem

**On-demand delivery is a real-time optimization problem disguised as a CRUD app.** You have minutes,
moving couriers, traffic, prep times, and a buyer watching a map. The principal-level insight (Uber's,
Talabat's): **don't greedily assign the nearest courier per order — buffer orders for a beat and solve
the whole batch as an assignment problem weighted by predicted ETA.** The closest courier on a blocked
road loses to one two hexagons away on a clear one. Spatial indexing makes that decision *fast*;
batched matching makes it *good*.

Two worlds live here: **on-demand delivery** (couriers, the hard part) and **shipping** (carriers, a
solved integration problem). Identify which (or both, per category) before building.

---

## 1. Mandate

- **Index space with H3, decide with ETA.** H3 hexagons give O(1) "who's near" candidate sets; final assignment uses real road-network ETA (Routes API / ML model), never straight-line distance.
- **Batch, don't greedy-assign.** Buffer requests ~100–300ms, build a courier×order bipartite graph weighted by ETA, solve globally.
- **Throttle GPS on-device.** Stream at 3–5s (or movement-based), not 10Hz — battery, cost, and your ingest all thank you.
- **Block what you can't deliver.** Zone + capacity + hours validated at checkout, not discovered at dispatch.

## 2. When to use / when NOT

**Use when:** building courier dispatch/assignment, delivery zones/ETA, live tracking, courier/ops apps, batching, or carrier shipping integration. **Pairs with** `cart-checkout-orders` (the sub-order being fulfilled) and `marketplace-payments-payouts` (courier payouts, COD reconciliation).

**Skip on-demand dispatch when:** product marketplace with carrier shipping only → jump to §9 (carriers). **Skip the whole skill** for digital/services marketplaces (no physical fulfillment).

## 3. DECISION MATRIX — fulfillment model

| Model | Latency | Inventory | Routing | Use |
|-------|---------|-----------|---------|-----|
| **On-demand courier** ⭐ | minutes | local, per-branch | live dispatch + ETA | Food, q-commerce, pharmacy (Talabat) |
| **Scheduled delivery** | same/next-day slots | local DC | route optimization (VRP) | Groceries, furniture |
| **Carrier shipping** | days | seller/warehouse | carrier network | Products (Amazon/Noon) |
| **Platform-fulfilled (FBA-style)** | days | platform warehouse | platform logistics | High-volume sellers, returns control |

## 4. On-demand dispatch — the architecture

```
order ACCEPTED → predict ready_at (prep time) → H3 candidate couriers (online, near, capacity)
 → score by ETA-to-pickup + load + direction + rating → BATCH MATCH (assignment) → offer/auto-assign
 → courier → pickup (PICKED_UP) → drop-off (live ETA) → DELIVERED (proof: OTP/photo) → settle
```

### H3 proximity index (candidate set in microseconds)

```ts
import { latLngToCell, gridDisk } from "h3-js";
const RES = 9;                                   // res-9 ≈ ~174m edge, city-block scale

// Couriers publish location → store IDs by H3 cell in Redis (cheap to update on cell change).
async function indexCourier(courierId: string, lat: number, lng: number) {
  const cell = latLngToCell(lat, lng, RES);
  await redis.sadd(`couriers:${cell}`, courierId);  // move = SREM old cell, SADD new cell
}

// Candidate lookup: expand rings until enough candidates (k-ring / gridDisk).
async function candidates(pickupLat: number, pickupLng: number, need = 20): Promise<string[]> {
  const center = latLngToCell(pickupLat, pickupLng, RES);
  const out = new Set<string>();
  for (let k = 0; k <= 4 && out.size < need; k++) {
    for (const cell of gridDisk(center, k))
      (await redis.smembers(`couriers:${cell}`)).forEach((c) => out.add(c));
  }
  return [...out];                                  // tiny set → feed to expensive ETA + scoring
}
```

H3 (Uber's open grid) beats geohash here: near-equal cell areas and uniform neighbor distances, so
ring expansion is honest in every direction. **H3 narrows the search; it is not the answer** — the
final pick uses ETA + business signals on the small candidate set.

### ETA — real road-network, traffic-aware

```ts
// Google Routes API — Compute Route Matrix: M couriers × 1 pickup, traffic-aware, one call.
const eta = await fetch(
  "https://routes.googleapis.com/distanceMatrix/v2:computeRouteMatrix",
  { method: "POST",
    headers: { "X-Goog-Api-Key": KEY,
               "X-Goog-FieldMask": "originIndex,destinationIndex,duration,distanceMeters" },
    body: JSON.stringify({
      origins: couriers.map((c) => ({ waypoint: { location: { latLng: { latitude: c.lat, longitude: c.lng } } } })),
      destinations: [{ waypoint: { location: { latLng: { latitude: pickup.lat, longitude: pickup.lng } } } }],
      travelMode: "DRIVE", routingPreference: "TRAFFIC_AWARE",
    }) });
// Alternatives: Mapbox Matrix, self-hosted OSRM/Valhalla (cost control at scale). Uber's DeepETA
// is an ML model over physics ETAs at p95 ~4ms — graduate to that when API cost/latency bites.
```

### Batched assignment (DISCO-style) — not greedy

```ts
// Buffer requests for a short window, then solve courier×order assignment minimizing total ETA.
class DispatchBatcher {
  private pending: RideReq[] = [];
  constructor(private windowMs = 200) { setInterval(() => this.flush(), windowMs); }
  add(r: RideReq) { this.pending.push(r); }

  private async flush() {
    if (!this.pending.length) return;
    const batch = this.pending.splice(0);
    const cands = await this.candidatesForAll(batch);            // H3 per order
    const cost = await this.etaMatrix(batch, cands);             // edge weights = predicted ETA + penalties
    // Solve as min-cost bipartite matching (Hungarian / auction algo). Greedy nearest is the bug here.
    const assignments = hungarian(cost);
    for (const a of assignments) await this.offer(a.orderId, a.courierId, a.eta);
  }
}
```

**Candidate score** (before/with matching): `w1·etaToPickup + w2·currentLoad + w3·wrongDirection −
w4·rating − w5·readinessSoon`. **Auto-assign** scales better than broadcast offer/accept; reassign on
decline/timeout/no-show; **surge incentives** when supply < demand in a zone.

## 5. Delivery zones — PostGIS truth + H3 speed

```sql
-- Source of truth: exact polygons in PostGIS (ops draw them; per-zone fee/min-order/hours).
create table delivery_zones (
  id uuid primary key, branch_id uuid, area geography(polygon,4326),
  base_fee bigint, min_order bigint, active_hours jsonb
);
create index on delivery_zones using gist (area);

-- "Can we deliver to this drop-off?" at checkout:
SELECT id, base_fee FROM delivery_zones
 WHERE branch_id = $1 AND ST_Covers(area, ST_Point($lng, $lat)::geography) LIMIT 1;
```

For high-QPS membership checks, **polyfill** each polygon to H3 cells (`polygonToCells`) and cache the
cell set in Redis → an incoming ping becomes an O(1) "is this cell in the zone?" lookup, with PostGIS
as the authoritative geometry. Block out-of-zone addresses at checkout; dynamic fee by distance/demand.

## 6. Real-time tracking

- Courier app streams GPS **throttled on-device** (3–5s or movement-gated) → ingest → buyer sees live map + ETA.
- Transport: WebSocket/MQTT/SSE for status + location; **smooth jitter** + **snap-to-road** for clean trails.
- States: `assigned → arriving_pickup → picked_up → arriving_dropoff → delivered`. Recompute ETA on each ping (or on meaningful movement) — static ETAs are broken promises.

## 7. Apps & ops

- **Courier app:** online toggle, order offers + accept/decline, navigation handoff, proof of delivery, earnings + tips, cash-collected (COD) reconciliation.
- **Dispatch/ops console:** live map of orders + couriers, manual reassign, SLA/exception alerts (stuck order, no courier, late), zone supply heatmap, surge controls.

## 8. Edge cases

- **No courier available** → queue with backoff + surge incentive; widen rings/zones; notify buyer of delay; auto-cancel + refund past SLA.
- **Decline / no-show / unreachable** → reassign (the batcher re-enters the order next window); penalize chronic decliners in scoring.
- **Multi-pickup batch (stacking)** → group nearby orders to one courier; reorder stops to minimize total ETA; cap batch size so the first buyer isn't punished.
- **Failed delivery** (buyer absent) → retry policy, photo evidence, return-to-store, partial charge/fee.
- **Prep overrun** → push pickup ETA; don't dispatch courier to wait (idle cost) — time the offer to `ready_at`.
- **COD** → courier collects cash; reconcile collected vs expected; settle into platform → seller payout (`marketplace-payments-payouts`).
- **Cancel mid-route** → courier compensation + cancellation fee; sub-order → `cancelled`.

## 9. Shipping (product marketplaces)

- **Carrier aggregators** (Shippo, EasyPost) or direct (DHL/UPS/Aramex/SMSA/local) → rates, labels, tracking via one API. Multi-package per sub-order.
- **Rate at checkout:** live carrier rates or table-based (weight × zone); print labels from the seller dashboard.
- **Tracking sync:** carrier webhook/poll → update sub-order status → notify buyer.
- **Fulfillment models:** seller-fulfilled vs platform-fulfilled (FBA-style warehouse, platform controls returns/SLA).

## 10. Performance & scale

- **H3 lookups are O(1)** and shard evenly (cell IDs distribute) — the live courier index scales horizontally; only run expensive ETA/matching on the tiny candidate set.
- **GPS ingest** is the firehose: throttle on-device, batch writes, keep hot location in Redis, archive trails to columnar storage.
- **Matrix calls cost money** — cap candidates (H3 first), cache ETAs briefly, consider OSRM/Valhalla self-hosting or an ML ETA model at volume.
- **Geo queries**: GiST indexes + H3 cache; never `ST_Distance` scan the whole courier table.

## 11. Security & privacy

- **Location is sensitive PII**: minimize retention of courier/buyer GPS trails; share buyer↔courier location only during an active delivery; mask exact home location after drop-off.
- **Proof of delivery**: OTP / photo / signature — store securely, used as dispute evidence.
- **Courier identity/KYC** before payouts (`seller-vendor-management` patterns apply to couriers too).
- **COD cash** is a fraud + safety surface: reconcile per courier, cap outstanding cash, settle frequently.
- **Anti-collusion**: detect courier↔seller↔buyer fraud rings (fake deliveries) — feed `reviews-ratings-trust-safety`.

## 12. Observability

- **Dispatch:** assign time (request → courier accepted), reassignment rate, % auto vs manual, no-courier rate.
- **Delivery:** on-time rate, avg total time (accept→delivered), ETA accuracy (predicted vs actual), failed-delivery rate.
- **Supply:** courier utilization, idle vs active, surge frequency per zone, supply/demand heatmap.
- **Money:** COD reconciliation diffs, courier payout accuracy, tip flow.

## 13. i18n / RTL (MENA)

- **Addressing is the real MENA challenge:** many areas lack formal street addresses → rely on **pin-drop + landmark + free-text directions** and (in KSA) the **National Address / short-address** system; don't assume Western postal structure. Capture lat/lng as primary, text as hint.
- **Arabic in courier/buyer apps:** RTL UI, Arabic addresses + voice notes for directions (`ui-master`, `mobile-master`).
- **COD dominance:** robust cash handling + reconciliation is table stakes, not an edge case.
- **Demand patterns:** Ramadan/iftar spikes, prayer-time lulls, late-night peaks → forecast + courier supply planning differ from Western curves.
- Per-emirate/city zones; bilingual SMS/push for tracking.

## 14. Anti-patterns

- **Greedy nearest-courier assignment** → suboptimal ETAs, courier thrash. Batch + assignment.
- **Broadcasting every order to all couriers** → chaos, race conditions. Scored, targeted offers.
- **Straight-line distance instead of road/traffic ETA** → wrong courier, broken promises.
- **Streaming raw 10Hz GPS** → battery drain, ingest meltdown, cost. Throttle on-device.
- **No reassignment on no-show** → orders rot. **Static ETAs** ignoring prep + traffic → angry buyers.
- **Accepting out-of-zone/closed-branch orders** you can't fulfill.
- **Assuming formal addresses in MENA** → undeliverable; build pin-drop + landmark first.

## 15. Agent checklist

```
- [ ] Fulfillment model chosen (on-demand / scheduled / carrier / platform)
- [ ] H3 live courier index in Redis; gridDisk candidate sets
- [ ] ETA via road-network (Routes computeRouteMatrix / OSRM / ML), not Euclidean
- [ ] Batched bipartite assignment (ETA-weighted), reassign on decline/timeout; surge
- [ ] Zones: PostGIS polygons (truth) + H3 polyfill cache; checkout address validation
- [ ] Throttled on-device GPS; WS/MQTT live tracking; snap-to-road; recompute ETA
- [ ] Courier app (offers/nav/POD/earnings/COD) + ops console (map/reassign/SLA)
- [ ] Shipping: carrier aggregator rates/labels/tracking + checkout rating (products)
- [ ] Proof of delivery; location privacy; COD reconciliation; collusion detection
- [ ] On-time / assign-time / ETA-accuracy / utilization metrics
- [ ] MENA: pin-drop + landmark addressing, COD, Arabic RTL, Ramadan demand
```

## References (verify current — 2026)
- Uber H3 spatial index: https://h3geo.org/docs · https://github.com/uber/h3
- Google Routes API (Compute Route Matrix): https://developers.google.com/maps/documentation/routes/compute_route_matrix
- PostGIS spatial queries: https://postgis.net/docs/ST_Covers.html
- OSRM (self-host routing): https://project-osrm.org · Valhalla: https://valhalla.github.io/valhalla/
- EasyPost / Shippo (carrier shipping): https://www.easypost.com/docs · https://docs.goshippo.com

## Related
`cart-checkout-orders` (sub-order fulfillment FSM), `marketplace-payments-payouts` (courier payouts, COD), `reviews-ratings-trust-safety` (courier rating, fraud) · cross-master: `backend-api-master` (gis-maps, gps-integration), `mobile-master` (courier/buyer apps), `ai-mcp-master` (ETA/demand models)
