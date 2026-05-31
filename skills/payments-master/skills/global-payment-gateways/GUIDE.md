---
name: global-payment-gateways
description: >-
  Integrate global/international payment gateways and PSPs. Use to accept cards
  and local methods worldwide via Stripe, Adyen, PayPal/Braintree, Checkout.com,
  Worldpay, Authorize.Net, Square, Razorpay, Mollie, Klarna, 2Checkout, Amazon
  Pay, etc. Covers provider selection, integration patterns, local payment methods,
  and per-provider notes.
---

# Global Payment Gateways

Integrate worldwide PSPs behind your `payments-architecture` adapter layer. Pick by market,
methods, pricing, and payout reach.

## Provider selection

| Provider | Best for | Notes |
|----------|----------|-------|
| **Stripe** ⭐ | Global SaaS/e-com, devs | Best DX; Payment Intents + Elements; many local methods; Connect for marketplaces |
| **Adyen** | Enterprise, omnichannel, global | Single platform acquiring; great for scale |
| **PayPal / Braintree** | Consumer reach, wallets | PayPal + cards + Venmo; Braintree = card API |
| **Checkout.com** | Global enterprise, MENA presence | Strong in EMEA/MENA |
| **Worldpay / FIS** | Large merchants | Broad acquiring |
| **Authorize.Net** | US SMB | Mature, US-centric |
| **Square** | US/retail + POS | Online + in-person |
| **Razorpay** | India | UPI, cards, netbanking, wallets |
| **Mollie** | Europe | iDEAL, SEPA, Bancontact, cards |
| **Klarna / Afterpay** | BNPL (buy-now-pay-later) | Installments |
| **2Checkout (Verifone) / Paddle** | Merchant-of-record, global tax | They handle VAT/tax for you |
| **Amazon Pay** | Amazon customers | Wallet + address book |

> **Merchant-of-record** (Paddle, Lemon Squeezy, 2Checkout): they become the seller, handle global
> tax/VAT/compliance — great for digital goods/SaaS selling worldwide without tax headaches.

## Local payment methods (cards aren't enough globally)

| Region | Key methods |
|--------|-------------|
| Europe | SEPA Direct Debit, iDEAL (NL), Bancontact (BE), SOFORT, Przelewy24 (PL), Giropay |
| LATAM | **PIX** (Brazil instant), Boleto, OXXO (Mexico), Mercado Pago |
| India | **UPI**, netbanking, RuPay, wallets |
| SE Asia | GrabPay, GCash, DANA, PromptPay, FPX |
| China | **Alipay, WeChat Pay** |
| MENA | mada (KSA), KNET (Kuwait), Benefit (Bahrain), local cards |
| Global | Apple Pay, Google Pay, PayPal (see ewallets skill) |

Offer the **right local method per country** — it's the single biggest conversion lever abroad.

## Integration pattern (Stripe example — applies generally)

```
SERVER: create PaymentIntent { amount(minor), currency, automatic_payment_methods }
        → return client_secret  (amount comes from YOUR DB, with an idempotency key)
CLIENT: mount Payment Element (hosted fields) → confirmPayment() → handles 3DS/redirect
SERVER: listen to webhook payment_intent.succeeded (source of truth) → fulfil
REFUND: refunds.create({ payment_intent, amount? })  — idempotent
```
Same shape elsewhere: create intent/order server-side → collect via hosted fields/redirect →
confirm via webhook. Wrap each in an adapter implementing your `PaymentProvider` interface.

## Cross-provider essentials
- **Tokenization / cards-on-file** for repeat & subscriptions (store provider token, never PAN).
- **Authorize then capture** for delayed fulfilment; auto-capture for instant.
- **3-D Secure / SCA** (mandatory EU/PSD2) — let the provider handle the challenge.
- **Multi-currency**: present in local currency; know your settlement currency + FX/fees.
- **Payouts/settlement** timing (T+2…T+7) differs per provider — track for reconciliation.

## Checklist
```
- [ ] Pick provider(s) by market/methods/payout + MoR if selling globally
- [ ] Server-side intent/order creation (amount from DB) + idempotency
- [ ] Hosted fields/Elements (minimal PCI) + 3DS/SCA
- [ ] Enable relevant LOCAL methods per country
- [ ] Tokenization for repeat/subscriptions; auth/capture as needed
- [ ] Webhooks verified + idempotent = source of truth
- [ ] Multi-currency + settlement/FX tracked for reconciliation
```

## Anti-patterns
- Cards-only in markets that prefer PIX/UPI/iDEAL/wallets → lost conversions.
- Hardcoding one PSP; no adapter; no fallback routing (see orchestration skill).
- Confirming orders on client redirect instead of webhook.
- Ignoring SCA/3DS in Europe → declines.
- Selling globally without tax handling (consider a merchant-of-record).
