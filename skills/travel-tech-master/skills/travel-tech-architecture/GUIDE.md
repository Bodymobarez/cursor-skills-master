---
name: travel-tech-architecture
description: >-
  The architectural foundation for any travel/tourism system (OTA, TMC, tour operator, DMC,
  bed bank, hotel tech) at staff/principal depth. Defines the supply↔demand ecosystem, the
  canonical domain model (Money in minor units, Offer/RatePlan/CancellationPolicy/Booking
  state machine), the universal search→recheck→book→pay→confirm flow, multi-currency/FX,
  idempotency, the 2026 standards map (OTA/OpenTravel, NDC 21.3, EDIFACT), PCI/PII scope, and
  look-to-book economics. Read this first; every other travel-tech skill builds on this model.
---

# Travel Tech Architecture

**Mandate: normalize everything into ONE canonical model, cache the search but never the booking
price, and make money + booking state explicit and idempotent from day one.** Every travel platform
that fails does so for the same reasons — supplier shapes leaked into business logic, a booking made
on a stale price, floating-point money, or a half-finished booking with the customer charged and no
supplier reference. Decide the model here, before you write an adapter.

## When to use this skill
- **Use first**, always — it sets the vocabulary, the canonical types, and the flow the other skills assume.
- Use when scoping an OTA/IBE, agent portal, tour operator/DMC/TMC, bed bank, or channel manager.
- **Don't** treat it as code to copy wholesale; it's the *model*. The runnable adapters/sagas/pricing
  live in `supplier-api-integration`, `booking-orchestration`, `b2b-b2c-booking-platform`.

## The ecosystem (who talks to whom)

```
            CONTENT / SUPPLY                         DISTRIBUTION / DEMAND
  Airlines ──(GDS EDIFACT / NDC 21.3)──┐        ┌── B2C web/app (end traveller)
  Hotels (PMS) ──(Channel Manager)─────┤        ├── B2B agent portal (sub-agents, TMCs, corporates)
  Bed banks / wholesalers ─────────────┼─► YOUR ┼── White-label partners (per-tenant branding)
  Transfers / activities / car / rail  │  CRS + ┤── Metasearch (Google/Trivago/Kayak) — you = supplier
  Direct contracts (via Extranet) ─────┘  IBE ──┴── API-OUT (XML/JSON) to your own B2B clients
                                            │
              Mapping · Search Cache · Pricing/Markup · Payments · Booking Saga · Mid-office
```

The middle band is *your* IP. The edges are commodities you integrate. Most teams over-invest in edges
and under-invest in the middle (mapping, cache, pricing, saga) — invert that.

## DECISION MATRIX — which supply channel for which content

| Channel | Content | Price model | Booking model | Settlement | Latency / L2B pressure | Use when |
|---------|---------|-------------|---------------|------------|------------------------|----------|
| **GDS (Amadeus/Sabre/Travelport)** | Air (also hotel/car) — broadest schedules | Published/negotiated fares, EDIFACT | PNR, ticket within time limit | **BSP/ARC** | High volume, strict look-to-book | Air-heavy OTA/TMC needing global reach |
| **NDC (airline direct, 21.3)** | Rich air: branded fares, ancillaries, continuous pricing | Airline offer (dynamic) | **Order** (OrderCreate→OrderView) | Airline / agg | Per-airline onboarding cost | Branded fares, ancillaries, NDC mandates |
| **Bed bank / wholesaler (Hotelbeds/TBO/EAN/WebBeds)** | Hotels (+activities/transfers) | **Net** (you mark up) | Instant confirm / on-request | **VCC** or credit line | Hard L2B caps + penalties | Fast hotel breadth without contracting |
| **Direct contract (via Extranet)** | Your contracted hotels/DMCs | Net, your margin | Allotment / free-sale | Bank transfer / VCC | You own throttle | Best margin, exclusive product |
| **Channel Manager (you = supplier)** | Push *your* ARI to OTAs | Sell (your rate) | OTA reservation pull | OTA collects/you collect | OTA rate limits | You own inventory, want OTA distribution |

