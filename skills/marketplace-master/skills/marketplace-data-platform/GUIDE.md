---
name: marketplace-data-platform
description: >-
  Scale and measure a marketplace at staff/principal depth — the data + multi-tenancy
  layer: OLTP/OLAP split, the outbox→CDC→stream→read-model pipeline (CQRS), multi-tenant
  isolation (shared+RLS vs schema vs DB vs shard-per-tenant), seller-balance + buy-box
  read models, the canonical GMV / take-rate / liquidity / cohort metric definitions,
  daily ledger↔PSP reconciliation, and data quality/freshness SLOs. Numbers you can trust.
---

# Marketplace Data Platform — Scale, Read Models & the Numbers That Matter

**A marketplace that can't state its GMV and take-rate to the penny is flying blind, and one that runs
those numbers against its orders primary is flying into a wall.** Two principal-level jobs live here:
**(1) keep the transactional system fast and isolated per tenant as it scales**, and **(2) derive
trustworthy business + money metrics from events, not from hammering OLTP.** The backbone for both is
the same: changes flow OLTP → outbox/CDC → stream → **read models** (for serving) and a **warehouse**
(for analytics). Define metrics once, reconcile money daily, and never let a dashboard query block a
checkout.

---

## 1. Mandate

- **OLTP serves transactions; OLAP serves questions.** Analytics/GMV run on a warehouse/read model fed by events — never on the orders/payments primary.
- **Events are the integration backbone** via the transactional outbox + CDC (no dual-write). Read models and the warehouse are projections.
- **Metrics are defined once, centrally.** GMV, take-rate, liquidity have exact, documented SQL — not five dashboards with five definitions.
- **Money reconciles daily**: ledger ↔ PSP, to zero. A drift is a Sev-1, not a rounding note.

## 2. When to use / when NOT

**Use when:** designing multi-tenant data isolation; building read models / CQRS; standing up the analytics/warehouse pipeline; defining GMV/take-rate/cohort metrics; ledger reconciliation; data quality SLOs; sharding for scale. **Implements** the read-model + outbox patterns referenced across `marketplace-architecture`, `-payments-payouts`, `-seller-vendor-management`.

**Skip/defer when:** pre-PMF MVP — a single Postgres with RLS + a read replica for dashboards + a nightly metrics view is plenty. Don't build Kafka + a lakehouse for 1,000 orders/month. Add this layer when dashboards contend with OLTP or a single DB can't hold the tenants.

## 3. Architecture — the projection pipeline

```
OLTP (Postgres: orders, ledger, catalog)
  │  (transactional outbox / Debezium CDC — same-txn, no dual write)
  ▼
Stream (Kafka / Kinesis / PubSub)  ──►  Read models (Postgres/Redis): seller balance, buy-box,
  │                                       seller dashboard rollups, search docs  (low-latency serving)
  └──►  Warehouse / lakehouse (ClickHouse / BigQuery / Snowflake / Redshift)  ──► BI + cohorts + GMV
```

- **Read models** = serving projections (CQRS write/read split): the seller dashboard, wallet balance, buy-box winner, search index. Eventually consistent, rebuildable from the log.
- **Warehouse** = analytical truth for GMV/cohorts/finance; columnar, append-mostly, time-partitioned.
- **Rebuildability**: every projection can be rebuilt by replaying events — so a bad deploy is recoverable, not catastrophic.

## 4. DECISION MATRIX — multi-tenant (seller) isolation

| Strategy | Isolation | Ops cost | Scale ceiling | Use when |
|----------|-----------|----------|---------------|----------|
| **Shared schema + `seller_id` + RLS** ⭐ | Logical (RLS-enforced) | Low | High (with sharding) | Default for most marketplaces — simple, dense, RLS = defense in depth |
| **Schema-per-tenant** | Stronger logical | Medium (migrations × N) | Hundreds–low thousands | Few large enterprise sellers needing separation |
| **Database-per-tenant** | Strong physical | High | Limited by DB count | Strict compliance/data-residency per seller |
| **Shard-per-tenant-group** | Logical + physical scale | High | Very high | Hyperscale — shard catalog/offers by seller, orders by buyer/time |

