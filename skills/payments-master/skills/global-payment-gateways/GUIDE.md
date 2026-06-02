---
name: global-payment-gateways
description: >-
  Integrate global PSPs at production depth — Stripe (PaymentIntents + Elements + webhook
  signing + idempotency), Adyen (/payments + HMAC notifications), PayPal Orders v2 (decimal
  strings + postback verify), plus Checkout.com, Braintree, Razorpay, Mollie, Klarna, and
  merchant-of-record (Paddle). Server-side intent creation, 3DS2/SCA, local methods (PIX/UPI/
  iDEAL/Alipay), tokenization, and per-provider money/webhook gotchas. Behind your adapter layer.
---

# Global Payment Gateways

**Create the intent server-side, collect on hosted fields, confirm on the webhook — for every PSP.**
The provider differs; the shape never does. Each PSP below is one `PaymentProvider` adapter
(`payments-architecture`). Pick by market, methods, payout reach, and price — then make them
interchangeable so orchestration can route and fail over.

## When to use / when NOT

- **Use** for cards + global wallets + local methods via worldwide PSPs, marketplaces (Stripe
  Connect / Adyen for Platforms), and tax-handled selling (merchant-of-record).
- **NOT** for African PSPs (`africa-payment-gateways`), wallet/mobile-money flows
  (`ewallets-and-mobile-money`), or routing/retry/fraud logic (`payment-orchestration-and-security`).

## DECISION MATRIX — pick the PSP

| Provider | Best for | Money on wire | Webhook auth | Watch out |
|----------|----------|---------------|--------------|-----------|
| **Stripe** ⭐ | SaaS/e-com, devs, marketplaces | integer minor units | `Stripe-Signature` HMAC, raw body | pin `apiVersion`; zero-decimal currency list |
| **Adyen** | Enterprise, omnichannel, global acquiring | integer minor units (`amount.value`) | HMAC-SHA256 in `additionalData.hmacSignature` | `/payments` sync result ≠ final; webhook is | 
| **PayPal** | Consumer wallet reach | **decimal string** (`"19.99"`) | postback to `verify-webhook-signature` | not minor units; auth valid ~29 days |
| **Checkout.com** | EMEA/MENA enterprise | integer minor units | HMAC (`cko-signature`) | strong in MENA; flow-based 3DS |
| **Braintree** (PayPal) | Cards + Venmo/PayPal (US) | decimal string | signed webhook (`bt_signature`) | GraphQL or SDK; drop-in |
| **Razorpay** | India (UPI/cards/netbanking) | integer paise | HMAC-SHA256 (`X-Razorpay-Signature`) | UPI collect is async |
| **Mollie** | EU (iDEAL/SEPA/Bancontact) | **decimal string** + currency | no payload sig → **always re-fetch** payment | pull status, don't trust body |
| **Klarna / Afterpay** | BNPL / installments | minor units (varies) | provider events | settlement & returns differ |
| **Paddle / Lemon Squeezy** | **Merchant-of-record** (SaaS, digital) | provider-managed | signed webhook | THEY are seller; handle global VAT/sales tax |

> **Merchant-of-record** (Paddle, Lemon Squeezy, 2Checkout) become the legal seller and remit global
> VAT/sales tax for you. For cross-border digital goods/SaaS this removes the single biggest
> compliance burden — at a higher fee. Use it when tax > engineering pain.

## Local payment methods — cards alone lose money abroad

| Region | Must-have methods |
|--------|-------------------|
| Europe | SEPA Direct Debit, **iDEAL** (NL), Bancontact (BE), Przelewy24 (PL), Giropay |
| LATAM | **PIX** (BR instant), Boleto, OXXO (MX), Mercado Pago |
| India | **UPI**, netbanking, RuPay |
| SE Asia | GrabPay, GCash, PayNow/PromptPay, FPX |
| China | **Alipay, WeChat Pay** |
| MENA | mada (KSA), KNET (KW), Benefit (BH), Checkout.com local acquiring |
| Global | Apple Pay, Google Pay, PayPal (`ewallets-and-mobile-money`) |

Enable methods per locale via **Stripe `automatic_payment_methods`** / **Adyen `/paymentMethods`** so
the right ones surface by country+currency. Offering the dominant local method is the #1 conversion lever.

## Stripe — server-side intent (copy-paste)

