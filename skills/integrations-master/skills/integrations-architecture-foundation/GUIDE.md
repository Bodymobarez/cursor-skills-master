---
name: integrations-architecture-foundation
description: >-
  Staff-level foundation for every third-party integration: hexagonal adapter/port layer,
  inbound+outbound webhooks, polling/CDC sync, idempotency keys, retries with jittered backoff,
  DLQ + replay, token-bucket rate limiting, circuit breakers, per-tenant KMS secret vault,
  and correlation-ID observability. Read this BEFORE any platform-specific skill.
---

# Integrations Architecture — Foundation

**Mandate: an integration is a fault-tolerant distributed system, not a `fetch()` call.** The
network *will* flake, providers *will* send duplicates, tokens *will* expire mid-request, and a
tenant *will* hit a rate limit at 3am. Design for all four on day one or you will rebuild under fire.

> Extends `integrations-pro` (backend-api-master) with concrete implementation structure. Every
> platform skill in this master assumes the patterns below; they only add provider-specific deltas.

## When to use / when NOT

| Use this foundation | Don't bother (yet) |
|---------------------|--------------------|
| Any external system you read **and** write | One-off internal script, run once, deleted |
| Multi-tenant SaaS connecting customer accounts | Throwaway prototype with a single hardcoded key |
| Webhooks, OAuth, or sync involved | A pure outbound fire-and-forget log ping |
| You need an audit trail / replay | — |

## Decision 1 — which integration shape?

| Shape | Provider pushes? | Latency | Use when | Skill |
|-------|------------------|---------|----------|-------|
| **Inbound webhook** | Yes | seconds | Stripe/GitHub/Shopify notify you | `integrations-webhooks-events` |
| **Outbound webhook** | You push | seconds | You notify *your* customers' systems | `integrations-webhooks-events` |
| **OAuth user connector** | — | — | Act on a user's Google/Slack/Notion account | `integrations-oauth-api-keys` |
| **App / service auth** | — | — | Server-to-server (GitHub App, SF JWT, AWS) | `integrations-oauth-api-keys` |
| **Polling + cursor** | No | minutes | No webhooks, or backfill/reconciliation | `integrations-sync-engine-cdc` |
| **CDC / change stream** | DB-level | sub-second | DB-to-DB, log-based replication | `integrations-sync-engine-cdc` |
| **iPaaS connector** | varies | varies | No-code; you expose triggers/actions | `integrations-ipaas-n8n-zapier` |

Most real integrations combine **webhook (hot path) + polling reconcile (safety net)** — webhooks
are best-effort, never exactly-once. The poll catches what the webhook dropped.

## Decision 2 — hexagonal adapter (mandatory)

Define a **narrow port** in your domain; each provider gets an **adapter**. Business logic depends
on the port, never on `api.hubspot.com`. This is what makes providers swappable and testable.

```ts
// ports/crm.ts — domain owns this interface, not the vendor
export interface CrmPort {
  upsertContact(input: ContactInput): Promise<{ externalId: string }>;
  listDealsUpdatedSince(cursor: string | null): Promise<DealPage>;
}
export interface DealPage { deals: Deal[]; nextCursor: string | null }

// adapters/hubspot.ts — all vendor knowledge quarantined here
export class HubSpotAdapter implements CrmPort { /* fetch + mapping live ONLY here */ }
export class SalesforceAdapter implements CrmPort { /* ... */ }
```

**Never** scatter raw `fetch('https://api.hubspot.com/...')` across services. One leak and a vendor
migration becomes a six-month archaeology project.

## Connection model (per tenant, encrypted)

