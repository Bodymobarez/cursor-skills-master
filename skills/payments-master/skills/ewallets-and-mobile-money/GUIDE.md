---
name: ewallets-and-mobile-money
description: >-
  Integrate wallets and mobile money at production depth — M-Pesa Daraja STK Push (OAuth, base64
  password, callback parsing, STK Query fallback), MTN MoMo Collections RequestToPay (X-Reference-Id
  idempotency, status poll), Airtel/Orange Money, Wave, and global wallets (Apple Pay, Google Pay,
  PayPal, Alipay/WeChat) enabled THROUGH your gateway. Async PIN-approval UX, E.164 numbers, B2C
  disbursements, idempotent callbacks. Behind your adapter layer.
---

# E-Wallets & Mobile Money (global + Africa)

**Mobile money is asynchronous: you push a prompt, the customer enters a PIN seconds-to-minutes
later, and the *callback* (or a status poll) is the truth — never the HTTP response to your push.**
Two families: **device/online wallets** (button → token → charge, instant) and **mobile money**
(push/USSD → PIN → callback, async). Both sit behind your `payments-architecture` adapter.

## When to use / when NOT

- **Use** for M-Pesa/MTN/Airtel/Orange/Wave collections + payouts, and to turn on Apple Pay/Google Pay/
  PayPal/Alipay through an existing PSP.
- **NOT** for raw card flows (`global-payment-gateways`) or PSP selection per country
  (`africa-payment-gateways`). Routing/retries → `payment-orchestration-and-security`.

## DECISION MATRIX — wallets & rails

| Rail | Markets | API / how | Flow |
|------|---------|-----------|------|
| **Apple Pay / Google Pay** | global (iOS/Safari, Android/Chrome) | **via your gateway** (Stripe/Adyen) → token | instant, tokenized, biometric |
| **PayPal** | global consumer | Orders v2 redirect/JS SDK | approve → capture |
| **Alipay / WeChat Pay** | China + travelers | via Stripe/Adyen/Alipay+ | redirect / QR |
| **M-Pesa** | Kenya, Tanzania, … | Safaricom **Daraja** (STK/C2B/B2C) | STK push → PIN → callback |
| **MTN MoMo** | 15+ countries | **Collections** RequestToPay | push → PIN → 202 + status poll |
| **Airtel Money** | multi-country | Airtel Africa API | push → PIN → callback |
| **Orange Money** | Francophone | Orange Web Payment / aggregator | redirect/USSD → callback |
| **Wave** | SN, CI | Wave API / aggregator | checkout link → callback |
| **Aggregators** | pan-African | **Onafriq**, Flutterwave, Cellulant | one API → many wallets |

> Apple Pay & Google Pay are **enabled through your existing PSP**, not integrated from scratch — you
> toggle them on and add the button. One-tap, tokenized, biometric checkout is a large conversion win.
> For many wallets at once, prefer a **mobile-money aggregator** over N direct telco integrations.

## M-Pesa Daraja — STK Push end to end (copy-paste)

```ts
// mpesa-adapter.ts — KES is sent as WHOLE shillings (no cents in STK). Truth = callback or STK Query.
const BASE = process.env.MPESA_ENV === "production"
  ? "https://api.safaricom.co.ke" : "https://sandbox.safaricom.co.ke";

// 1) OAuth — cache the token (~1h). Basic auth = base64(consumerKey:consumerSecret).
async function token() {
  const basic = Buffer.from(`${process.env.MPESA_KEY}:${process.env.MPESA_SECRET}`).toString("base64");
  const r = await fetch(`${BASE}/oauth/v1/generate?grant_type=client_credentials`,
    { headers: { Authorization: `Basic ${basic}` } }).then((x) => x.json());
  return r.access_token as string;
}

// 2) STK Push (Lipa na M-Pesa Online). Password = base64(Shortcode + Passkey + Timestamp).
export async function stkPush(i: { amount: Money; phoneE164: string; reference: string }) {
  const ts = new Date().toISOString().replace(/\D/g, "").slice(0, 14);          // yyyyMMddHHmmss
  const password = Buffer.from(`${process.env.MPESA_SHORTCODE}${process.env.MPESA_PASSKEY}${ts}`).toString("base64");
  const phone = i.phoneE164.replace("+", "");                                    // 2547XXXXXXXX (no +)
  const r = await fetch(`${BASE}/mpesa/stkpush/v1/processrequest`, {
    method: "POST",
    headers: { Authorization: `Bearer ${await token()}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      BusinessShortCode: process.env.MPESA_SHORTCODE,
      Password: password, Timestamp: ts,
      TransactionType: "CustomerPayBillOnline",   // or CustomerBuyGoodsOnline for a Till
      Amount: toWholeMajor(i.amount),             // WHOLE KES — Daraja rejects decimals
      PartyA: phone, PartyB: process.env.MPESA_SHORTCODE, PhoneNumber: phone,
      CallBackURL: `${process.env.BASE_URL}/webhooks/mpesa`,   // MUST be public HTTPS in prod
      AccountReference: i.reference.slice(0, 12),  // shows on statement; ≤12 chars
      TransactionDesc: "Order",
    }),
  }).then((x) => x.json());
  // r.CheckoutRequestID identifies this attempt for the STK Query fallback.
  return { providerRef: r.CheckoutRequestID, status: "requires_action" as const, raw: r };
}
```

```ts
// 3) Callback — Daraja has NO HMAC. IP-allowlist Safaricom + treat as a hint, then reconcile idempotently.
app.post("/webhooks/mpesa", express.json(), async (req, res) => {
  res.json({ ResultCode: 0, ResultDesc: "Accepted" });            // ack ALWAYS, even on failure
  const cb = req.body?.Body?.stkCallback;
  if (!cb) return;
  if (cb.ResultCode === 0) {                                       // 0 = success
    const items = Object.fromEntries(cb.CallbackMetadata.Item.map((x: any) => [x.Name, x.Value]));
    await fulfilOnce(cb.CheckoutRequestID, {                       // dedupe by CheckoutRequestID
      receipt: items.MpesaReceiptNumber, amountKES: items.Amount, phone: items.PhoneNumber,
    });
  } else {
    await markFailed(cb.CheckoutRequestID, cb.ResultDesc);         // 1032 = user cancelled, 1037 = timeout
  }
});

