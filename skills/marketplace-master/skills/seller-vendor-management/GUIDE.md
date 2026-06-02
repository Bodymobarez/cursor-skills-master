---
name: seller-vendor-management
description: >-
  Build the supply side at staff depth — seller onboarding + KYC/KYB via Stripe
  Connect (Accounts v2 / controller properties, hosted Account Links + embedded
  onboarding, capability/requirements gating), a configurable commission engine in
  basis points, payout scheduling with hold/escrow, the seller wallet ledger, SLA/
  performance scoring with auto-suspension, multi-branch + staff RBAC, and payout-
  fraud defenses (bank-change step-up). Gate listing/selling on KYC capability state.
---

# Seller / Vendor Management — Onboarding, Commission, Payouts, SLAs

**Sellers are not users with an extra flag.** A seller is a *legally verified payee* whose ability to
list, sell, and get paid is gated by KYC capability state, commission terms, and performance SLAs.
The supply side is where money-laundering risk, payout fraud, and trust erosion live — so the seller
lifecycle is a state machine with hard gates, not a profile form. Get onboarding + capability gating
right and you can pay sellers programmatically and sleep at night.

---

## 1. Mandate

- **No payout capability → no selling.** Listing and checkout eligibility are gated on the PSP's KYC/capability state, re-checked on `account.updated`. Never let a seller transact before they can receive funds.
- **Commission is configuration, not code** — stored per seller/category in **basis points (integer)**, computed at order time, and written to the ledger as an auditable breakdown.
- **Payouts hold through the refund/dispute window.** Released money is unrecoverable; default to delayed transfer (escrow) and clawback-aware balances.
- **Changing a payout bank account is a Sev-risk event** — step-up auth + cooldown + payout pause.

## 2. When to use / when NOT

**Use when:** building seller signup/KYC; the seller dashboard; commission/fee plans; payout scheduling + wallet; performance/SLA scoring + suspension; multi-branch/staff. **Read with `marketplace-payments-payouts`** (it owns the flow-of-funds; this skill owns the seller-facing lifecycle around it).

**Skip/trim when:** you're the only seller (no marketplace); fewer than ~20 hand-vetted sellers with manual onboarding may not need a full KYC integration yet — but you still need the commission + payout ledger.

## 3. Onboarding & KYC/KYB state machine

```
signup → business profile (legal name, entity type, tax id, address, beneficial owners)
       → KYC/KYB via PSP (Stripe Connect onboarding) — DON'T store raw ID docs
       → accept seller terms + commission plan (versioned)
       → store/menu setup (branding, policies, zones, hours)
       → catalog/menu upload → ADMIN MODERATION
       → capability ENABLED (charges + payouts) → ACTIVE
```

```sql
create table seller_kyc (
  seller_id   uuid primary key references sellers(id),
  provider_account_id text not null,        -- Stripe acct_... (or Adyen/Mangopay)
  charges_enabled  bool not null default false,
  payouts_enabled  bool not null default false,
  requirements_due jsonb not null default '[]',   -- mirror of provider currently_due
  disabled_reason  text,
  updated_at  timestamptz not null default now()
);
```

