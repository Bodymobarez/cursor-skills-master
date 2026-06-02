---
name: payments-architecture
description: >-
  Architect a multi-gateway payment system at staff/principal depth: provider-agnostic
  adapter layer, a canonical Payment model + explicit state machine, integer minor-units
  Money with per-provider formatting, idempotency-key derivation, webhooks-as-source-of-truth,
  the authorize/capture/refund lifecycle, and PCI SAQ-A scope. Read FIRST; it defines the
  contracts every gateway/wallet/checkout/orchestration skill implements.
---

# Payments Architecture

**Your application must never know which PSP charged the card.** Business logic speaks one
canonical model; every gateway/wallet lives behind an adapter that translates to/from it. If you
can't swap Stripe for Adyen (or add Paystack for Nigeria) by writing one adapter and a routing rule
— without touching order, ledger, or fulfilment code — the abstraction is broken and this skill
hasn't been applied. Get this layer right once; everything else is an adapter.

## When to use / when NOT

- **Use** at the start of any payments work, and any time you add a second provider, a new market,
  or a new method (card → mobile money). This skill defines the interfaces the other five skills fill in.
- **NOT** a place for provider-specific code. Stripe/Adyen/Paystack specifics live in
  `global-payment-gateways`, `africa-payment-gateways`, `ewallets-and-mobile-money`. Routing/failover
  lives in `payment-orchestration-and-security`. Webhook plumbing → `payment-webhooks-and-idempotency`.
  Settlement accounting → `reconciliation-and-ledger`.

## Architecture (the layering that survives 5 providers)

```
        order/cart/subscription domain  ── speaks ONLY canonical Payment ──┐
                                                                           │
   PaymentService (orchestration: routing, failover, retries)             │
        │  resolves canonical request → provider                          │
        ▼                                                                  │
   PaymentProvider interface  ◄──────────── adapters implement it ────────┘
        ├── StripeAdapter      (minor units, PaymentIntents)
        ├── AdyenAdapter       (minor units, /payments)
        ├── PaystackAdapter    (minor units / kobo)
        ├── FlutterwaveAdapter (⚠ MAJOR units)
        ├── PaymobAdapter      (minor units, Intention API)
        ├── MpesaAdapter       (whole KES, STK push)
        └── MtnMomoAdapter     (MAJOR units string, RequestToPay)
   Money (integer minor units) ── formatted to each provider AT THE ADAPTER BOUNDARY
   PaymentEvent (canonical) ◄── every webhook normalises into this
```

The single most important rule: **money is stored and reasoned about as integer minor units
everywhere in your system, and converted to each provider's wire format only inside that provider's
adapter.** Providers disagree wildly on money format (see matrix) — that disagreement must never
leak past the adapter.

## DECISION MATRIX — provider money & confirmation semantics (verify per account)

| Provider | Wire amount format | Idempotency mechanism | Final-state source |
|----------|--------------------|-----------------------|--------------------|
| **Stripe** | integer minor units (`amount: 1999`) | `Idempotency-Key` header | webhook `payment_intent.succeeded` |
| **Adyen** | integer minor units (`amount.value`) | `idempotencyKey` / `Idempotency-Key` | webhook `AUTHORISATION` (success="true") |
| **PayPal** | **decimal string major** (`"19.99"`) | `PayPal-Request-Id` header | capture response + `PAYMENT.CAPTURE.COMPLETED` |
| **Paystack** | integer minor units (kobo/pesewa/cent) | reuse your `reference` | `GET /transaction/verify/:ref` + webhook |
| **Flutterwave** | **MAJOR units** (`amount: 1000` = ₦1000) | reuse your `tx_ref` | `GET /transactions/:id/verify` + webhook |
| **Paymob** | integer minor units (piastres) | your `special_reference` | callback HMAC + transaction inquiry |
| **M-Pesa Daraja** | **whole shillings** integer (no cents) | `AccountReference` + dedupe | STK callback / STK query |
| **MTN MoMo** | **major units string** (`"100"`) | `X-Reference-Id` (UUID) | `GET requesttopay/{ref}` + callback |

