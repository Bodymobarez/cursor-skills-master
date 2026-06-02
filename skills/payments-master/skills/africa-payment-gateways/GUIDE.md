---
name: africa-payment-gateways
description: >-
  Integrate African PSPs at production depth — Paystack (init/verify + HMAC-SHA512 webhook),
  Flutterwave (⚠ MAJOR units + verif-hash/v4 signature), Paymob Egypt (Intention API + HMAC-SHA512
  lexicographic), Fawry (SHA-256 signed charge + async voucher), plus Interswitch/Monnify, Geidea,
  Ozow/Yoco/Stitch (SA), CinetPay/Wave (Francophone). Per-currency minor units, server-side verify,
  duplicate/slow-callback handling. Behind your adapter layer.
---

# Africa Payment Gateways

**Africa is mobile-money-first and country-fragmented: choose PSPs per country, support card +
mobile money + bank/voucher, and ALWAYS re-verify server-side.** Client callbacks lie or get lost;
the truth is a signed webhook plus a verify-by-reference call. Minor-unit and major-unit conventions
differ per gateway and per currency — encode each in its adapter (`payments-architecture`).

## When to use / when NOT

- **Use** to accept money across Africa, route per country, and combine a pan-African base
  (Paystack/Flutterwave) with country specialists (Fawry/Paymob in Egypt, Ozow/Yoco in SA, M-Pesa in Kenya).
- **NOT** for the mobile-money rails themselves (STK push, RequestToPay) → `ewallets-and-mobile-money`;
  not for global PSPs → `global-payment-gateways`.

## DECISION MATRIX — gateway by country/region

| Country / Region | Primary | Also | Local rails to support |
|------------------|---------|------|------------------------|
| **Pan-African** | **Flutterwave**, **Paystack** | DPO, Cellulant (Tingg), Onafriq, PayTabs | card + momo + bank transfer + USSD |
| **Nigeria** | Paystack, Flutterwave | **Interswitch**, Monnify, Opay, Squad | cards (Verve), **virtual accounts/transfer**, USSD |
| **Egypt** | **Paymob**, **Fawry** | Kashier, **Geidea**, PayTabs | Meeza cards, wallets, **Fawry voucher**, ValU (BNPL) |
| **Kenya / E. Africa** | **M-Pesa (Daraja)**, Pesapal | DPO, Cellulant | **M-Pesa STK**, Airtel Money, cards |
| **South Africa** | **Yoco**, **Ozow** (instant EFT) | PayFast, Peach, **Stitch**, SnapScan | cards, instant EFT, **debit-order/PayShap** |
| **Ghana** | **Hubtel**, Paystack | ExpressPay | MTN/Voda/AirtelTigo momo, cards |
| **Francophone (CI/SN/CM)** | **Wave**, **CinetPay** | PayDunya, Orange/MTN aggregators | Orange/MTN/Moov money, **XOF/XAF cards** |
| **Morocco** | **CMI** | PayZone, Checkout.com | local cards (CMI mandatory for many) |

> Start with **Flutterwave or Paystack** for multi-country card+transfer+momo, then add specialists
> for local reach and better economics. One global PSP does **not** cover Africa (coverage/settlement gaps).

## DECISION MATRIX — money format & verification per gateway (the part that loses money)

| Gateway | Wire amount | Webhook auth | Re-verify endpoint |
|---------|-------------|--------------|---------------------|
| **Paystack** | **integer minor** (kobo/pesewa/cent) | `x-paystack-signature` = HMAC-SHA512(secret, rawBody) | `GET /transaction/verify/:reference` |
| **Flutterwave** | ⚠ **MAJOR units** (`amount: 5000` = ₦5000) | v3 `verif-hash` == secret; v4 signed header | `GET /transactions/:id/verify` |
| **Paymob** | **integer minor** (piastres) | `hmac` query = HMAC-SHA512 over sorted values | transaction inquiry / retrieve |
| **Fawry** | **decimal major** (`amount: 100.00`) | signed callback (SHA-256) | charge status / staus API |
| **M-Pesa** | **whole shillings** integer | callback (no HMAC → IP allowlist) | STK Query |

## Currency minor units in Africa

| Currency | Minor units | Rule |
|----------|-------------|------|
| NGN, KES, EGP, GHS, ZAR, MAD, UGX*, TZS* | ×100 | standard 2-decimal (kobo, cents, piastres, pesewas) |
| **XOF, XAF** (Francophone CFA) | **×1** | **zero-decimal — multiplying by 100 over-charges 100×** |

> XOF/XAF have **no minor unit**. `money(5000,"XOF")` is 5000 CFA, not 50. Your `Money` exponent table
> (`payments-architecture`) already encodes this — never special-case it inline.

## Paystack — initialize + verify + verify-on-webhook (copy-paste)

