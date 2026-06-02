---
name: systems-platforms-foundation
description: >-
  Choose and operate the right data/infra platform at staff depth: a real decision matrix
  (MongoDB vs Postgres/Supabase/Neon vs Cloudflare D1), 12-factor config & secrets, connection
  pooling math, migration discipline (expand/contract), backup/restore + DR (RPO/RTO), observability
  (RED/USE, slow-query logs), and an IaC mindset. Read this FIRST before any platform-specific skill.
---

# Systems & Platforms — Foundation (the decisions that outlive the code)

**Mandate:** Pick the data platform that fits the *access pattern* and the *operational budget*, then
make it boring: config in env, secrets in a vault, connections pooled, migrations reversible, backups
tested by restore. The platform you choose is a 5-year decision; the schema migration you ship today is
a 3am decision. Get both right on purpose.

## When to use / when NOT to use

- **Use** at the very start of any backend/platform task: greenfield DB choice, adding a second data
  store, "should this be Mongo or Postgres", standing up env/secrets/migrations/backup discipline.
- **NOT** for app-layer API/auth design (→ `backend-api-master`), container/K8s/Terraform mechanics
  (→ `devops-master`), or a single platform's full admin surface (→ the specific skill in this hub).
- This skill is **platform-agnostic doctrine**. The 6 sibling skills are the deep dives.

---

## 1. Mental model: pick by access pattern, not by hype

Three questions decide 90% of data-platform choices:

1. **Shape of reads.** Do you fetch *one aggregate at a time* (a document: user + their settings + recent
   activity) or do you *join and aggregate across entities* (orders × customers × products, ad-hoc
   analytics, reporting)? Document-shaped reads → MongoDB. Relational/ad-hoc → Postgres.
2. **Consistency & invariants.** Do you need multi-row transactional invariants and foreign keys enforced
   by the DB (money, inventory, bookings)? → Postgres. Can the app own consistency and you mostly write
   self-contained documents? → MongoDB is fine.
3. **Runtime & ops budget.** Long-lived Node server with a real connection pool? Anything works. Serverless/
   edge (Workers, Vercel/Lambda) with 1000s of short-lived isolates? → you need HTTP/pooled access
   (Neon serverless driver, Supabase pooler, D1, or Mongo Atlas Data API-style access), **not** a raw TCP
   pool per invocation.

> **Default in 2026:** Postgres unless you have a concrete document/scale reason. "Relational by default,
> document when the access pattern is genuinely document-shaped." Postgres also gives you `jsonb` for the
> 10% of your schema that *is* document-shaped — you rarely need a second engine just for that.

---

## 2. DECISION MATRIX — which platform

| Need / Trait | **Postgres (self/RDS)** | **Supabase** | **Neon** | **MongoDB Atlas** | **Cloudflare D1** |
|---|---|---|---|---|---|
| Data model | Relational + `jsonb` | Relational + `jsonb` | Relational + `jsonb` | Document (BSON) | Relational (SQLite) |
| Best for | OLTP, invariants, joins | Postgres **+ Auth/Storage/Realtime/RLS** batteries | Postgres for **serverless/branch-per-PR** | Document aggregates, flexible schema, high write fan-out | Edge-local, small/medium read-heavy at Cloudflare edge |
| Transactions | Full ACID, FKs | Full ACID, FKs | Full ACID, FKs | Multi-doc txns (replica set/sharded) | SQLite txns (single DO) |
| Serverless/edge fit | Needs pooler (PgBouncer/RDS Proxy) | Pooler (Supavisor :6543) | **Native** (HTTP/WS driver, scale-to-zero) | Driver pool or Data API | **Native** (binding, no driver) |
| Scale ceiling | Vertical + read replicas + partitioning | Postgres limits + platform caps | Autoscale compute; storage decoupled | Horizontal **sharding** built-in | 10 GB/db (paid), edge-replicated reads |
| Branching | ❌ (manual) | Preview branches | ⭐ **instant copy-on-write** | ❌ | Time Travel (PITR) not branching |
| Ops burden | High (self) / medium (RDS) | Low | Low | Low–medium (Atlas) | Very low |
| Killer feature | Maturity, SQL, ecosystem | RLS + Auth + Realtime in one box | Branch-per-PR, scale-to-zero cost | Schema flexibility + sharding | Zero-latency at edge, $0 idle |
| Watch out for | You operate pooling/backups (self) | RLS mistakes; pooler txn-mode limits | Cold starts (~0.5s) after scale-to-zero | Modeling discipline; unbounded arrays | 10 GB cap; no extensions; SQLite SQL subset |