// 4) Fallback when no callback lands within ~90s (lost callbacks happen): STK Query.
async function stkQuery(checkoutRequestId: string) {
  const ts = new Date().toISOString().replace(/\D/g, "").slice(0, 14);
  const password = Buffer.from(`${process.env.MPESA_SHORTCODE}${process.env.MPESA_PASSKEY}${ts}`).toString("base64");
  return fetch(`${BASE}/mpesa/stkpushquery/v1/query`, {
    method: "POST", headers: { Authorization: `Bearer ${await token()}`, "Content-Type": "application/json" },
    body: JSON.stringify({ BusinessShortCode: process.env.MPESA_SHORTCODE, Password: password, Timestamp: ts, CheckoutRequestID: checkoutRequestId }),
  }).then((x) => x.json());                                        // ResultCode 0 = paid
}
```

## MTN MoMo Collections — RequestToPay (X-Reference-Id is the idempotency key)

```ts
// mtn-momo-adapter.ts — amount is a STRING in MAJOR units; X-Reference-Id (UUID) dedupes + identifies.
import { randomUUID } from "node:crypto";
const MOMO = process.env.MOMO_ENV === "production"
  ? "https://proxy.momoapi.mtn.com" : "https://sandbox.momodeveloper.mtn.com";

async function momoToken() {
  const basic = Buffer.from(`${process.env.MOMO_API_USER}:${process.env.MOMO_API_KEY}`).toString("base64");
  const r = await fetch(`${MOMO}/collection/token/`, {
    method: "POST",
    headers: { Authorization: `Basic ${basic}`, "Ocp-Apim-Subscription-Key": process.env.MOMO_SUB_KEY! },
  }).then((x) => x.json());
  return r.access_token as string;                                  // ~1h
}

