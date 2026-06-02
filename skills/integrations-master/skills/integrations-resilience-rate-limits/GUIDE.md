---
name: integrations-resilience-rate-limits
description: >-
  Staff-level integration resilience: token-bucket + adaptive-concurrency rate limiting per tenant,
  retries with full jitter and a retry budget, circuit breakers, bulkheads, timeouts/hedging, queue
  topology with delayed-retry + DLQ + replay, poison-message handling, and idempotency. Use to make
  any third-party call survive flakiness, throttling, and provider outages without melting your system.
---

# Integration Resilience & Rate Limits

**Mandate: every outbound call to a third party must be rate-limited per tenant, retried with a
budget, wrapped in a circuit breaker, and time-bounded — and every retry must be idempotent.** The
provider's rate limit is a contract you obey *proactively*; 429s should be rare because you throttled
yourself first. This skill is the deep dive that `integrations-architecture-foundation` only summarizes.

## When to reach for this

| Reach for it | Skip (foundation summary is enough) |
|--------------|-------------------------------------|
| Outbound volume that can hit provider limits | A single low-frequency call |
| Multi-tenant — one tenant can't starve others | Internal-only, no external dependency |
| Provider has flaky uptime / strict quotas | Provider is your own service with SLOs |
| Webhook fan-out / bulk sync workloads | One-shot script |

## The resilience stack (compose, in this order)

```
caller → [token bucket] → [bulkhead/concurrency] → [circuit breaker] → [timeout] → [retry w/ budget] → provider
                                                                                          └→ DLQ on exhaustion
```

Each layer answers a different failure: bucket = *don't exceed quota*, bulkhead = *don't exhaust your
own pool*, breaker = *don't hammer a dead provider*, timeout = *don't hang forever*, retry = *survive
transient blips*, DLQ = *don't lose the message*.

## 1. Rate limiting — token bucket per integration

One global limiter is wrong: a noisy tenant throttles everyone. Run a bucket **per `integration_id`**
(tenant × provider), sized just under the provider's published quota.

```ts
// Distributed token bucket in Redis (atomic via Lua) — works across N app instances
const BUCKET = `
local key, rate, cap, now, cost = KEYS[1], tonumber(ARGV[1]), tonumber(ARGV[2]), tonumber(ARGV[3]), tonumber(ARGV[4])
local b = redis.call('HMGET', key, 'tokens', 'ts')
local tokens = tonumber(b[1]) or cap
local ts = tonumber(b[2]) or now
tokens = math.min(cap, tokens + (now - ts) * rate)        -- refill since last call
if tokens < cost then
  redis.call('HMSET', key, 'tokens', tokens, 'ts', now); redis.call('PEXPIRE', key, 60000)
  return math.ceil((cost - tokens) / rate * 1000)         -- ms to wait
end
redis.call('HMSET', key, 'tokens', tokens - cost, 'ts', now); redis.call('PEXPIRE', key, 60000)
return 0`;
async function acquire(integrationId: string, ratePerSec: number, cap: number, cost = 1) {
  const waitMs = await redis.eval(BUCKET, 1, `rl:${integrationId}`, ratePerSec, cap, Date.now(), cost);
  if (waitMs > 0) await sleep(Number(waitMs));            // or reject + enqueue for backpressure
}
```

**Adaptive concurrency** (AIMD): start with a small concurrency limit, increase on success, halve on
429/5xx — it discovers the provider's real ceiling without a hardcoded guess. **Honor the server**:
always obey `Retry-After` and read `X-RateLimit-Remaining`/`Reset` (Shopify: GraphQL cost points) to
slow down *before* you get blocked.

## 2. Retries — full jitter + a budget

```ts
async function withRetry<T>(fn: () => Promise<T>, o = { max: 5, baseMs: 200, capMs: 30_000 }): Promise<T> {
  for (let attempt = 1; ; attempt++) {
    try { return await fn(); }
    catch (e: any) {
      const s = e?.status;
      const retriable = s === 429 || s === 408 || (s >= 500 && s < 600) || e?.code === "ETIMEDOUT" || s == null;
      if (!retriable || attempt >= o.max || !retryBudget.tryConsume()) throw e;   // budget guards retry storms
      const ra = Number(e?.headers?.["retry-after"]) * 1000;
      const expo = Math.min(o.capMs, o.baseMs * 2 ** (attempt - 1));
      await sleep(Number.isFinite(ra) && ra > 0 ? ra : Math.random() * expo);      // FULL jitter
    }
  }
}
```

- **Full jitter** (`random(0, expo)`) beats fixed/equal jitter at preventing synchronized retry
  stampedes after an outage (AWS Architecture Blog).
- **Retry budget**: cap retries to e.g. 10% of requests over a rolling window. Without it, a provider
  brownout turns into a self-inflicted DDoS (the "retry storm").
- **Only retry idempotent ops.** Non-idempotent writes need an idempotency key first, or no retry.

## 3. Circuit breaker + bulkhead

