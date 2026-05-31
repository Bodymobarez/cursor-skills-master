---
name: africa-payment-gateways
description: >-
  Integrate African payment gateways and PSPs. Use to accept payments across
  Africa — Paystack, Flutterwave, Interswitch, Monnify (Nigeria); Fawry, Paymob,
  Kashier, Geidea, PayTabs (Egypt); M-Pesa/Pesapal/DPO (Kenya/East Africa);
  PayFast, Yoco, Ozow, Peach, Stitch (South Africa); CinetPay, PayDunya, Wave
  (Francophone); Hubtel (Ghana). Covers per-country choice, methods, and patterns.
---

# Africa Payment Gateways

Accept payments across Africa. The continent is **mobile-money-first and country-fragmented** —
choose providers per country, and almost always support card **+ mobile money + bank transfer**.

## Gateways by country/region

| Country / Region | Gateways (PSPs) |
|------------------|-----------------|
| **Pan-African** | **Flutterwave**, **Paystack**, DPO Group, Cellulant (Tingg), Onafriq (MFS Africa), PayTabs |
| **Nigeria** | Paystack, Flutterwave, **Interswitch**, Monnify, Remita, Opay, Kuda, Squad |
| **Egypt** | **Fawry**, **Paymob (Accept)**, Kashier, **Geidea**, PayTabs, Khazna; networks: **Meeza**, ValU (BNPL) |
| **Kenya / East Africa** | **M-Pesa (Daraja API)**, Pesapal, DPO, Cellulant, iPay |
| **South Africa** | **PayFast**, **Yoco**, **Ozow** (instant EFT), Peach Payments, SnapScan, Paygate, **Stitch** |
| **Ghana** | **Hubtel**, ExpressPay, Paystack |
| **Francophone (CI, SN, CM…)** | **CinetPay**, **PayDunya**, **Wave**, Orange/MTN aggregators |
| **Morocco** | **CMI**, PayZone |
| **Maghreb/MENA overlap** | PayTabs, Checkout.com |

> Start with **Flutterwave or Paystack** for multi-country card+transfer+momo coverage, then add
> country specialists (Fawry/Paymob in Egypt, M-Pesa in Kenya, Ozow/Yoco in SA) for local reach.

## Methods to support in Africa (beyond cards)
- **Mobile money** (often #1): M-Pesa, MTN MoMo, Airtel Money, Orange Money, Vodafone Cash, Wave —
  see the `ewallets-and-mobile-money` skill for the actual flows (STK push/USSD).
- **Bank transfer / instant EFT**: Ozow (SA), virtual accounts (Nigeria — Monnify/Paystack), Fawry
  reference codes (Egypt).
- **Cash / agent / reference codes**: **Fawry** (pay at kiosk via reference), retail networks.
- **Cards**: local schemes (Meeza in Egypt, Verve in Nigeria) + Visa/Mastercard.
- **USSD & QR**: widely used; many PSPs expose USSD push and QR.

## Integration patterns (per major PSP)

```
Paystack (Nigeria/Ghana/SA/Kenya/Egypt):
  POST /transaction/initialize { email, amount(kobo/cents), currency, channels[] }
  → authorization_url (redirect/popup) → user pays → VERIFY via GET /transaction/verify/:ref
  → confirm with webhook (x-paystack-signature HMAC-SHA512). Amount in MINOR units.

Flutterwave (pan-African):
  Standard/inline checkout with public key → tx_ref → on success VERIFY /transactions/:id/verify
  → webhook (verif-hash header). Supports card, momo, bank, USSD across countries/currencies.

Paymob (Egypt):
  Auth token → create order → payment key → iframe/redirect (card, wallet, Fawry) → webhook (HMAC).

Fawry (Egypt):
  Charge request (signed SHA-256) → returns reference code → customer pays at kiosk/app/online
  → notification callback confirms. Great for the unbanked.

M-Pesa (Kenya, Daraja API):
  OAuth token → STK Push (Lipa na M-Pesa) → prompt on phone → C2B confirmation callback.
  (See ewallets-and-mobile-money for full mobile-money flows.)
```

## Africa-specific gotchas
- **Currencies & minor units**: NGN (kobo ×100), KES (cents), EGP (piastres ×100), GHS, ZAR, XOF/XAF
  (no decimals — don't ×100). Always confirm each currency's minor-unit rule.
- **Settlement currency & FX**: many PSPs settle in local currency; cross-border = FX.
- **Verify server-side**: always re-verify a transaction by reference + webhook; don't trust the
  client callback alone.
- **Reliability**: telco/momo callbacks can be slow/duplicated → idempotent handling + status polling
  fallback (query transaction status).
- **KYC/compliance & licensing** vary per country; settlement may require a local entity/bank account.
- **Reference/voucher flows** (Fawry) are async — the user pays later; reconcile on callback.

## Checklist
```
- [ ] Pick PSP per target country (Flutterwave/Paystack base + local specialists)
- [ ] Support card + mobile money + bank transfer/reference per market
- [ ] Correct minor units per currency (watch XOF/XAF = no decimals)
- [ ] Server-side initialize + verify-by-reference + signed webhooks (idempotent)
- [ ] Status-polling fallback for slow/duplicate momo callbacks
- [ ] Settlement currency/FX + reconciliation; local KYC/licensing checked
- [ ] All behind your payments-architecture adapter
```

## Anti-patterns
- Cards-only in mobile-money-first markets → very low conversion.
- Multiplying XOF/XAF by 100 (they have no minor unit) → 100× overcharge.
- Trusting client callback without server verify + webhook → fraud/missed payments.
- Non-idempotent handling of duplicate telco callbacks → double fulfilment.
- One global PSP assumed to cover all of Africa (coverage/settlement gaps).
