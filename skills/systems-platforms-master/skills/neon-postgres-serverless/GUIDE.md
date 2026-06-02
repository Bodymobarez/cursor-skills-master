---
name: neon-postgres-serverless
description: >-
  Neon serverless Postgres at staff depth (2026): storage/compute separation, instant copy-on-write
  branching (branch-per-PR), autoscaling + scale-to-zero (and cold-start handling), pooled (-pooler)
  vs direct connections, the @neondatabase/serverless driver over HTTP/WebSocket for edge runtimes, and
  Prisma/Drizzle config. Use when you want Postgres that branches like Git and costs $0 when idle.
---

# Neon — Serverless Postgres (branch like Git, scale to zero)

**Mandate:** Neon is real Postgres with compute decoupled from storage — so you get **instant branches**
(a full DB copy in <1s, copy-on-write) and **scale-to-zero** (pay nothing when idle). Use the **pooled**
connection string everywhere except migrations, the **serverless driver** on edge runtimes, and design for
the ~0.5s **cold start** after a compute suspends. It's Postgres, so all your SQL/Prisma/Drizzle knowledge
transfers unchanged.

## When to use / when NOT to use
- **Use** for serverless/edge backends (Vercel, Cloudflare Workers, Lambda), **branch-per-PR / preview
  environments**, spiky or low-idle traffic where scale-to-zero saves real money, and anywhere you want
  Postgres without managing instance sizing.
- **NOT** when you need the Supabase batteries (Auth/RLS/Storage/Realtime → `supabase-complete`), a document
  store (→ `mongodb-complete`), or steady 24/7 high traffic where always-on provisioned Postgres is cheaper
  and cold starts are unwanted. If you keep the compute always-on anyway, you're paying for serverless without
  using its main win.

## Mental model
Traditional Postgres bundles compute + storage in one always-on box you pay for 24/7. Neon splits them:
**storage** is a durable, versioned page service; **compute** is a stateless Postgres process that attaches
to a branch and can be **suspended** (scale-to-zero) and **resumed** in ~0.5s. Because storage is versioned
and copy-on-write, a **branch** is just a new pointer into the same pages — instant, near-free until you
write. This is the entire reason Neon exists: Git-like branching + idle = $0.

---

## 1. Setup + connection strings (pooled vs direct — get this right first)

```bash
npm i @neondatabase/serverless        # the serverless driver (HTTP/WebSocket)
# Neon CLI for branches/automation:  npm i -g neonctl   →   neonctl auth
```

Every Neon endpoint gives you **two** connection strings. The only difference is `-pooler` in the host:

| String | Host contains | Routes through | Use for | Limit |
|---|---|---|---|---|
| **Pooled** | `...-pooler.<region>.aws.neon.tech` | PgBouncer (transaction mode) | **app queries, serverless, edge** | up to ~10,000 concurrent clients |
| **Direct** | `...<region>.aws.neon.tech` (no `-pooler`) | straight to compute | **migrations, admin, session-state ops** | compute `max_connections` (100–4,000 by size) |

```bash
# .env
DATABASE_URL="postgresql://user:pass@ep-cool-name-123-pooler.us-east-1.aws.neon.tech/neondb?sslmode=require"
DIRECT_URL="postgresql://user:pass@ep-cool-name-123.us-east-1.aws.neon.tech/neondb?sslmode=require"
```
**Default to pooled.** Serverless functions that use the direct string exhaust `max_connections` fast.
Reserve the direct string for `prisma migrate` / `drizzle-kit` and anything needing session state.

---

## 2. The serverless driver — HTTP vs WebSocket (edge-native)

Edge runtimes (Cloudflare Workers, Vercel Edge) **can't open raw TCP**, so the standard `pg` driver fails
there. `@neondatabase/serverless` speaks Postgres over **HTTP** (one-shot queries) and **WebSocket**
(sessions/transactions/`pg`-compatible `Pool`/`Client`).

```ts
// HTTP — fastest for a SINGLE independent query (no transaction). Ideal in edge handlers.
import { neon } from "@neondatabase/serverless";
const sql = neon(process.env.DATABASE_URL!);            // use the POOLED url
const [user] = await sql`select id, email from users where id = ${userId}`; // params are safely bound
```

```ts
// WebSocket — when you need a transaction or node-postgres-style Pool/Client (interactive multi-statement)
import { Pool } from "@neondatabase/serverless";
const pool = new Pool({ connectionString: process.env.DATABASE_URL });
try {
  await pool.query("BEGIN");
  await pool.query("UPDATE accounts SET balance = balance - $1 WHERE id = $2", [amt, from]);
  await pool.query("UPDATE accounts SET balance = balance + $1 WHERE id = $2", [amt, to]);
  await pool.query("COMMIT");
} catch (e) { await pool.query("ROLLBACK"); throw e; }
finally { /* in serverless, create+end the Pool within ONE request; use ctx.waitUntil(pool.end()) */ }
```

