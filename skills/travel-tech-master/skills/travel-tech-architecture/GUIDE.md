---
name: travel-tech-architecture
description: >-
  Understand and architect travel technology systems end-to-end. Use as the
  foundation for any travel/tourism software — OTA, TMC, tour operator, DMC, bed
  bank, or hotel tech. Covers the ecosystem (GDS, NDC, bed banks, channel manager,
  extranet, CRS/PMS/IBE, mapping), core flows (search→book→ticket/voucher), and
  the glossary so the agent speaks travel-tech correctly.
---

# Travel Tech Architecture

The mental model + glossary for building travel/tourism systems. Read this first, then go to the
specific skill (supplier integration, channel manager, extranet, mapping, B2B/B2C).

## The ecosystem (who talks to whom)

```
            CONTENT / SUPPLY                      DISTRIBUTION / DEMAND
  Airlines ──(GDS / NDC)──┐                ┌── B2C website / app (end traveller)
  Hotels (PMS) ──(CM)─────┤                ├── B2B agent portal (sub-agents, TMCs)
  Bed banks / wholesalers ┼─►  YOUR        ┼── White-label partners (see white-label)
  Car / transfer / activity│   PLATFORM ───┤── OTAs / metasearch (you as supplier)
  Cruise / rail ───────────┘  (CRS + IBE)  └── API out (XML/JSON to your B2B clients)
                                  │
                          Mapping · Caching · Markup/Rules · Payments · Mid-office
```

## Key systems & acronyms (glossary)

| Term | Meaning |
|------|---------|
| **GDS** | Global Distribution System — Amadeus, Sabre, Travelport (air/hotel/car content) |
| **NDC** | New Distribution Capability — IATA XML standard for rich airline content/offers |
| **Bed bank / wholesaler** | Hotel aggregator supplier — Hotelbeds, TBO, WebBeds, EAN/Expedia Rapid, GRN |
| **OTA** | Online Travel Agency (Booking.com, Expedia, Agoda) — and the **OpenTravel Alliance** XML schema |
| **CRS** | Central Reservation System — owns inventory/rates/bookings |
| **PMS** | Property Management System — the hotel's on-site system |
| **IBE / booking engine** | Internet Booking Engine — the search+book front end |
| **CM** | Channel Manager — distributes ARI from a property to many OTAs (see channel-manager) |
| **Extranet** | Portal where suppliers load inventory/rates/content (see extranet-system) |
| **ARI** | Availability, Rates & Inventory — the data a CM/extranet syncs |
| **Mapping** | Matching the same hotel/room/content across suppliers (see mapping-system) |
| **PNR** | Passenger Name Record (air booking) ; **BSP** = billing settlement (IATA) |
| **VCC** | Virtual Credit Card — pay suppliers securely per booking |
| **Mid/Back office** | Post-booking ops: ticketing, vouchers, invoicing, reconciliation |
| **DMC / TMC** | Destination / Travel Management Company |
| **Markup / commission** | Rules that turn net (supplier) price into sell price |

## Core booking flow (universal)

```
1. SEARCH   — fan out to suppliers (cache!), normalize results, map duplicates, rank
2. PRICE/RECHECK — re-validate price+availability before booking (rates change fast)
3. BOOK     — create reservation with supplier; hold/confirm; idempotent
4. PAY      — customer pay (B2C) or credit/wallet (B2B); pay supplier (VCC/BSP)
5. CONFIRM  — issue ticket (air PNR) / voucher (hotel) ; itinerary + docs
6. POST     — amendments, cancellations, refunds, reconciliation, reporting
```

## Architecture principles (travel-specific)

- **Normalize everything**: each supplier returns different schemas → map to ONE canonical model
  (hotel, room, rate plan, board, cancellation policy, pax, segment).
- **Cache search, never cache booking price**: cache supplier search results (minutes) for speed,
  but **always re-price/recheck** at booking time (rates & availability are volatile).
- **Async fan-out** to suppliers with per-supplier timeouts; return partial results fast.
- **Idempotency** on book/cancel (network retries must not double-book).
- **Resilience**: suppliers are flaky — circuit breakers, retries, graceful degradation.
- **Money**: store net + markup + sell + currency; multi-currency with FX; supplier in net,
  customer in sell. (Pair with `accounting-finance`.)
- **Mid-office** is not optional: queues for ticketing, failed bookings, amendments, refunds.

## Standards & protocols you'll meet
- **OTA (OpenTravel) XML** — classic hotel/air messaging (OTA_HotelAvailRQ/RS, OTA_HotelResRQ…).
- **NDC XML** (IATA) — airline offers/orders (AirShoppingRQ, OfferPriceRQ, OrderCreateRQ).
- **JSON REST** — modern bed banks (Hotelbeds APITude, EAN Rapid, TBO).
- **Booking.com / Expedia connectivity** — for channel-manager distribution.

## Where to go next
- Connecting suppliers/GDS/NDC/bed banks → **supplier-api-integration**
- Distributing a property's ARI to OTAs → **channel-manager-system**
- Letting suppliers load inventory/rates → **extranet-system**
- Deduping hotels/rooms across suppliers → **mapping-system**
- Building the agent/customer booking product → **b2b-b2c-booking-platform**

## Anti-patterns
- One giant per-supplier code path instead of a canonical model + adapters.
- Booking on a cached/stale price without a recheck step.
- Synchronous serial calls to every supplier (slow, fragile) — fan out async.
- No idempotency/mid-office → duplicate bookings and stuck reservations.
- Mixing net/sell currencies without explicit FX + markup rules.