**Principled default: shared schema + RLS** (`marketplace-architecture` §9), then **shard** the hot
tables once a single primary tops out: catalog/offers by `seller_id`, orders/payments by buyer or
time. Keep a **tenant routing map**; isolate noisy tenants (rate limits, dedicated shard for whales).

## 5. Read models / CQRS (serve fast, derive correctly)

```sql
-- Seller balance: a PROJECTION of the append-only ledger, refreshed on ledger events.
-- Never SUM() the whole ledger on each dashboard load.
create materialized view seller_balance as
select a.owner_id as seller_id, a.currency,
       sum(case when e.direction='credit' then e.amount else -e.amount end) as available
from ledger_entries e join ledger_accounts a on a.id = e.account_id
where a.owner_type='seller'
group by a.owner_id, a.currency;
-- Incrementally maintained (trigger/stream) at scale; minus held + pending payouts = payable.
```

Other read models: **buy-box winner** per variant (Redis, invalidated by `OfferChanged`), **seller
dashboard rollups** (daily sales/commission/defects), **search docs** (`multi-vendor-catalog` §8).
Reads hit projections + replicas; the OLTP primary only takes writes + the checkout critical path.

## 6. The canonical metric definitions (define once)

```sql
-- GMV: gross value of SOLD goods. Be explicit: completed/delivered, EXCLUDING cancellations.
-- Decide and document refund treatment (gross GMV vs net GMV). Normalize FX to a reporting currency.
select date_trunc('day', so.completed_at) d,
       sum(so.subtotal * fx.rate_to_usd) / 100.0 as gmv_usd
from sub_orders so
join fx_rates fx on fx.currency = so.currency and fx.day = date_trunc('day', so.completed_at)
where so.status in ('delivered','completed')
group by 1;

-- Take rate = platform net revenue / GMV. The single most-watched marketplace health number.
-- Net revenue = commission + fees − seller-incentive spend − payment cost.
select sum(commission + platform_fees - promo_platform_funded - payment_cost)::float
       / nullif(sum(subtotal), 0) as take_rate
from sub_orders where status in ('delivered','completed');
```

Other must-haves: **liquidity** (% listings with a sale in 30d; search→purchase conversion;
time-to-first-sale), **two-sided cohorts** (buyer + seller retention by signup month), **AOV**,
**repeat rate**, **contribution margin per order**. Put these in a **semantic/metrics layer** (dbt,
or a metrics store) so every dashboard agrees. GMV is *not* revenue — never conflate them in a board deck.

## 7. Ledger ↔ PSP reconciliation (the money truth check)

```
nightly: pull Stripe balance transactions (charges, transfers, refunds, payouts, fees)
       → match to ledger_entries by ref_id/transfer_group/payment_intent
       → assert per-currency: Σ(your ledger) == Σ(Stripe)  AND  every txn_id balances
       → any unmatched / imbalance → quarantine + page (Sev-1)
```

This is the job that catches a missed webhook, a double transfer, or a funding bug *before* finance
does. Treat a non-zero diff as an incident. Pairs with `marketplace-payments-payouts` §7 (the ledger)
and `business-master` accounting-finance (statements/close).

## 8. Edge cases

- **Late / out-of-order events** → projections must be idempotent + order-tolerant (event version/sequence); reconcile on a watermark.
- **Event schema evolution** → versioned event payloads + a schema registry; never break old consumers.
- **Reprocessing / backfill** → rebuild a projection by replaying from offset 0; design consumers to be replay-safe (idempotent upserts).
- **Hot tenant (whale)** skews shards + dashboards → isolate to a dedicated shard; sample/aggregate their events.
- **Multi-currency GMV** → normalize to a reporting currency at the day's FX rate; store rate used (don't retro-rewrite history).
- **Refund/cancel after the reporting period** → restating periods: pick gross-vs-net GMV policy and stick to it.

## 9. Performance & scale

- **Incremental materialization** (stream-maintained read models or incremental MVs), not full recompute.
- **Columnar warehouse** + time partitioning for analytics; pre-aggregate rollups for hot dashboards.
- **Replica reads** for seller/admin dashboards; checkout path never reads from analytics.
- **Outbox hygiene**: prune published rows; partition by time; monitor relay lag.

## 10. Security

