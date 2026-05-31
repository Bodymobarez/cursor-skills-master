---
name: payments-architecture
description: >-
  Architect a multi-gateway payment system end-to-end. Use as the foundation for
  any payments work — accepting cards, wallets, bank transfers, and mobile money
  across the world and Africa. Covers the provider-agnostic abstraction layer,
  canonical payment model, the payment lifecycle, idempotency, webhooks, and PCI
  scope. Read first, then go to the gateway/wallet/checkout/security skills.
---

# Payments Architecture

The foundation for accepting payments via many providers without coupling your app to any one of
them. Build a **provider-agnostic layer**; each gateway/wallet is an adapter behind it.

## Provider-agnostic abstraction (the core)

```
PaymentProvider (interface):
  createPayment(amount, currency, method, customer, metadata) → { providerRef, status, redirectUrl? }
  capture(ref) / authorize+capture
  refund(ref, amount?) → RefundResult
  getStatus(ref) → canonical status
  handleWebhook(payload, sig) → canonical PaymentEvent
Adapters: StripeAdapter, PayPalAdapter, PaystackAdapter, FlutterwaveAdapter, PaymobAdapter,
          MpesaAdapter, MtnMomoAdapter, ...
Registry routes payment → adapter by country/method/currency (see payment-orchestration).
Your app only ever sees the canonical model — never a provider's raw shape.
```

## Canonical model & states

```
Payment { id, amount(minor units), currency, method[card|wallet|bank|mobile_money|...],
          provider, providerRef, status, customer, metadata, createdAt }
Status:  initiated → pending → (requires_action: 3DS/redirect/USSD/STK) → authorized
         → captured/succeeded → (refunded/partially_refunded) ; or failed / cancelled / expired
```
Map every provider's statuses to this enum. Store the **provider's raw payload** too (audit/debug).

## Payment lifecycle (universal)

```
1. CREATE intent on your server (never trust client amounts)  — amount/currency from your DB
2. PRESENT method (card form / wallet button / redirect / mobile-money prompt)
3. AUTHENTICATE if needed (3-D Secure, OTP, STK push, USSD, redirect approval)
4. AUTHORIZE → CAPTURE (or auto-capture) ; or fail
5. CONFIRM via WEBHOOK (source of truth) — not just the client redirect
6. POST: receipt, fulfilment, reconciliation, refunds, disputes
```

## Non-negotiable rules

- **Money = integer minor units + currency.** Never floats. Always store currency. (Pair with
  `accounting-finance`.)
- **Server is the source of truth for amount** — compute from your DB, not the client/request.
- **Idempotency keys** on every create/capture/refund (network retries must not double-charge).
- **Webhooks are the source of truth** for final status (client can drop off after paying). Verify
  signatures, process idempotently (dedupe by event id), return 2xx fast + work async.
- **PCI scope minimization**: never let raw PAN/CVV touch your servers — use the provider's
  hosted fields / tokenization / hosted page. Stay PCI **SAQ-A** where possible.
- **Reconciliation**: match provider settlements ↔ your ledger daily; handle fees/FX.

## Concepts & glossary

| Term | Meaning |
|------|---------|
| **PSP / Gateway / Acquirer** | Payment Service Provider / routes transaction / bank that settles |
| **Authorize vs Capture** | Hold funds vs actually take them |
| **Tokenization** | Replace card with a token for reuse (cards-on-file, subscriptions) |
| **3-D Secure (SCA)** | Bank authentication step (required in EU/PSD2; risk-based elsewhere) |
| **STK Push / USSD** | Mobile-money prompt on phone (M-Pesa) / dial-code flow |
| **Settlement / Payout** | When the PSP actually deposits funds to you (T+n) |
| **Chargeback / Dispute** | Buyer reverses a card payment |
| **MDR** | Merchant Discount Rate — the fee % per transaction |

## Build roadmap
```
- [ ] Provider interface + canonical model + adapter registry
- [ ] Server-side intent creation (amount from DB) + idempotency
- [ ] Webhook receiver (verify, dedupe, async) as source of truth
- [ ] Choose providers by market (global-payment-gateways, africa-payment-gateways, wallets)
- [ ] Checkout/payment page (checkout-and-payment-pages) with minimal PCI scope
- [ ] Orchestration, fraud, retries, reconciliation (payment-orchestration-and-security)
- [ ] Refunds, disputes, receipts; ledger posting (accounting-finance)
```

## Anti-patterns
- Coupling business logic to one PSP's SDK/shape (build adapters).
- Trusting the client redirect instead of webhooks for final status.
- Floats for money; missing currency; computing amount from the request.
- No idempotency → duplicate charges on retry.
- Raw card data on your servers (massive PCI burden + risk).
