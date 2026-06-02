---
name: marketplace-promotions-pricing
description: >-
  Build the promotions, coupons, and pricing engine at staff depth — the missing
  money primitive every marketplace needs. Models discount types + deterministic
  stacking, and (critically) WHO FUNDS each discount (platform vs seller vs co-funded)
  so payouts stay correct, plus campaign budget pacing, coupon/referral fraud defenses,
  dynamic/surge pricing, and discount↔refund accounting. Wire funding into the ledger.
---

# Marketplace Promotions & Pricing — Who Funds the Discount?

**A discount is a money movement, so the only question that matters is *whose money*.** A naïve coupon
engine that just subtracts from the order total silently steals from sellers (or from you) at payout
time. The staff-level model: every promotion has an explicit **funding source** (platform / seller /
co-funded), and that funding is posted to the ledger so commission and payouts come out right. Get
that wrong and your sellers revolt, your finance team can't reconcile, and your "growth" promo is an
unbudgeted hole in the P&L.

This is the engine the other skills assume exists when they say "platform-funded vs seller-funded
coupon." It lives between catalog/pricing and checkout/payments.

---

## 1. Mandate

- **Every discount has a funding source** (platform / seller / co-funded), posted to the ledger. Discount math is downstream of funding, not the reverse.
- **Stacking is deterministic and capped.** Defined precedence, max-discount floor, and "exclusive" flags — never "apply everything and hope."
- **Validate at cart *and* re-validate at checkout.** Coupons expire, budgets exhaust, eligibility changes between the two.
- **Treat coupons as an attack surface.** Enumeration, multi-account farming, referral self-dealing — rate-limit, fingerprint, cap.

## 2. When to use / when NOT

**Use when:** building coupons/vouchers, campaigns, seller promotions, free-delivery/BOGO, referral credits, dynamic/surge pricing, or sponsored-listing budgets. **Feeds** `cart-checkout-orders` (apply + re-validate), `marketplace-payments-payouts` (funding → commission/payout), `search-discovery-recommendations` (promoted/sale boosts).

**Skip when:** no discounts at all (rare) — but even a single launch coupon needs the funding + ledger model, so don't hand-roll a `total -= 10`.

## 3. DECISION MATRIX — promotion types & funding

| Type | Example | Typical funder | Note |
|------|---------|----------------|------|
| **Platform welcome/growth coupon** | "AED 25 off first order" | **Platform** | Acquisition cost; never deduct from seller payout |
| **Seller promotion / sale** | "20% off this store" | **Seller** | Reduces seller's net; commission policy on pre- or post-discount price matters |
| **Co-funded campaign** | "Eid sale: split 50/50" | **Both** | Split per agreed ratio; post two funding legs |
| **Free / discounted delivery** | "Free delivery > AED 50" | Platform or seller | Funds the delivery fee line, not goods |
| **BOGO / bundle** | "Buy 2 get 1" | Seller (usually) | Effectively a line-item discount; watch margin |
| **Referral / wallet credit** | "Invite a friend, AED 20" | Platform | Wallet credit, not a price cut; fraud-prone |
| **Loyalty / cashback** | points → credit | Platform | Accrues as a liability; redeem as wallet |

> The funder decides the ledger postings. **Commission base policy** (commission on pre-discount vs
> post-discount price) is a business decision you must encode — it changes seller economics materially.

## 4. Data model

```sql
create table promotions (
  id          uuid primary key default uuidv7(),
  code        text unique,                         -- null = automatic (no code)
  kind        text not null check (kind in ('percent','fixed','free_shipping','bogo','bundle')),
  value       int not null,                         -- percent (bps) or fixed minor-units
  funder      text not null check (funder in ('platform','seller','cofunded')),
  cofund_platform_bps int,                          -- if cofunded: platform's share
  seller_id   uuid references sellers(id),          -- null = platform-wide
  scope       jsonb not null default '{}',          -- {category, product_ids, min_order, first_order_only}
  max_discount bigint,                               -- cap (esp. for percent)
  budget_total bigint, budget_spent bigint default 0,-- campaign budget (minor units)
  per_user_limit int default 1, total_limit int,
  exclusive   bool not null default false,           -- cannot stack with others
  starts_at timestamptz, ends_at timestamptz,
  status text not null default 'active'
);
create table promotion_redemptions (                 -- idempotent: one row per (promo,order)
  promotion_id uuid references promotions(id),
  order_id  uuid not null, user_id uuid not null,
  discount  bigint not null, funded_by_platform bigint not null, funded_by_seller bigint not null,
  created_at timestamptz default now(),
  primary key (promotion_id, order_id)
);
```