**Quick router:**
- *"Next.js app, want auth+db+storage fast, RLS"* → **Supabase**.
- *"Serverless/branch-per-PR Postgres, pay nothing when idle"* → **Neon**.
- *"Flexible documents, massive write fan-out, will shard"* → **MongoDB Atlas**.
- *"Edge app, data lives at Cloudflare, small footprint"* → **D1**.
- *"Boring, proven, full control, big team"* → **managed Postgres (RDS/Cloud SQL)** or self-host.

Anti-pattern: choosing Mongo because "schema-less is faster to start". You still have a schema — it's just
now enforced in scattered application code and three years of inconsistent documents instead of one DDL.

---

## 3. 12-factor config & secrets (non-negotiable)

**Config is environment, secrets are vaulted, neither is committed.** Code is identical across dev/stage/prod;
only env differs.

```bash
# .env.example  — COMMITTED (documents the contract, no real values)
DATABASE_URL=postgresql://USER:PASSWORD@HOST:5432/db?sslmode=require
DATABASE_URL_POOLED=postgresql://USER:PASSWORD@HOST:6543/db?sslmode=require&pgbouncer=true
REDIS_URL=
JWT_SECRET=
RESEND_API_KEY=
NODE_ENV=development
```

```gitignore
# .gitignore  — real env never enters git history
.env
.env.*
!.env.example
```

Validate config **at boot** and crash loudly if missing — never let a service start half-configured:

```ts
// src/env.ts — fail fast, typed, single source of truth
import { z } from "zod";

const Env = z.object({
  NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
  DATABASE_URL: z.string().url(),
  DATABASE_URL_POOLED: z.string().url().optional(),
  JWT_SECRET: z.string().min(32, "JWT_SECRET must be >=32 chars"),
  RESEND_API_KEY: z.string().startsWith("re_").optional(),
});

export const env = (() => {
  const parsed = Env.safeParse(process.env);
  if (!parsed.success) {
    console.error("❌ Invalid environment:", z.treeifyError(parsed.error));
    process.exit(1); // do NOT boot a misconfigured process
  }
  return parsed.data;
})();
```

**Secret rules (least privilege, rotatable):**
- Never `console.log` a secret; never put it in a URL you log; redact `DATABASE_URL` in logs.
- One credential **per service per environment** — not one god-user shared everywhere. Rotation then has
  blast radius = one service.
- Store in a real manager: **AWS Secrets Manager / SSM**, **Doppler**, **Infisical**, **Vault**, or the
  platform's own (Supabase secrets, `wrangler secret put`, Vercel/GitHub Actions encrypted secrets).
- Rotate on a schedule and on offboarding. Design every credential assuming it *will* leak someday.

---

## 4. Connection pooling — the #1 production outage source

Postgres/MySQL = **one OS process/thread per connection**. A `db.t3.medium` tops out near
`max_connections ≈ 100–200`. 50 serverless instances × a naive `new Pool()` each = thousands of
connections = `FATAL: too many clients` = total outage.

**Sizing rule of thumb** (PgBouncer/HikariCP folklore that holds up): for a CPU-bound workload,
`pool_size ≈ (core_count × 2) + effective_spindle_count`. Most app servers want **5–20** per instance,
not 100. More connections ≠ more throughput past the DB's core count — it just adds context-switch tax.