```sql
CREATE TABLE integrations (
  id              uuid PRIMARY KEY,
  tenant_id       uuid NOT NULL,
  provider        text NOT NULL,                 -- 'github' | 'hubspot' | ...
  status          text NOT NULL,                 -- active | needs_reauth | disabled
  access_token_enc  bytea,                        -- AES-256-GCM ciphertext (envelope-encrypted)
  refresh_token_enc bytea,
  dek_wrapped       bytea,                         -- data key wrapped by KMS CMK
  expires_at      timestamptz,
  scopes          text[],
  external_account_id text,                        -- the org/installation/workspace id
  metadata        jsonb,
  created_at      timestamptz DEFAULT now(),
  UNIQUE (tenant_id, provider, external_account_id)
);
CREATE TABLE integration_sync_cursors (integration_id uuid, resource text, cursor text,
  PRIMARY KEY (integration_id, resource));
CREATE TABLE processed_events (provider text, event_id text, processed_at timestamptz DEFAULT now(),
  PRIMARY KEY (provider, event_id));                -- idempotency ledger
CREATE TABLE integration_dlq (id uuid PRIMARY KEY, integration_id uuid, payload jsonb,
  error text, attempts int, last_attempt_at timestamptz, replayable bool DEFAULT true);
```

## Reliability — the four non-negotiables

**1. Idempotency.** Send `Idempotency-Key: <uuid>` on every create (Stripe/most modern APIs honor
it). On the receive side, dedupe by the provider's event id in `processed_events`.

```ts
// outbound idempotency: derive a stable key from the business intent, not Math.random()
const key = `${tenantId}:invoice:${invoiceId}:create`;  // retries reuse the SAME key
await stripe.invoices.create(body, { idempotencyKey: key });
```

**2. Retries with jittered exponential backoff + a budget.** Retry only idempotent/safe ops; cap
attempts; never retry a 4xx (except 408/429).

```ts
export async function withRetry<T>(fn: () => Promise<T>, opts = { max: 5, baseMs: 200 }): Promise<T> {
  let attempt = 0;
  for (;;) {
    try { return await fn(); }
    catch (e) {
      const status = (e as any)?.status;
      const retriable = status === 429 || status === 408 || (status >= 500 && status < 600) || status == null;
      if (!retriable || ++attempt >= opts.max) throw e;
      const retryAfter = Number((e as any)?.headers?.["retry-after"]) * 1000;
      const expo = opts.baseMs * 2 ** (attempt - 1);
      const jitter = Math.random() * expo;                       // full jitter (AWS) avoids stampede
      await sleep(Number.isFinite(retryAfter) && retryAfter > 0 ? retryAfter : Math.min(expo / 2 + jitter, 30_000));
    }
  }
}
```

**3. Circuit breaker.** After N consecutive failures, open the circuit (fail fast for `cooldown`),
then half-open one probe. Protects you from hammering a down provider and from cascading timeouts.

**4. DLQ + replay.** Exhausted retries → dead-letter row with full payload + error. Expose an
operator "replay" button. A DLQ you can't replay is just an error log.

## Rate limits — respect the contract

- Always honor `Retry-After` (seconds *or* HTTP-date) and `X-RateLimit-Remaining`/`Reset`.
- Run a **token bucket per `integration_id`** (per tenant per provider), not one global limiter —
  one noisy tenant must not starve the rest. Size it just under the provider's published quota.
- Prefer **bulk/batch endpoints** (HubSpot `batch/upsert`, Shopify bulk) over N single calls.

## Inbound webhook handler (the canonical 5 lines that matter)

```ts
export async function POST(req: Request) {
  const raw = await req.text();                              // 1. RAW bytes — never req.json() first
  if (!verifySignature(provider, raw, req.headers)) return new Response("bad sig", { status: 401 });
  const event = JSON.parse(raw);
  const fresh = await claimEventId(provider, event.id);      // 2. idempotent INSERT ... ON CONFLICT
  if (!fresh) return new Response("ok");                      // 3. duplicate → 200, do nothing
  await queue.enqueue("integration-events", { provider, raw, headers: pick(req.headers) }); // 4. async
  return new Response("ok", { status: 200 });                // 5. ACK fast (<1s); process off-thread
}
```

Signature verification details per provider live in `integrations-webhooks-events`. The shape never
changes: **verify on raw body → dedupe → enqueue → 200 fast → process in a worker.**

## Outbound webhook delivery (you as the provider)

