---
name: ewallets-and-mobile-money
description: >-
  Integrate e-wallets and mobile money worldwide and across Africa. Use for Apple
  Pay, Google Pay, PayPal, Alipay, WeChat Pay, Cash App, Paytm, GCash, GrabPay
  (global wallets) and M-Pesa, MTN MoMo, Airtel Money, Orange Money, Vodafone
  Cash/InstaPay, Wave, OPay, PalmPay, Telebirr, EcoCash, Chipper (African mobile
  money). Covers wallet buttons, STK push/USSD flows, and confirmation.
---

# E-Wallets & Mobile Money (global + Africa)

Accept digital wallets and mobile money. Two families with different flows: **device/online
wallets** (button → token → charge) and **mobile money** (push prompt/USSD → callback).

## Global e-wallets

| Wallet | Region | How |
|--------|--------|-----|
| **Apple Pay** | iOS/Safari global | Payment Request / provider (Stripe/Adyen) → token → charge |
| **Google Pay** | Android/Chrome global | Google Pay API / provider → token → charge |
| **PayPal** | Global consumer | Redirect/JS SDK → approve → capture order |
| **Amazon Pay** | Amazon markets | Button → wallet + address |
| **Cash App Pay / Venmo** | US | Via Stripe/Braintree |
| **Alipay / WeChat Pay** | China + travelers | Redirect/QR via Stripe/Adyen/Alipay+ |
| **Paytm / PhonePe (UPI)** | India | UPI intent/collect via Razorpay |
| **GCash / GrabPay / DANA / TrueMoney** | SE Asia | Via Adyen/Stripe/local |

> Apple Pay & Google Pay are usually enabled **through your existing gateway** (Stripe/Adyen/etc.)
> — you don't integrate them from scratch; you turn them on + add the button (a big conversion win
> with one-tap, tokenized, often biometric-auth checkout).

## African mobile money (the dominant rails)

| Service | Countries | API |
|---------|-----------|-----|
| **M-Pesa** | Kenya, Tanzania, etc. | Safaricom **Daraja** (STK Push / C2B / B2C) |
| **MTN Mobile Money (MoMo)** | 15+ countries | **MTN MoMo API** (Collections/Disbursements) |
| **Airtel Money** | Multi-country | Airtel Africa API |
| **Orange Money** | Francophone Africa | Orange Web Payment / aggregators |
| **Vodafone Cash / InstaPay / Meeza** | Egypt | Via Paymob/Fawry/Accept; InstaPay (IPN) |
| **Wave** | Senegal, Côte d'Ivoire | Wave API / aggregators |
| **OPay / PalmPay** | Nigeria | Provider APIs |
| **Telebirr** | Ethiopia | Ethio Telecom API |
| **EcoCash** | Zimbabwe | EcoCash API |
| **Chipper Cash** | Pan-African P2P | Chipper API |
| **Aggregators** | Pan-African | **Onafriq (MFS Africa)**, Flutterwave, Cellulant, Beyonic — one API → many MoMo wallets |

> Easiest path to many wallets: a **mobile-money aggregator** (Flutterwave, Onafriq, Cellulant) or a
> PSP that bundles MoMo (Paystack/Paymob). Integrate one telco API directly only when needed.

## Mobile-money flows

```
STK Push (M-Pesa Lipa na M-Pesa / MoMo RequestToPay):
  1. OAuth token from provider
  2. Your server initiates push: { phone, amount, account_ref, callback_url, idempotency }
  3. Customer gets a prompt on their phone → enters PIN to approve
  4. Provider POSTs a CALLBACK with result (success/fail) → confirm + fulfil
  5. If callback is slow/lost → POLL transaction status as fallback

USSD / collect:
  Customer dials a code or you trigger a collect request; confirm via callback.
  (Common where smartphones/data are limited.)
```

## Essentials
- **Phone number formatting**: normalize to international (E.164, e.g. 2547XXXXXXXX); validate the
  network/prefix where the API requires it.
- **Idempotency**: telco callbacks can duplicate/retry — dedupe by transaction/reference id.
- **Async + timeouts**: payment may take seconds to minutes (user PIN entry) — design async UX,
  show "approve on your phone", and poll status as a fallback.
- **Minor units & currency** per market (KES cents, NGN kobo; XOF/XAF have **no decimals**).
- **Payouts/disbursements (B2C)**: same APIs often send money out (refunds, seller payouts, salaries).
- **Confirmation is the callback/verify**, never the client.

## Checklist
```
- [ ] Global wallets (Apple/Google Pay, PayPal) enabled via your gateway + buttons added
- [ ] African MoMo via aggregator (Flutterwave/Onafriq/Cellulant) or direct telco API
- [ ] STK push/USSD: initiate → phone approval → callback confirm → poll fallback
- [ ] E.164 phone normalization + network validation
- [ ] Idempotent callback handling (dedupe); async UX with status polling
- [ ] Correct minor units/currency per market
- [ ] Disbursement/B2C path for refunds & payouts if needed
```

## Anti-patterns
- Building Apple/Google Pay from scratch instead of via your gateway.
- Synchronous UX assuming instant payment (MoMo needs PIN approval time).
- Trusting client result instead of the provider callback/verify.
- Non-idempotent callbacks → double fulfilment from telco retries.
- Wrong minor units (×100 on XOF/XAF) or unnormalized phone numbers → failures.