| Mode | What it pools | Use when | Cost |
|---|---|---|---|
| **Session** (PgBouncer/Supavisor :5432) | 1 client = 1 server conn for the session | Long-lived servers, need `SET`/prepared/`LISTEN` | Fewer multiplexing wins |
| **Transaction** (:6543) | server conn returned **per transaction** | Serverless/edge, many short connections | ⭐ huge fan-in; **no session state, no `SET`, careful with prepared statements** |
| **Statement** | per statement | rare, very strict | most aggressive |

```ts
// Long-lived Node server: ONE shared pool for the whole process (module singleton)
import { Pool } from "pg";
export const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  max: 10,                       // per instance; multiply by instance count, stay under DB max
  idleTimeoutMillis: 30_000,
  connectionTimeoutMillis: 5_000, // fail fast instead of hanging the request
  ssl: { rejectUnauthorized: true },
});
process.on("SIGTERM", () => pool.end()); // drain on shutdown
```

- **Serverless/edge:** use the platform's **transaction-mode pooler** or an HTTP driver (Neon
  `@neondatabase/serverless`, Supabase Supavisor :6543, RDS Proxy, Hyperdrive). Never open a raw TCP pool
  per invocation. In transaction mode, disable client-side prepared-statement caching (`pgbouncer=true`,
  Prisma `?pgbouncer=true`).
- **Always set a connection timeout.** A pool that blocks forever waiting for a connection turns a DB
  hiccup into a full thread/request pileup.

---

## 5. Migration discipline — expand/contract, always reversible

**Schema changes are deploys.** Rules that prevent 3am incidents:

1. **Migrations are forward-only files in git**, ordered, applied by a tool (Prisma Migrate, Drizzle Kit,
   `node-pg-migrate`, Flyway, Atlas, Supabase migrations, `migrate-mongo` for Mongo). Never hand-edit prod.
2. **Never destructive + deploy in one step.** Use **expand → migrate → contract** so old and new code run
   simultaneously during a rolling deploy:

```sql
-- ❌ BREAKS running pods the instant it applies (rename is not backward compatible)
ALTER TABLE users RENAME COLUMN email TO email_address;
```

```sql
-- ✅ EXPAND (deploy 1): add new, backfill, dual-write from app
ALTER TABLE users ADD COLUMN email_address text;
UPDATE users SET email_address = email WHERE email_address IS NULL;
-- (app now writes BOTH columns)

-- ✅ CONTRACT (deploy 2, after all pods read/write the new column): drop old
ALTER TABLE users DROP COLUMN email;
```

3. **Big tables need online DDL.** A plain `ALTER`/`CREATE INDEX` can take a long lock. On Postgres use
   `CREATE INDEX CONCURRENTLY` and add NOT NULL via a `CHECK ... NOT VALID` + `VALIDATE CONSTRAINT`. Set a
   `lock_timeout`/`statement_timeout` on migrations so a blocked DDL fails fast instead of freezing writes:

```sql
SET lock_timeout = '3s';
SET statement_timeout = '5min';
CREATE INDEX CONCURRENTLY idx_orders_customer_created ON orders (customer_id, created_at DESC);
```

4. **Test the down path** (or have a tested forward-fix). "We can't roll back" = you can't deploy safely.
5. **Seed data is separate** from schema migrations (`seed.sql` / a seeding script), and idempotent.

---

## 6. Backups, restore & DR — a backup you haven't restored is a rumor

Define the two numbers up front, in writing, per data store:

- **RPO (Recovery Point Objective):** how much data you can afford to lose (e.g. "≤ 5 min").
- **RTO (Recovery Time Objective):** how long you can be down (e.g. "≤ 1 hour").

| Mechanism | RPO | Use |
|---|---|---|
| Nightly logical dump (`pg_dump`/`mongodump`) | up to 24h | small DBs, portability, dev refreshes |
| Continuous WAL / PITR (RDS, Neon, Supabase, Atlas) | seconds–minutes | production OLTP |
| Cross-region replica / snapshot copy | ~replica lag | regional-failure DR |

