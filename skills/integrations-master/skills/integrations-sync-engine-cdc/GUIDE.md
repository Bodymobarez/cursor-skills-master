---
name: integrations-sync-engine-cdc
description: >-
  Staff-level data-sync engine: full vs incremental vs CDC, durable cursors/watermarks/sync-tokens,
  the transactional outbox (kill dual-writes), Debezium/log-based CDC, idempotent upserts, tombstone
  deletes, reconciliation/drift repair, conflict resolution (LWW / per-field source-of-truth / vector
  clocks), and resumable backfill. Use whenever you mirror data between systems reliably.
---

# Sync Engine & CDC

**Mandate: sync is a checkpointed, idempotent, resumable pipeline — never a fire-and-forget loop, and
never a dual-write.** Webhooks are best-effort and lossy; the durable truth is an incremental cursor
plus a periodic reconcile. If your "sync" can't crash mid-run and resume exactly where it left off
without duplicating or dropping records, it isn't a sync engine yet.

## Decision — which sync strategy

| Strategy | Latency | Cost | Use when |
|----------|---------|------|----------|
| **Full snapshot** | high | high | First load, small datasets, or repair after corruption |
| **Incremental (cursor)** | minutes | low | `updated_since`/sync-token available; the workhorse |
| **CDC (log-based)** | sub-second | medium | DB-to-DB, need every change incl. deletes, no app hooks |
| **Webhook + reconcile** | seconds + safety net | low | Provider pushes; poll backfills missed events |

Reality: **webhooks for the hot path + incremental poll for completeness.** Webhooks alone are never
a complete record — they drop during your downtime and arrive unordered.

## Cursors & watermarks (the heart of it)

Persist a durable cursor per `(integration_id, resource)`; advance it **only after** the batch is
committed, so a crash re-reads (at-least-once) rather than skips (lossy).

```ts
async function syncResource(integ: string, resource: string, adapter: Port) {
  let cursor = await cursors.load(integ, resource);          // null on first run → full snapshot
  for (;;) {
    const page = await adapter.changesSince(cursor);         // updated_since / syncToken / deltaLink
    await db.transaction(async (tx) => {
      for (const rec of page.items) await upsert(tx, integ, rec);   // idempotent (below)
      await cursors.save(tx, integ, resource, page.nextCursor);     // advance INSIDE the same tx
    });
    if (!page.hasMore) break;
    await checkpoint(integ, resource);                       // resumable; safe to kill here
  }
}
```

- **High-water-mark caveat**: an `updated_at`-based cursor misses records written with an equal/earlier
  timestamp during the read (clock skew, batch commits). Overlap the window (re-read the last few
  seconds) and dedupe, or use a monotonic change id / sequence where the provider offers one.
- Provider token expiry (Google **410 GONE**, expired delta) → discard cursor, full resync.

## Idempotent upsert + tombstones

```ts
// upsert keyed by external id; version-guard so an out-of-order OLD event can't clobber a NEW one
async function upsert(tx, integ, rec) {
  if (rec.deleted) {                                         // tombstone: deletes arrive as events too
    await tx`UPDATE entities SET deleted_at=now() WHERE integ=${integ} AND ext_id=${rec.id}`;
    return;
  }
  await tx`
    INSERT INTO entities (integ, ext_id, data, ext_version, updated_at)
    VALUES (${integ}, ${rec.id}, ${rec.data}, ${rec.version}, ${rec.updatedAt})
    ON CONFLICT (integ, ext_id) DO UPDATE SET data=EXCLUDED.data, ext_version=EXCLUDED.ext_version,
      updated_at=EXCLUDED.updated_at
    WHERE entities.ext_version < EXCLUDED.ext_version`;       // drop stale/reordered events
}
```

At-least-once + unordered delivery is the norm — the `ext_version`/`updated_at` guard makes replays
and reordering harmless.

## Kill dual-writes: the transactional outbox

Writing to your DB **and** calling the external API in one request is a distributed-transaction trap —
one succeeds, the other fails, data diverges. Instead, write the business row and an `outbox` row in
**one local transaction**; a relay publishes the outbox afterward (at-least-once, idempotent consumer).

```sql
BEGIN;
  INSERT INTO orders (...) VALUES (...);
  INSERT INTO outbox (id, topic, payload) VALUES (gen_random_uuid(), 'order.created', $1);
COMMIT;                          -- relay/CDC tails outbox → publishes → marks sent
```

