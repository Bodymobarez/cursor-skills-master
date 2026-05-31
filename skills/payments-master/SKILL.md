---
name: payments-master
description: >-
  Master hub for Payments — accept money worldwide and across Africa. Use to build
  payment pages/checkout and integrate every kind of merchant gateway and e-wallet:
  global PSPs (Stripe, Adyen, PayPal, Checkout.com, Razorpay…), African gateways
  (Paystack, Flutterwave, Fawry, Paymob, M-Pesa, Ozow, Yoco, CinetPay…), and
  mobile money/wallets (Apple/Google Pay, Alipay, MTN MoMo, Airtel/Orange Money,
  Vodafone Cash, Wave…), plus orchestration, PCI security, fraud, and reconciliation.
  Bundles 6 specialized skills (in skills/<name>/GUIDE.md). Use for any payments task.
---

# Payments — Master Hub

Use to build payment pages and integrate **merchant gateways and e-wallets worldwide and across
Africa** — cards, wallets, bank transfers, and mobile money — securely and reliably.

## How to use this hub

This single skill bundles **all 6 payments skills**. Each bundled skill's full instructions live
in `skills/<name>/GUIDE.md`.

**Workflow:**
1. Start with **payments-architecture** for the provider-agnostic layer, canonical model, and lifecycle.
2. Pick gateways/wallets by market (global / africa / ewallets skills).
3. Build the page with **checkout-and-payment-pages**, then harden with **payment-orchestration-and-security**.

## Bundled skills

- **payments-architecture** ⭐ — Foundation: provider-agnostic adapter layer, canonical payment model & states, the payment lifecycle, idempotency, webhooks-as-source-of-truth, minor-units money rules, and PCI scope.  
  → `skills/payments-architecture/GUIDE.md`
- **global-payment-gateways** — Integrate worldwide PSPs (Stripe, Adyen, PayPal/Braintree, Checkout.com, Worldpay, Authorize.Net, Square, Razorpay, Mollie, Klarna, merchant-of-record like Paddle) + local methods (PIX, UPI, iDEAL, Alipay/WeChat).  
  → `skills/global-payment-gateways/GUIDE.md`
- **africa-payment-gateways** — African PSPs per country: Paystack/Flutterwave/Interswitch/Monnify (Nigeria), Fawry/Paymob/Kashier/Geidea (Egypt), M-Pesa/Pesapal/DPO (East Africa), PayFast/Yoco/Ozow/Peach/Stitch (South Africa), CinetPay/PayDunya/Wave (Francophone), Hubtel (Ghana), CMI (Morocco) — with minor-unit & verification gotchas.  
  → `skills/africa-payment-gateways/GUIDE.md`
- **ewallets-and-mobile-money** — Global wallets (Apple Pay, Google Pay, PayPal, Alipay, WeChat Pay, Cash App, Paytm/UPI, GCash/GrabPay) and African mobile money (M-Pesa Daraja, MTN MoMo, Airtel/Orange Money, Vodafone Cash/InstaPay, Wave, OPay/PalmPay, Telebirr, EcoCash, Chipper; aggregators Onafriq/Flutterwave/Cellulant) with STK-push/USSD flows.  
  → `skills/ewallets-and-mobile-money/GUIDE.md`
- **checkout-and-payment-pages** — Build high-converting, PCI-safe payment pages: hosted vs embedded (Stripe Elements/Adyen Drop-in) vs hosted page, method selection per market, 3-D Secure, tokenization/saved cards, and conversion/trust UX.  
  → `skills/checkout-and-payment-pages/GUIDE.md`
- **payment-orchestration-and-security** — Reliability + safety + accuracy: multi-gateway routing/failover, smart retries/dunning, PCI DSS (SAQ-A), fraud prevention (3DS/Radar/device), webhooks, subscriptions/recurring, refunds/disputes/chargebacks, and daily reconciliation.  
  → `skills/payment-orchestration-and-security/GUIDE.md`

## Pairs well with
`backend-api-master` (Stripe deep-dives: adding-stripe, stripe-best-practices; auth, MFA,
integrations-pro webhooks), `business-master` (accounting-finance for the money ledger),
`marketplace-master` (split payments/payouts), and `ui-master` (checkout UI).

## Note

These bundled skills are intentionally not registered as separate Cursor skills (their files are
`GUIDE.md`, not `SKILL.md`) so only this master appears in the skills list. Read the relevant
`GUIDE.md` on demand.