```bash
# Postgres logical backup (portable) — verify it RESTORES, monthly, into a scratch DB
pg_dump --format=custom --no-owner --dbname="$DATABASE_URL" --file="backup_$(date +%F).dump"
createdb restore_test && pg_restore --no-owner --dbname=restore_test "backup_$(date +%F).dump"
psql restore_test -c "SELECT count(*) FROM users;"   # sanity-check row counts

# Mongo logical backup
mongodump --uri="$MONGODB_URI" --gzip --archive="mongo_$(date +%F).gz"
mongorestore --uri="$MONGODB_URI_SCRATCH" --gzip --archive="mongo_$(date +%F).gz" --nsFrom='prod.*' --nsTo='restore.*'
```

**DR rules:** managed PITR is your default RPO win — *enable it and know the retention window*. Store dumps
**off the provider** (different cloud/region) so a provider-account compromise can't delete both prod and
backups. Run a **quarterly restore drill** and time it against your RTO. Encrypt backups at rest; treat the
backup bucket as production-sensitive (it contains all your PII).

---

## 7. Observability — RED/USE + the slow-query log

You cannot operate what you can't see. Instrument every data store:

- **RED** (request-centric): **R**ate, **E**rrors, **D**uration (p50/p95/p99) per endpoint and per query class.
- **USE** (resource-centric): **U**tilization, **S**aturation, **E**rrors for CPU, memory, **connections**,
  disk, replication lag.
- **The four signals that predict every DB incident:** connection-pool saturation, replication lag,
  slow-query rate, disk/IOPS headroom. Alert on these before users do.

```sql
-- Postgres: turn on the slow-query log + pg_stat_statements, then read the top offenders
ALTER SYSTEM SET log_min_duration_statement = '500ms';   -- log anything slower than 500ms
-- (pg_stat_statements in shared_preload_libraries)
SELECT round(mean_exec_time::numeric,1) AS ms, calls, query
FROM pg_stat_statements ORDER BY mean_exec_time DESC LIMIT 20;
```

```js
// Mongo: profile slow ops, then explain the worst ones
db.setProfilingLevel(1, { slowms: 100 });
db.system.profile.find().sort({ millis: -1 }).limit(10);
db.orders.find({ customerId: x }).sort({ createdAt: -1 }).explain("executionStats"); // want IXSCAN, not COLLSCAN
```

Emit structured JSON logs (correlation/request id on every line), traces (OpenTelemetry) across the
app→DB boundary, and a dashboard per data store. Wire alerts to the four signals above with sane thresholds
(e.g. pool > 80% for 5 min, replica lag > 30s, p99 query > SLO).

---

## 8. IaC mindset — the platform is code too

Click-ops doesn't survive an audit or a 2am rebuild. Declare infra (DB instances, buckets, Cloudflare
bindings, DNS, IAM) in **Terraform/OpenTofu/Pulumi** or the platform's declarative config (`wrangler.jsonc`,
`supabase/config.toml`, migration files). Plan in CI, apply via pipeline, never by hand in the console. State
lives in a remote backend with locking. (Mechanics → `devops-master`.) The test: *can you rebuild the entire
data tier in a new account from this repo?* If not, you have undocumented production.

---

## Edge cases & war stories
- **"It worked locally, prod fell over at 200 users."** Local = 1 process, 1 pool. Prod = 30 instances ×
  100-conn pools = 3000 conns into a 200-conn DB. Cap `max`, count instances, use a pooler.
- **Idle-in-transaction killers.** An app that `BEGIN`s and forgets to commit (lost error path) holds a
  connection + locks forever. Set `idle_in_transaction_session_timeout`.
- **The "schemaless" tax.** Three years in, the Mongo collection has `email`, `Email`, `email_address`,
  and `null` for the same concept. Schema validation (`$jsonSchema`) or Postgres would have prevented it.
- **Backups that never restored.** The dump job was green for 18 months; the restore failed because nobody
  tested it and the format was incompatible. Green backup job ≠ recoverable.