> Most platforms blend all of these. The canonical model below is what makes that blend possible.

## Glossary (speak travel-tech correctly)

| Term | Meaning |
|------|---------|
| **GDS** | Global Distribution System — Amadeus, Sabre, Travelport. Air/hotel/car via **EDIFACT** + REST. |
| **NDC** | New Distribution Capability — IATA XML standard; **21.3** is the milestone schema (Offer/Order model). |
| **Bed bank / wholesaler** | Hotel aggregator supplying **net** rates — Hotelbeds, TBO, WebBeds, Expedia EAN/Rapid, GRNConnect, Restel. |
| **OTA** | Online Travel Agency (Booking.com, Expedia, Agoda) **and** the OpenTravel Alliance XML schema (`OTA_Hotel*RQ/RS`). |
| **CRS / PMS / IBE** | Central Reservation System / Property Management System / Internet Booking Engine. |
| **ARI** | Availability, Rates & Inventory — the payload a channel manager/extranet syncs. |
| **PNR / Order** | Passenger Name Record (EDIFACT/GDS air) vs NDC **Order** (the modern equivalent). |
| **BSP / ARC** | Billing & Settlement Plan (IATA, global) / Airlines Reporting Corp (US) — air ticket settlement. |
| **VCC** | Virtual Credit Card — single-use card to pay a supplier per booking (bed banks). |
| **Look-to-book (L2B)** | Searches ÷ bookings. Suppliers cap it; breach → throttling, fees, or suspension. |
| **GIATA ID** | Industry hotel master ID used to dedupe the same property across suppliers (see `mapping-system`). |
| **DMC / TMC** | Destination Management Company / Travel Management Company (corporate travel). |
| **Net / markup / sell** | Supplier price / your rule-based uplift / customer price. Store all three. |

## Canonical domain model (normalize to THIS)

The single most important code in your platform. Every adapter maps *into* these types; core logic
never sees a supplier shape.

```ts
// Money is ALWAYS integer minor units + ISO-4217. Never float, never bare number.
export interface Money { amount: number; currency: string; } // amount = cents/fils/etc.
export const money = (amount: number, currency: string): Money => ({ amount: Math.round(amount), currency });

export type Board = "RO" | "BB" | "HB" | "FB" | "AI"; // room-only, B&B, half/full board, all-inclusive
export type CancellationType = "FREE_UNTIL" | "NON_REFUNDABLE" | "PARTIAL";

export interface CancellationPolicy {
  // Structured & machine-usable — NEVER free text. Penalties are absolute Money, not %, at read time.
  segments: Array<{ from: string /* ISO datetime, supplier TZ resolved to UTC */; penalty: Money }>;
  refundableUntil?: string; // ISO; absent => non-refundable
  type: CancellationType;
}

export interface RatePlan {
  rateKey: string;            // opaque supplier token used for recheck+book (DO NOT parse/derive)
  board: Board;
  occupancy: { adults: number; children: number; childAges?: number[] };
  net: Money;                 // supplier price (B2B/internal only)
  cancellation: CancellationPolicy;
  nonRefundable: boolean;
  payAtHotel: boolean;
  opaque?: boolean;           // e.g. Hotelbeds "packaging" rates — only sellable when bundled
  expiresAt: string;          // ISO — after this, recheck is mandatory
}

export interface HotelOffer {
  canonicalHotelId: string;   // from mapping-system, NOT the supplier id
  supplier: string;           // "hotelbeds" | "tbo" | "ean" | direct contract id
  supplierHotelId: string;
  rooms: Array<{ canonicalRoomId?: string; supplierRoomName: string; ratePlans: RatePlan[] }>;
  searchedAt: string;
}

export type BookingStatus =
  | "QUOTED" | "RECHECKED" | "PENDING" | "CONFIRMED"
  | "ON_REQUEST" | "FAILED" | "CANCELLED" | "REFUNDED";

export interface Booking {
  id: string;                 // YOUR id (idempotency anchor)
  status: BookingStatus;
  supplierRef?: string;       // PNR / confirmation no / itinerary id
  pricing: { net: Money; markup: Money; sell: Money; fx?: { rate: number; at: string } };
  items: Array<HotelOffer | FlightOffer>;
  pax: Pax[];
  createdAt: string;
}

export interface Pax {
  type: "ADT" | "CHD" | "INF";
  firstName: string; lastName: string; dob?: string;
  // Passport/document fields are PII — encrypt at rest, mask in logs (see Security).
  document?: { type: "PASSPORT"; number: string; expiry: string; nationality: string };
}

export interface FlightOffer {
  offerId: string;            // Amadeus offer / NDC OfferID / Sabre itinerary token
  segments: Array<{ from: string; to: string; dep: string; arr: string; carrier: string; flight: string; cabin: string; rbd: string }>;
  fareBasis: string;
  net: Money;
  fareRules: { refundable: boolean; changeable: boolean; lastTicketingDate?: string };
}
```

