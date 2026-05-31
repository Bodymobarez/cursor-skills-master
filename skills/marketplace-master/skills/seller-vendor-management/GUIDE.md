---
name: seller-vendor-management
description: >-
  Build seller/vendor management for a marketplace. Use for seller onboarding,
  KYC/verification, the seller dashboard, commission/fee plans, payouts, store
  pages, performance metrics/SLAs, and seller policies. Covers the full supply-side
  lifecycle from signup to payout.
---

# Seller / Vendor Management

Everything supply-side: onboard sellers/restaurants, verify them, give them a dashboard, take
commission, and pay them out reliably.

## Onboarding & KYC

```
Signup → business profile (legal name, type, tax id, address)
       → KYC/KYB verification (ID, business docs; bank account for payouts)
       → agree to seller terms/commission plan
       → store setup (name, logo, banner, policies, shipping/delivery zones)
       → product upload / menu setup → ADMIN APPROVAL → live
```
- Use a KYC/onboarding provider (e.g. **Stripe Connect onboarding**, Persona, Onfido) — don't
  store raw ID docs yourself if avoidable.
- Status machine: `pending → under_review → approved → active → suspended → offboarded`.

## Seller dashboard (build these)
- **Orders**: incoming, accept/reject, prep/ship/deliver status, print labels/invoices.
- **Catalog**: add/edit products or menu, stock toggles, pricing, promotions.
- **Earnings**: sales, commission deducted, payout schedule, statements, tax docs.
- **Performance**: rating, response/ship time, cancellation/defect rate, SLA compliance.
- **Settings**: store profile, hours, delivery zones, bank/payout, staff/roles.
- **Analytics**: sales trends, top products, conversion (pair with `charts-and-dashboards`).

## Commission & fee models

| Model | Use |
|-------|-----|
| **% commission per sale** | Most marketplaces (often per-category rate) |
| **Flat fee per order/listing** | Classifieds, some food apps |
| **Subscription** (seller plan) | Pro seller tiers (e.g. Amazon Pro) |
| **Hybrid** | Subscription + lower % |
| **Surcharges** | Payment fee, delivery fee, service fee, promotion/ads |

Store fees per seller/category; compute commission at order time; keep an auditable breakdown
(gross → fees → net payout). Pair with `marketplace-payments-payouts` + `accounting-finance`.

## Payouts
- Schedule: instant / daily / weekly / on-delivery-confirmed; min threshold; hold for
  return/dispute window before releasing.
- Wallet/balance with ledger; payout to bank (Connect/Mangopay); statements + invoices.
- Handle refunds/chargebacks → clawback from seller balance.

## Performance, SLAs & policies
- Track metrics: rating, on-time ship/prep, accept rate, cancel/defect rate, response time.
- Define SLA thresholds → warnings → throttle visibility → suspension for repeat offenders.
- Policy enforcement: prohibited items, counterfeit, pricing abuse; appeals process.

## Multi-store / staff
- One seller account → multiple branches/stores (food chains); staff roles per store.

## Checklist
```
- [ ] Onboarding flow + KYC/KYB + status state machine + admin approval
- [ ] Seller dashboard: orders, catalog, earnings, performance, settings
- [ ] Commission/fee config (per category/seller) + auditable breakdown
- [ ] Payout engine: schedule, hold window, wallet ledger, statements, clawback
- [ ] Performance metrics + SLA enforcement + suspension/appeals
- [ ] Multi-branch + staff roles; store page for buyers
```

## Anti-patterns
- Manual spreadsheet payouts; no payout hold for refund window → paying out money you'll refund.
- Storing raw KYC/ID docs without compliance (use a provider/vault).
- No performance SLAs → bad sellers hurt buyer trust.
- Commission hard-coded instead of configurable per category/seller.
- No suspension/appeal workflow.
