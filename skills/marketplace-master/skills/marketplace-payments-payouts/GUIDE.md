---
name: marketplace-payments-payouts
description: >-
  Implement marketplace split payments and seller payouts. Use for collecting one
  buyer payment and splitting funds to multiple sellers minus commission — Stripe
  Connect / Adyen / Mangopay / PayPal Marketplace, escrow/hold, commission, payouts,
  refunds/chargebacks, wallets, and compliance (KYC, flow of funds).
---

# Marketplace Payments & Payouts

Collect **one payment** from the buyer and route money to **multiple sellers minus your
commission** — compliantly. This is the hardest money problem in a marketplace.

## Provider options

| Provider | Notes |
|----------|-------|
| **Stripe Connect** ⭐ | Most popular; Express/Standard/Custom accounts, automatic splits, payouts, KYC |
| **Adyen for Platforms** | Enterprise, global acquiring |
| **Mangopay / Lemonway** | EU-focused, e-wallet/escrow model |
| **PayPal Commerce / Marketplaces** | Quick, wide consumer reach |

> Don't move other people's money through your own bank account without a licensed provider —
> it's a regulated activity. Use a provider that handles **flow of funds + KYC**.

## Flow-of-funds patterns (Stripe Connect example)

| Pattern | How | Use |
|---------|-----|-----|
| **Destination charge** | Charge buyer on platform, transfer to seller, take `application_fee` | Most marketplaces |
| **Separate charges & transfers** | Charge then transfer later (per sub-order) | Split shipments / delayed capture |
| **Direct charge** | Charge on the connected account | Seller "owns" the buyer relationship |

```
buyer pays $100 (1 PaymentIntent for the whole cart)
 → platform application_fee = $15 (commission)
 → transfers: Seller A $50, Seller B $35   (per sub-order)
 → payouts to sellers' banks on schedule (instant/daily/weekly)
```

## Escrow / hold
- Hold funds until **delivery confirmed / return window passes**, then release to seller.
- Critical for services/high-value; reduces fraud and refund risk.

## Commission & fees
- Compute per sub-order: gross → platform commission (%/flat/category) → payment fee → taxes →
  **net payout**. Store the full breakdown (auditable). Pair with `accounting-finance` for the ledger.
- Other fees: delivery fee, service fee, small-order fee, ads/promotion — track who they fund.

## Refunds, chargebacks & disputes
- Refund flows back through the original payment; **claw back** the seller's transfer/balance.
- Decide who bears chargebacks (platform vs seller) and reflect in the ledger.
- Reserve/negative-balance handling if a seller's balance can't cover a refund.

## Wallets & buyer credit
- Buyer wallet (refunds-as-credit, top-ups, loyalty); seller balance/wallet with ledger.
- Idempotent ledger entries; never compute balances you can't re-derive.

## Compliance & security
- KYC/KYB via the provider before payouts; sanctions/AML handled by provider.
- **PCI**: never touch raw card data — use provider tokenization/elements.
- 3-D Secure / SCA for cards; idempotency keys on all charge/refund/transfer calls.
- Webhooks: verify signatures, handle idempotently, post to ledger only on confirmed events.

## Checklist
```
- [ ] Pick a licensed provider (Stripe Connect/Adyen/Mangopay) — don't self-custody funds
- [ ] One buyer PaymentIntent per cart + idempotency key
- [ ] Split via destination charge / transfers per sub-order; application_fee = commission
- [ ] Escrow/hold until delivery/return window; scheduled payouts + min threshold
- [ ] Commission breakdown stored + posted to ledger (accounting-finance)
- [ ] Refund + chargeback clawback + negative-balance handling
- [ ] Webhooks verified + idempotent; 3DS/SCA; PCI via provider only
```

## Anti-patterns
- Routing marketplace funds through your own account (unlicensed money transmission).
- Manual payouts / spreadsheets at scale; paying out before the refund window.
- No idempotency on charges/transfers → double charges or double payouts.
- Storing raw card data; trusting unverified webhooks.
- Refunding buyers without clawing back from sellers.