Map supplier board codes, room names, cancellation tiers, and fare classes into these enums/types at the
adapter boundary. Unmapped values go to a review queue — never silently dropped.

## The universal flow (memorize this)

```
1. SEARCH   fan-out to suppliers (async, per-supplier timeout) → normalize → map (dedupe) → rank
            ↳ CACHE results (short TTL, minutes) keyed by canonical criteria
2. RECHECK  re-price+re-check availability on the chosen rateKey/offerId BEFORE booking
            ↳ price drift / sold-out handled here, not at payment
3. BOOK     create supplier reservation with an IDEMPOTENCY KEY; persist supplierRef + raw payload
4. PAY      customer-in (3DS/SCA) or B2B credit/wallet hold; supplier-out (VCC / BSP)
5. CONFIRM  issue ticket (PNR/Order) or voucher; generate itinerary + documents; notify
6. POST     amend / cancel (penalty from policy) / refund / reconcile net-vs-sell / report
```

**The two non-negotiable rules:**
1. **Cache search, never cache booking price.** Search results are a hint for ranking and UX; the rate you
   *charge* must come from a fresh recheck (Hotelbeds CheckRates, Amadeus Flight Offers Price, Expedia Price
   Check, Sabre Revalidate). Skipping recheck is the #1 cause of "price changed at payment" disputes and, in
   regulated markets (e.g. UK Package Travel Regs), a compliance breach.
2. **Booking is a saga, not a transaction.** Steps 3–5 span multiple systems with no shared commit. Use the
   state machine + idempotency + compensation in `booking-orchestration`. Charging before a confirmed
   `supplierRef` (or vice-versa without compensation) creates orphaned money or orphaned reservations.

## Money & multi-currency (get this wrong once, lose trust forever)

- **Minor units + ISO-4217**, integer math only. JPY/KWD/BHD have 0 or 3 decimals — never hardcode 2.
- Store **net + markup + sell + the FX rate and timestamp** used. Supplier settles in net currency; customer
  pays in sell currency; the spread is your margin and must reconcile (see `b2b-b2c-booking-platform`).
- Pin the FX rate at quote time and carry it through booking — never re-derive at capture (rates move).
- Round **once**, at the sell boundary, per a documented policy (e.g. round-half-up to the display currency's
  minor unit). Inconsistent rounding = pennies of drift × millions of bookings = an unreconcilable ledger.

## Standards & protocols you'll meet (2026)

| Standard | Where | Notes |
|----------|-------|-------|
| **OpenTravel (OTA) XML** | Hotels, channel managers | `OTA_HotelAvailNotifRQ`, `OTA_HotelRateAmountNotifRQ`, `OTA_HotelResNotifRQ` — Booking.com connectivity is OTA-style. |
| **NDC XML (IATA 21.3)** | Airline-direct | `AirShopping → OfferPrice → OrderCreate → OrderView`; `OrderChange/Cancel`; Seller-generated **Correlation ID** ties the flow. |
| **EDIFACT** | Classic GDS | Legacy but everywhere; usually hidden behind the GDS's REST/SOAP facade. |
| **REST/JSON** | Modern bed banks | Hotelbeds APItude, Expedia Rapid v3, Amadeus Self-Service, Duffel (NDC-as-API). |