- **Tenant isolation extends to analytics**: a seller's dashboard/API can only see *its* aggregates — enforce tenant scoping in read models + the BI layer, not just OLTP.
- **PII in the warehouse**: minimize, tokenize/hash buyer identifiers; separate PII from analytical facts; honor deletion (right-to-be-forgotten) across projections + warehouse.
- **Data residency** (MENA): some markets require in-region storage → influences DB/warehouse region + the per-DB isolation choice.
- **Access control**: row/column-level security in the warehouse; audit analytical access to money/PII.

## 11. Observability (this skill *is* the observability layer)

- **Business**: GMV, take-rate, AOV, liquidity, cohort retention, contribution margin — defined once, trended.
- **Money safety**: ledger imbalance count (=0), reconciliation diff, unreconciled PSP events, payout failure rate, negative balances.
- **Data quality/freshness SLOs**: event→read-model lag, projection staleness, warehouse load freshness, schema-validation failures, dropped/duplicate events.
- **Two-sided funnels**: seller onboarding completion, buyer checkout completion (sources in `seller-vendor-management` / `cart-checkout-orders`).

## 12. i18n / RTL (MENA)

- **Multi-currency normalization**: store the FX rate used per fact; report GMV/take-rate in a reporting currency *and* local currency.
- **Data residency**: KSA/UAE data-localization expectations push toward in-region warehouse/DB and may favor stronger per-tenant isolation; verify per market.
- **Localized BI**: Arabic dashboards + RTL for seller/admin analytics (`ui-master` charts-and-dashboards); Hijri calendar reporting where relevant.

## 13. Anti-patterns

- **Running GMV/analytics on the OLTP primary** → dashboards throttle checkout; the classic outage.
- **Dual-write to DB + broker** (no outbox/CDC) → events and state diverge silently.
- **Five definitions of GMV** across five dashboards → nobody trusts any number; centralize the metric.
- **Calling GMV "revenue"** → off by ~10× (your take); a credibility-ending error in a board deck.
- **Live `SUM()` of the whole ledger** for balances → slow + dangerous; use a maintained projection.
- **No reconciliation job** → money drift discovered by finance/auditors, not you.
- **Non-idempotent / order-dependent consumers** → unreplayable projections, corrupt on retry.
- **PII sprayed across the warehouse** with no deletion path → compliance landmine.

## 14. Agent checklist

```
- [ ] OLTP/OLAP split; analytics + GMV never hit the transactional primary
- [ ] Outbox/CDC → stream → read models + warehouse (no dual write); projections rebuildable
- [ ] Multi-tenant isolation chosen (shared+RLS default; shard hot tables when needed)
- [ ] Seller balance / buy-box / dashboard read models maintained incrementally
- [ ] GMV, take-rate, liquidity, cohorts defined ONCE in a metrics/semantic layer (with FX policy)
- [ ] Daily ledger↔PSP reconciliation asserting zero drift; imbalance pages
- [ ] Idempotent, order-tolerant, replay-safe consumers; versioned event schemas
- [ ] Data-quality/freshness SLOs (event→read-model lag, staleness, drops)
- [ ] Tenant isolation + PII minimization + deletion across warehouse; residency (MENA)
- [ ] Reporting + local currency; Arabic/RTL/Hijri dashboards
```

## References (verify current — 2026)
- Transactional outbox + CDC: https://microservices.io/patterns/data/transactional-outbox.html · https://debezium.io/documentation/
- CQRS: https://martinfowler.com/bliki/CQRS.html
- dbt (metrics/semantic layer): https://docs.getdbt.com · ClickHouse: https://clickhouse.com/docs
- Postgres partitioning + materialized views: https://www.postgresql.org/docs/current/ddl-partitioning.html
- Marketplace metrics (GMV/take-rate/liquidity): https://www.nfx.com/post/19-marketplace-metrics

## Related
`marketplace-architecture` (outbox, RLS, read models), `marketplace-payments-payouts` (ledger, reconciliation), `seller-vendor-management` (seller analytics), `multi-vendor-catalog`/`search-discovery-recommendations` (search read model) · cross-master: `business-master` (accounting-finance), `ui-master` (charts-and-dashboards), `analytics-master` (product analytics/funnels)