> The four ⚠ rows (PayPal, Flutterwave, M-Pesa, MTN) are where teams lose money: a 100× over/under
> charge or a duplicate. Encode each in the adapter and unit-test the conversion.

## Money — the one module everything imports

```ts
// money.ts — integer minor units + ISO-4217 currency. Never a float, never a bare number.
export type Currency = "USD" | "EUR" | "GBP" | "NGN" | "KES" | "EGP" | "GHS" | "ZAR"
  | "XOF" | "XAF" | "JPY" | "KWD" | "BHD" | "TND" /* … */;

export interface Money { readonly amount: number; readonly currency: Currency } // amount = minor units

// ISO-4217 exponent: how many minor units per major unit. THIS is the source of truth.
const EXPONENT: Record<string, number> = {
  JPY: 0, KRW: 0, XOF: 0, XAF: 0, CLP: 0, VND: 0, // zero-decimal — DO NOT ×100
  BHD: 3, KWD: 3, OMR: 3, TND: 3, JOD: 3,          // three-decimal — ×1000
  // default for everything else (USD, EUR, NGN, KES, EGP, GHS, ZAR, …) = 2
};
export const exponent = (c: Currency) => EXPONENT[c] ?? 2;

export const money = (amount: number, currency: Currency): Money => {
  if (!Number.isInteger(amount)) throw new Error(`Money must be integer minor units, got ${amount}`);
  return { amount, currency };
};

// Boundary converters — used ONLY inside adapters, never in business logic.
export const toMajorString = (m: Money) =>
  (m.amount / 10 ** exponent(m.currency)).toFixed(exponent(m.currency)); // "19.99" — PayPal/Fawry
export const toMajorNumber = (m: Money) => m.amount / 10 ** exponent(m.currency); // 1000 — Flutterwave
export const toWholeMajor = (m: Money) => Math.round(m.amount / 10 ** exponent(m.currency)); // KES — M-Pesa

// Allocation without losing cents (split a charge across N — fees, marketplace payouts).
export const allocate = (m: Money, weights: number[]): Money[] => {
  const total = weights.reduce((a, b) => a + b, 0);
  let remainder = m.amount;
  const out = weights.map((w) => {
    const share = Math.floor((m.amount * w) / total);
    remainder -= share;
    return share;
  });
  for (let i = 0; remainder > 0; i++, remainder--) out[i % out.length]++; // largest-remainder
  return out.map((a) => money(a, m.currency));
};
```

> **Never** `parseFloat`, `*100`, or `toFixed` in business logic. The exponent table is the only place
> the ×100-vs-not decision is made. XOF/XAF (×1) and BHD/KWD (×1000) bugs are common and expensive.

## The canonical contract every adapter implements

```ts
// payment-provider.ts
export type PaymentMethod = "card" | "wallet" | "bank" | "mobile_money" | "bnpl" | "voucher";

export type PaymentStatus =
  | "initiated" | "pending" | "requires_action"  // 3DS / redirect / STK / USSD / voucher
  | "authorized" | "succeeded"
  | "failed" | "cancelled" | "expired"
  | "refunded" | "partially_refunded";

export interface CreatePaymentInput {
  amount: Money;                       // from YOUR DB, never the client
  method: PaymentMethod;
  idempotencyKey: string;              // see derivation below
  reference: string;                   // your order id; survives into provider + webhook
  customer: { id: string; email?: string; phoneE164?: string };
  capture?: "automatic" | "manual";    // manual = authorize-only (delayed capture)
  returnUrl?: string;                  // for redirect/3DS flows
  metadata?: Record<string, string>;
}

export interface PaymentResult {
  providerRef: string;                 // provider's id (pi_…, psp ref, tx id)
  status: PaymentStatus;
  clientSecret?: string;               // Stripe Elements / Paymob client secret
  redirectUrl?: string;                // hosted page / approval / bank redirect
  raw: unknown;                        // ALWAYS persist the raw provider payload (audit/debug)
}

export interface PaymentProvider {
  readonly name: string;
  createPayment(i: CreatePaymentInput): Promise<PaymentResult>;
  capture(providerRef: string, amount?: Money): Promise<PaymentResult>; // partial capture allowed
  refund(providerRef: string, amount?: Money, idemKey?: string): Promise<PaymentResult>;
  getStatus(providerRef: string): Promise<PaymentStatus>;
  verifyAndParseWebhook(rawBody: Buffer, headers: Record<string, string>): Promise<PaymentEvent>;
}

export interface PaymentEvent {
  type: "payment.succeeded" | "payment.failed" | "payment.refunded" | "dispute.created" | "unknown";
  providerRef: string;
  reference?: string;
  amount?: Money;
  providerEventId: string;             // dedupe key for idempotent webhook handling
  occurredAt: string;
  raw: unknown;
}
```

