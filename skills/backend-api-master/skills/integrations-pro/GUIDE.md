---
name: integrations-pro
description: >-
  Build professional third-party integrations and connectors. Use for integrating
  external APIs/SaaS, building webhooks (in/out), OAuth connectors, sync engines,
  iPaaS-style flows, rate-limit/retry handling, and idempotency. Covers patterns
  for reliable, secure, observable integrations.
---

# Integrations Pro

Build reliable, secure, observable integrations with third-party APIs and SaaS.

## Integration patterns

| Pattern | When |
|---------|------|
| **Outbound webhooks** (you notify others) | Let customers react to your events |
| **Inbound webhooks** (others notify you) | React to Stripe/GitHub/etc. events |
| **Polling sync** | API has no webhooks; pull deltas on a schedule |
| **OAuth connector** | Act on behalf of a user's external account |
| **Batch/file** | Bulk import/export (CSV/SFTP) |

## Outbound webhooks (done right)

```
event occurs → enqueue delivery → POST to subscriber URL
  headers: X-Signature (HMAC-SHA256 of body), X-Event, X-Delivery-Id, timestamp
  retry with exponential backoff + jitter (e.g. 1m,5m,30m,2h,6h) up to N
  expose delivery log + manual "resend"; let users rotate signing secret
```
Sign every payload (HMAC) so receivers can verify authenticity.

## Inbound webhooks (receiving)

```
- [ ] Verify signature BEFORE parsing (use raw body)
- [ ] Return 2xx fast; do work async (enqueue, don't block)
- [ ] Idempotency: dedupe by event id (store processed ids)
- [ ] Handle out-of-order + duplicate delivery
- [ ] Log raw payloads for replay/debugging
```

## Reliability primitives (non-negotiable)

- **Idempotency keys** on all create/charge calls (avoid duplicates on retry).
- **Retries** with exponential backoff + jitter; cap attempts; **dead-letter queue** for failures.
- **Rate limiting**: respect `Retry-After` / `X-RateLimit-*`; token-bucket on your side.
- **Circuit breaker / timeout** on every outbound call (never hang forever).
- **Pagination**: handle cursor/offset; don't assume one page.

## OAuth connectors

Store per-connection: `access_token`, `refresh_token` (encrypted), `scopes`, `expires_at`.
Auto-refresh before expiry; handle revocation/re-auth; isolate tokens per tenant.
(See `google-sign-in` and `adding-auth` for OAuth flow details.)

## Sync engine (no webhooks)

- Track a **cursor** (updated_at / sequence) per source; pull deltas.
- Upsert into a normalized model; map external IDs ↔ internal IDs in a mapping table.
- Decide conflict resolution (last-write-wins vs source-of-truth) explicitly.

## Security & secrets
- Secrets in a vault / env, never in code or logs. Redact tokens in logs.
- Validate/scope inbound data; least-privilege scopes outbound.
- Per-tenant isolation of credentials.

## Observability
- Log every call (latency, status, retry count); correlation id across the flow.
- Metrics: success rate, p95 latency, queue depth, DLQ size; alert on spikes.

## Anti-patterns
- Doing webhook work synchronously in the request → timeouts & lost events.
- No idempotency → duplicate orders/charges on retry.
- Ignoring rate limits → bans/backpressure.
- Storing tokens in plaintext; one shared credential across tenants.
- No retry/DLQ → silent data loss when a provider blips.
