---
name: extranet-system
description: >-
  Build a travel supplier extranet. Use when suppliers (hotels, DMCs, transfer/
  activity providers) need a self-service portal to load and manage inventory,
  rates, availability, content, promotions, and contracts. Covers data model,
  rate/allotment management, contracting, roles, and publishing into your CRS.
---

# Extranet System

An extranet is the **supplier-facing portal** where hotels/DMCs/providers load their own
inventory, rates, availability, and content — which then becomes bookable in your platform
(directly, or distributed via the `channel-manager-system`).

## Who uses it & what they do
- **Hotel/DMC/provider** logs in → manages **properties, rooms, rate plans, allotment,
  availability calendar, restrictions, content/photos, promotions, contracts**.
- Your ops team → reviews/approves, sets commissions, audits.

## Data model

```
Supplier (account, currency, payment terms, markets)
 └─ Property (name, address, geo, category, content, amenities, photos)
     └─ RoomType (name, occupancy, count)
         └─ RatePlan (board[BB/HB/FB/AI], refundable?, cancellation policy, market/channel)
             └─ RateCalendar (date → price net, min/max, closed?, stop-sell)
             └─ Allotment (date → rooms available, release days)
Contract (period, board basis, child policy, cancellation rules, special offers)
Promotion (early-bird, last-minute, LOS deal, free-night N-for-M)
```

## Core features

- **Bulk rate/availability editor**: calendar grid, date-range bulk update, copy week/season.
- **Allotment management**: free-sale vs allotment vs on-request; **release period** (cut-off
  days before arrival inventory returns).
- **Restrictions**: MinLOS/MaxLOS, CTA/CTD, stop-sell per date/room/rate.
- **Contracting**: seasons, board basis, child/infant policies, cancellation tiers, special
  offers — the contract drives pricing rules.
- **Content management**: descriptions (multi-language), photos, amenities, policies, geo.
- **Promotions**: early bird, last minute, length-of-stay, free nights, combinable rules.
- **Roles & multi-property**: chain admin vs single-property; approval workflow for changes.

## Publishing pipeline

```
Supplier edits in extranet → validation → (optional approval) → publish to CRS
   → searchable/bookable in B2B/B2C → optionally distributed via channel manager
```
Validate aggressively (overlapping rates, missing cancellation policy, negative allotment,
currency mismatches) **before** publishing.

## Integration options
- **Manual** (extranet UI) for small suppliers.
- **API/file upload** (CSV/XML) for bulk loaders.
- **Channel manager / direct connect** for connected hotels (then extranet is read-mostly).
Bridge with `supplier-api-integration` (inbound) and `mapping-system` (canonical IDs).

## Checklist
```
- [ ] Supplier accounts + multi-property + roles + approval workflow
- [ ] Property/room/rate-plan/contract model with seasons & board basis
- [ ] Calendar bulk editor for rates, availability, restrictions
- [ ] Allotment vs free-sale + release periods
- [ ] Promotions engine (early-bird/last-minute/LOS/free-night)
- [ ] Multi-language + multi-currency content
- [ ] Validation + publish pipeline into CRS; audit log of changes
- [ ] Commission/markup config per supplier (feeds pricing)
```

## Anti-patterns
- No release-period/cut-off logic → selling allotment you can't fulfil.
- Letting suppliers publish without validation (overlaps, missing cancellation policy).
- One rate plan can't express board/cancellation/market variants → model them explicitly.
- No audit trail of who changed rates/availability (disputes are common).
- Free text for board/cancellation instead of structured, machine-usable rules.
