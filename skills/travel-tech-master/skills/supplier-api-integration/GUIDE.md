---
name: supplier-api-integration
description: >-
  Integrate travel supplier APIs and normalize them. Use to connect GDS (Amadeus,
  Sabre, Travelport), NDC airline content, and hotel bed banks/wholesalers
  (Hotelbeds, TBO, Expedia EAN/Rapid, WebBeds, GRN), plus transfers/activities/car.
  Covers the adapter pattern, canonical model, search caching, price recheck,
  booking/cancel, and resilience.
---

# Supplier / GDS / NDC / Bed-bank Integration

Connect many travel suppliers behind **one canonical model** using per-supplier adapters.

## Adapter pattern (the core)

```
SupplierAdapter (interface):
  search(criteria)        → canonical Offer[]
  recheck(offerRef)       → canonical Offer (fresh price/avail)
  book(offer, pax, pay)   → canonical Booking (supplier ref)
  cancel(bookingRef)      → CancelResult
  details/voucher(ref)    → docs
Implementations: AmadeusAdapter, SabreAdapter, HotelbedsAdapter, EanRapidAdapter, TboAdapter, NdcAdapter…
Registry maps supplier_id → adapter. Core code only ever sees the canonical model.
```

## Supplier landscape

| Category | Suppliers | Protocol |
|----------|-----------|----------|
| **Air GDS** | Amadeus, Sabre, Travelport | SOAP/XML (+ REST), session/PCC |
| **Air NDC** | Airline NDC APIs / aggregators (Duffel, Travelfusion) | IATA NDC XML / JSON |
| **Hotel bed banks** | Hotelbeds (APItude), TBO, WebBeds, Expedia **EAN/Rapid**, GRNConnect, Restel | REST JSON / OTA XML |
| **Transfers/Activities** | Hotelbeds Activities, Musement, GetYourGuide | REST JSON |
| **Car / Rail / Cruise** | CarTrawler, Rail providers | REST/XML |

## Canonical model (normalize to this)

```
HotelOffer { hotelId(canonical), supplier, rooms[ { roomType, ratePlan, board,
  occupancy, price{net,currency}, cancellationPolicy[], nonRefundable, rateKey } ],
  expiresAt }
FlightOffer { segments[], fareBasis, pax[], baggage, price{net,currency}, fareRules, offerId }
```
Map supplier board codes (BB/HB/FB/AI), room types, and cancellation policies to your enums.
Use `mapping-system` to unify hotel/room IDs across suppliers.

## Search → recheck → book

```
SEARCH:  async fan-out to selected suppliers, per-supplier timeout (e.g. 5–8s),
         return partial results; CACHE results (short TTL) keyed by criteria
RECHECK: before booking, call supplier price-check with the rateKey/offerRef
         (rates expire — never book on the cached price)
BOOK:    send pax + payment; pass an IDEMPOTENCY key; store supplier booking ref + raw payload
CANCEL:  read cancellation policy/penalty first; call cancel; store result + refund amount
```

## Resilience (suppliers are flaky)
- Per-supplier **timeout + retry (idempotent reads only)** + **circuit breaker**.
- **Rate limits / concurrency caps** per supplier credentials; queue overflow.
- **Session/token management** (GDS sessions, OAuth tokens) with refresh + pooling.
- Log raw request/response (redact PII/cards) for dispute/debug; correlation id end-to-end.
- Graceful degradation: one supplier down ≠ whole search fails.

## Credentials & config
- Per-supplier secrets in a vault; per-environment (test/cert/prod) endpoints.
- Many suppliers require **certification** before prod — track cert status per supplier.
- Test/sandbox data differs from prod — keep fixtures.

## Checklist
```
- [ ] Adapter interface + canonical model + supplier registry
- [ ] Map board/room/cancellation/fare codes to your enums
- [ ] Async fan-out search + short-TTL cache + partial results
- [ ] Mandatory price recheck before book
- [ ] Idempotent book/cancel; store supplier ref + raw payloads (redacted)
- [ ] Timeouts, retries, circuit breaker, rate-limit per supplier
- [ ] Session/token pooling (GDS/OAuth); credentials in vault
- [ ] Supplier certification tracking; sandbox vs prod endpoints
```

## Anti-patterns
- Leaking supplier-specific shapes into core/business logic (always normalize).
- Booking on cached price without recheck → price/avail failures.
- No idempotency → duplicate PNRs/reservations on retry.
- Storing raw card/passport data unredacted in logs.
- Serial supplier calls; no circuit breaker → one slow supplier stalls everything.