The relay can poll the outbox or, better, **CDC-tail** it. This is the canonical fix for the
dual-write problem and gives you an exactly-once-*effect* pipeline with idempotent consumers.

## CDC (log-based change data capture)

For DB-to-DB or "capture every change including deletes without touching app code": tail the
**transaction log** (Postgres logical replication / `wal2json`, MySQL binlog, Mongo change streams),
typically via **Debezium → Kafka**. You get ordered, low-latency change events with before/after images
and tombstones for deletes. Manage **schema evolution** (a registry) and **snapshot + stream** (initial
snapshot then switch to streaming at the captured LSN/offset). Checkpoint the consumer offset durably.

## Reconciliation & drift repair

Even with webhooks + CDC, systems drift (missed events, manual edits, bugs). Run a periodic reconcile:

```
nightly: page both sides by key → compare a content hash → emit diffs
  missing here  → pull + upsert
  missing there → push (or tombstone, per policy)
  mismatch      → apply conflict policy, log the drift
```

Reconcile is your safety net and your audit. Track `drift_detected_total` — a rising trend means the
hot path is dropping events.

## Conflict resolution (decide BEFORE you code)

| Policy | Use when |
|--------|----------|
| **Last-write-wins (timestamp)** | Simple, single-writer-ish; needs synced clocks (watch skew) |
| **Per-field source-of-truth** | "Jira owns status, we own priority" — most B2B sync |
| **Vector clocks / version vectors** | True multi-master concurrent edits; expensive, rare |
| **Manual review queue** | High-value records where wrong-merge is costly |

Pair with the **loop-guard** from `integrations-pm-notion-linear-jira`: an origin tag + content hash so
you don't re-sync your own writes into an infinite echo.

## Backfill at scale

- Chunk by key range or time window; checkpoint each chunk; make it **resumable** (idempotent upserts
  mean a re-run is safe).
- Throttle against the source's rate limit (see `integrations-resilience-rate-limits`); run backfill on
  a separate, lower-priority lane so it never starves live sync.
- Prefer the provider's **bulk export** (Shopify bulkOperation, Salesforce Bulk 2.0, GA export) over
  paginated live reads for the initial load.

## Observability

- `sync_lag_seconds` (now − cursor time), `records_synced_total{direction}`, `cursor_reset_total`
  (410s), `drift_detected_total`, `outbox_pending`, CDC `connector_state` + consumer lag, conflict count.
- Alert on stalled cursors (lag climbing), growing outbox backlog, and CDC connector failure.

## Anti-patterns

- Dual-write (DB + API in one request) with no outbox → guaranteed eventual divergence.
- Advancing the cursor before the batch commits → silent data loss on crash.
- `updated_at >` cursor with no overlap/dedupe → missed records on equal timestamps / skew.
- Ignoring deletes (no tombstones) → ghost records forever.
- Blind LWW with unsynced clocks across systems.
- Backfill that can't resume (re-runs duplicate everything).

## Agent checklist

```
- [ ] Strategy chosen (full / incremental / CDC / webhook+reconcile) and documented
- [ ] Durable cursor per (integration,resource); advanced only after commit; resumable checkpoints
- [ ] Idempotent upsert keyed by external id + version guard; tombstones handled
- [ ] Transactional outbox (no dual-writes); relay/CDC publishes at-least-once
- [ ] Periodic reconcile compares hashes + repairs drift; conflict policy explicit
- [ ] Backfill chunked, throttled, resumable, on a separate lane; bulk export for initial load
- [ ] sync_lag / drift / outbox metrics + stalled-cursor alerts
```

## References

- Transactional Outbox (microservices.io): https://microservices.io/patterns/data/transactional-outbox.html
- Debezium CDC: https://debezium.io/documentation/ · Postgres logical replication: https://www.postgresql.org/docs/current/logical-replication.html
- Change Data Capture (Kleppmann, DDIA ch.11 concepts): https://martin.kleppmann.com/2015/06/02/change-data-capture-complex-streaming-analytics.html

## Related

`integrations-architecture-foundation`, `integrations-resilience-rate-limits`,
`integrations-pm-notion-linear-jira` (loop-safe two-way), `integrations-crm-salesforce-hubspot`
