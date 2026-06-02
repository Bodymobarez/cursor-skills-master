---
name: integrations-webhooks-events
description: >-
  Staff-level webhook engineering: exact 2026 signature schemes per provider (GitHub, Stripe,
  Shopify, Slack, Discord ed25519, HubSpot v3, Notion, Linear, GitLab), raw-body HMAC on the
  receive path, replay/clock-skew defense, idempotent async processing, ordering, and signed
  outbound delivery with retries, rotation, and a subscriber replay API.
---

# Webhooks & Events

**Mandate: verify the signature on the RAW request bytes, dedupe by event id, ACK 200 in under a
second, and do the real work in a worker.** Every webhook outage traces back to violating one of
those four. Webhooks are *at-least-once and unordered* — design for duplicates and reordering, never
assume exactly-once.

## When to use / NOT

| Use webhooks | Use polling/CDC instead |
|--------------|-------------------------|
| Provider offers them + you need low latency | Provider has none (Notion *automation* only, some legacy) |
| Event-driven side effects (paid → provision) | You need a guaranteed complete history / backfill |
| Paired with a reconcile poll as safety net | Strict ordering across entities required |

## The one rule that breaks everyone: raw body

Any JSON middleware that parses then re-serializes the body changes bytes (whitespace, key order,
unicode) and **every HMAC fails**. Capture raw bytes before parsing.

```ts
// Express: keep the raw buffer for webhook routes only
app.use("/webhooks", express.raw({ type: "*/*" }));   // req.body is a Buffer here
// Next.js App Router / Hono / Workers: const raw = await req.text();  (already raw)
```

## Signature schemes — verified, current (2026)

| Provider | Header(s) | Alg | Encoding | Signed material | Replay guard |
|----------|-----------|-----|----------|-----------------|--------------|
| **GitHub** | `X-Hub-Signature-256` | HMAC-SHA256 | hex, `sha256=` | raw body | dedupe `X-GitHub-Delivery` |
| **Stripe** | `Stripe-Signature` `t=,v1=` | HMAC-SHA256 | hex | `"{t}.{raw}"` | `t` tolerance 300s |
| **Shopify** | `X-Shopify-Hmac-SHA256` | HMAC-SHA256 | **base64** | raw body (key=app secret) | dedupe `X-Shopify-Webhook-Id` |
| **Slack** | `X-Slack-Signature` `v0=` + `X-Slack-Request-Timestamp` | HMAC-SHA256 | hex | `"v0:{ts}:{raw}"` | ts ±300s |
| **Discord** | `X-Signature-Ed25519` + `X-Signature-Timestamp` | **Ed25519** (asymmetric) | hex | `"{ts}{raw}"` | PING handshake |
| **HubSpot v3** | `X-HubSpot-Signature-v3` + `X-HubSpot-Request-Timestamp`(ms) | HMAC-SHA256 | **base64** | `method+fullURL+raw+ts` | ts 300s |
| **Notion** | `X-Notion-Signature` `sha256=` | HMAC-SHA256 | hex | raw body (key=`verification_token`) | one-time token setup |
| **Linear** | `Linear-Signature` + `Linear-Delivery` + `Linear-Event` | HMAC-SHA256 | hex | raw body | body `webhookTimestamp` 60s |
| **GitLab** | `X-Gitlab-Token` | shared secret | plain | — (token compare) | use HTTPS + constant-time |
| **WooCommerce** | `X-WC-Webhook-Signature` | HMAC-SHA256 | base64 | raw body | dedupe delivery id |

Watch the **encoding trap**: Stripe/GitHub/Slack/Notion/Linear are **hex**; Shopify/HubSpot/WooCommerce
are **base64**. Copy-pasting a Stripe verifier into a Shopify route is the classic silent failure.

## Production verifiers (constant-time, raw body)

