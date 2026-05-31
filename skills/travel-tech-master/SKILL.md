---
name: travel-tech-master
description: >-
  Master hub for Travel & Tourism technology. Use to build OTAs, booking engines,
  tour operator/DMC/TMC systems, bed banks, and hotel tech — supplier/GDS/NDC/bed-bank
  API integration, channel managers, supplier extranets, hotel/room mapping &
  deduplication, and B2B/B2C booking platforms. Bundles 6 specialized skills (in
  skills/<name>/GUIDE.md). Use this for any travel-tech, tourism, OTA, GDS, channel
  manager, extranet, mapping, or B2B/B2C travel platform task.
---

# Travel & Tourism Technology — Master Hub

Use to build travel/tourism systems end-to-end: supplier integration (GDS, NDC, bed banks),
channel managers, supplier extranets, hotel/room mapping, and B2B/B2C booking platforms.

## How to use this hub

This single skill bundles **all 6 travel-tech skills**. Each bundled skill's full instructions
live in `skills/<name>/GUIDE.md` (plus any `scripts/`, `references/` next to it).

**Workflow:**
1. Start with **travel-tech-architecture** for the ecosystem, glossary, and core booking flow.
2. Match the user's request to one or more skills below and read its `GUIDE.md` before acting.
3. Combine skills — most real builds span several (supplier integration + mapping + B2B/B2C).

## Bundled skills

- **travel-tech-architecture** ⭐ — The foundation: travel ecosystem (GDS/NDC/bed banks/CRS/PMS/IBE/CM/extranet), glossary (ARI, PNR, VCC, BSP, OTA/NDC standards), canonical model, and the universal search→recheck→book→confirm flow.  
  → `skills/travel-tech-architecture/GUIDE.md`
- **supplier-api-integration** — Integrate GDS (Amadeus/Sabre/Travelport), NDC airline content, and bed banks (Hotelbeds/TBO/Expedia EAN/WebBeds/GRN) via the adapter pattern: canonical model, search caching, price recheck, idempotent book/cancel, sessions, and resilience.  
  → `skills/supplier-api-integration/GUIDE.md`
- **channel-manager-system** — Distribute a property's ARI to OTAs (Booking.com/Expedia/Agoda) and pull reservations back: per-channel adapters, OTA/connectivity standards, pooled inventory, derived rates, restrictions, overbooking protection, and 2-way sync reliability.  
  → `skills/channel-manager-system/GUIDE.md`
- **extranet-system** — Supplier-facing portal to load/manage inventory, rates, availability, content, promotions, and contracts: data model, calendar bulk editor, allotment/release periods, roles/approval, validation, and publishing into the CRS.  
  → `skills/extranet-system/GUIDE.md`
- **mapping-system** — Match the same hotel/room/board/content across suppliers into one canonical entity: property & room mapping, GIATA/master IDs, geo+name+address fuzzy matching, confidence thresholds, and human-review/QA workflow.  
  → `skills/mapping-system/GUIDE.md`
- **b2b-b2c-booking-platform** — Build the demand side (OTA/IBE, agent portal, tour operator/DMC): pricing engine (markup/commission), agent hierarchy + credit/wallet, multi-currency, payments (customer 3DS + supplier VCC/BSP), itineraries/vouchers, and mid/back office.  
  → `skills/b2b-b2c-booking-platform/GUIDE.md`

## Pairs well with
`backend-api-master` (auth, integrations-pro, Stripe, GIS maps), `business-master`
(accounting-finance for net/sell ledger, white-label for per-agency branding), `ui-master`
(charts-and-dashboards for reporting), and `documents-master` (vouchers/invoices).

## Note

These bundled skills are intentionally not registered as separate Cursor skills (their files are
`GUIDE.md`, not `SKILL.md`) so only this master appears in the skills list. Read the relevant
`GUIDE.md` on demand.