```ts
// paystack-adapter.ts — amount in MINOR units; reference is your idempotency anchor; ALWAYS verify.
const PS = "https://api.paystack.co";
const auth = { Authorization: `Bearer ${process.env.PAYSTACK_SECRET_KEY}`, "Content-Type": "application/json" };

export async function createPaystack(i: { amount: Money; email: string; reference: string }) {
  const r = await fetch(`${PS}/transaction/initialize`, {
    method: "POST", headers: auth,
    body: JSON.stringify({
      email: i.email,
      amount: i.amount.amount,             // integer minor units (kobo/pesewa/cent) — NOT naira
      currency: i.amount.currency,         // NGN | GHS | ZAR | KES | USD
      reference: i.reference,              // reuse on retry ⇒ idempotent (Paystack rejects dup refs)
      channels: ["card", "bank", "ussd", "mobile_money", "bank_transfer"],
    }),
  }).then((x) => x.json());
  return { providerRef: i.reference, redirectUrl: r.data.authorization_url, raw: r };
}

// Webhook: HMAC-SHA512 of the RAW body with your SECRET key. Then RE-VERIFY before giving value.
import crypto, { timingSafeEqual } from "node:crypto";
app.post("/webhooks/paystack", express.raw({ type: "application/json" }), async (req, res) => {
  const expected = crypto.createHmac("sha512", process.env.PAYSTACK_SECRET_KEY!)
    .update(req.body).digest("hex");                                  // req.body is a Buffer (raw)
  const got = req.headers["x-paystack-signature"] as string;
  if (!got || !timingSafeEqual(Buffer.from(expected), Buffer.from(got))) return res.sendStatus(401);
  res.sendStatus(200);                                                // ack fast
  const evt = JSON.parse(req.body.toString());
  if (evt.event === "charge.success") {
    const v = await fetch(`${PS}/transaction/verify/${evt.data.reference}`, { headers: auth }).then(r => r.json());
    if (v.data.status === "success" && v.data.amount === expectedMinor && v.data.currency === expectedCcy) {
      await fulfilOnce(evt.data.reference);                           // idempotent reducer
    }
  }
});
```

> Optional defense-in-depth: also IP-allowlist Paystack's webhook IPs (`52.31.139.75`, `52.49.173.169`,
> `52.214.14.220`). Signature verification is mandatory regardless.

## Flutterwave — the MAJOR-units trap + always re-query

```ts
// Flutterwave amount is in MAJOR units: 5000 = ₦5,000 (NOT 5000 kobo). Convert at the boundary.
body: JSON.stringify({
  tx_ref: input.reference,                  // your idempotency anchor
  amount: toMajorNumber(input.amount),      // ⚠ 5000 NGN, not input.amount.amount (kobo)
  currency: input.amount.currency,
  redirect_url: input.returnUrl,
  customer: { email: input.customer.email },
})
// v3 webhook: verify header `verif-hash` === process.env.FLW_SECRET_HASH (constant-time compare).
// v4 webhook: signed header — verify the HMAC. EITHER WAY, then re-query and check status/amount/ccy:
const v = await fetch(`https://api.flutterwave.com/v3/transactions/${id}/verify`,
  { headers: { Authorization: `Bearer ${process.env.FLW_SECRET_KEY}` } }).then(r => r.json());
const ok = v.data.status === "successful"
  && v.data.amount >= toMajorNumber(expectedMoney)   // ≥ guards under-payment
  && v.data.currency === expectedMoney.currency
  && v.data.tx_ref === input.reference;
```

## Paymob (Egypt) — Intention API + HMAC-SHA512 over sorted values

```ts
// 1) Create intention server-side (amount in PIASTRES — minor units). Returns client_secret.
const intent = await fetch("https://accept.paymob.com/v1/intention/", {
  method: "POST",
  headers: { Authorization: `Token ${process.env.PAYMOB_SECRET_KEY}`, "Content-Type": "application/json" },
  body: JSON.stringify({
    amount: input.amount.amount,                  // integer minor units (e.g. 10000 = 100.00 EGP)
    currency: "EGP",
    payment_methods: [Number(process.env.PAYMOB_INTEGRATION_ID)],
    special_reference: input.reference,           // your idempotency anchor
    billing_data: { first_name: "—", last_name: "—", email: input.customer.email, phone_number: input.customer.phoneE164 },
  }),
}).then((r) => r.json());
// 2) Redirect to Unified Checkout:
const url = `https://accept.paymob.com/unifiedcheckout/?publicKey=${process.env.PAYMOB_PUBLIC_KEY}&clientSecret=${intent.client_secret}`;

