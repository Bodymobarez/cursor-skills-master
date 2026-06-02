---
name: marketplace-architecture
description: >-
  Architect a multi-vendor marketplace at staff/principal depth — the load-bearing
  decisions every other skill inherits: bounded contexts, the one-cart→many-sub-orders
  split, money as an immutable double-entry ledger, idempotency, the transactional
  outbox, multi-tenant seller isolation (Postgres RLS), and orchestration vs choreography.
  Read FIRST. Covers product (Amazon), food/q-commerce (Talabat), services, rentals.
---

# Marketplace Architecture — The Load-Bearing Decisions

**A marketplace is not a store with multiple logins.** It is a *distributed money-movement system*
with a catalog bolted on. The defining constraint: **one buyer payment fans out to N independent
sellers, each fulfilling, refunding, and getting paid out on its own timeline** — and you must keep
every cent reconcilable while doing it. Get the order-split, the ledger, and seller isolation right
on day one; everything else (catalog, search, dispatch) is replaceable later. These three are not.

This is the mental model + canonical schema the other 9 skills build on. Read it, then go deep in
`cart-checkout-orders`, `marketplace-payments-payouts`, etc.

---

## 1. Mandate

- **The split is the product.** One `Cart` → one `Payment` → many `SubOrder`s (one per seller) → many `Payout`s. If you can't refund seller B without touching seller A's money, your model is wrong.
- **Money lives in a ledger you own, not in Stripe.** The PSP is a *rail*. Your double-entry ledger is the source of truth for GMV, balances, commission, and payouts. Re-derivable, append-only, immutable.
- **Every seller-owned row is tenant-scoped and isolated** at the database layer (RLS), not just in app code. A query bug must not leak seller A's orders to seller B.
- **Idempotency is mandatory, not optional**, on checkout, webhooks, transfers, and inventory moves. Networks retry; money must not double.

## 2. When to use / when NOT

**Use this skill when:** designing a new marketplace; deciding service boundaries; modeling the order/money flow; choosing orchestration; setting up multi-tenancy. **Read before writing any schema.**

**You do NOT need a marketplace (stop here) when:** single seller (you) → that's just e-commerce, skip the split/payouts/Connect entirely. One brand, many warehouses → still single-tenant. "Multi-vendor" with manual monthly bank-transfer payouts and < 20 sellers → a spreadsheet + Stripe standard is cheaper than this architecture until you have liquidity. **Don't build a distributed saga for 3 sellers.**

## 3. Marketplace types — the type dictates the architecture

| Type | Examples | Inventory | Fulfillment | Payment timing | Defining hard problem |
|------|----------|-----------|-------------|----------------|----------------------|
| **Product** | Amazon, Noon, Etsy | Stock units, shared product + many offers | Carrier shipping | Capture at order, payout after return window | **Buy box** + catalog dedup at scale |
| **Food / q-commerce** | Talabat, Uber Eats, instashop | Menu, 86-ing, prep time | On-demand courier dispatch | Capture at order, payout daily | **Time + geo + dispatch** in < 45 min |
| **Services** | Fiverr, Upwork | Capacity/calendar, no SKU | Digital/in-person, milestones | **Escrow** until accepted | Trust + dispute mediation |
| **Rental / booking** | Airbnb, Turo | Time-bound availability calendar | Hand-off + return | Deposit + hold | Double-booking prevention, deposits |

> **Identify the type before modeling.** Amazon optimizes catalog/shipping; Talabat optimizes a
> 30-minute physics problem (prep + drive + traffic). The same `Order` table serves both, but
> inventory, payment capture timing, and fulfillment diverge hard. Building product patterns into a
> food app (or vice-versa) is the #1 architecture mistake.

## 4. Bounded contexts (modular monolith → services)

Start as a **modular monolith** with hard module boundaries; extract to services only where scale or
team topology forces it (usually Dispatch and Search first). Premature microservices on a 5-person
team is how marketplaces die before liquidity.

```
Identity & Tenancy ── buyers, sellers, staff, RBAC, KYC state
Catalog ──────────── categories, products, variants, offers, inventory  → emits Catalog.OfferChanged
Search/Discovery ─── read model fed from Catalog events (Algolia/OpenSearch)
Pricing/Promotions ─ commission plans, coupons, campaigns, funding source
Order ────────────── cart, checkout SAGA, order, sub-orders, lifecycle FSM
Payments/Ledger ──── PSP integration, double-entry ledger, payouts, escrow
Fulfillment ──────── shipping (carriers) | delivery (courier dispatch)
Trust & Safety ───── reviews, moderation, fraud, disputes
Notifications ────── buyer/seller/courier/admin (email, push, WS)
```