```
POST subscriber_url
  X-Webhook-Id: <delivery uuid>      X-Webhook-Timestamp: <unix>
  X-Webhook-Signature: t=<ts>,v1=<hex HMAC-SHA256 of "ts.body">   # Stripe-style, signed secret/tenant
Retry schedule: 0s, 1m, 5m, 30m, 2h, 6h (then DLQ) — give subscribers a dashboard + manual replay.
```

Sign with a **per-subscriber secret**, support secret rotation (two active secrets during overlap),
and publish a JSON-schema'd event catalog so subscribers can verify exactly like you do.

## Security (treat every integration as hostile boundary)

- **Tokens at rest**: envelope encryption (KMS-wrapped DEK + AES-256-GCM), never plaintext columns.
  See `integrations-oauth-api-keys` for the vault.
- **Least privilege**: request the minimum scopes; document why each exists.
- **SSRF defense on outbound/user-supplied URLs**: deny RFC-1918/link-local/metadata IPs
  (`169.254.169.254`), resolve+pin DNS, no redirects to internal hosts. This is the #1 webhook-relay
  and "import from URL" vulnerability.
- **Validate inbound payloads with Zod** before any side effect; providers add/rename fields.
- Log **redacted** tokens only (`sk_live_…abcd`), never full secrets.

## Multi-tenant & scale

- One **token bucket + circuit breaker per `integration_id`** — isolation is the whole point.
- Queue topology: `events.incoming → worker → events.retry (delayed) → events.dlq`.
- Backpressure: bound worker concurrency per provider; shed load to the queue, never to the DB.
- Workers must be **idempotent and stateless** — any message can be redelivered.

## Observability

- **Correlation id** = `tenant_id` + `integration_id` + `delivery_id`, propagated through every log,
  span, and queue message.
- Golden metrics per provider: `webhook_verify_fail_total`, `delivery_success_rate`, `p95_latency`,
  `retry_count`, `dlq_depth`, `token_refresh_fail_total`, `rate_limit_hit_total`.
- Alert on `dlq_depth > 0` and `needs_reauth` count — both are silent revenue killers.

## Testing

- Golden fixtures of real provider payloads in `tests/fixtures/<provider>/`.
- A signature test per provider (valid passes, tampered body fails, stale timestamp fails).
- Contract-test adapters against the **port**, with the provider behind a recorded mock (Nock/MSW).
- Chaos: inject 429/500/timeout and assert backoff + DLQ behavior.

## Anti-patterns

- Synchronous webhook processing > ~1s (you'll miss the ACK window and get re-delivered storms).
- One global API key / token bucket shared across all tenants.
- `JSON.parse` before signature verification (breaks the raw-body HMAC every time).
- No `external_id ↔ internal_id` mapping table → infinite-loop syncs and dup records.
- Retrying non-idempotent writes without an idempotency key.
- Storing tokens in plaintext, in env vars per tenant, or in the SPA.

## Agent checklist

```
- [ ] Port interface defined; vendor code only inside its adapter
- [ ] Inbound: verify(raw) → dedupe(event_id) → enqueue → 200 fast → worker processes
- [ ] Idempotency key on every create; processed_events ledger on every receive
- [ ] Retry w/ full jitter + cap + Retry-After honored; circuit breaker per integration
- [ ] DLQ row on exhaustion + operator replay path
- [ ] Tokens envelope-encrypted (KMS); least-priv scopes; SSRF guard on outbound URLs
- [ ] Token bucket per integration_id; bulk endpoints preferred
- [ ] Correlation id everywhere; dlq_depth + needs_reauth alerts wired
```

## References

- AWS "Exponential Backoff and Jitter": https://aws.amazon.com/blogs/architecture/exponential-backoff-and-jitter/
- Stripe idempotent requests: https://docs.stripe.com/api/idempotent_requests
- OWASP SSRF Prevention Cheat Sheet: https://cheatsheetseries.owasp.org/cheatsheets/Server_Side_Request_Forgery_Prevention_Cheat_Sheet.html
- Webhooks.fyi (cross-provider patterns): https://webhooks.fyi

## Related

`integrations-oauth-api-keys`, `integrations-webhooks-events`, `integrations-resilience-rate-limits`,
`integrations-sync-engine-cdc`, `integrations-platform-index`