## State machine — enforce legal transitions, reject illegal ones

A payment row is a state machine. Webhooks arrive **out of order and more than once**; an
illegal/duplicate transition must be a no-op, not a corruption.

```ts
const NEXT: Record<PaymentStatus, PaymentStatus[]> = {
  initiated: ["pending", "requires_action", "authorized", "succeeded", "failed", "cancelled", "expired"],
  pending: ["requires_action", "authorized", "succeeded", "failed", "cancelled", "expired"],
  requires_action: ["authorized", "succeeded", "failed", "cancelled", "expired"],
  authorized: ["succeeded", "cancelled", "expired", "failed"],     // capture / void / auth-expiry
  succeeded: ["refunded", "partially_refunded"],                   // terminal except refunds
  partially_refunded: ["refunded", "partially_refunded"],
  refunded: [], failed: [], cancelled: [], expired: [],
};
export const canTransition = (from: PaymentStatus, to: PaymentStatus) =>
  from === to || NEXT[from].includes(to); // idempotent: same→same is allowed (no-op)
```

Persist transitions with a DB guard so a late `pending` webhook can't move a `succeeded` row backwards:

```sql
UPDATE payments SET status = $next, updated_at = now()
WHERE id = $id AND status = $expectedFrom;   -- 0 rows affected ⇒ already advanced; ignore
```

## Idempotency keys — derive them, don't sprinkle UUIDs

An idempotency key must be **stable for "the same logical attempt"** so a network retry reuses it,
but **distinct across genuinely new attempts** (the customer re-tries after fixing their card).

```ts
import { createHash } from "node:crypto";
// stable per (order, attempt, operation, amount): a retry of the SAME attempt reuses the key.
export const idemKey = (orderId: string, attempt: number, op: string, m: Money) =>
  createHash("sha256").update(`${orderId}:${attempt}:${op}:${m.amount}:${m.currency}`).digest("hex");
```

- **create/capture/refund** each get a key. Refund key includes the refund amount so two different
  partial refunds don't collapse into one.
