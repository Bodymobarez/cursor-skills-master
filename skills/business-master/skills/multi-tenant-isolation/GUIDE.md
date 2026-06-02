---
name: multi-tenant-isolation
description: >-
  The hard part of B2B SaaS: keep tenant A's data unreachable from tenant B at principal depth.
  Postgres Row-Level Security (ENABLE + FORCE, SET LOCAL under PgBouncer), shared-DB vs
  schema-per-tenant vs DB-per-tenant trade-offs, RBAC→ABAC→ReBAC layering, audit logging, noisy
  neighbors, data residency, sharding, and a cross-tenant test harness. Use for any multi-tenant data layer.
---

# Multi-Tenant Isolation — Defense in Depth

**A missing `tenant_id` filter is a data breach, not a bug ticket.** In B2B SaaS the worst outage is
silent: customer A sees customer B's invoices and nobody notices until it's a headline. So isolation
must be **structural** (enforced by the database), not **disciplinary** (enforced by remembering to
add `WHERE tenant_id = ?`). This skill is the canonical isolation layer the other business skills
build on (CRM, ERP, accounting, white-label all reference it).

---

## 1. Mandate
1. Every tenant-scoped table has `tenant_id` and is protected by **Postgres RLS with `FORCE`**.
2. Application code **cannot** issue a query that escapes the tenant boundary — the DB rejects it.
3. The app connects as a **non-owner, non-superuser role** with no `BYPASSRLS`.
4. Tenant context is set with **`SET LOCAL` inside a transaction**, never session-wide.
5. Isolation is **tested** (a cross-tenant access attempt is part of CI), because RLS bugs are invisible to unit tests.

## 2. When to use / when NOT
**Use** for any system serving multiple customers/orgs from shared infrastructure. **Default to
shared-DB + RLS.** Reach for stronger physical isolation **only** when a specific driver demands it
(below) — don't pay schema/DB-per-tenant operational cost for a fear you can't name.

## 3. Tenancy model — decision matrix

| Model | Isolation | Tenants supported | Noisy-neighbor | Per-tenant restore | Ops cost | Pick when |
|-------|-----------|-------------------|----------------|--------------------|----------|-----------|
| **Shared DB + `tenant_id` (RLS)** | Logical (DB-enforced) | 10k–1M+ | Shared pool | Hard (row filtering) | Low | **Default.** Most B2B SaaS |
| **Schema-per-tenant** | Medium | 100s–low 1000s | Per-schema tuning | Easier (`pg_dump -n`) | Medium | Mid-market, per-tenant migrations/exports |
| **DB-per-tenant** | Strong (physical) | 10s–100s | Isolated | Trivial (drop/restore DB) | High | Enterprise, regulated, data residency |
| **Cell / shard-per-cohort** | Strong (blast-radius) | Unlimited | Bounded | Per-cell | High | Hyperscale; route tenants → cells |

**Reality check:** migrating 5,000 schemas takes 5,000 `ALTER`s and your migration tool will hate you;
DB-per-tenant connection-pool math explodes (N tenants × M connections). The shared model with RLS is
chosen by most serious SaaS *because* it scales operationally — physical isolation is the exception you
justify, not the default you assume. You can also **mix**: shared by default, "dedicated DB" as an
enterprise upsell, with the same app code if `tenant_id` resolution is abstracted.

## 4. Postgres RLS — the canonical, correct setup

```sql
-- 1) Connect the APP as a role that is NOT the table owner and NOT superuser.
--    Owners/superusers bypass RLS unless FORCE is set; never give the app BYPASSRLS.
create role app_rw login noinherit;        -- app uses this; migrations use the owner role

-- 2) Every tenant table:
alter table invoice enable row level security;
alter table invoice force  row level security;   -- ← without FORCE, the owner silently ignores policies

-- 3) ONE simple policy. USING = read filter; WITH CHECK = write guard (block cross-tenant INSERT/UPDATE).
create policy tenant_isolation on invoice
  using      (tenant_id = current_setting('app.tenant_id', true)::uuid)
  with check (tenant_id = current_setting('app.tenant_id', true)::uuid);
--                                              ^^^^ missing_ok=true → returns NULL (not ERROR)
--                                              during migrations/maintenance when the GUC is unset.

-- 4) tenant_id LEADS every index, or RLS turns each query into a seq scan.
create index on invoice (tenant_id, entry_date);
create index on invoice (tenant_id, customer_id);
```