```ts
import { createHmac, timingSafeEqual } from "crypto";
import nacl from "tweetnacl";

const safeEq = (a: string, b: string) =>
  a.length === b.length && timingSafeEqual(Buffer.from(a), Buffer.from(b));

// GitHub — sha256=<hex>
export const verifyGitHub = (raw: Buffer, sig = "", secret: string) =>
  safeEq(sig, "sha256=" + createHmac("sha256", secret).update(raw).digest("hex"));

// Stripe — t=...,v1=...  signed payload is `${t}.${raw}`; reject schemes != v1; enforce tolerance
export function verifyStripe(raw: Buffer, header = "", secret: string, toleranceS = 300) {
  const parts = Object.fromEntries(header.split(",").map((kv) => kv.split("=")));
  const t = Number(parts["t"]); const v1 = parts["v1"];
  if (!t || !v1) return false;
  if (Math.abs(Date.now() / 1000 - t) > toleranceS) return false;           // replay window
  const expected = createHmac("sha256", secret).update(`${t}.${raw}`).digest("hex");
  return safeEq(v1, expected);
}
// …or just: stripe.webhooks.constructEvent(raw, header, whsec) — it does all of the above.

// Slack — base string v0:{ts}:{raw}; reject ts older than 5 min
export function verifySlack(raw: Buffer, sig = "", ts = "", secret: string) {
  if (Math.abs(Date.now() / 1000 - Number(ts)) > 300) return false;
  const expected = "v0=" + createHmac("sha256", secret).update(`v0:${ts}:${raw}`).digest("hex");
  return safeEq(sig, expected);
}

// Shopify — base64, NOT hex; key is the app client secret
export const verifyShopify = (raw: Buffer, hmac = "", secret: string) =>
  safeEq(hmac, createHmac("sha256", secret).update(raw).digest("base64"));

// HubSpot v3 — base64 over method+fullUrl+raw+timestamp; ts in ms; full URL incl. query
export function verifyHubSpot(method: string, fullUrl: string, raw: Buffer, sig = "", ts = "", secret: string) {
  if (Date.now() - Number(ts) > 300_000) return false;                      // ts is milliseconds
  const base = method + fullUrl + raw.toString("utf8") + ts;
  return safeEq(sig, createHmac("sha256", secret).update(base, "utf8").digest("base64"));
}

// Discord — Ed25519 asymmetric: verify {timestamp}{raw} against the app PUBLIC key (no shared secret)
export const verifyDiscord = (raw: Buffer, sig = "", ts = "", publicKeyHex: string) =>
  nacl.sign.detached.verify(
    Buffer.concat([Buffer.from(ts), raw]),
    Buffer.from(sig, "hex"),
    Buffer.from(publicKeyHex, "hex"),
  );

// Linear — hex; also assert body.webhookTimestamp within 60s
export const verifyLinear = (raw: Buffer, sig = "", secret: string) =>
  safeEq(sig, createHmac("sha256", secret).update(raw).digest("hex"));
```

**Discord & Slack send a handshake**: Discord posts an `interaction.type === 1` PING — reply
`{ type: 1 }`. Slack URL verification posts `{type:"url_verification", challenge}` — echo the
`challenge`. Notion posts a one-time `{verification_token}` you paste back into the dashboard; that
token then becomes the HMAC key.

## The canonical handler

```ts
export async function POST(req: Request) {
  const raw = Buffer.from(await req.arrayBuffer());                 // RAW first
  const h = req.headers;
  if (!verifyShopify(raw, h.get("x-shopify-hmac-sha256") ?? "", SECRET))
    return new Response("bad signature", { status: 401 });

  const eventId = h.get("x-shopify-webhook-id")!;                   // provider-stable delivery id
  const fresh = await db.query(                                     // idempotent claim
    `INSERT INTO processed_events(provider,event_id) VALUES('shopify',$1)
     ON CONFLICT DO NOTHING RETURNING event_id`, [eventId]);
  if (fresh.rowCount === 0) return new Response("ok");              // duplicate → no-op

  await queue.enqueue("integration-events", {                      // hand off; do NOT process inline
    provider: "shopify", topic: h.get("x-shopify-topic"), raw: raw.toString(), eventId });
  return new Response("ok", { status: 200 });                      // ACK < 1s
}
```

## Event router (in the worker, not the handler)