| Mode | Use when | Don't use when |
|---|---|---|
| `neon()` HTTP | single query, edge, statelessness, lowest latency | you need a transaction or session |
| `Pool`/`Client` WS | transactions, multiple dependent statements, `pg` parity | a one-shot query (HTTP is faster) |

In Node.js (a long-lived server), the plain `pg` driver against the pooled URL is also fine — the serverless
driver's win is **edge** and short-lived functions. On Node WebSocket you may need to set
`neonConfig.webSocketConstructor = ws` (import `ws`).

---

## 3. Branching workflow — the killer feature (branch-per-PR)

A branch is a full, isolated, writable copy of the DB at a point in time — created in <1s, charged only for
the **delta** you write. Use it for preview environments, migration rehearsals, and safe debugging on
prod-shaped data.

```bash
# Spin up an isolated branch off main, get its (pooled) connection string, run the app/tests against it
neonctl branches create --name pr-1234 --parent main
neonctl connection-string pr-1234 --pooled
# ...run migrations + e2e tests on the branch (zero risk to prod)...
neonctl branches delete pr-1234        # tear down when the PR merges/closes
```

```yaml
# .github/workflows/preview.yml — ephemeral DB per pull request (the canonical Neon pattern)
name: neon-preview
on: pull_request
jobs:
  db:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: neondatabase/create-branch-action@v6
        id: branch
        with:
          project_id: ${{ vars.NEON_PROJECT_ID }}
          branch_name: preview/pr-${{ github.event.number }}
          api_key: ${{ secrets.NEON_API_KEY }}
      - run: npx prisma migrate deploy          # apply schema to the fresh branch
        env: { DATABASE_URL: "${{ steps.branch.outputs.db_url_pooled }}" }
      # ...run tests against the branch; a separate workflow deletes the branch on PR close...
```
Schema-migration safety: branch prod → run the migration on the branch → verify → only then apply to prod.
A bad migration ruins a throwaway branch, not production.

---

## 4. Autoscaling + scale-to-zero (and cold starts)

- **Autoscaling:** compute sizes in Compute Units (CU = vCPU+RAM) and scales **up/down with load** between a
  min and max you set — no manual resizing.
- **Scale-to-zero:** after **~5 minutes idle** (default), the compute **suspends** → you pay $0 for compute.
- **Cold start:** the next connection **resumes** the compute in roughly **0.5s** (sometimes a few seconds).

Design for it:
```ts
// Treat the first query after idle as potentially slow. Set a sane connect timeout + one retry.
// Don't set client connect timeouts below ~10s on scale-to-zero branches, or cold starts will error.
```
Trade-offs: keep scale-to-zero **on** for dev/preview/low-traffic (cost win); for latency-critical prod
either raise the autosuspend window or keep a minimum compute warm (paid). **Gotcha:** extensions that hold
state across the cluster (`pg_cron`, cross-DB `postgres_fdw`) don't run while suspended — keep that endpoint
always-on if you depend on them.

---

## 5. Prisma & Drizzle config

```ts
// Prisma with the Neon serverless driver adapter (edge/serverless). Pooled at runtime, direct for migrate.
import { Pool, neonConfig } from "@neondatabase/serverless";
import { PrismaNeon } from "@prisma/adapter-neon";
import { PrismaClient } from "@prisma/client";
import ws from "ws"; neonConfig.webSocketConstructor = ws;        // needed in Node

const pool = new Pool({ connectionString: process.env.DATABASE_URL }); // POOLED
export const prisma = new PrismaClient({ adapter: new PrismaNeon(pool) });
```
```prisma
// schema.prisma — pooled for the client, direct for the CLI (migrate/introspect)
datasource db {
  provider  = "postgresql"
  url       = env("DATABASE_URL")   // pooled (-pooler), with ?pgbouncer=true if not using the adapter
  directUrl = env("DIRECT_URL")     // direct — prisma migrate/db pull use this
}
```

```ts
// Drizzle — pick the matching entrypoint for your transport:
import { drizzle } from "drizzle-orm/neon-http";          // HTTP, single queries (edge)
import { neon } from "@neondatabase/serverless";
export const db = drizzle(neon(process.env.DATABASE_URL!));

// ...or for transactions/sessions:
// import { drizzle } from "drizzle-orm/neon-serverless"; // WebSocket, transaction-capable
```
With raw PgBouncer-pooled strings (no driver adapter), add `?pgbouncer=true` so prepared statements don't
break in transaction mode. `drizzle-kit` migrations should use the **direct** URL.

---