```ts
// Breaker: closed → (N failures) → open (fail fast for cooldown) → half-open (1 probe) → closed/open
class Breaker {
  private fails = 0; private openedAt = 0; state: "closed" | "open" | "half" = "closed";
  constructor(private threshold = 5, private cooldownMs = 30_000) {}
  async run<T>(fn: () => Promise<T>): Promise<T> {
    if (this.state === "open") {
      if (Date.now() - this.openedAt < this.cooldownMs) throw new Error("circuit_open"); // fail fast
      this.state = "half";
    }
    try { const r = await fn(); this.fails = 0; this.state = "closed"; return r; }
    catch (e) { if (++this.fails >= this.threshold) { this.state = "open"; this.openedAt = Date.now(); } throw e; }
  }
}
```

**One breaker per provider/integration** so a down HubSpot doesn't open the circuit for Slack.
**Bulkhead**: cap concurrent calls per provider (a semaphore) so one slow dependency can't consume your
whole worker pool and cascade. Always set a **timeout** (5–30s) on every HTTP call — no timeout is the
quietest outage there is.

## 4. Queue topology — delayed retry + DLQ + replay

```
events.incoming ──▶ worker ──success──▶ done
                     │
                     ├─retriable─▶ events.retry (delay backoff: 1m,5m,30m,2h) ─▶ worker
                     └─exhausted─▶ events.dlq (full payload + error + attempts)
                                         └─ operator replay ─▶ events.incoming
```

- Use a delay/visibility-timeout queue (SQS delay, Rabbit DLX + TTL, BullMQ backoff) for the retry tier.
- **DLQ rows store the full payload + headers + last error + attempt count** so replay is possible.
  A DLQ you can't replay is just a log.
- **Poison messages**: cap redeliveries (`maxReceiveCount`) → DLQ; never let one bad message wedge the
  consumer forever. Make consumers idempotent so replay is safe.

## Idempotency (the precondition for all retries)

- Outbound: stable `Idempotency-Key` derived from business intent (`tenant:invoice:123:create`), reused
  on every retry.
- Inbound/worker: dedupe by provider event id in a `processed_events` ledger (atomic
  `INSERT … ON CONFLICT` / DynamoDB conditional put).

## Observability (you can't tune what you can't see)

- Per provider/integration: `rate_limit_wait_ms`, `429_total`, `retry_count`, `retry_budget_exhausted`,
  `breaker_state` (gauge), `timeout_total`, `dlq_depth`, `dlq_replay_total`, p50/p95/p99 latency.
- **Alert on**: `breaker_state=open`, `dlq_depth>0`, retry budget exhaustion, oldest-retry age.
- Tag every metric/log with the correlation id (`tenant:integration:delivery`).

## Performance

- Prefer **bulk/batch** endpoints over N calls (the cheapest rate-limit win there is).
- Coalesce duplicate in-flight requests (single-flight) for hot reads; cache idempotent GETs + ETags.
- Keep retry delays bounded (`capMs`) so the queue drains; backpressure to the queue, never to the DB.

## Testing

- Fault injection: a mock provider that returns 429/`Retry-After`, 500, and timeouts on demand.
- Assert: bucket throttles before quota, retries back off with jitter, breaker opens/half-opens/closes,
  exhausted messages land in DLQ, replay reprocesses idempotently (no double effect).
- Load test per-tenant isolation: hammer tenant A, prove tenant B's throughput is unaffected.

## Anti-patterns

- One global rate limiter / breaker shared across tenants and providers.
- Retries with no jitter, no cap, no budget (synchronized stampede / self-DDoS).
- Retrying non-idempotent writes.
- No timeout on HTTP calls (silent hangs exhaust the pool).
- DLQ with no payload/replay; poison messages with unbounded redelivery.
- Reacting only to 429 instead of proactively throttling off remaining/cost headers.

## Agent checklist

```
- [ ] Token bucket per integration_id, sized under provider quota; Retry-After + remaining headers honored
- [ ] Adaptive concurrency (AIMD) or a sane per-provider concurrency cap (bulkhead)
- [ ] Retries: full jitter, capped, retry budget, idempotent ops only
- [ ] Circuit breaker + timeout per provider; fail fast when open
- [ ] Delayed-retry queue → DLQ with full payload + operator replay; poison-message cap
- [ ] Idempotency keys (out) + dedupe ledger (in); metrics + breaker/DLQ alerts wired
```

## References

- AWS Exponential Backoff and Jitter: https://aws.amazon.com/blogs/architecture/exponential-backoff-and-jitter/
- Google SRE — Handling Overload / retry budgets: https://sre.google/sre-book/handling-overload/
- Circuit Breaker (Fowler): https://martinfowler.com/bliki/CircuitBreaker.html
- Stripe rate limits: https://docs.stripe.com/rate-limits · Shopify GraphQL cost: https://shopify.dev/docs/api/usage/rate-limits

## Related

`integrations-architecture-foundation`, `integrations-webhooks-events`, `integrations-cloud-aws-gcp-azure`,
`integrations-sync-engine-cdc`