**Dependency rule:** Catalog/Pricing publish events; Order *orchestrates*; Payments/Ledger is the
only context that mutates money; everyone else reacts. Search and recommendations are **read models**
— never query the catalog OLTP tables for buyer-facing search.

## 5. Canonical data model (Postgres — the spine)

Conventions used across all marketplace skills: **money = `bigint` minor units + ISO currency** (never float); **PKs = UUID v7 / ULID** (time-sortable, index-friendly); **`seller_id` on every seller-owned row**; **`updated_at` + optimistic `version` for concurrency**.

```sql
-- ── Tenancy ──────────────────────────────────────────────────────────────
create table sellers (
  id            uuid primary key default uuidv7(),       -- PG18 uuidv7(); else app-gen ULID
  legal_name    text not null,
  status        text not null default 'pending'
                check (status in ('pending','under_review','approved','active','suspended','offboarded')),
  payout_account_id text,                                  -- Stripe connected account id (acct_...)
  default_currency  char(3) not null default 'AED',
  commission_bps    int not null default 1500,             -- 15.00% in basis points (integer math)
  created_at    timestamptz not null default now()
);

-- ── Money: append-only double-entry ledger (YOUR source of truth) ─────────
create table ledger_accounts (
  id        uuid primary key default uuidv7(),
  owner_type text not null check (owner_type in ('platform','seller','buyer','psp','tax')),
  owner_id   uuid,                                         -- seller_id / buyer_id; null for platform/psp
  currency   char(3) not null,
  unique (owner_type, owner_id, currency)
);
create table ledger_entries (
  id           uuid primary key default uuidv7(),
  txn_id       uuid not null,                              -- groups the balanced legs of one event
  account_id   uuid not null references ledger_accounts(id),
  direction    text not null check (direction in ('debit','credit')),
  amount       bigint not null check (amount > 0),         -- minor units, always positive
  currency     char(3) not null,
  ref_type     text not null,                              -- 'capture'|'commission'|'transfer'|'refund'|'reversal'|'payout'
  ref_id       text not null,                              -- external/internal id (idempotent key)
  created_at   timestamptz not null default now()
);
-- INVARIANT (assert in CI + a nightly job): per txn_id, sum(debit) = sum(credit) per currency.
create unique index on ledger_entries (ref_type, ref_id, account_id, direction); -- dedupe replays
```

> See `marketplace-payments-payouts` for the posting rules and `marketplace-data-platform` for the
> balance read-model and GMV/take-rate derivations.

## 6. The multi-vendor order flow (the defining feature)

```
1. Buyer fills ONE cart from MULTIPLE sellers (grouped by seller in model + UI)
2. Checkout = idempotent SAGA:
     reserve inventory (per item, atomic) →  create ONE PaymentIntent (whole cart total)
     → on payment success: split into SubOrder per seller, fan out events
     → on failure / timeout: COMPENSATE (release reservations, void/refund, fail order)
3. Each SubOrder runs its OWN lifecycle FSM (ship | prepare+dispatch), independently
4. Money: capture → post commission → transfer net to each seller (now or after escrow) → payout
5. Returns/refunds/disputes resolved PER SubOrder, with proportional payout clawback
```

This fan-out (one cart/payment → many seller sub-orders + payouts) is the line between a marketplace
and a single store. Model `Order` (buyer-facing, the payment) and `SubOrder` (seller-facing, the
fulfillment + money unit) as **distinct aggregates from day one** — retrofitting the split later is a
migration from hell.

## 7. DECISION MATRIX — orchestration vs choreography for checkout