## Edge cases & war stories
- **Direct string in a Lambda** → `too many clients` under load. Use the `-pooler` host for app traffic.
- **`pg` driver on Cloudflare Workers** → fails (no TCP). Use `@neondatabase/serverless` HTTP/WS.
- **Cold-start timeout.** A 2s client connect timeout on a scaled-to-zero branch errors on the first hit.
  Raise it (~10s) and/or keep prod compute warm.
- **`pg_cron` "stopped" on scale-to-zero.** Scheduled jobs don't fire while suspended — that endpoint must be
  always-on. Same for long-lived `LISTEN/NOTIFY`.
- **Prepared-statement error under pooler.** Add `?pgbouncer=true` (or use the Prisma adapter which handles it).
- **Branch sprawl/cost.** Orphaned PR branches accumulate storage + (if used) compute. Auto-delete on PR close.
- **Pool not closed in serverless** → leaked connections. Create the Pool inside the handler and
  `ctx.waitUntil(pool.end())`, or use the HTTP `neon()` function which needs no teardown.

## Performance
- HTTP `neon()` for single queries (lowest latency, no connection lifecycle); WS Pool only for transactions.
- Pooled string for fan-in; index as you would any Postgres (this is Postgres). Keep payloads small over HTTP.
- Co-locate compute region with your app region to cut RTT; the driver pipelines to reduce round trips.

## Security
- `sslmode=require` (Neon enforces TLS). Per-role least privilege; separate roles for app vs migrations.
- Store the Neon API key (used by branch automation) as a CI secret with minimal scope. IP allow-list +
  Postgres roles; protected branches for prod so previews can't touch it.

## Scale & reliability
- Autoscaling handles load; pooled endpoint handles up to ~10k clients. Set min/max CU sensibly.
- Storage is durable + versioned (PITR / restore-to-timestamp via branches). Read replicas (compute on the
  same storage) for read-heavy load. Multi-region is via project region choice (no cross-region write).

## Testing
- Branch-per-PR gives you a **real Postgres** with prod-shaped schema for CI e2e — far better than mocks or
  SQLite. Reset = delete + recreate the branch. Rehearse every migration on a branch before prod.

## Observability
- Neon Console: compute activity (suspend/resume events), connection counts, query metrics; integrates with
  Datadog/OTel. Alert on connection saturation and unexpected always-on compute (cost).

## Cost notes
- Billed on **compute-hours** (CU × time the compute is active) + **storage** + egress. Scale-to-zero makes
  idle ≈ free — the big win for dev/preview/spiky apps. Free tier covers hobby; Launch (~$19/mo) for always-on
  / more compute. Branch storage is the *delta* only. Always-on prod compute is the main line item — size min CU.

## Anti-patterns
- Using the direct (non-pooler) string for application traffic.
- The plain `pg` driver on edge runtimes (use the serverless driver).
- Aggressive client connect timeouts on scale-to-zero branches (cold-start failures).
- Keeping compute always-on "for safety" while paying serverless prices and ignoring the branching/idle wins.
- Leaving preview branches undeleted (storage/compute creep).
- Depending on `pg_cron`/`fdw` on a scale-to-zero endpoint.

## Agent checklist
```
- [ ] DATABASE_URL = pooled (-pooler); DIRECT_URL = direct (no -pooler) for migrations
- [ ] App/edge queries use @neondatabase/serverless (HTTP neon() for single, Pool/Client WS for txns)
- [ ] Prisma: adapter-neon + pooled url + directUrl; Drizzle: neon-http vs neon-serverless chosen per need
- [ ] ?pgbouncer=true when using raw pooled string with prepared statements
- [ ] Cold-start handled: generous connect timeout / keep prod warm if latency-critical
- [ ] Branch-per-PR in CI; migrations rehearsed on a branch before prod; branches auto-deleted on close
- [ ] sslmode=require; least-privilege roles; Neon API key scoped + in CI secrets; prod branch protected
- [ ] Min/max CU set; alerts on connections + unexpected always-on compute
```

## References (2026-current)
- Serverless driver: https://neon.com/docs/serverless/serverless-driver
- Connection pooling (pooled vs direct): https://neon.com/docs/connect/connection-pooling
- Branching: https://neon.com/docs/introduction/branching · GitHub Actions: https://neon.com/docs/guides/branching-github-actions
- Autoscaling & scale-to-zero: https://neon.com/docs/introduction/autoscaling & https://neon.com/docs/introduction/scale-to-zero
- Prisma: https://www.prisma.io/docs/orm/overview/databases/neon · Drizzle: https://orm.drizzle.team/docs/connect-neon

## Related
`systems-platforms-foundation`, `supabase-complete`, `cloudflare-platform-complete` (this hub) ·
`backend-api-master`, `fullstack-stacks-master`.
