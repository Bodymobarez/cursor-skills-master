---
name: channel-manager-system
description: >-
  Build a hotel channel manager. Use to distribute a property's ARI (availability,
  rates, inventory) to OTAs (Booking.com, Expedia, Agoda) and pull reservations
  back, with 2-way sync, pooled/derived rates, restrictions, and overbooking
  protection. Covers OTA connectivity standards, sync architecture, and mapping.
---

# Channel Manager System

A channel manager (CM) keeps **one source of truth** (the property's CRS/PMS) in sync with many
sales channels: push **ARI** out, pull **reservations** in — in near real time.

## What it syncs (ARI + more)

```
OUT (push to channels):  Availability (rooms left), Rates (price per rate plan/date),
                         Inventory (room types), Restrictions (MinLOS, CTA/CTD, stop-sell)
IN  (pull from channels): new/modified/cancelled reservations
```

## Connectivity per channel (each is different)

| Channel | Connectivity |
|---------|--------------|
| **Booking.com** | Connectivity APIs (Rates & Availability, Reservations, Content, Promotions) |
| **Expedia** | EPS / Expedia QuickConnect (EQC) / Partner Central APIs |
| **Agoda / others** | YCS / partner APIs |
| **Generic** | **OTA (OpenTravel) XML** — OTA_HotelAvailNotifRQ, OTA_HotelRateAmountNotifRQ, OTA_HotelResNotifRQ |

Build a **channel adapter** per OTA (like supplier adapters) behind a canonical ARI model.

## Architecture

```
PMS/CRS ──ARI change──► CM core ──per-channel adapter──► OTA push API
                          ▲                                  │
   reservation ◄──────────┴──── poll / webhook / push ◄──────┘
CM core: room/rate mapping table, ARI queue, retry, conflict resolution, rate derivation
```

## Critical concepts

- **Room & rate mapping**: map your room types + rate plans to each OTA's IDs (the #1 setup task).
- **Pooled vs allocated inventory**: pooled = shared count across channels (best, avoids
  overbooking); allocated = fixed per channel (risk of unsold/oversell).
- **Derived / linked rates**: child rates computed from a base (e.g. non-ref = base −10%); push
  the computed value or let the OTA derive — be consistent.
- **Restrictions**: MinLOS/MaxLOS, CTA (closed to arrival), CTD, stop-sell, release periods.
- **Overbooking protection**: decrement availability atomically on any channel sale; debounce and
  re-push true availability immediately after a booking.

## Sync reliability (must-haves)
- **Queue every ARI change**; push with retry + backoff; reconcile periodically (full refresh).
- **Idempotent reservation ingestion**: dedupe by channel reservation id (avoid double-import).
- **Delta + full sync**: deltas for speed, scheduled full sync to self-heal drift.
- **Rate-limit aware**: respect each OTA's throttles; batch updates per date range.
- **Conflict resolution**: two near-simultaneous sales → last availability wins, then re-push.
- Modification/cancellation handling from channels updates the CRS and re-opens inventory.

## Checklist
```
- [ ] Canonical ARI model + per-OTA channel adapters
- [ ] Room-type & rate-plan mapping UI/table per channel
- [ ] Pooled inventory with atomic decrement; immediate re-push on sale
- [ ] Derived rates + restrictions (MinLOS/CTA/CTD/stop-sell)
- [ ] ARI change queue + retry/backoff + scheduled full reconcile
- [ ] Reservation pull (webhook/poll) idempotent by channel res id
- [ ] Modify/cancel flows re-open inventory
- [ ] Per-channel rate-limit handling + monitoring/alerts on sync lag
```

## Anti-patterns
- Allocated inventory everywhere → oversell or unsold rooms (prefer pooled).
- Pushing ARI without a queue/retry → channels drift out of sync.
- No full-reconcile job → silent drift accumulates.
- Non-idempotent reservation import → duplicate bookings.
- Ignoring OTA rate limits → throttling/suspension.
