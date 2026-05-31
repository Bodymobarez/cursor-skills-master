---
name: marketplace-master
description: >-
  Master hub for building professional multi-vendor marketplaces — product
  (Amazon/Noon/Etsy-style), food & quick-commerce (Talabat/Uber-Eats-style),
  services, and rentals. Covers architecture, multi-vendor catalog, seller
  management, cart/checkout/order-splitting, split payments & payouts, delivery/
  courier dispatch, search/recommendations, and reviews/trust & safety. Bundles 8
  specialized skills (in skills/<name>/GUIDE.md). Use for any marketplace task.
---

# Marketplace Platforms — Master Hub

Use to build professional multi-vendor marketplaces like **Amazon** (products) or **Talabat /
Uber Eats** (food & delivery), plus services and rentals.

## How to use this hub

This single skill bundles **all 8 marketplace skills**. Each bundled skill's full instructions
live in `skills/<name>/GUIDE.md` (plus any `scripts/`, `references/` next to it).

**Workflow:**
1. Start with **marketplace-architecture** for the model, entities, and the multi-vendor order flow.
2. Match the request to one or more skills below and read its `GUIDE.md` before acting.
3. Combine skills — a real marketplace spans most of them.

## Bundled skills

- **marketplace-architecture** ⭐ — Foundation: marketplace types (product/food/services/rental), the two-sided model, core entities, the one-cart→many-sub-orders flow, tech stack, and build roadmap.  
  → `skills/marketplace-architecture/GUIDE.md`
- **multi-vendor-catalog** — Catalog data model: categories/taxonomy, products, variants/SKUs, the product↔offer split + buy box, attributes/facets, inventory, food-menu/modifiers, and bulk import/moderation.  
  → `skills/multi-vendor-catalog/GUIDE.md`
- **seller-vendor-management** — Supply side: onboarding + KYC/KYB, seller dashboard, commission/fee plans, payouts + wallet ledger, performance metrics/SLAs, multi-branch, and policies.  
  → `skills/seller-vendor-management/GUIDE.md`
- **cart-checkout-orders** — Multi-vendor cart, idempotent checkout, splitting one payment into per-vendor sub-orders, order lifecycle state machines (product + food), returns/RMA, cancellations, refunds, and tracking.  
  → `skills/cart-checkout-orders/GUIDE.md`
- **marketplace-payments-payouts** — Split payments & seller payouts via Stripe Connect/Adyen/Mangopay: flow-of-funds patterns, commission/application-fee, escrow/hold, refunds + chargeback clawback, wallets, and compliance (KYC/PCI).  
  → `skills/marketplace-payments-payouts/GUIDE.md`
- **delivery-logistics-dispatch** — Talabat-style on-demand delivery: courier dispatch/assignment, batching, delivery zones, live GPS tracking + ETA, courier & dispatch apps; plus shipping/carrier integration for products.  
  → `skills/delivery-logistics-dispatch/GUIDE.md`
- **search-discovery-recommendations** — Search & discovery: Meilisearch/Typesense/Elastic, typo-tolerant faceted search, ranking/relevance signals, buy box, personalized recommendations, merchandising, and sponsored listings.  
  → `skills/search-discovery-recommendations/GUIDE.md`
- **reviews-ratings-trust-safety** — Reviews/ratings (verified purchase, smart aggregation), moderation (auto + ML/LLM), fraud prevention, buyer/seller protection, disputes/chargebacks, and reputation systems.  
  → `skills/reviews-ratings-trust-safety/GUIDE.md`

## Pairs well with
`backend-api-master` (auth, MFA, Stripe, integrations, GIS maps, GPS), `business-master`
(accounting-finance for the money ledger, white-label for multi-brand), `ui-master`
(charts-and-dashboards for seller/admin analytics), and `ai-mcp-master` (camera-ai-vision +
recommendations).

## Note

These bundled skills are intentionally not registered as separate Cursor skills (their files are
`GUIDE.md`, not `SKILL.md`) so only this master appears in the skills list. Read the relevant
`GUIDE.md` on demand.