- **Migration locked the orders table at peak.** A naive `ALTER`/index build took an `ACCESS EXCLUSIVE`
  lock. `CONCURRENTLY` + `lock_timeout` turns an outage into a retried job.
- **Transaction-mode pooler + prepared statements.** Prisma/pg silently broke under PgBouncer txn mode
  until `pgbouncer=true` disabled the statement cache.

## Performance
- Pool small, time out fast, reuse one pool per process. Index for the actual query (see platform skills).
- Read replicas for read-heavy load; route reads explicitly — replicas are **eventually** consistent.
- Cache the expensive-and-stable (Redis/KV) with explicit TTL + invalidation; never cache without an
  invalidation story.

## Security
- TLS in transit everywhere (`sslmode=require`/verify-full). Least-privilege DB roles (app user ≠ migration
  user ≠ admin). Network isolation: DB in a private subnet/VPC, no public IP unless the platform *is* the
  perimeter (and then IP-allowlist). Secrets vaulted + rotated. Audit who can read prod and the backup bucket.

## Scale & reliability
- Vertical first (cheapest), then read replicas, then partitioning/sharding. Multi-AZ for HA, cross-region
  for DR. Define RPO/RTO; test failover. Backpressure + timeouts + retries-with-jitter on every dependency.

## Testing
- Run migrations in CI against a fresh DB on every PR (Testcontainers / `supabase db reset` / ephemeral Neon
  branch). Restore-drill quarterly. Load-test connection limits *before* launch, not during it.

## Cost notes
- Idle compute is the silent bill: scale-to-zero (Neon) or serverless (D1/Workers) for spiky/low traffic;
  reserved/provisioned for steady high traffic. Egress and per-row pricing (D1) can dominate — model it.
  Storage + backups + cross-region replication are line items, not free.

## Anti-patterns
- One shared god DB user with full superuser, reused across every service.
- `new Pool()` (or `new MongoClient()`) per request / per serverless invocation.
- Destructive migration shipped with the code that needs the new shape (no expand/contract).
- "We'll add indexes / backups / monitoring later." Later = the incident.
- Secrets in `.env` committed to git, or printed in logs.
- Choosing the engine by trend instead of by read shape + invariants + runtime.

## Agent checklist
```
- [ ] Platform chosen via the matrix (read shape + invariants + runtime), not by hype
- [ ] Config in env, validated at boot (zod), crash on missing; .env gitignored, .env.example committed
- [ ] Secrets in a manager, least-privilege, rotatable; never logged
- [ ] One pooled connection per process; max sized to (cores×2)+, under DB max; conn timeout set
- [ ] Serverless/edge uses transaction-mode pooler or HTTP driver (pgbouncer=true)
- [ ] Migrations are git files, applied by a tool, expand→contract, reversible, CONCURRENTLY for indexes
- [ ] RPO/RTO defined per store; PITR on; backups off-provider + encrypted; restore drilled
- [ ] RED/USE dashboards + alerts on pool saturation, replica lag, slow queries, disk
- [ ] Infra declared as code; rebuildable from repo
```

## References (2026-current)
- The Twelve-Factor App: https://12factor.net
- Postgres connection pooling / PgBouncer: https://www.pgbouncer.org & https://www.postgresql.org/docs/current/runtime-config-connection.html
- Postgres `pg_stat_statements`: https://www.postgresql.org/docs/current/pgstatstatements.html
- Safe Postgres migrations (strong_migrations doctrine): https://github.com/ankane/strong_migrations
- AWS Well-Architected — Reliability (RPO/RTO): https://docs.aws.amazon.com/wellarchitected/latest/reliability-pillar/welcome.html
- OpenTelemetry: https://opentelemetry.io/docs/

## Related
`mongodb-complete`, `supabase-complete`, `neon-postgres-serverless`, `cloudflare-platform-complete`,
`email-server-complete`, `postman-api-tooling` (this hub) · `backend-api-master`, `devops-master`,
`integrations-master`.
