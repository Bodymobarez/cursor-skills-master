---
name: marketplace-architecture
description: >-
  Architect a professional multi-vendor marketplace end-to-end. Use as the
  foundation for any marketplace — product (Amazon-style), food/quick-commerce
  (Talabat/Uber Eats-style), services, or rentals. Covers marketplace types,
  the two-sided model, core entities, multi-vendor order flow, tech stack, and
  the build roadmap. Read first, then go to catalog/seller/orders/payments/etc.
---

# Marketplace Architecture

The mental model + roadmap for building a multi-vendor marketplace. Read this first, then go to
the specific skill (catalog, seller management, orders, payments, delivery, search, trust).

## Marketplace types (the model changes by type)

| Type | Example | Key traits |
|------|---------|-----------|
| **Product** | Amazon, Etsy, Noon | Catalog, shipping, multiple sellers per product (buy box), returns |
| **Food / quick-commerce** | Talabat, Uber Eats, Instacart | Local, real-time, **delivery dispatch**, prep time, live tracking, narrow delivery window |
| **Services** | Fiverr, Upwork | Listings = offers, scheduling, escrow, milestones |
| **Rental / booking** | Airbnb | Availability calendar, time-bound inventory, deposits |

> Identify the type first — it dictates inventory, payments, and fulfillment. Amazon ≠ Talabat:
> one optimizes catalog/shipping, the other optimizes **time + geography + dispatch**.

## The two-sided market (always design for both + the operator)

```
SUPPLY (sellers/vendors/restaurants)  ⇄  PLATFORM (you)  ⇄  DEMAND (buyers)
  onboarding, catalog, inventory,         matching, search,    discovery, cart,
  pricing, fulfillment, payouts           trust, payments,     checkout, tracking,
                                          commission, ops      reviews, support
```
Three apps/portals: **buyer** app, **seller/vendor** dashboard, **admin/operator** console
(+ a **courier** app for delivery marketplaces).

## Core domain entities

```
User (buyer) · Seller/Vendor (store/restaurant) · Admin
Catalog: Category/Taxonomy → Product → Variant/SKU → Offer (seller-specific price+stock)
Cart (multi-vendor) → Order → SubOrder per vendor → OrderItem
Payment (split) → Commission → Payout (per seller)
Fulfillment: Shipment | Delivery (courier, zone, tracking)
Review/Rating · Dispute · Wallet · Promotion/Coupon
```

## Multi-vendor order flow (the defining feature)

```
1. Buyer adds items from MULTIPLE vendors to ONE cart
2. Checkout → ONE payment, but order SPLITS into sub-orders per vendor
3. Each vendor fulfills its sub-order independently (ship / prepare+deliver)
4. Platform takes commission; remainder is paid out to each vendor
5. Returns/refunds/disputes handled per sub-order
```
This split (one cart/payment → many vendor sub-orders + payouts) is what makes it a marketplace,
not a single-store shop.

## Tech stack (typical)
- Backend: Postgres (transactions matter), Node/NestJS · Django · Laravel; Redis (cart/cache/queues).
- Search: **Meilisearch / Typesense / Elastic** (see search-discovery skill).
- Payments: **Stripe Connect** / Adyen / Mangopay / PayPal Marketplace (split payouts).
- Frontend: Next.js/React (buyer + dashboards); mobile (React Native/Flutter) for food/delivery.
- Real-time (food): WebSockets/MQTT for order + courier tracking; maps (`gis-maps`, `gps-integration`).

## Build roadmap
```
- [ ] 1. Domain model + multi-tenant seller isolation + RBAC (buyer/seller/admin)
- [ ] 2. Seller onboarding + KYC (seller-vendor-management)
- [ ] 3. Catalog: categories, products, variants, seller offers, inventory (multi-vendor-catalog)
- [ ] 4. Search & discovery (search-discovery-recommendations)
- [ ] 5. Cart → checkout → multi-vendor order split (cart-checkout-orders)
- [ ] 6. Split payments + commission + payouts (marketplace-payments-payouts)
- [ ] 7. Fulfillment: shipping OR delivery dispatch + tracking (delivery-logistics-dispatch)
- [ ] 8. Reviews, ratings, trust & safety, disputes (reviews-ratings-trust-safety)
- [ ] 9. Promotions, wallets, notifications, analytics dashboards
```

## Cross-cutting principles
- **Atomicity**: cart→order→payment→sub-orders→inventory decrement in transactions; idempotent checkout.
- **Money correctness**: track item price, commission, taxes, payout per sub-order (pair with `accounting-finance`).
- **Solve the chicken-and-egg**: seed one side first (often supply) to bootstrap liquidity.
- **Trust is the product**: reviews, verified sellers, buyer protection, dispute resolution.

## Anti-patterns
- Treating it as a single store (no per-vendor sub-orders/payouts) — that's not a marketplace.
- Decrementing inventory at "add to cart" instead of at order/payment.
- One global payment with manual seller payouts (use programmatic split/Connect).
- Ignoring the operator/admin console and the courier app.
- Building product-marketplace patterns for a food app (or vice-versa).