```ts
// stripe-adapter.ts — integer minor units; idempotency on every mutation; webhook is truth.
import Stripe from "stripe";
import type { PaymentProvider, CreatePaymentInput, PaymentResult, PaymentEvent } from "./payment-provider";

// Pin the API version so payloads/types don't shift under you. stripe-node defaults to its build's
// pinned version; pin explicitly to the version shown in your Dashboard. Current GA: 2026-05-27.dahlia.
const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!, {
  apiVersion: "2026-05-27.dahlia",
  maxNetworkRetries: 2, // SDK retries are idempotent (it sends an Idempotency-Key automatically)
});

export const stripeAdapter: PaymentProvider = {
  name: "stripe",

  async createPayment(i: CreatePaymentInput): Promise<PaymentResult> {
    const pi = await stripe.paymentIntents.create(
      {
        amount: i.amount.amount,                 // already integer minor units
        currency: i.amount.currency.toLowerCase(),
        capture_method: i.capture === "manual" ? "manual" : "automatic",
        automatic_payment_methods: { enabled: true }, // surfaces cards + wallets + local per locale
        metadata: { reference: i.reference, ...i.metadata },
        // off_session + a saved payment_method here ⇒ marks the charge as a Merchant-Initiated Txn (MIT)
      },
      { idempotencyKey: i.idempotencyKey },      // network retries never double-charge
    );
    return { providerRef: pi.id, status: "pending", clientSecret: pi.client_secret!, raw: pi };
  },

  async capture(ref, amount) {
    const pi = await stripe.paymentIntents.capture(ref, amount ? { amount_to_capture: amount.amount } : {});
    return { providerRef: pi.id, status: pi.status === "succeeded" ? "succeeded" : "authorized", raw: pi };
  },

  async refund(ref, amount, idemKey) {
    const r = await stripe.refunds.create(
      { payment_intent: ref, ...(amount ? { amount: amount.amount } : {}) },
      { idempotencyKey: idemKey ?? `refund:${ref}:${amount?.amount ?? "full"}` },
    );
    return { providerRef: r.id, status: amount ? "partially_refunded" : "refunded", raw: r };
  },

  async getStatus(ref) {
    const pi = await stripe.paymentIntents.retrieve(ref);
    return pi.status === "succeeded" ? "succeeded" : pi.status === "canceled" ? "cancelled" : "pending";
  },

  // RAW body is mandatory — JSON-parsing first breaks the signature (Stripe hides it in whitespace).
  async verifyAndParseWebhook(rawBody: Buffer, headers): Promise<PaymentEvent> {
    const event = stripe.webhooks.constructEvent(
      rawBody, headers["stripe-signature"], process.env.STRIPE_WEBHOOK_SECRET!, // whsec_… per endpoint
    );
    const pi = event.data.object as Stripe.PaymentIntent;
    const map: Record<string, PaymentEvent["type"]> = {
      "payment_intent.succeeded": "payment.succeeded",
      "payment_intent.payment_failed": "payment.failed",
      "charge.refunded": "payment.refunded",
      "charge.dispute.created": "dispute.created",
    };
    return {
      type: map[event.type] ?? "unknown",
      providerRef: pi.id,
      reference: pi.metadata?.reference,
      providerEventId: event.id,             // evt_… → webhook dedupe key
      occurredAt: new Date(event.created * 1000).toISOString(),
      raw: event,
    };
  },
};
```

```ts
// Express receiver — RAW body, verify, 2xx fast, process async. (Full pattern: payment-webhooks skill.)
app.post("/webhooks/stripe", express.raw({ type: "application/json" }), async (req, res) => {
  let evt: PaymentEvent;
  try { evt = await stripeAdapter.verifyAndParseWebhook(req.body, req.headers as any); }
  catch { return res.status(400).send("bad signature"); }   // never 5xx a bad signature → infinite retries
  await enqueue(evt);                                        // dedupe + reduce happens in the worker
  res.json({ received: true });                              // ack within Stripe's seconds-long timeout
});
```

## Adyen — the sync `/payments` result is NOT final

```ts
// Adyen: resultCode (Authorised/Refused/RedirectShown/Pending) is provisional. The AUTHORISATION
// webhook with success:"true" is the source of truth; verify its HMAC and ALWAYS reply "[accepted]".
import { Client, CheckoutAPI, hmacValidator } from "@adyen/api-library";
const adyen = new CheckoutAPI(new Client({ apiKey: process.env.ADYEN_API_KEY!, environment: "LIVE" }));

const res = await adyen.PaymentsApi.payments({
  amount: { value: input.amount.amount, currency: input.amount.currency }, // integer minor units
  reference: input.reference,
  paymentMethod: /* from /paymentMethods or Drop-in state.data */ undefined as any,
  merchantAccount: process.env.ADYEN_MERCHANT!,
  returnUrl: input.returnUrl,
}, { idempotencyKey: input.idempotencyKey });

// Webhook handler:
app.post("/webhooks/adyen", express.json(), (req, res) => {
  const v = new hmacValidator();
  for (const item of req.body.notificationItems) {
    const n = item.NotificationRequestItem;
    if (!v.validateHMAC(n, process.env.ADYEN_HMAC_KEY!)) return res.status(401).end();
    if (n.eventCode === "AUTHORISATION" && n.success === "true") { /* reduce by n.merchantReference */ }
  }
  res.send("[accepted]"); // Adyen REQUIRES this literal ack or it retries for days
});
```

## PayPal Orders v2 — decimal strings, not minor units