**Status FSM (mirror provider, don't invent your own truth):**
`pending → under_review → approved → active → (suspended ⇄ active) → offboarded`.
The seller is sellable only when `charges_enabled && payouts_enabled && status='active'`.

## 4. Stripe Connect onboarding (2026 — Accounts v2 / controller properties)

Stripe now steers new platforms to the **Accounts v2 API** and to **controller properties** over the
legacy Standard/Express/Custom *types* (the types still exist as presets and map onto controller
properties). Pick the model deliberately — see `marketplace-payments-payouts` §4 for the full matrix.

```ts
import Stripe from "stripe";
const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!);

// Accounts v1 + controller properties (GA, mainstream): platform pays fees + bears losses,
// Express dashboard for the seller. Maps to the classic "Express" preset.
const account = await stripe.accounts.create({
  country: "AE",
  controller: {
    fees:   { payer: "application" },          // platform collects fees
    losses: { payments: "application" },       // platform bears chargeback losses
    stripe_dashboard: { type: "express" },     // immutable after creation — choose carefully
  },
  capabilities: { card_payments: { requested: true }, transfers: { requested: true } },
  metadata: { seller_id: sellerId },
});

// Hosted onboarding via Account Links (simplest, Stripe-maintained UI):
const link = await stripe.accountLinks.create({
  account: account.id,
  type: "account_onboarding",
  refresh_url: `${APP}/seller/onboarding/refresh`,
  return_url:  `${APP}/seller/onboarding/done`,
});
// → redirect seller to link.url
```

> **Embedded onboarding** (`@stripe/connect-js` + an Account Session with `account_onboarding` in
> `components`) keeps sellers on *your* domain — better conversion, more integration work. Accounts v2
> (`POST /v2/core/accounts`, `Stripe-Version: 2026-01-28.clover`) unifies the connected-account and
> customer identity and uses `configuration.merchant` / `recipient` instead of capabilities-on-create.

**Capability gating (the part that matters):** treat the `account.updated` webhook as the source of
truth. Persist `charges_enabled`/`payouts_enabled`/`requirements.currently_due`; when requirements
appear, surface them and (if `disabled_reason`) pause the seller. Never assume onboarding "stuck" —
poll the account, show the outstanding requirements.

## 5. DECISION MATRIX — commission & fee models

| Model | Use | Implementation note |
|-------|-----|--------------------|
| **% per sale (per-category)** ⭐ | Most marketplaces | Store `commission_bps` per seller *and* per category; category overrides seller default. |
| **Flat fee per order/listing** | Classifieds, some food | Fixed minor-units; stacks with or replaces %. |
| **Subscription (seller tier)** | Pro sellers (Amazon Pro) | Recurring charge to the seller (Billing); often pairs with lower %. |
| **Hybrid** | Mature platforms | Subscription + reduced % + per-order fee. |
| **Surcharges** | Payment, delivery, service, small-order, ads | Track *who funds each* (platform vs seller vs buyer) — critical for payout accuracy. |

```ts
// Commission in basis points → integer math only, no floats. Returns the auditable breakdown.
export function computeCommission(input: {
  itemsSubtotal: number; shipping: number; bps: number; flatFee: number; currency: string;
}): { gross: number; commission: number; netToSeller: number } {
  const { itemsSubtotal, shipping, bps, flatFee } = input;
  const gross = itemsSubtotal + shipping;
  const commission = Math.round((itemsSubtotal * bps) / 10_000) + flatFee; // commission on goods, not shipping (policy)
  return { gross, commission, netToSeller: gross - commission };
}
```

Commission is computed at order time and **frozen onto the sub-order** (don't recompute from
live rates later — rates change). Post `gross → commission → fees → net` to the ledger.

## 6. Payouts & the seller wallet ledger

The PSP moves funds (`marketplace-payments-payouts`); **you** keep the seller balance as a projection
of your double-entry ledger — never trust a number you can't re-derive.

```sql
create table seller_payouts (
  id          uuid primary key default uuidv7(),
  seller_id   uuid not null references sellers(id),
  amount      bigint not null, currency char(3) not null,
  status      text not null default 'pending'
              check (status in ('pending','in_transit','paid','failed')),
  provider_payout_id text,
  period_start timestamptz, period_end timestamptz,
  created_at  timestamptz not null default now()
);
-- Balance = SUM(ledger credits) − SUM(debits) for the seller account, MINUS held + pending payouts.
```

**Schedule options:** instant / daily / weekly / on-delivery-confirmed; **min threshold**; **hold
window** (don't release until the return/dispute window passes — see escrow in payments). **Statements
+ tax docs** per period. Refund/chargeback → clawback from balance (reverse transfer; if balance is
short, carry a negative balance and net future earnings — see payments §9).

## 7. Performance, SLAs & reputation

```ts
// Rolling 30/90-day defect score → drives visibility, payout speed, badges, suspension.
type SellerMetrics = {
  orders: number; lateShipments: number; cancellations: number;
  defects: number; disputes: number; avgRating: number; responseHrs: number;
};
export function defectRate(m: SellerMetrics): number {
  return (m.defects + m.cancellations + m.disputes) / Math.max(m.orders, 1);
}
export function tier(m: SellerMetrics): "top" | "good" | "watch" | "suspend" {
  const d = defectRate(m);
  if (d > 0.10 || m.avgRating < 3.0) return "suspend";       // hard gate
  if (d > 0.05 || m.avgRating < 3.8) return "watch";         // throttle visibility, warn
  if (d < 0.01 && m.avgRating >= 4.7) return "top";          // boost + faster payout
  return "good";
}
```

SLA breach → warning → search throttle → suspension, with a defined **appeals** path. The score feeds
search ranking (`search-discovery-recommendations`) and payout speed. Decay old behavior; reward
consistency. Cross-link the dispute/fraud signals from `reviews-ratings-trust-safety`.

## 8. Multi-branch & staff RBAC

One seller (chain) → many branches (own hours, menu price, zones, inventory); staff have **branch-
scoped roles** (`owner | manager | staff`). Branch is the unit of fulfillment + dispatch (food), so
inventory/availability and courier assignment key off `branch_id`, not `seller_id`.

## 9. Edge cases

- **Bank account change** → step-up auth (re-verify identity/MFA) + payout pause + cooldown before next payout clears. The #1 account-takeover cashout vector.
- **KYC requirements appear post-onboarding** (Stripe adds `currently_due` as volume grows) → surface them, keep selling if `payouts_enabled` still true, else pause.
- **Seller suspended with funds in escrow + open orders** → keep fulfilling open orders, hold payouts, resolve disputes, *then* offboard.
- **Negative balance** (refund > available) → carry negative, net from future sales, escalate to collection if no future volume.
- **Commission plan change** → versioned + effective-dated; in-flight orders keep the rate frozen at order time.
- **Offboarding** → settle final payout after the last return window closes; retain records for tax/audit.

## 10. Performance & scale

- Seller dashboard reads come from **read models / replicas**, never the orders OLTP primary — a seller pulling 90-day analytics must not contend with checkout.
- Pre-aggregate earnings/performance daily (materialized rollups) — see `marketplace-data-platform`.
- Webhook ingestion (`account.updated`, `payout.paid`) is idempotent + queued; don't process inline.

## 11. Security

- **Payout fraud:** bank-change step-up (above); anomaly alerts on payout destination + amount; velocity limits on new sellers.
- **KYC PII:** never store raw ID docs/card data — the PSP/KYC vault holds them; you store status + the provider account id only.
- **Seller isolation:** RLS so a seller's dashboard/API can only read its own orders, payouts, catalog (`marketplace-architecture` §9). Treat IDOR on another seller's payout as Sev-1.
- **Staff least-privilege:** branch-scoped roles; audit log every payout-setting and bank change.

## 12. Observability

- **Onboarding funnel:** signup → KYC submitted → capability enabled → first listing → first sale (drop-off per step, cohort by acquisition).
- **Supply health:** active sellers, % with a sale (liquidity), churn, time-to-first-sale.
- **Money safety:** payout failure rate, negative-balance count + age, clawback volume, escrow held.
- **Quality:** defect-rate distribution, suspensions, appeal turnaround.

## 13. i18n / RTL (MENA)

- **KYB docs differ by market:** Saudi **Commercial Registration (CR)** + VAT cert, UAE **trade license** + Emirates ID, Egypt commercial register + tax card. Map each to the PSP's required fields; some MENA entities need a local acquiring setup or a local PSP (Stripe coverage varies — `payments-master` for regional rails).
- **Payout rails:** IBAN-based bank payouts; verify IBAN format per country; some sellers prefer local wallets.
- **e-Invoicing onboarding:** sellers (or the platform as MoR) need tax IDs captured for ZATCA/Egypt-ETA/UAE-Peppol invoice generation — collect at onboarding (`marketplace-architecture` §14).
- RTL seller dashboard + Arabic statements (`ui-master`).

## 14. Anti-patterns

- **Letting sellers transact before `payouts_enabled`** → you owe money you can't route; reconciliation nightmare.
- **Manual/spreadsheet payouts** at scale; **paying out before the refund window** → refunding money you already sent.
- **Hard-coded commission** instead of per-seller/category config → can't run promos, category economics, or seller deals.
- **Storing raw KYC/ID docs** yourself → compliance + breach liability; use the provider/vault.
- **No bank-change protection** → trivial account-takeover cashout.
- **No SLA/suspension/appeal loop** → bad sellers erode buyer trust unchecked.
- **Trusting the PSP balance as your books** → you can't audit commission or detect drift.

## 15. Agent checklist

```
- [ ] KYC/KYB via PSP (Stripe Connect Accounts v2 / controller properties); no raw docs stored
- [ ] Capability gating: charges_enabled + payouts_enabled from account.updated before selling
- [ ] Onboarding via Account Links (or embedded); persist requirements.currently_due
- [ ] Commission in basis points, per seller/category, frozen onto sub-order at order time
- [ ] Payout schedule + min threshold + HOLD/escrow window; wallet balance = ledger projection
- [ ] Performance/defect score → visibility throttle → suspension + appeals
- [ ] Multi-branch + branch-scoped staff RBAC; branch = fulfillment/dispatch unit
- [ ] Bank-change step-up + payout pause; payout-destination anomaly alerts
- [ ] RLS seller isolation; audit log payout/bank changes
- [ ] MENA: CR/trade-license/tax-id capture, IBAN payouts, e-invoicing tax IDs
```

## References (verify current — 2026)
- Connect account creation + controller properties: https://docs.stripe.com/connect/migrate-to-controller-properties
- Accounts v2 API: https://docs.stripe.com/connect/accounts-v2
- Hosted onboarding (Account Links): https://docs.stripe.com/connect/custom/hosted-onboarding
- Embedded onboarding component: https://docs.stripe.com/connect/embedded-onboarding
- Handling `account.updated` / requirements: https://docs.stripe.com/connect/handling-api-verification

## Related
`marketplace-payments-payouts` (flow of funds, escrow, clawback), `reviews-ratings-trust-safety` (defect signals, fraud), `marketplace-data-platform` (seller analytics) · cross-master: `backend-api-master` (auth/MFA/RBAC), `payments-master` (regional PSP/KYC), `business-master` (accounting-finance)