**Order matters:** write the policy *before* you rely on the table — enabling RLS with **no** policy
denies all rows to non-owners (safe default, but it'll look like "everything disappeared"). Keep the
policy predicate **trivial** (`col = setting`); a subquery in the policy runs **per row** and destroys
performance — resolve anything complex in the app and pass it as the GUC.

### Setting tenant context safely (the part everyone gets wrong)

```ts
import type { Pool, PoolClient } from "pg";

/**
 * One transaction per unit of work. SET LOCAL dies at COMMIT/ROLLBACK, so the next
 * client to borrow this pooled connection can NOT inherit our tenant. This is what makes
 * RLS safe under PgBouncer transaction-pooling. Use set_config(...,true) because you
 * cannot bind a parameter to a bare `SET LOCAL` statement.
 */
export async function withTenant<T>(pool: Pool, tenantId: string, fn: (c: PoolClient) => Promise<T>) {
  const c = await pool.connect();
  try {
    await c.query("begin");
    await c.query("select set_config('app.tenant_id', $1, true)", [tenantId]); // is_local = true
    const out = await fn(c);
    await c.query("commit");
    return out;
  } catch (err) {
    await c.query("rollback");
    throw err;
  } finally {
    c.release();
  }
}
```

> **The pooling trap:** `SET` (no `LOCAL`) persists for the whole connection. Under PgBouncer
> *transaction* pooling one physical connection is shared across many tenants — a leaked `SET`
> means tenant B runs with tenant A's scope. **Always `SET LOCAL` / `set_config(..., true)`**, always
> inside the transaction, as the first statement. (Alternative: PgBouncer *session* pooling — safer but
> burns far more connections. The wrapper above is the production choice.)

## 5. Resolving the tenant (and never trusting the client)

Resolve `tenant_id` **server-side** from the authenticated principal — the JWT/session claim or the
request host (`acme.app.com` / custom domain → `domains` table). **Never** from a request body, query
param, or header the client controls. Set it once in middleware (the start of the request transaction),
and let RLS do the rest so no handler can forget a filter.

## 6. RBAC → ABAC → ReBAC (authorization layered on top of isolation)

Isolation answers *"which tenant's rows exist for this request"*; **authorization** answers *"which of
those rows may this user act on, and how."* Layer them:

| Layer | Question | 2026 tooling |
|-------|----------|--------------|
| **RBAC** | Coarse: is the user `admin`/`manager`/`member` of the tenant? | Roles table; cheap; ~90% of cases |
| **ABAC** | Conditional: region, time, record stage, ownership, amount limit | Policy engine: AWS **Cedar**, **OPA/Rego**, **Cerbos**, **Oso** (Polar) |
| **ReBAC** | Per-resource graphs: "editor of Project X in Folder Y" | Zanzibar-derived: **OpenFGA** (CNCF), **SpiceDB** (Authzed) |

**Opinion:** start with RBAC + ownership predicates at the query layer; most B2B apps never need more.
Add a policy engine (Cedar/Cerbos/OPA) when rules become attribute-driven (approval thresholds, regional
data rules). Reach for **OpenFGA/SpiceDB** only for genuine relationship graphs (nested folders, sharing,
deep hierarchies) — ReBAC is a superset of RBAC and can model ABAC via contextual tuples, but it adds a
relationship store and the dual-write problem. Don't adopt a permission graph to check `role = 'admin'`.

```sql
-- Ownership/role scoping composes with RLS (RLS already removed other tenants' rows):
-- reps see own + team; managers see their team; admins see the whole tenant.
where (
     current_setting('app.role') = 'admin'
  or owner_id = current_setting('app.user_id')::uuid
  or (current_setting('app.role') = 'manager'
      and owner_id = any (string_to_array(current_setting('app.team_ids'), ',')::uuid[]))
)
```

## 7. Scale: sharding, cells, noisy neighbors

- **Shard by tenant** (hash or directory) once one DB can't hold the fleet. Keep a tenant a *single
  shard's* problem — never split one tenant across shards (cross-shard joins are pain).
- **Cell architecture**: route cohorts of tenants to isolated "cells" (app+DB) to bound blast radius;
  a bad deploy or hot tenant takes down one cell, not everyone.
- **Noisy neighbors**: per-tenant rate limits and query budgets; watch for a single tenant's heavy
  queries starving the shared pool. Big tenants can graduate to a dedicated cell/DB.
- **Connection math**: serverless + per-request connections + many tenants = pool exhaustion. Use a
  pooler (PgBouncer/RDS Proxy) and the `SET LOCAL` pattern above.

## 8. Data residency & lifecycle
- **Residency** (EU/KSA/UAE data-localization): route tenants to region-pinned DBs/cells; record the
  tenant's region and resolve storage from it. This is a real driver for DB-per-tenant or per-region cells.
- **Offboarding**: deleting a tenant must be complete and provable (cascade or `tenant_id`-scoped purge,
  plus backups expiry). "We forgot we still had their data" is a GDPR finding.
- **Backups/restore**: shared-DB per-tenant restore is genuinely hard — design point-in-time export per
  tenant up front if customers will demand "give me my data" / "delete only tenant X".

## 9. Testing & observability (RLS bugs are invisible to unit tests)
- **Cross-tenant test in CI**: open a transaction as tenant A, insert; open as tenant B, assert
  `SELECT` returns **zero** A rows and an `INSERT` with A's `tenant_id` is **rejected** by `WITH CHECK`.
- **Static guard**: lint/grep for raw queries that bypass the `withTenant` wrapper; fail the build.
- **Negative test**: temporarily drop `FORCE` in a test DB and prove your cross-tenant test now *fails*
  — confirms the test actually exercises isolation.
- **Observe**: alert on any query executed without a tenant GUC set; log `tenant_id` on every request
  (structured logs/traces) for forensics; track per-tenant query latency to catch noisy neighbors.

## 10. Anti-patterns
- **`tenant_id` filtering only in application code** — one forgotten `WHERE` = breach. Use RLS.
- **`ENABLE` without `FORCE`** while the app connects as the table owner → policies silently do nothing.
- **`SET` instead of `SET LOCAL`** with a transaction pooler → tenant context bleeds between requests.
- **Trusting a client-supplied `tenant_id`** (body/param/header). Resolve from auth only.
- **Subqueries inside the RLS policy** → per-row evaluation, full scans.
- **Index without `tenant_id` leading** → RLS predicate can't use it → seq scans.
- **Shared cache/session keys** not namespaced by tenant → cross-tenant cache hits.
- **Schema/DB-per-tenant chosen by default** "for safety" → migration & connection nightmares at scale.

## 11. Agent checklist
```
- [ ] tenant_id on every tenant table; RLS ENABLE + FORCE; USING + WITH CHECK policy
- [ ] App connects as non-owner, non-superuser, no BYPASSRLS
- [ ] withTenant(): BEGIN → set_config('app.tenant_id', id, true) → work → COMMIT
- [ ] tenant_id leads every composite index
- [ ] tenant resolved server-side from auth/host, never from client input
- [ ] AuthZ layered on isolation: RBAC (+ ownership) → policy engine → ReBAC only if needed
- [ ] Cross-tenant isolation test runs in CI and actually fails without FORCE
- [ ] Per-tenant rate limits; tenant_id in logs/traces; residency + offboarding handled
```

## 12. References (2026-current)
- Postgres RLS: https://www.postgresql.org/docs/current/ddl-rowsecurity.html
- PgBouncer pooling modes: https://www.pgbouncer.org/features.html
- OpenFGA (CNCF, ReBAC): https://openfga.dev · SpiceDB: https://authzed.com/docs
- AWS Cedar / Verified Permissions: https://www.cedarpolicy.com · Cerbos: https://docs.cerbos.dev · OPA: https://www.openpolicyagent.org

## Related
`white-label-platform`, `accounting-finance`, `crm-builder`, `erp-builder`,
`auth-rbac-multi-tenant` (backend-api-master), `tailwind-design-tokens` (tailwind-master)