// 3) Callback HMAC: sort the documented keys lexicographically, concatenate VALUES, HMAC-SHA512, compare to ?hmac=
function verifyPaymobHmac(p: Record<string, string>, received: string) {
  const KEYS = ["amount_cents","created_at","currency","error_occured","has_parent_transaction","id",
    "integration_id","is_3d_secure","is_auth","is_capture","is_refunded","is_standalone_payment",
    "is_voided","order.id","owner","pending","source_data.pan","source_data.sub_type","source_data.type","success"];
  const concat = KEYS.map((k) => String(p[k])).join("");
  const calc = crypto.createHmac("sha512", process.env.PAYMOB_HMAC_SECRET!).update(concat).digest("hex");
  return timingSafeEqual(Buffer.from(calc), Buffer.from(received));
}
```

## Fawry (Egypt) — signed charge + async voucher (the unbanked path)

```ts
// Fawry amounts are DECIMAL MAJOR ("100.00"). Charge is SHA-256 signed; the customer pays LATER at a
// kiosk/app via a reference code → your status is confirmed by the (signed) notification callback.
const amount = toMajorString(input.amount);                       // "100.00"
const signature = crypto.createHash("sha256").update(
  `${MERCHANT_CODE}${input.reference}${input.customer.id}${PAYMENT_METHOD}${amount}${SECURE_KEY}`
).digest("hex");
// POST chargeRequest → returns referenceNumber (the voucher). Payment state = requires_action until paid.
// On the server callback, recompute the signature over Fawry's documented field order and verify before fulfil.
```

> Voucher/reference flows (Fawry, bank transfer, virtual accounts) are **asynchronous** — the customer
> pays minutes-to-days later. Model as `requires_action`, set an expiry, and reconcile on the callback.

## Africa-specific edge cases

- **Minor units per currency**: NGN/KES/EGP/GHS/ZAR ×100; **XOF/XAF ×1**. Flutterwave wants **major** units.
- **Slow / duplicated telco & voucher callbacks** → idempotent reducer (dedupe by reference) **plus** a
  status-poll fallback (verify/query) when no callback arrives within N minutes.
- **Settlement currency & FX**: many PSPs settle in local currency; cross-border = FX spread — store the rate.
- **Verify server-side, always**: re-query by reference and check `status` + `amount` + `currency` + `tx_ref`
  before granting value. The client callback is a hint, never proof.
- **KYC/licensing/local entity**: settlement often requires a local bank account/entity; varies per country.
- **Underpayment on vouchers**: a customer can pay a different amount at the kiosk — verify the exact amount.

## Performance, reliability & observability

- Cache provider auth tokens (Paymob token, Flutterwave/Interswitch OAuth) — don't mint per request.
- Per-PSP metrics: auth rate, callback lag, % needing poll-fallback, verify mismatches. Feed orchestration.
- Telco/PSP outages are common — make each gateway a swappable adapter and fail over per market.

## Testing

- **Paystack**: test secret key + test cards; resend webhook from the dashboard; verify HMAC locally with the raw body.
- **Flutterwave**: sandbox keys + test cards/momo numbers; confirm the **major-units** conversion in a unit test.
- **Paymob**: test integration IDs; trigger callbacks and assert the lexicographic-HMAC verifier passes/fails correctly.
- **M-Pesa**: sandbox shortcode `174379`, passkey + test MSISDN `254708374149` (see `ewallets-and-mobile-money`).

## Anti-patterns

- **Cards-only** in mobile-money-first markets → very low conversion.
- **`×100` on XOF/XAF**, or sending **minor units to Flutterwave** (it wants major) → 100× over/undercharge.
- Trusting the client callback without a signed webhook **and** a server-side re-verify.
- Non-idempotent handling of duplicate telco/voucher callbacks → double fulfilment.
- Assuming one PSP covers all of Africa; ignoring local settlement/KYC requirements.
- Treating a Fawry/transfer voucher as instant instead of `requires_action` + expiry + reconcile.

## Agent checklist

```
- [ ] PSP chosen per target country (pan-African base + local specialists)
- [ ] card + mobile money + bank/voucher supported per market
- [ ] Correct money format per gateway: Paystack/Paymob minor, Flutterwave major, Fawry decimal, XOF/XAF ×1
- [ ] Server-side initialize + verify-by-reference + signed webhook (HMAC-SHA512 / verif-hash / SHA-256)
- [ ] Idempotent reducer (dedupe by reference) + status-poll fallback for slow/duplicate callbacks
- [ ] Async voucher/transfer modelled as requires_action with expiry; exact amount verified
- [ ] Settlement currency/FX stored; local KYC/licensing checked; all behind the adapter layer
```

## References (current 2026)

- Paystack webhooks & verify: https://paystack.com/docs/payments/webhooks/ · https://paystack.com/docs/payments/verify-payments/
- Flutterwave webhooks/verify: https://developer.flutterwave.com/docs/webhooks · v4: https://developer.flutterwave.com
- Paymob Intention API & HMAC: https://developers.paymob.com/ · Fawry: https://developer.fawrystaging.com / https://atfawry.fawrystaging.com
- M-Pesa Daraja: https://developer.safaricom.co.ke · Geidea: https://docs.geidea.net · Ozow: https://docs.ozow.com

## Related

`payments-architecture`, `ewallets-and-mobile-money`, `payment-webhooks-and-idempotency`,
`payment-orchestration-and-security`, `checkout-and-payment-pages`, `reconciliation-and-ledger`.