## 5. Application engine — compute + fund

```ts
type Line = { sellerId: string; subtotal: number; categoryId: string };
type Applied = { promoId: string; discount: number; platformFunded: number; sellerFunded: number };

// Deterministic: sort by precedence, skip exclusives after one applies, enforce max-discount cap.
export function applyPromotions(lines: Line[], promos: Promo[], user: User): Applied[] {
  const orderTotal = lines.reduce((s, l) => s + l.subtotal, 0);
  const eligible = promos.filter(p => isEligible(p, lines, user, orderTotal));   // scope+limits+budget+window
  eligible.sort(byPrecedence);                       // e.g. fixed before percent; exclusive handled below
  const applied: Applied[] = [];
  let exclusiveUsed = false, runningTotal = orderTotal;
  for (const p of eligible) {
    if (exclusiveUsed) break;
    let raw = p.kind === "percent" ? Math.round((runningTotal * p.value) / 10_000) : p.value;
    if (p.maxDiscount) raw = Math.min(raw, p.maxDiscount);
    raw = Math.min(raw, runningTotal);               // never discount below zero
    if (raw <= 0) continue;
    // Split funding so payouts/commission stay correct:
    const platformFunded = p.funder === "platform" ? raw
      : p.funder === "cofunded" ? Math.round((raw * p.cofundPlatformBps!) / 10_000) : 0;
    applied.push({ promoId: p.id, discount: raw, platformFunded, sellerFunded: raw - platformFunded });
    runningTotal -= raw;
    if (p.exclusive) exclusiveUsed = true;
  }
  return applied;       // checkout records redemptions + ledger funding legs (idempotent on order id)
}
```

**Ledger impact** (`marketplace-payments-payouts` §7): buyer pays `total − discount`; the **funder's
account is debited for its share**. Seller-funded → seller's net drops; platform-funded → platform
marketing expense; the buyer charge is genuinely lower. Never make the buyer pay full and "refund"
the discount — that's a different (worse) flow.

## 6. Budget pacing (campaigns + sponsored)

```ts
// Atomic budget decrement at redemption — the WHERE clause prevents overspend races.
const ok = await sql`
  UPDATE promotions SET budget_spent = budget_spent + ${discount}
   WHERE id = ${promoId} AND (budget_total IS NULL OR budget_spent + ${discount} <= budget_total)
   RETURNING id`;
if (ok.rowCount === 0) reject("PROMO_BUDGET_EXHAUSTED");   // compensate in the checkout saga
```

For always-on campaigns/sponsored listings, **pace** spend across the period (target spend curve;
throttle eligibility as you approach the hourly/daily cap) so budget doesn't burn by noon — same
discipline as ad budget pacing in `search-discovery-recommendations` §9.

## 7. Dynamic & surge pricing

- **Surge** (food/delivery): multiply delivery fee by a zone demand factor when supply < demand — bounded, transparent, time-boxed (ties to dispatch surge, `delivery-logistics-dispatch` §4).
- **Dynamic/rule-based pricing** for sellers (price by demand/competition) — guard against price-gouging + collusion; log every change for audit.
- Keep pricing changes **auditable + reversible**; never silently reprice a placed order.

## 8. Edge cases (the discount↔money minefield)