| Approach | What | Use when | Cost |
|----------|------|----------|------|
| **Synchronous DB transaction** | Reserve + order + sub-orders in one ACID txn; payment intent created, confirmed client-side | Single region, < ~100 orders/s, payment is the only external call | Simplest. Payment confirm happens *outside* the txn → reconcile via webhook. |
| **Orchestrated saga (recommended)** | A coordinator (state machine / **Temporal** workflow) drives steps + compensations | Multi-step, external calls (PSP, inventory svc, fraud), needs retries/timeouts/visibility | Operational weight, but **explicit compensation** + durable retries. Best default at scale. |
| **Choreography (events only)** | Each service reacts to events, no central brain | Loosely-coupled teams, simple flows | Emergent behavior is hard to debug; "where is order X stuck?" has no single answer. **Avoid for checkout.** |

**Principled default:** orchestrate checkout (Temporal or a hand-rolled FSM + outbox); use
choreography for *downstream* reactions (notifications, search re-index, analytics). Never put money
movement on best-effort choreography.

## 8. Idempotency + transactional outbox (the two patterns that save you)

```sql
create table idempotency_keys (
  key         text primary key,                  -- client-supplied (checkout) or derived (webhook id)
  scope       text not null,                      -- 'checkout' | 'stripe_webhook' | 'transfer'
  request_hash bytea not null,                    -- guard against key reuse w/ different body
  response    jsonb,                              -- cached result for safe replay
  status      text not null default 'in_progress' check (status in ('in_progress','done')),
  created_at  timestamptz not null default now()
);

create table outbox (
  id          uuid primary key default uuidv7(),
  aggregate   text not null,                      -- 'order' | 'suborder' | 'payout'
  aggregate_id uuid not null,
  event_type  text not null,                      -- 'OrderPlaced' | 'SubOrderCreated' ...
  payload     jsonb not null,
  published_at timestamptz                        -- null = unpublished; relay polls/CDC streams it
);
```

Write domain change **and** the outbox row in the **same transaction**; a relay (Debezium CDC or a
poller) publishes to Kafka/SQS. This is how you emit events without dual-write inconsistency between
your DB and the broker. See `cart-checkout-orders` for the checkout handler that uses both tables.

## 9. Multi-tenant seller isolation (Postgres RLS — defense in depth)

App-layer `where seller_id = ?` is necessary but not sufficient; one forgotten clause leaks data.
Enforce at the database:

```sql
alter table offers enable row level security;
create policy seller_isolation on offers
  using (seller_id = current_setting('app.seller_id')::uuid);
-- platform/admin connections use a role that BYPASSRLS; seller API sets app.seller_id per request.
```

Set `app.seller_id` from the authenticated principal at the start of each seller-scoped request
(transaction-local `set local`). Buyers query the **search read model**, not seller tables.
See `marketplace-data-platform` for shard-per-tenant and noisy-neighbor strategy at scale.

## 10. Edge cases the architecture must natively support

- **Partial fulfillment:** sub-order A delivered, sub-order B cancelled → buyer sees a split status; payment captured once, payout/refund computed per sub-order.
- **Multi-seller cart:** stock for one seller vanishes mid-checkout → that seller's items fail; the rest can proceed (configurable: all-or-nothing vs best-effort).
- **Refund across sellers:** refund seller B's item → reverse *only* B's transfer, claw back *only* B's commission, leave A untouched.
- **Payout hold/escrow:** funds captured but not yet transferred (return window / KYC pending / dispute) → money sits in platform balance with a `held` ledger marker.
- **Currency:** buyer pays AED; seller settles in USD → FX is a ledger event, not a rounding afterthought.

## 11. Performance & scale baseline

- **OLTP/OLAP split:** orders/payments on Postgres (transactions matter); analytics/GMV on a warehouse/columnar read model fed by the outbox. Never run GMV dashboards against the orders primary.
- **Search is a read model** (Algolia/OpenSearch), reindexed from `Catalog.OfferChanged` events — buyer search must never touch OLTP.
- **Hot paths to cache:** cart (Redis), buy-box winner per product, courier proximity index (H3 in Redis). Catalog reads behind a CDN/edge cache.
- **Shard by tenant** (seller) for catalog/offers; **shard orders by buyer or time**. Read replicas for seller dashboards.

## 12. Security & compliance baseline

- **Seller isolation:** RLS (above) + per-seller object storage prefixes + scoped API tokens.
- **Money integrity:** ledger append-only; no `UPDATE`/`DELETE` on `ledger_entries` (revoke at role level); corrections are *reversing entries*.
- **PII minimization:** never store raw KYC docs or card data — delegate to the PSP/KYC vault (see `seller-vendor-management`, `marketplace-payments-payouts`).
- **Payout fraud surface:** changing a seller's bank account is a high-risk event → step-up auth + cooldown + payout pause (see `reviews-ratings-trust-safety`).
- **Authorization:** every seller/admin endpoint authorizes by tenant + role; treat IDOR on order/sub-order as a Sev-1.

