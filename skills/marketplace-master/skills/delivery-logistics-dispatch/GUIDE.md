---
name: delivery-logistics-dispatch
description: >-
  Build delivery, logistics, and courier dispatch for a marketplace. Use for
  Talabat/Uber-Eats-style food/quick-commerce delivery, last-mile logistics,
  rider/courier assignment, live tracking, delivery zones, ETAs, batching, and
  fulfillment. Also covers shipping/carrier integration for product marketplaces.
---

# Delivery, Logistics & Dispatch

Move orders from seller to buyer. Two worlds: **on-demand delivery** (Talabat-style couriers) and
**shipping** (carriers for product marketplaces).

## A) On-demand delivery (food / quick-commerce)

### Dispatch flow
```
order ACCEPTED → estimate prep time → find candidate couriers (online, near, free, capacity)
 → assign (auto algorithm or offer/accept) → courier to pickup → PICKED_UP
 → navigate to drop-off (live tracking + ETA) → DELIVERED (proof: photo/OTP/signature)
```

### Courier assignment algorithm
- Score candidates by: **distance to pickup + current load + direction + rating + readiness**.
- **Auto-assign** (system picks) vs **offer/accept** (broadcast, courier accepts) — auto scales better.
- **Batching/stacking**: group nearby orders to one courier (efficiency vs delivery time tradeoff).
- Re-assign on decline/timeout/no-show; surge incentives when supply is short.

### Delivery zones & ETA
- Define zones (polygons via `gis-maps`); per-zone fees, min order, availability.
- ETA = prep_time + courier-to-pickup + pickup-to-dropoff (use a routing/ETA API).
- Block out-of-zone addresses at checkout; dynamic delivery fee by distance/demand.

### Real-time tracking
- Courier app streams GPS (`gps-integration`) → throttled → buyer sees live map + ETA.
- WebSocket/MQTT/push for status + location; smooth jitter; snap-to-road for clean trails.
- States: assigned → arriving_pickup → picked_up → arriving_dropoff → delivered.

### Apps & ops
- **Courier app**: available toggle, order offers, navigation, proof of delivery, earnings.
- **Dispatch/ops console**: live map of orders+couriers, manual reassign, exceptions, SLA alerts.

## B) Shipping (product marketplace)
- **Carrier integration**: rates, labels, tracking via aggregators (Shippo, EasyPost) or carriers
  (DHL/UPS/Aramex/local). Multi-package per sub-order.
- **Rate at checkout** (real or table-based by weight/zone); print labels from seller dashboard.
- **Tracking sync**: poll/webhook carrier → update order status → notify buyer.
- Fulfillment models: seller-fulfilled vs platform-fulfilled (FBA-style warehouse).

## Cross-cutting
- Capacity & working hours per courier/zone; pause when overloaded.
- Proof of delivery (OTP/photo/signature); failed-delivery handling + retry.
- Delivery fees + courier payouts/tips (feed into payments + accounting).
- Metrics: on-time rate, avg delivery time, assign time, courier utilization (dashboards).

## Checklist
```
- [ ] Decide on-demand delivery vs shipping (or both per category)
- [ ] Delivery zones (polygons), per-zone fee/min-order, address validation at checkout
- [ ] Dispatch: candidate scoring, auto-assign/offer, reassign on decline/timeout, batching
- [ ] Live tracking: courier GPS → throttled → buyer map + ETA via routing API
- [ ] Courier app + dispatch console; proof of delivery
- [ ] Shipping: carrier rates/labels/tracking integration + checkout rating
- [ ] Courier payouts/tips + delivery metrics dashboards
```

## Anti-patterns
- Broadcasting every order to all couriers (chaos) — use scored assignment.
- Streaming raw high-frequency GPS (battery/cost) — throttle on device.
- No reassignment on no-show → stuck orders.
- Static ETAs that ignore prep time + traffic → broken promises.
- Accepting out-of-zone orders you can't deliver.
