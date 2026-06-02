---
name: payment-webhooks-and-idempotency
description: >-
  The webhook backbone at staff depth — verify (Stripe/Adyen/PayPal/Paystack/Flutterwave/Paymob/
  M-Pesa/MTN signature schemes), ack fast, enqueue, and reduce idempotently. Raw-body capture,
  event-id dedupe with a DB unique constraint, out-of-order handling, replay & dead-letter, request
  idempotency keys vs event dedupe, the never-5xx-a-bad-signature rule, and reconcile-not-trust. The
  most bug-prone surface in payments — give it its own hardened pipeline.
---

# Payment Webhooks & Idempotency

**The webhook is the source of truth, and it WILL arrive twice, out of order, and from impostors.**
Every payment system needs exactly one hardened pipeline: **verify → ack 2xx fast → enqueue → reduce
idempotently**. Get the five invariants below right and the rest of payments becomes reliable; get
them wrong and you ship double-charges, double-fulfilment, and "paid but not credited" tickets.

## The five invariants (memorize)

1. **Verify on the RAW body.** Any JSON parse before verification breaks HMAC signatures (the signature
   covers exact bytes/whitespace). Capture raw bytes first.
2. **Never 5xx a bad signature.** Return **400** and drop it — a 5xx makes the provider retry a forged
   or malformed event forever. Reserve non-2xx (or 5xx) for *your* transient failures you want retried.
3. **Ack within seconds, work async.** Verify + enqueue only (<50 ms), return 2xx; do real work in a
   worker. Providers have short timeouts and will retry if you block.
4. **Dedupe by provider event id** with a DB unique constraint — delivery is **at-least-once**.
5. **Reconcile, don't trust.** For African/redirect PSPs especially, re-verify by reference (amount +
   currency + status) before granting value; treat the payload as a *trigger*, not proof.

> Two different idempotency concepts, both required: **request idempotency keys** (stop double-charge
> on API retry, set on create/capture/refund — see `payments-architecture`) and **event dedupe** (stop
> double-processing of redelivered webhooks, here). They are not interchangeable.

## DECISION MATRIX — verification per provider (current 2026)

| Provider | Where | Scheme | Verify how |
|----------|-------|--------|-----------|
| **Stripe** | `Stripe-Signature` header | HMAC-SHA256, timestamped (`t=,v1=`) | `stripe.webhooks.constructEvent(raw, sig, whsec_…)`; dedupe `evt_…` |
| **Adyen** | `additionalData.hmacSignature` (in body) | HMAC-SHA256 over a field subset | `new hmacValidator().validateHMAC(item, key)`; reply `"[accepted]"` |
| **PayPal** | 5 `PAYPAL-*` headers | asymmetric (cert) → **postback** | POST to `/v1/notifications/verify-webhook-signature`; require `SUCCESS` |
| **Paystack** | `x-paystack-signature` | HMAC-SHA512 with **secret key** | `hmac512(secret, rawBody)`; then verify-by-reference |
| **Flutterwave** | `verif-hash` (v3) / signed (v4) | shared secret / HMAC | compare constant-time; then re-query `/transactions/:id/verify` |
| **Paymob** | `hmac` query param | HMAC-SHA512 over sorted values | concat documented keys' values; compare |
| **M-Pesa** | — (no signature) | IP allowlist | allowlist Safaricom IPs; reconcile via STK Query |
| **MTN MoMo** | callback to your host | poll-confirmed | trust `X-Reference-Id` + GET status; verify amount |

## The pipeline (provider-agnostic, copy-paste)

```ts
// 1) Ingest: verify on raw body, ack fast, enqueue. ONE route per provider; same shape.
app.post("/webhooks/:provider", express.raw({ type: "*/*" }), async (req, res) => {
  const adapter = registry.get(req.params.provider);            // StripeAdapter, PaystackAdapter, …
  let evt: PaymentEvent;
  try {
    evt = await adapter.verifyAndParseWebhook(req.body, req.headers as Record<string, string>);
  } catch {
    return res.status(400).send("invalid signature");           // 4xx ⇒ provider stops retrying a forgery
  }
  // Stripe wants {received:true}; Adyen REQUIRES "[accepted]"; M-Pesa wants {ResultCode:0}. Per adapter:
  res.status(200).send(adapter.ackBody ?? "ok");
  await queue.add(evt.type, { provider: req.params.provider, evt }, {
    jobId: evt.providerEventId,                                 // queue-level dedupe within the active window
    attempts: 8, backoff: { type: "exponential", delay: 5_000 },
  });
});
```

```sql
-- 2) Dedupe table: the unique constraint is the dedupe mechanism. Insert BEFORE doing work.
CREATE TABLE processed_events (
  provider          text        NOT NULL,
  provider_event_id text        NOT NULL,
  received_at       timestamptz NOT NULL DEFAULT now(),
  status            text        NOT NULL DEFAULT 'processing',  -- processing | done | dead
  payload           jsonb       NOT NULL,
  PRIMARY KEY (provider, provider_event_id)
);
```