```ts
const handlers: Record<string, (e: Event) => Promise<void>> = {
  "orders/create": handleOrderCreate,
  "pull_request.opened": handlePrOpened,
  "invoice.paid": handleInvoicePaid,
};
const fn = handlers[topic];
if (!fn) { metrics.inc("webhook_unhandled_total", { topic }); return; } // log + drop, don't 500
await fn(JSON.parse(raw));                                              // validate with Zod inside
```

## Ordering & idempotency at the entity level

At-least-once + unordered means: an `updated` can arrive before the `created`, and any event twice.
Defend with **entity version/updated_at guards** — drop an event whose payload is older than what
you've stored. Make every handler a safe upsert keyed by external id.

## Outbound delivery (you emit webhooks)

```
POST {subscriber.url}
  X-Webhook-Id: <uuid>     X-Webhook-Timestamp: <unix>
  X-Webhook-Signature: t=<ts>,v1=<HMAC-SHA256(secret,"ts.body") hex>   # Stripe-style; document it
Retries: 0, 1m, 5m, 30m, 2h, 6h → DLQ. Treat non-2xx / timeout as failure. Disable after N days dead.
```

Ship for subscribers: a **JSON-schema'd event catalog**, **secret rotation** (two active secrets in
overlap), a **delivery log + manual replay API**, and ideally an idempotency key so they can dedupe.
SSRF-guard subscriber URLs (block RFC-1918 / `169.254.169.254`, pin DNS, no internal redirects).

## Performance & scale

- Verification is cheap; the work isn't — keep the HTTP handler to verify+enqueue only.
- Bound worker concurrency per provider; one tenant's burst can't starve others (token bucket).
- High volume → partition the queue by `tenant_id`/entity to preserve per-entity order while
  parallelizing across entities.

## Testing

- Golden fixtures per provider in `tests/fixtures/webhooks/<provider>/`.
- Three signature tests each: valid passes, **one-byte-tampered body fails**, **stale timestamp fails**.
- Local delivery: `stripe listen --forward-to localhost:3000/webhooks/stripe`; GitHub → smee.io or
  `gh api` replays; Shopify CLI `app webhook trigger`; Slack/Discord re-send from their dashboards.

## Observability

- `webhook_received_total{provider,topic}`, `webhook_verify_fail_total` (alert — usually a secret
  rotation gone wrong or an attack), `webhook_dedup_hits_total`, worker `lag`, `dlq_depth`.
- Log the correlation id (`provider:event_id`) on every step.

## Anti-patterns

- `await req.json()` before verifying (kills the HMAC).
- `===` on signatures (timing leak) → always `timingSafeEqual`.
- Processing synchronously in the handler → missed ACK window → re-delivery storms.
- No dedupe ledger → double-charges, double-provisions.
- Returning 500 for an *unhandled* event type (the provider retries forever) — 200 and drop.
- Trusting `payload.timestamp` from the body for replay defense when the provider signs a header ts.

## Agent checklist

```
- [ ] Raw body captured before any parsing
- [ ] Correct alg + ENCODING per provider (hex vs base64; Ed25519 for Discord)
- [ ] Timestamp/replay window enforced where the provider provides one
- [ ] timingSafeEqual everywhere; handshake (PING/challenge/verification_token) handled
- [ ] Dedupe by provider delivery id; 200 fast; process in worker
- [ ] Outbound: signed, retried, rotatable secret, replay API, SSRF-guarded
```

## References

- Stripe: https://docs.stripe.com/webhooks · Slack: https://docs.slack.dev/authentication/verifying-requests-from-slack
- GitHub: https://docs.github.com/en/webhooks/using-webhooks/validating-webhook-deliveries
- Shopify: https://shopify.dev/docs/apps/build/webhooks/verify-deliveries · Discord: https://discord.com/developers/docs/interactions/overview
- HubSpot: https://developers.hubspot.com/docs/apps/developer-platform/build-apps/authentication/request-validation
- Notion: https://developers.notion.com/reference/webhooks · Linear: https://linear.app/developers/webhooks

## Related

`integrations-architecture-foundation`, `integrations-oauth-api-keys`,
`integrations-resilience-rate-limits`, and every provider skill in this master