```ts
// 1) OAuth: POST /v1/oauth2/token (grant_type=client_credentials, Basic clientId:secret)
// 2) Create order — value is a DECIMAL STRING in major units; PayPal-Request-Id = idempotency.
const order = await fetch(`${PP}/v2/checkout/orders`, {
  method: "POST",
  headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json",
             "PayPal-Request-Id": input.idempotencyKey },
  body: JSON.stringify({
    intent: "CAPTURE", // or AUTHORIZE (hold ~29 days)
    purchase_units: [{ reference_id: input.reference,
      amount: { currency_code: input.amount.currency, value: toMajorString(input.amount) } }], // "19.99"
  }),
}).then((r) => r.json());
// 3) Buyer approves at the HATEOAS `approve` link → 4) POST /v2/checkout/orders/{id}/capture
// 5) Verify webhook by POSTING it back to /v1/notifications/verify-webhook-signature with the 5
//    PAYPAL-* headers + webhook_id; require verification_status === "SUCCESS". Use req.rawBody.
```

## Cross-provider essentials

- **Tokenization / cards-on-file**: store the *provider* token (Stripe `payment_method`/`customer`,
  Adyen `recurringDetailReference`), never the PAN. Reuse for repeat + subscriptions.
- **Authorize-then-capture** for ship-then-charge; partial capture for partial fulfilment; **auto** for instant.
- **3DS2 / SCA**: let the PSP run the challenge (`requires_action` → re-confirm). Request frictionless-first
  with full device data; tag MITs/exemptions. See `checkout-and-payment-pages` for the client handling.
- **Multi-currency**: present in the buyer's currency; know your **settlement** currency + FX spread; store
  the rate used (`reconciliation-and-ledger`).
- **Payout/settlement timing** (T+2…T+7) differs per PSP — feed it to reconciliation.

## Performance & reliability

- **Idempotent SDK retries** (`maxNetworkRetries`) for transient 5xx/timeouts; never re-issue a create
  without the same idempotency key.
- Cache OAuth tokens (PayPal ~9h, Adyen API key, M-Pesa 1h) — don't mint one per request.
- Webhook handler does **verify + enqueue only** (<50 ms); all real work is async and idempotent.
- Make the PSP a swappable adapter so orchestration can fail over on a technical decline/outage.

## Testing

- **Stripe**: test cards `4242…` (success), `4000 0027 6000 3184` (3DS2 challenge), `4000 0000 0000 9995`
  (insufficient funds); `stripe listen --forward-to` + `stripe trigger payment_intent.succeeded` to replay.
- **PayPal/Adyen/Checkout.com**: sandbox accounts + test cards; Adyen "Send test webhook" recalculates HMAC.
- Assert: idempotent double-create returns one charge; out-of-order/duplicate webhooks reduce once;
  partial capture + partial refund land correctly in the ledger.

## Anti-patterns

- Treating Adyen's sync `resultCode` / Stripe's client redirect as final instead of the webhook.
- PayPal/Flutterwave/Mollie amounts as minor units (they're major) → 100× errors.
- `express.json()` before the webhook route → signature verification fails every time.
- Hardcoding one PSP through the codebase; no adapter; no failover.
- Cards-only in PIX/UPI/iDEAL markets; ignoring SCA in the EEA → mass declines.
- Selling digital goods globally with no tax handling (consider merchant-of-record).

## Agent checklist

```
- [ ] Provider implemented as a PaymentProvider adapter; domain code stays canonical
- [ ] Server-side intent/order creation (amount from DB) + idempotency key on create/capture/refund
- [ ] Money formatted per provider (minor vs decimal-string vs major) at the adapter boundary
- [ ] Hosted fields/Elements (SAQ-A) + 3DS2/SCA handled via requires_action
- [ ] Relevant LOCAL methods enabled per country (automatic_payment_methods / paymentMethods)
- [ ] Webhook verified (raw body / HMAC / postback) + idempotent = source of truth
- [ ] OAuth tokens cached; SDK network retries idempotent; multi-currency + settlement tracked
```

## References (current 2026)

- Stripe PaymentIntents & webhooks: https://docs.stripe.com/payments/payment-intents · https://docs.stripe.com/webhooks/signature · versioning: https://docs.stripe.com/sdks/versioning
- Adyen sessions/payments + HMAC: https://docs.adyen.com/online-payments/ · https://docs.adyen.com/development-resources/webhooks/verify-hmac-signatures
- PayPal Orders v2 + webhook verify: https://developer.paypal.com/docs/api/orders/v2/ · https://developer.paypal.com/api/rest/webhooks/
- Checkout.com: https://www.checkout.com/docs · Razorpay: https://razorpay.com/docs · Mollie: https://docs.mollie.com

## Related

`payments-architecture`, `checkout-and-payment-pages`, `payment-orchestration-and-security`,
`payment-webhooks-and-idempotency`, `ewallets-and-mobile-money`; `adding-stripe`,
`stripe-best-practices` (backend-api-master).