- Keys are **request-side** dedupe (don't double-charge on retry). They are *not* the same as webhook
  dedupe (provider event id) — you need **both**. See `payment-webhooks-and-idempotency`.

## Lifecycle (universal, with the failure branches)

```
1 CREATE intent server-side  (amount from DB, idempotency key, capture mode)
2 PRESENT method             (Elements/hosted page/redirect/STK prompt)
3 AUTHENTICATE if required   (3DS2 challenge, OTP, STK PIN, bank approval) → requires_action
4 AUTHORIZE → CAPTURE        (auto, or manual for ship-then-charge) ; or fail
5 CONFIRM via WEBHOOK        (source of truth; client redirect can be lost) → reconcile state machine
6 SETTLE → RECONCILE         (payout T+n vs ledger) ; REFUND / DISPUTE handling
```

## Edge cases this layer must own (not push onto callers)

- **Double-submit / retry storm** → request idempotency key makes create/capture/refund safe.
- **Customer drops off after paying** → webhook (not redirect) finalises; show "pending" if unknown.
- **Out-of-order webhooks** → state machine + DB guard; never advance backwards.
- **Partial capture / partial refund** → `capture(ref, amount)` / `refund(ref, amount)`; ledger reflects both.
- **Authorization expiry** (PayPal ~29 days, cards vary) → background sweep voids/expires stale auths.
- **Async/voucher** (Fawry reference, bank transfer, M-Pesa PIN delay) → `requires_action` + poll fallback.
- **Zero/negative/rounding** → reject in `money()`; never construct amounts client-side.

## Security (PCI scope is an architecture decision, made here)

- **Stay SAQ-A**: PAN/CVV never touch your servers — hosted fields/redirect/tokenization only. The
  moment raw card data hits your box you are **SAQ-D** (pen tests, ASV scans, segmentation; ~300 controls).
- **Never persist CVV/CVV2** (prohibited after authorization, full stop) and avoid storing PAN — store
  a **provider token** instead.
- Server is the **sole** source of the amount; the client sends an order id, never a price.
- Secrets in a vault/KMS, not env files in git; rotate webhook signing secrets per environment.

## Observability & reliability built into the model

- Persist `raw` on every create and every event → replay, dispute evidence, debugging.
- Emit metrics keyed by `provider`: authorization rate, p95 create latency, webhook lag, decline-code
  histogram. Routing/failover (orchestration skill) is only as good as these signals.
- One **idempotent reducer** applies `PaymentEvent`s to the payment + ledger so re-delivery is safe.

## Build roadmap

```
- [ ] Money module (exponent table) + boundary converters + tests for XOF/BHD/JPY
- [ ] PaymentProvider interface + canonical Payment model + state machine guard
- [ ] First adapter (usually Stripe) + idempotency-key derivation
- [ ] Webhook receiver: verify → dedupe → enqueue → idempotent reduce (webhooks skill)
- [ ] Add providers by market (global / africa / ewallets skills) behind the same interface
- [ ] Checkout page at minimal PCI scope (checkout skill)
- [ ] Routing/failover/fraud/retries (orchestration skill)
- [ ] Settlement reconciliation + double-entry ledger (reconciliation-and-ledger skill)
```

## Anti-patterns

- Provider types leaking into domain code (`if (stripePI.status === …)` in an order service).
- `number`/`float`/`Decimal`-as-major-units for money; constructing amounts on the client.
- One idempotency UUID per process/request instead of a **derived, stable** key.
- Treating the client redirect as confirmation; advancing fulfilment before the webhook.
- A `status: string` column with no transition guard (silent backward moves, double fulfilment).
- "We'll add the second gateway later" with Stripe calls hardwired through the codebase.

## Agent checklist

```
- [ ] No provider SDK type crosses the adapter boundary into domain/order/ledger code
- [ ] All money is integer minor units; conversion happens ONLY in adapters; XOF/BHD/JPY tested
- [ ] Every create/capture/refund carries a derived idempotency key
- [ ] Webhook is source of truth; state machine guards every transition (DB-level)
- [ ] Raw provider payloads persisted on create + every event
- [ ] PCI scope is SAQ-A by construction; no PAN/CVV on our servers
- [ ] Adding a provider = one adapter + one routing rule; zero domain edits
```

## References (current 2026)

- Stripe PaymentIntents: https://docs.stripe.com/payments/payment-intents · API versioning (`2026-05-27.dahlia`): https://docs.stripe.com/sdks/versioning
- ISO-4217 currency exponents: https://en.wikipedia.org/wiki/ISO_4217 · Stripe zero-decimal list: https://docs.stripe.com/currencies#zero-decimal
- PCI DSS v4.0.1 SAQ-A: https://www.pcisecuritystandards.org/document_library/
- Idempotency: https://docs.stripe.com/api/idempotent_requests

## Related

`global-payment-gateways`, `africa-payment-gateways`, `ewallets-and-mobile-money`,
`checkout-and-payment-pages`, `payment-orchestration-and-security`, `payment-webhooks-and-idempotency`,
`reconciliation-and-ledger`; `accounting-finance` (business-master).