- **Coupon expires between cart and checkout** → re-validate at checkout; if invalid, recompute total + tell the buyer (don't honor a dead promo or silently charge full).
- **Refund of a discounted item** → refund the **buyer's actually-paid** (post-discount) amount, and unwind funding proportionally: seller-funded discount → seller gets back less clawback; platform-funded → platform absorbs. Get this wrong and refunds leak money.
- **Partial refund with order-level coupon** → re-allocate the discount across remaining items; refund the delta the buyer truly paid.
- **Stacking conflict** → exclusive flag + precedence + max-discount floor (e.g. order can't go below cost).
- **Budget exhausts mid-checkout** → atomic decrement fails → drop the promo, recompute, inform buyer.
- **Free-shipping + seller-funded sale** → fund the right lines (delivery vs goods) separately.

## 9. Performance & scale

- Coupon validation is **hot** — cache promo definitions + per-user redemption counts (Redis); atomic budget/limit decrements in Postgres.
- **Idempotent redemption** keyed by `(promo, order)` so retries don't double-count or double-spend budget.
- Precompute eligibility for automatic promos; don't scan all promotions per cart — index by scope.

## 10. Security & abuse

- **Code enumeration**: rate-limit + don't leak "valid but ineligible" vs "invalid"; high-value codes are signed/opaque, not guessable sequences.
- **Multi-account farming** of welcome coupons → device fingerprint + phone verification + `first_order_only` enforced server-side (`reviews-ratings-trust-safety` fraud signals).
- **Referral self-dealing** → require the referred user to complete a real paid order before credit vests; cap chains; detect circular referrals.
- **Seller-funded abuse**: a seller can't fund a discount that pushes their net negative without consent; cap and confirm.
- **Server-authoritative**: never trust client-computed discounts (mirrors `cart-checkout-orders` §11 anti-tamper).

## 11. Observability — did the promo actually work?

- **Redemption rate, discount depth (% of GMV), per-promo spend vs budget, pacing.**
- **Incrementality / ROI**: did it drive *net-new* orders or just discount orders that would happen anyway? (Holdout groups.)
- **Funding split**: platform vs seller discount expense (a real P&L + seller-relations line).
- **Abuse**: coupon-fraud catch rate, multi-account redemptions blocked, referral fraud.

## 12. i18n / RTL (MENA)

- **Seasonal campaigns are huge**: Ramadan/Eid, White Friday (the MENA "Black Friday", e.g. Noon), national days — model recurring, time-boxed, often co-funded campaigns with big budgets + pacing.
- **Per-market currency + thresholds** (min-order in AED/SAR/EGP); localized promo copy (Arabic, RTL — `ui-master`).
- **COD interaction**: discounts must reconcile against cash collected (`delivery-logistics-dispatch`).
- Localize discount/price formatting via ICU; show savings in the buyer's currency.

## 13. Anti-patterns

- **Subtracting from the order total with no funding source** → silently steals from sellers or your P&L; reconciliation impossible.
- **Charging buyer full price then "refunding" the discount** → fees on the wrong base, ugly accounting.
- **Unbounded stacking** → orders go negative / margins evaporate.
- **No budget cap / no pacing** → a viral coupon burns the quarter's marketing budget by lunch.
- **Validating only at cart** → expired/exhausted promos slip through at checkout.
- **Ignoring discount on refunds** → refund the discounted-away money back to the buyer = double loss.
- **Trusting client-side discount math** → trivial price tampering.

## 14. Agent checklist

```
- [ ] Every promotion has an explicit funder (platform/seller/cofunded) → ledger funding legs
- [ ] Commission base policy (pre- vs post-discount) decided + encoded
- [ ] Deterministic stacking: precedence + exclusive + max-discount cap; never below zero/cost
- [ ] Apply at cart, RE-VALIDATE at checkout (expiry/budget/eligibility)
- [ ] Atomic budget decrement + idempotent redemption (per promo,order); pacing for campaigns
- [ ] Refund unwinds discount + funding proportionally (buyer paid amount, not list)
- [ ] Abuse defenses: enumeration limits, first_order_only, device/phone fingerprint, referral vesting
- [ ] Server-authoritative discount math; cache promos + redemption counts
- [ ] Redemption/depth/ROI/incrementality + funding-split metrics
- [ ] MENA: Ramadan/Eid/White-Friday campaigns, per-market currency, COD reconciliation, RTL
```

## References (verify current — 2026)
- Stripe Coupons/Promotion Codes (mechanics reference): https://docs.stripe.com/billing/subscriptions/coupons
- Budget pacing concepts (ad delivery): https://developers.google.com/google-ads/api/docs/campaigns/budgets
- Referral fraud patterns: https://stripe.com/guides/primer-on-fraud-prevention
- ICU message/number formatting (i18n): https://unicode-org.github.io/icu/userguide/format_parse/numbers/

## Related
`cart-checkout-orders` (apply + re-validate), `marketplace-payments-payouts` (funding → commission/payout, refund unwind), `search-discovery-recommendations` (promoted/sponsored budgets), `seller-vendor-management` (seller-funded consent) · cross-master: `business-master` (accounting-finance), `ui-master` (RTL promo UI)
