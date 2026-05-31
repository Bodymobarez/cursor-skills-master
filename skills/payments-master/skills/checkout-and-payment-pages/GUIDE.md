---
name: checkout-and-payment-pages
description: >-
  Build payment pages and checkout flows that convert and stay PCI-safe. Use to
  create card forms, hosted/embedded checkout, payment method selection, 3-D
  Secure handling, tokenization, saved cards, and high-conversion checkout UX.
  Covers hosted vs embedded vs API, PCI scope, and trust/conversion best practices.
---

# Checkout & Payment Pages

Build the page where money changes hands — **secure, fast, trusted, and high-converting**.
Always behind your `payments-architecture` layer.

## 1. Integration style (PCI scope ↓ as you go left)

| Style | PCI scope | UX control | Use |
|-------|-----------|-----------|-----|
| **Hosted payment page** (redirect) | Lowest (SAQ-A) | Low | Fastest/safest; many African PSPs (Paystack/Flutterwave/Paymob) default here |
| **Embedded hosted fields / Elements** (iframe) | Low (SAQ-A) | High | Stripe Elements, Adyen Components — card stays in provider iframe |
| **Drop-in / prebuilt UI** | Low | Medium | Provider's prebuilt widget (multiple methods) |
| **Full API / raw card** | **Highest (SAQ-D)** | Total | Avoid unless you must — huge compliance burden |

> Default to **embedded hosted fields** (Stripe Payment Element / Adyen Drop-in) or a **hosted page**.
> Never collect raw card numbers in your own inputs — that drags you into PCI SAQ-D.

## 2. Payment method selection
- Show methods **relevant to the customer's country/currency**: cards, Apple/Google Pay, PayPal,
  local methods (PIX/UPI/iDEAL), and in Africa **mobile money + bank transfer + Fawry reference**.
- Order by likelihood (express wallets at top → one-tap), then cards, then local.
- Use the provider's "automatic payment methods" to surface the right ones per locale.

## 3. The card form (if you render fields)
- Hosted fields only; format card number (groups), detect brand, validate Luhn + expiry + CVC,
  inline real-time validation, autofill (`autocomplete="cc-number"` etc.), numeric inkeyboard.
- **3-D Secure / SCA**: let the provider trigger the challenge; handle `requires_action`, then
  re-confirm. Don't block low-risk frictionless flows.

## 4. Tokenization & saved cards
- Save cards as **provider tokens** (never PAN) for one-click repeat + subscriptions.
- Show saved methods (brand + last4 + expiry); allow add/remove/set-default; re-auth (CVV/3DS) per
  risk rules.

## 5. Conversion & trust UX (this is real money)
```
- [ ] Express wallets (Apple/Google Pay) one-tap at the very top
- [ ] Guest checkout; minimal fields; address autocomplete; auto-detect country/currency
- [ ] Show total, currency, taxes, fees BEFORE pay; no surprise costs
- [ ] Trust signals: security badges, lock icon, accepted-method logos, refund/policy
- [ ] Inline validation + clear, specific error messages (decline reasons)
- [ ] Mobile-first, fast, no full-page reloads; loading/disabled states on submit
- [ ] One-tap retry on soft declines; keep entered data
- [ ] Post-payment: clear success, receipt/email, order status, "approve on phone" for MoMo
- [ ] Localized language, currency, and method set
```

## 6. Security on the page
- HTTPS only; CSP; never log card data; never put secret keys client-side (publishable keys only).
- Idempotency key per checkout attempt (prevent double submit/charge).
- Confirm final status via **webhook**, not the client redirect (show pending if unknown).
- Bot/fraud: rate-limit, CAPTCHA on abuse, device fingerprint (see security skill).

## 7. Pages to build
- Checkout (method select + pay) · 3DS/redirect return page · success/receipt · failure/retry ·
  pending (MoMo/bank reference) · saved methods management · subscription manage/upgrade.

## Anti-patterns
- Rolling your own raw card inputs (PCI SAQ-D) instead of hosted fields.
- Hiding fees/taxes until the last step → abandonment.
- No express wallets / forcing account creation → lost mobile conversions.
- Marking success on client redirect before webhook confirms.
- Generic "payment failed" with no reason or retry path.
- Same method set for every country (show local + mobile money where relevant).