## Production concerns (every travel system needs these)

- **Performance:** async fan-out with `Promise.allSettled` + per-supplier timeout; short-TTL search cache;
  return partial results fast; never block the whole search on the slowest supplier. (Detail: `supplier-api-integration`.)
- **Security / PCI:** keep raw PANs out of your systems — tokenize via PSP; passport/DOB are PII (encrypt at
  rest, mask in logs). VCCs reduce supplier-side card exposure. Minimize PCI scope (SAQ A where possible).
- **Reliability / scale:** suppliers are flaky — timeouts, retries (idempotent reads only), circuit breakers,
  graceful degradation. Respect **look-to-book** caps; a runaway crawler can get your credentials suspended.
- **Observability:** track **look-to-book ratio**, search latency p50/p95/p99 per supplier, recheck-price-drift
  rate, booking funnel conversion, supplier confirm/timeout/fail rates, and net-vs-sell reconciliation gap.
- **Testing:** every serious supplier has a sandbox/cert environment (Amadeus test, Hotelbeds `api.test`,
  Sabre CERT). Record real responses as fixtures; replay in contract tests. Track per-supplier cert status.
- **i18n / RTL / currency:** content is multi-language (Arabic/Hebrew need RTL; pair `ui-master`); display
  currency ≠ settlement currency; localize dates (no ambiguous MM/DD), names, and address formats.

## Where to go next
- Connect suppliers (GDS/NDC/bed banks) → **supplier-api-integration**
- Orchestrate the booking saga (idempotency/compensation/PNR lifecycle) → **booking-orchestration**
- Distribute a property's ARI to OTAs → **channel-manager-system**
- Let suppliers load inventory/rates → **extranet-system**
- Dedupe hotels/rooms across suppliers → **mapping-system**
- Build the agent/customer product (pricing/credit/payments) → **b2b-b2c-booking-platform**

## Anti-patterns
- One giant per-supplier code path instead of canonical model + adapters → unmaintainable, untestable.
- Booking on a cached/search price without a recheck step → price disputes, failed books, compliance risk.
- Floating-point money, single-currency assumptions, or storing only the sell price → unreconcilable ledger.
- Treating booking as a DB transaction → charged customers with no supplier reference (or vice-versa).
- Synchronous serial supplier calls → one slow supplier stalls the whole search.
- Free-text board/cancellation instead of structured enums/policy → can't price, can't refund correctly.

## Checklist
```
- [ ] Canonical model (Money minor-units, Offer, RatePlan, CancellationPolicy, Booking state machine)
- [ ] Every supplier maps INTO canonical types at the adapter boundary; unmapped → review queue
- [ ] Search cached (short TTL); recheck mandatory before book/charge
- [ ] Booking modeled as a saga with idempotency + compensation (not a transaction)
- [ ] net + markup + sell + FX rate/timestamp persisted; rounding policy documented
- [ ] PCI scope minimized (PSP tokenization); passport/PII encrypted + masked in logs
- [ ] Look-to-book + latency + reconciliation observability in place
- [ ] Per-supplier sandbox/cert tracked; fixtures recorded for contract tests
```

## References (2026-current)
- IATA NDC 21.3 Implementation Guide: https://guides.developer.iata.org
- OpenTravel Alliance schemas: https://opentravel.org
- Amadeus for Developers (Self-Service + Enterprise): https://developers.amadeus.com
- ISO 4217 currency minor units: https://www.iso.org/iso-4217-currency-codes.html

## Related
`supplier-api-integration`, `booking-orchestration`, `channel-manager-system`, `extranet-system`,
`mapping-system`, `b2b-b2c-booking-platform`; pairs with `backend-api-master`, `accounting-finance` (business-master), `documents-master`.