```ts
// 3) Worker: claim via unique-insert, then reduce inside a transaction. Re-delivery is a no-op.
async function handle({ provider, evt }: { provider: string; evt: PaymentEvent }) {
  try {
    await db.query(
      `INSERT INTO processed_events(provider, provider_event_id, payload) VALUES ($1,$2,$3)`,
      [provider, evt.providerEventId, evt.raw],
    );
  } catch (e: any) {
    if (e.code === "23505") return;                             // unique_violation ⇒ already seen; skip
    throw e;
  }
  await db.transaction(async (tx) => {
    // state-machine guarded update (payments-architecture): late/out-of-order events can't move backward
    const moved = await tx.query(
      `UPDATE payments SET status=$1, updated_at=now()
         WHERE reference=$2 AND status = ANY($3)`,           // only advance from legal predecessor states
      [reduce(evt), evt.reference, legalPredecessors(reduce(evt))],
    );
    if (moved.rowCount) await postLedgerEntries(tx, evt);     // reconciliation-and-ledger
    await tx.query(`UPDATE processed_events SET status='done' WHERE provider=$1 AND provider_event_id=$2`,
      [provider, evt.providerEventId]);
  });
}
```

## Out-of-order & missing events

- **Out of order**: a `payment.failed` can arrive after `payment.succeeded` (retried delivery). The
  **state machine guard** (`UPDATE … WHERE status = ANY(legalPredecessors)`) makes the illegal
  transition a no-op. Never code `if (event) status = event.status`.
- **Missing/lost**: providers don't guarantee delivery forever. Run a **sweeper** that polls
  `getStatus()`/verify-by-reference for payments stuck in `pending`/`requires_action` past a threshold
  (also the M-Pesa STK Query / MoMo status path).
- **Duplicate with different data**: keep the first; log divergence. (Shouldn't happen with a stable event id.)

## Replay & dead-letter

- **Persist every raw event** (`processed_events.payload`) → you can re-run the reducer after a bug fix
  without asking the provider to resend.
- After N failed attempts, move the job to a **dead-letter queue** with the error; alert; expose an
  admin **manual replay** that re-enqueues by event id (dedupe keeps it safe).
- Stripe/Adyen/PayPal also let you **resend from their dashboard** and run a CLI listener
  (`stripe listen`/`stripe trigger`) for local replay.

## Security

- HMAC verify is mandatory where available; **constant-time compare** (`crypto.timingSafeEqual`) — never `===`.
- **Per-endpoint, per-environment signing secret** (Stripe `whsec_` differs test vs live vs each endpoint).
  Store in a vault; rotate on leak.
- **Reject stale events**: enforce a max age via the signed timestamp (Stripe tolerance, your own clock
  skew window) to blunt replay attacks.
- For unsigned callbacks (M-Pesa): **IP-allowlist** + always reconcile by query; never fulfil on the body alone.
- HTTPS only; the webhook URL is public — assume hostile input on every field.

## Performance & scale

- Ingest endpoint does verify+enqueue only; horizontal-scale workers behind the queue.
- The dedupe `INSERT` is O(1) on the PK; partition/TTL old `processed_events` (e.g., 90 days) to bound size.
- Backpressure: a slow downstream must not block ingest (you already 2xx'd) — the queue absorbs spikes.

## Testing

- **Replay/duplicate**: deliver the same event id twice → exactly one ledger effect.
- **Out-of-order**: deliver succeeded then failed → row stays succeeded.
- **Bad signature** → 400 and no processing; **transient downstream error** → retried then dead-lettered.
- Stripe: `stripe trigger payment_intent.succeeded`; Adyen "test webhook" recalculates HMAC; PayPal
  webhook simulator; Paystack/Flutterwave dashboard resend.

## Anti-patterns

- `express.json()` before the webhook route (Stripe/Paystack signature fails every time).
- Returning 500 on a bad signature → infinite retry of garbage; or returning 200 on *your* failure → event lost.
- Processing synchronously in the request → timeouts → provider retries → duplicates.
- Dedupe by `(amount, time)` or no dedupe at all instead of the **provider event id**.
- Trusting the payload without verify-by-reference (amount/currency/status) on redirect/African PSPs.
- Mutating state with `status = event.status` and no transition guard (backward moves, double fulfil).

## Agent checklist

```
- [ ] Raw body captured; signature verified per provider (constant-time); bad sig ⇒ 400, not 5xx
- [ ] Ack 2xx fast (correct ack body: {received} / "[accepted]" / {ResultCode:0}); work async on a queue
- [ ] Dedupe by (provider, event id) via DB unique constraint before any work
- [ ] Reduce in a transaction with state-machine guard; ledger posted only on a real transition
- [ ] Sweeper polls stuck pending/requires_action (STK Query / MoMo status / getStatus)
- [ ] Raw events persisted; dead-letter + manual replay; per-endpoint secret in vault; stale-event rejection
- [ ] Verify-by-reference (amount+currency+status) before granting value on redirect/African PSPs
```

## References (current 2026)

- Stripe webhooks/signature: https://docs.stripe.com/webhooks · https://docs.stripe.com/webhooks/signature
- Adyen verify HMAC: https://docs.adyen.com/development-resources/webhooks/verify-hmac-signatures
- PayPal verify-webhook-signature: https://developer.paypal.com/api/rest/webhooks/rest/
- Paystack webhooks: https://paystack.com/docs/payments/webhooks/ · Flutterwave: https://developer.flutterwave.com/docs/webhooks · Paymob HMAC: https://developers.paymob.com

## Related

`payments-architecture`, `payment-orchestration-and-security`, `reconciliation-and-ledger`,
`global-payment-gateways`, `africa-payment-gateways`, `ewallets-and-mobile-money`;
`integrations-pro` webhooks (backend-api-master).
