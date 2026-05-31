---
name: b2b-b2c-booking-platform
description: >-
  Build B2B and B2C travel booking platforms. Use for an OTA/IBE, travel agent
  portal, tour operator or DMC system — search & booking engine, markup/commission
  rules, agent credit/wallet, multi-currency, payments (incl. supplier VCC/BSP),
  itineraries/vouchers, and mid/back office. Builds on the other travel-tech skills.
---

# B2B / B2C Booking Platform

Build the demand side: a booking engine that serves **B2C** (end travellers) and **B2B** (travel
agents, sub-agents, TMCs) on top of your supplier/CRS layer.

## B2C vs B2B differences

| Aspect | B2C | B2B |
|--------|-----|-----|
| User | End traveller | Agent / sub-agent / corporate |
| Price | Sell price (markup baked in) | Net + agent markup; sees commission |
| Payment | Card / wallet / pay-later | **Credit limit / deposit wallet** + invoice |
| Pricing rules | Promotions, coupons | Tiered markup per agent/group, contracts |
| Hierarchy | Single user | Agency → sub-agents → users (roles, limits) |
| Docs | Voucher/e-ticket to traveller | Agent vouchers, statements, invoices |

## Search → book (reuses supplier layer)

```
SEARCH → fan-out via supplier-api-integration → map (mapping-system) → apply PRICING RULES →
present → RECHECK price → BOOK with supplier → PAY → CONFIRM (voucher/ticket) → mid-office
```

## Pricing engine (markup / commission)

```
net (supplier) → + markup rule(s) → + taxes/fees → sell price
Rules by: market, channel(B2C/B2B), agent tier, supplier, product type, date, % or flat.
B2B: store net + commission visible to agent; B2C: hide net, show sell only.
Rule precedence + combinability must be explicit. Round per policy. Multi-currency w/ FX.
```

## B2B essentials
- **Agent hierarchy**: agency → sub-agencies → users, with roles & per-node markup.
- **Credit & wallet**: credit limit, available balance, deposits, top-ups, holds on booking,
  auto-block when exceeded; statements & reconciliation. (Pair with `accounting-finance`.)
- **Markup management UI** per agent/group; negotiated/contracted fares.
- **API out**: expose your inventory to B2B clients (XML/JSON) — you become their supplier.
- White-label per agency (pair with `white-label-platform`).

## B2C essentials
- Fast search UX, filters, maps (`gis-maps`), reviews; promotions/coupons; loyalty.
- Multiple payment methods; 3-D Secure; pay-later/installments; abandoned-cart recovery.

## Payments
- **Customer in**: cards (3DS), wallets, BNPL; PCI — use a PSP (pair with Stripe skills).
- **Supplier out**: **Virtual Credit Cards (VCC)** per booking for bed banks; **BSP/ARC** for
  air ticketing; bank transfer for contracted suppliers. Reconcile net vs sell margin.

## Mid / back office (don't skip)
- Booking queues: pending, failed, on-request, amendment, cancellation, refund.
- Ticketing/voucher issuance; document generation (itinerary, voucher, invoice — see
  `documents-master`); email/notifications.
- Cancellation with penalty calc from policy; refund workflow; supplier reconciliation; reporting
  (sales, margin, top suppliers/agents — pair with `charts-and-dashboards`).

## Checklist
```
- [ ] Canonical search+book on supplier-api-integration + mapping-system
- [ ] Pricing engine: markup/commission rules, precedence, multi-currency FX
- [ ] B2C: payments (3DS), promos/coupons, itinerary/voucher
- [ ] B2B: agent hierarchy, roles, per-tier markup, credit/wallet + statements
- [ ] B2B API-out (XML/JSON) + white-label
- [ ] Supplier payment (VCC/BSP) + margin reconciliation
- [ ] Mid-office queues (fail/on-request/amend/cancel/refund) + docs + notifications
- [ ] Reporting & dashboards; audit log; idempotent booking
```

## Anti-patterns
- Markup logic scattered in code instead of a configurable rule engine.
- Showing net price to B2C / exposing supplier identity.
- No credit-limit enforcement at booking time (agents overspend).
- Skipping price recheck before charging the customer.
- No mid-office → failed/on-request bookings silently lost.
- Single-currency assumptions; rounding applied inconsistently.