## 13. Observability — the metrics that define a marketplace

Instrument from day one (full catalog in `marketplace-data-platform`):

- **GMV** (gross merchandise value), **Take rate** = platform revenue / GMV, **Net revenue**.
- **Liquidity:** search→purchase conversion, % listings with a sale, time-to-first-sale.
- **Two-sided funnels:** seller onboarding completion, buyer checkout completion.
- **Money safety:** ledger imbalance count (must be 0), unreconciled PSP events, payout failure rate.
- **Ops SLOs:** checkout p99, dispatch assign time, order-stuck count per state.

## 14. i18n / RTL (MENA)

- **RTL-first** for Arabic (`dir="rtl"`, logical CSS props) — see `ui-master`. Bidi product titles (Arabic name + Latin brand) need explicit isolation (`&lrm;`/`&rlm;`).
- **Multi-currency from the schema up** (AED/SAR/EGP/USD): store currency per money column; FX as ledger events.
- **Tax / e-invoicing is an architecture concern, not a plugin:** Saudi **ZATCA Fatoora Phase 2** (UBL 2.1 XML, cryptographic stamp/CSID, UUID, QR, B2B real-time clearance / B2C 24h reporting), UAE Peppol-based e-invoicing (ASP, 2026 pilot → 2027), Egypt **ETA** e-invoice/e-receipt. Marketplace is often **merchant of record** → platform owns the VAT invoice. Design an invoicing service boundary early.
- Localize money/date/number formatting via ICU; never concatenate currency symbols by hand.

## 15. Anti-patterns (do not ship these)

- **One flat `orders` table, no `sub_orders`** → can't fulfill/refund/pay out per seller. The cardinal sin.
- **Treating Stripe as your ledger** → you can't compute GMV/take-rate/seller balance offline, and reconciliation is impossible.
- **`seller_id` filtering in app code only** (no RLS) → one missing `WHERE` leaks tenants.
- **Decrementing stock at "add to cart"** → carts hold inventory hostage; oversell on abandonment.
- **Synchronous fan-out** (call 5 seller services inline at checkout) → one slow seller fails the whole order; use the outbox.
- **Floats for money.** Ever. `0.1 + 0.2 != 0.3`.
- **Microservices before liquidity.** Modular monolith first.
- **Ignoring the operator console + courier app** — the marketplace runs on ops tooling you forgot to build.

## 16. Agent checklist

```
- [ ] Marketplace type identified (product/food/services/rental) → drives inventory + payment timing
- [ ] Order vs SubOrder modeled as distinct aggregates; money + fulfillment unit = SubOrder
- [ ] Money = bigint minor units + currency; double-entry append-only ledger is source of truth
- [ ] Checkout is an idempotent saga (orchestrated); compensations defined for every step
- [ ] Transactional outbox for all cross-context events (no dual-write)
- [ ] Seller isolation via Postgres RLS + scoped tokens (not just app-layer WHERE)
- [ ] Search/recs/analytics are read models fed by events — never query OLTP
- [ ] GMV, take-rate, liquidity, ledger-imbalance metrics instrumented
- [ ] MENA: multi-currency, RTL, e-invoicing (ZATCA/Peppol/ETA) boundary planned
- [ ] Modular monolith with hard boundaries; extract services only under proven pressure
```

## References (verify current — 2026)
- Stripe Connect design guide: https://docs.stripe.com/connect/design-an-integration
- Transactional outbox pattern: https://microservices.io/patterns/data/transactional-outbox.html
- Temporal (durable orchestration / sagas): https://docs.temporal.io
- Postgres Row-Level Security: https://www.postgresql.org/docs/current/ddl-rowsecurity.html
- Debezium CDC: https://debezium.io/documentation/

## Related
`cart-checkout-orders`, `marketplace-payments-payouts`, `multi-vendor-catalog`, `marketplace-data-platform`, `seller-vendor-management` · cross-master: `backend-api-master` (auth/RBAC), `business-master` (accounting-finance), `payments-master` (PSP depth)