export async function requestToPay(i: { amount: Money; phoneE164: string; reference: string }) {
  const referenceId = randomUUID();                                // == your idempotency key AND txn id
  const r = await fetch(`${MOMO}/collection/v1_0/requesttopay`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${await momoToken()}`,
      "X-Reference-Id": referenceId,
      "X-Target-Environment": process.env.MOMO_TARGET!,             // sandbox | mtnghana | mtnnigeria | …
      "Ocp-Apim-Subscription-Key": process.env.MOMO_SUB_KEY!,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      amount: toMajorString(i.amount).replace(/\.00$/, ""),        // "100" — MAJOR units, string
      currency: i.amount.currency,                                  // GHS | XOF | EUR | UGX | …
      externalId: i.reference,
      payer: { partyIdType: "MSISDN", partyId: i.phoneE164.replace("+", "") },
      payerMessage: "Order", payeeNote: i.reference,
    }),
  });
  // 202 Accepted = received (async). Poll status; configure providerCallbackHost for a push too.
  return { providerRef: referenceId, status: "requires_action" as const, raw: { http: r.status } };
}

export async function momoStatus(referenceId: string) {
  const r = await fetch(`${MOMO}/collection/v1_0/requesttopay/${referenceId}`, {
    headers: { Authorization: `Bearer ${await momoToken()}`, "X-Target-Environment": process.env.MOMO_TARGET!,
               "Ocp-Apim-Subscription-Key": process.env.MOMO_SUB_KEY! },
  }).then((x) => x.json());
  return r.status as "PENDING" | "SUCCESSFUL" | "FAILED";
}
```

## Async UX (the part teams get wrong)

```
push → show "Check your phone and enter your M-Pesa/MoMo PIN" + spinner
     → poll your own backend every 3–5s (backend polls callback table, then STK Query/MoMo status)
     → resolve to paid / failed / timed-out (cap ~2 min); offer retry; NEVER assume instant success
```

## Global wallets — enable, don't build

- **Apple Pay / Google Pay**: turn on in your PSP, add the button (Stripe Payment Request Button / Express
  Checkout Element; Google Pay API). Token flows to the same PaymentIntent — no PAN, biometric auth.
- **Domain verification** (Apple Pay) and HTTPS are required; the wallet returns a network token, not a PAN.

## Edge cases

- **E.164 normalization**: store/compare as `+2547…`; strip `+` only at the wire where the API wants `2547…`.
  Reject/repair `07…`, `2547…`, `+2547…` inconsistently-formatted input before pushing.
- **Lost/duplicated callbacks**: dedupe by `CheckoutRequestID` / `X-Reference-Id`; poll status as fallback.
- **PIN timeout / cancel**: M-Pesa `1037` (timeout), `1032` (cancelled), `1` (insufficient) → map to soft/hard.
- **Whole-shilling M-Pesa**: never send `19.99`; `toWholeMajor` rounds — reconcile any rounding in the ledger.
- **B2C / disbursements**: the same providers send money out (refunds, seller payouts, salaries) — different
  product/keys (M-Pesa B2C, MoMo Disbursements); a refund is often a fresh B2C/disbursement, not a reversal.
- **Wrong X-Target-Environment / Subscription-Key** (Collections vs Disbursements) → silent failures.

## Performance, reliability & observability

- Cache OAuth tokens (M-Pesa ~1h, MoMo ~1h). A token mint per push will rate-limit you.
- Metrics: push→callback latency, % requiring poll-fallback, PIN-timeout rate, success rate per rail.
- Outbound float (Disbursements) must be funded — a B2C/payout fails on an empty float account; alert on balance.

## Testing

- **M-Pesa sandbox**: Shortcode `174379`, the sandbox passkey, test MSISDN `254708374149`; expose the
  callback via a public HTTPS tunnel. Assert duplicate callbacks fulfil once and STK Query reconciles a lost one.
- **MTN MoMo sandbox**: self-provision an API user/key; `X-Target-Environment: sandbox`; the sandbox
  amount can force `FAILED`/`SUCCESSFUL` outcomes — test both plus the status poll.

## Anti-patterns

- Building Apple/Google Pay from scratch instead of enabling them via the gateway.
- Synchronous UX assuming instant settlement (mobile money needs PIN-approval time).
- Trusting the push HTTP response/client result instead of the callback or status query.
- Non-idempotent callbacks → double fulfilment from telco retries.
- Sending decimals to M-Pesa, minor units to MoMo, or an un-normalized MSISDN.
- One `X-Reference-Id` reused across attempts (collision) or regenerated on a network retry (double charge).

## Agent checklist

```
- [ ] Global wallets enabled via the PSP + button added; domain verified (Apple Pay)
- [ ] African MoMo via aggregator or direct (M-Pesa Daraja / MTN MoMo) behind the adapter
- [ ] STK/RequestToPay: push → PIN → callback confirm → status-poll fallback (cap timeout)
- [ ] E.164 normalization; provider wire format (no +, 2547…/MSISDN) correct
- [ ] Idempotent callbacks (dedupe by CheckoutRequestID / X-Reference-Id); async UX with polling
- [ ] M-Pesa whole shillings / MoMo major-string; tokens cached; rounding reconciled
- [ ] B2C/disbursement path for refunds & payouts with funded float + balance alerts
```

## References (current 2026)

- M-Pesa Daraja (STK Push, STK Query, C2B/B2C): https://developer.safaricom.co.ke/APIs
- MTN MoMo Collections/Disbursements: https://momodeveloper.mtn.com/api-documentation
- Apple Pay on the web (via Stripe): https://docs.stripe.com/apple-pay · Google Pay: https://docs.stripe.com/google-pay
- Airtel: https://developers.airtel.africa · Orange: https://developer.orange.com · Wave: https://docs.wave.com

## Related

`payments-architecture`, `africa-payment-gateways`, `payment-webhooks-and-idempotency`,
`payment-orchestration-and-security`, `checkout-and-payment-pages`, `reconciliation-and-ledger`.
