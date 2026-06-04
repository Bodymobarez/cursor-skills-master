---
name: database-studio-complete
description: >-
  Build a professional, multi-page Database Studio product end-to-end: connection manager,
  schema browser, visual table editor, SQL IDE (Monaco), ER diagrams, migrations, backups,
  monitoring, RBAC, audit logs, AI SQL copilot. Postgres/MySQL/MongoDB/SQLite/Redis adapters.
  Supabase Studio / DataGrip / PlanetScale / Compass tier. Use for any DB admin console or studio app.
---

# Database Studio — Complete (professional multi-page product)

**Mandate:** ship a **production-grade Database Studio** — not a single SQL textarea. Every module (connections,
schema, data grid, SQL IDE, migrations, backups, monitoring, team RBAC) must feel like **Supabase Studio +
DataGrip + PlanetScale console** combined: fast, trustworthy, keyboard-first, safe on production data.

**Pair with:** `systems-platforms-foundation`, `supabase-complete`, `mongodb-complete`, `database-design` (backend-api),
`elite-ui-ux-design-system`, `tailwind-master`, `cybersecurity-master`.

---

## When to use / when NOT

| Use | Don't |
|-----|-------|
| Build internal DB admin, customer-facing studio, white-label data console | Only need schema design docs → `database-design` |
| Multi-connection, multi-engine admin UI | Hosted-only: use Supabase Dashboard as-is with no custom UI |
| Visual migrations + ER + monitoring in one product | One-off `psql` script → CLI only |

---

## Reference stack (steal patterns, don't clone trademarks)

| Product | Steal |
|---------|-------|
| **Supabase Studio** | Table editor, RLS visibility, SQL editor, API docs sidebar |
| **DataGrip / TablePlus** | Multi-tab SQL, schema tree, data export, SSH tunnels |
| **PlanetScale** | Branching mental model, deploy requests, schema diff |
| **MongoDB Compass** | Document tree, aggregation pipeline builder |
| **Beekeeper Studio** | Clean OSS UX, connection cards, query history |
| **Metabase** (admin slice) | Saved questions, simple chart from SQL |
| **Retool** (DB resource) | Connection test, credential scoping per app |

**Avoid:** raw SQL as the only UI; no confirm on destructive ops; storing DB passwords in localStorage plaintext.

---

## Product architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│  Studio Shell (auth, org, theme, ⌘K, notifications, connection switcher) │
├────────────┬────────────────────────────────────────────────────────────┤
│  Primary   │  Main workspace (route-driven panels)                       │
│  Nav       │  ┌─────────────────────────────────────────────────────┐  │
│            │  │ Context header: connection · database · env badge   │  │
│  · Home    │  └─────────────────────────────────────────────────────┘  │
│  · Schema  │  Page content (see sitemap below)                           │
│  · SQL     │                                                           │
│  · Data    │  Optional right rail: inspector / AI copilot / properties │
│  · Migrate │                                                           │
│  · Monitor │                                                           │
│  · Backup  │                                                           │
│  · Users   │                                                           │
│  · Logs    │                                                           │
│  · Settings│                                                           │
└────────────┴────────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────────┐
│ Connection Pool │────▶│ Driver Adapters  │────▶│ Target databases     │
│ (per org)       │     │ PG/MySQL/Mongo/… │     │ (customer instances) │
└─────────────────┘     └──────────────────┘     └─────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ Studio metadata DB (your app): users, orgs, connections (encrypted),    │
│ saved queries, migration runs, audit events, alert rules                 │
└─────────────────────────────────────────────────────────────────────────┘
```

**Trust model:** browser **never** holds raw DB credentials. Studio backend holds secrets (Vault/KMS);
browser gets short-lived **connection session tokens** scoped to one connection + read/write mode.

---

## Full sitemap (every page — implement all)

### 0. Auth & onboarding
| Screen | Requirements |
|--------|----------------|
| Sign up / Sign in | SSO (Google/GitHub), MFA optional, magic link |
| Org create / invite | Multi-tenant; invite links expire |
| Onboarding wizard | Add first connection → test → pick default database |

### 1. Home dashboard (`/`)
| Widget | Content |
|--------|---------|
| Connection health | Green/yellow/red per connection; last ping |
| Quick actions | New query, open schema, recent table |
| Recent activity | Last 10 queries (user + duration + status) |
| Alerts | Slow query threshold, replication lag, disk % |
| Favorites | Pinned tables / saved queries |

### 2. Connections (`/connections`)
| Feature | Detail |
|---------|--------|
| Connection cards | Name, engine icon, host (masked), environment tag (prod/staging/dev) |
| Add connection wizard | Step 1 engine → Step 2 host/port/SSL → Step 3 auth → Step 4 test → Step 5 save |
| Engines | PostgreSQL, MySQL/MariaDB, MongoDB, SQLite (file upload), Redis (optional), SQL Server (optional) |
| Advanced | SSH tunnel, SSL mode (require/verify-full), read replica URL, connection pool size |
| Test connection | Sub-2s timeout; show server version + latency |
| Secrets | Encrypt at rest (AES-256-GCM + KMS); never log connection strings |
| Tags | `production` requires extra confirm + optional IP allowlist |

### 3. Schema browser (`/schema/:connectionId`)
| Tree node | Actions |
|-----------|---------|
| Databases / schemas | Expand, filter search, refresh metadata cache |
| Tables / views / mat. views | Open in table editor, copy name, DDL preview |
| Columns | Type, nullable, default, FK indicator |
| Indexes | List, duplicate detection hint |
| Constraints | PK, FK, UNIQUE, CHECK — link to referenced table |
| Functions / procedures | Show definition (read-only unless migrate mode) |
| Triggers | List + linked table |
| Enums / types | Postgres custom types |
| RLS policies (Postgres) | List policies per table — highlight if RLS off on sensitive table |
| Search | Fuzzy find table/column across connection |

**UX:** resizable tree (240–320px); breadcrumb `connection › db › public › users`; skeleton on first load.

### 4. Table / collection editor (`/data/:connectionId/:table`)
| Feature | Detail |
|---------|--------|
| Data grid | Virtualized rows (TanStack Virtual); 50–200 rows/page; server-side sort/filter |
| Inline edit | Cell edit with type-aware inputs (bool toggle, date picker, JSON editor) |
| Add row | Modal or inline new row; validate NOT NULL + FK before save |
| Delete | Row select + bulk delete; **confirm modal** on prod |
| Filters | Column filters (eq, contains, is null, between); save as view |
| Export | CSV, JSON, SQL INSERT batch (chunked) |
| Import | CSV upload → map columns → preview → insert (transaction) |
| FK navigation | Click FK cell → open referenced row |
| JSON / Array columns | Monaco mini-editor for Postgres JSONB |
| MongoDB mode | Document list + BSON-friendly JSON editor + nested expand |
| Read-only mode | Banner when connection or table is read-only |

### 5. SQL IDE (`/sql/:connectionId`)
| Feature | Detail |
|---------|--------|
| Editor | Monaco or CodeMirror 6; dialect per engine; bracket match, format (sql-formatter) |
| Tabs | Multi-tab queries; dirty indicator; session restore |
| Run | `⌘Enter` / `Ctrl+Enter`; selection-only execution |
| Results | Grid below (paginate 1k+); messages tab for NOTICE/errors; timing ms |
| Explain | `EXPLAIN (ANALYZE, BUFFERS)` button; visual plan tree (Postgres) |
| Autocomplete | Schema-aware: tables, columns, aliases, keywords |
| Parameters | `$1`, `:name` binding UI before run |
| Limit guard | Default `LIMIT 1000` on SELECT unless user overrides (prod) |
| Transaction mode | Toggle autocommit / explicit BEGIN-COMMIT |
| Save / share | Named snippets; org-shared vs private |
| History | Per-user query log (truncate secrets); re-run |
| Export results | CSV, clipboard, chart (optional quick viz) |
| Dangerous ops | Detect `DROP`, `TRUNCATE`, `DELETE` without WHERE → typed confirm `DELETE` |

### 6. Visual query builder (optional `/builder`)
| Feature | Detail |
|---------|--------|
| Tables | Drag tables → auto-join on FK |
| Columns | Select, aggregate, group by |
| Filters | Visual WHERE builder |
| Preview SQL | Read-only generated SQL → open in IDE |

### 7. ER diagram (`/diagram/:connectionId`)
| Feature | Detail |
|---------|--------|
| Canvas | react-flow or @xyflow/react; auto-layout (dagre) |
| Nodes | Table box: name + PK columns + FK edges |
| Interactions | Pan/zoom, minimap, export PNG/SVG |
| Scope | Whole schema or subset (pinned tables) |
| Diff overlay | Highlight new/changed tables after migration (optional) |

### 8. Migrations (`/migrations/:connectionId`)
| Feature | Detail |
|---------|--------|
| Migration list | Version, status, applied_at, author |
| Create | From SQL file upload or visual diff (source vs target) |
| Diff engine | Compare live schema to migration folder (Atlas, Flyway, Prisma migrate, Drizzle) |
| Apply | Dry-run → show SQL → confirm → apply in transaction |
| Rollback | One-step rollback where supported; never silent on prod |
| Branching (advanced) | Neon/PlanetScale-style: dev branch per PR (if platform supports) |
| CI hook | API to run pending migrations from pipeline |

### 9. Database users & roles (`/security/:connectionId`)
| Feature | Detail |
|---------|--------|
| DB roles list | Read from `pg_roles` / MySQL users (read-only by default) |
| Grants viewer | Table/column privileges matrix |
| Studio RBAC | Separate: who in your app can use which connection (see below) |
| RLS advisor (Postgres) | Tables without RLS flagged |

### 10. Backups (`/backups/:connectionId`)
| Feature | Detail |
|---------|--------|
| Manual backup | Trigger pg_dump / logical export; progress bar |
| Schedules | Cron per connection; retention policy |
| Restore | Point-in-time if provider supports; else restore from artifact |
| Storage | S3/R2 encrypted artifacts; checksum verify |

### 11. Monitoring (`/monitor/:connectionId`)
| Feature | Detail |
|---------|--------|
| Connections | Active / idle / max; graph over time |
| Slow queries | Top N by total time; link to SQL IDE |
| Storage | DB size, table sizes, bloat estimate (Postgres) |
| Replication | Lag seconds, replica status |
| Cache hit (Postgres) | Buffer cache ratio |
| Alerts | Configure thresholds → email/Slack webhook |

### 12. Logs & audit (`/logs`)
| Feature | Detail |
|---------|--------|
| Audit log | Who ran what query (hash), connection, duration, rows affected |
| Studio access log | Login, connection open, export events |
| Filter | User, connection, date range, severity |
| Compliance | Immutable append-only store; retention policy |

### 13. AI copilot panel (global rail)
| Feature | Detail |
|---------|--------|
| NL → SQL | Schema context injected; dialect-aware |
| Explain query | Plain English + index suggestions |
| Fix error | Paste error → suggested fix |
| Guardrails | Never auto-run on prod without confirm; read-only suggest mode default |

### 14. Settings (`/settings`)
| Section | Content |
|---------|---------|
| Profile | Name, avatar, MFA |
| Organization | Members, roles, billing |
| Connections defaults | Default LIMIT, timeout, theme |
| API keys | Studio API for automation (scoped) |
| Webhooks | Migration done, alert fired |
| Keyboard shortcuts | Cheat sheet modal |
| Appearance | Light/dark; density compact/comfortable |

---

## Studio app RBAC (your product users)

| Role | Permissions |
|------|-------------|
| **Owner** | Billing, delete org, all connections |
| **Admin** | Manage connections, members, prod write |
| **Developer** | SQL + schema read/write on non-prod; read-only prod |
| **Analyst** | SQL read-only all; export allowed |
| **Viewer** | Schema browse + table read only |

Enforce on **every API route** + UI hides disabled actions (don't rely on UI alone).

```typescript
// Example: connection-scoped permission check
type StudioPermission =
  | "connection:read"
  | "connection:write"
  | "connection:admin"
  | "sql:run"
  | "sql:run:destructive"
  | "migration:apply"
  | "backup:create";

function can(user: StudioUser, connectionId: string, perm: StudioPermission): boolean {
  const grant = user.grants.find((g) => g.connectionId === connectionId);
  return grant?.permissions.includes(perm) ?? false;
}
```

**Production connections:** require `sql:run:destructive` for DROP/TRUNCATE; default deny.

---

## Driver adapter layer (multi-engine)

```typescript
// packages/db-adapters/src/types.ts
export interface DatabaseAdapter {
  engine: "postgres" | "mysql" | "mongodb" | "sqlite";
  testConnection(config: ConnectionConfig): Promise<ConnectionInfo>;
  listDatabases(): Promise<string[]>;
  listTables(schema: string): Promise<TableMeta[]>;
  getTableColumns(schema: string, table: string): Promise<ColumnMeta[]>;
  getTableData(params: DataQueryParams): Promise<DataPage>;
  updateRow(params: RowUpdateParams): Promise<void>;
  runQuery(sql: string, params?: unknown[]): Promise<QueryResult>;
  explain(sql: string): Promise<ExplainPlan>;
  getDdl(schema: string, object: string): Promise<string>;
}

// Factory — never import pg in the browser bundle
export function createAdapter(config: ConnectionConfig): DatabaseAdapter {
  switch (config.engine) {
    case "postgres": return new PostgresAdapter(config);
    case "mysql": return new MysqlAdapter(config);
    case "mongodb": return new MongoAdapter(config);
    case "sqlite": return new SqliteAdapter(config);
    default: throw new Error(`Unsupported engine: ${config.engine}`);
  }
}
```

**Rules:**
- All queries run **server-side** (Node/Bun/Edge Worker with DB drivers).
- Use **read replicas** for analytics-style SELECT when configured.
- **Parameterized queries only** — no string concat from UI filters.
- Connection pooling: PgBouncer/Supavisor transaction mode for serverless; cap pool per org.

---

## Studio metadata schema (your Postgres)

```sql
-- Organizations & users (simplified)
create table orgs ( id uuid primary key, name text not null, created_at timestamptz default now() );
create table org_members ( org_id uuid references orgs, user_id uuid, role text not null, primary key (org_id, user_id) );

create table connections (
  id uuid primary key,
  org_id uuid not null references orgs,
  name text not null,
  engine text not null,
  host text not null,
  port int not null,
  database_name text,
  ssl_mode text default 'require',
  environment text not null default 'development', -- development | staging | production
  secret_ref text not null, -- KMS/Vault pointer, NOT the password
  ssh_tunnel jsonb,
  created_by uuid,
  created_at timestamptz default now()
);

create table saved_queries (
  id uuid primary key,
  org_id uuid not null,
  connection_id uuid references connections,
  name text not null,
  sql text not null,
  is_shared boolean default false,
  created_by uuid,
  updated_at timestamptz default now()
);

create table query_audit (
  id bigserial primary key,
  org_id uuid not null,
  user_id uuid not null,
  connection_id uuid not null,
  sql_hash text not null,
  duration_ms int,
  row_count int,
  status text not null, -- success | error
  is_destructive boolean default false,
  created_at timestamptz default now()
);
create index query_audit_org_created on query_audit (org_id, created_at desc);
```

---

## API surface (REST or tRPC)

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/connections` | GET/POST | List/create connections |
| `/api/connections/:id/test` | POST | Test + cache metadata |
| `/api/connections/:id/schema` | GET | Tree metadata (cached 60s) |
| `/api/connections/:id/tables/:table/data` | GET/PATCH | Paginated grid + row update |
| `/api/connections/:id/query` | POST | Execute SQL (guarded) |
| `/api/connections/:id/explain` | POST | Explain plan |
| `/api/connections/:id/migrations` | GET/POST | List/apply migrations |
| `/api/connections/:id/monitor` | GET | Metrics snapshot |
| `/api/saved-queries` | CRUD | Snippets |
| `/api/audit` | GET | Audit log (admin) |

**Rate limits:** 60 queries/min/user on prod connections; burst for dev.

---

## Frontend stack (recommended)

| Layer | Choice |
|-------|--------|
| Framework | Next.js 15 App Router or Remix |
| UI | shadcn/ui + Tailwind v4 (`elite-ui-ux-design-system` for shell) |
| SQL editor | `@monaco-editor/react` + `monaco-sql-languages` |
| Data grid | TanStack Table + TanStack Virtual |
| ER diagram | `@xyflow/react` + `dagre` |
| State | TanStack Query for server state; URL for connection/table context |
| Realtime | Optional: schema change notifications via SSE/pg_notify |
| Auth | Clerk / Supabase Auth / custom JWT |

**URL pattern:** `/studio/:orgSlug/connections/:connectionId/sql?tab=2`

---

## Security checklist (non-negotiable)

```
- [ ] Credentials in KMS/Vault; rotate supported
- [ ] TLS to database; verify-full in production
- [ ] Studio RBAC on every route; prod destructive ops gated
- [ ] SQL injection impossible (parameterized only)
- [ ] Default SELECT LIMIT on prod; DELETE without WHERE blocked or confirmed
- [ ] Audit log append-only; query text hashed or truncated for secrets
- [ ] No service_role / root DB user in browser-facing connections
- [ ] IP allowlist option for production connections
- [ ] Session timeout; MFA for prod write roles
- [ ] Export events logged; large export rate-limited
```

Cross-check `cybersecurity-master` for OWASP and secrets handling.

---

## Performance targets

| Area | Target |
|------|--------|
| Schema tree first paint | < 500ms cached, < 2s cold |
| Table page (1k rows) | < 1s server; virtualized render |
| SQL run (simple SELECT) | < 300ms perceived; streaming results for huge sets |
| Metadata cache | Redis 60–120s; invalidate on migration apply |
| Lighthouse | 90+ on shell pages (defer Monaco chunk) |

---

## Implementation phases (agent order)

```
Phase 1 — Foundation
  Auth, org, connections CRUD, test connection, encrypted secrets

Phase 2 — Browse & read
  Schema tree, table read-only grid, SQL IDE read-only + results

Phase 3 — Write & danger
  Inline edit, imports, transaction mode, destructive confirm, audit log

Phase 4 — Power user
  Migrations, ER diagram, explain plans, saved queries, keyboard shortcuts

Phase 5 — Operate
  Monitoring, backups, alerts, AI copilot (schema-grounded)

Phase 6 — Enterprise
  SSO, MFA, IP allowlist, compliance export, white-label theming
```

Never ship Phase 3 write paths without audit + prod guards.

---

## UI/UX bar (`elite-ui-ux-design-system`)

- **Shell:** collapsible sidebar, connection switcher in top bar, `⌘K` → jump table / run saved query
- **Environment badges:** `production` = red outline; extra friction on mutations
- **Empty states:** no connections → wizard; empty table → "No rows" + import CTA
- **Loading:** skeleton tree + grid; never blank white panels
- **Errors:** inline SQL error with line/column; retry on connection timeout
- **RTL:** mirror sidebar + grid scroll; monospace SQL LTR always

---

## Testing strategy

| Layer | Tests |
|-------|-------|
| Adapters | Integration tests against Docker Postgres/MySQL/Mongo |
| API | Permission matrix per role; destructive SQL rejected without perm |
| E2E (Playwright) | Add connection → browse → run SELECT → edit cell → audit entry exists |
| Security | Attempt SQL injection via filter UI; credential never in API response |

---

## Anti-patterns

- Exposing DB port directly to browser (WebSocket raw SQL without gateway)
- Storing passwords in `localStorage` or client env
- One giant "run anything" endpoint without RBAC
- No limit on SELECT → OOM on `SELECT * FROM logs`
- Click-to-run migrations on production without dry-run
- Schema tree that refetches entire catalog on every click
- Grid that loads 100k rows into DOM

---

## Agent checklist

```
- [ ] All 14 sitemap areas addressed or explicitly deferred with reason
- [ ] Driver adapter interface; server-side query execution only
- [ ] Studio metadata DB + encrypted connection secrets
- [ ] RBAC + prod destructive guards + audit log
- [ ] SQL IDE: autocomplete, explain, history, parameterized runs
- [ ] Table editor: virtualized grid, import/export, FK navigation
- [ ] Migrations: dry-run before apply
- [ ] Monitoring + backup modules sketched or implemented
- [ ] UI meets elite bar; environment badges on prod
- [ ] Security + performance checklist reviewed
```

---

## Related skills

| Skill | Use for |
|-------|---------|
| `systems-platforms-foundation` | Pooling, migrations discipline, backups |
| `supabase-complete` | If studio targets Supabase projects + RLS |
| `mongodb-complete` | Document adapter + aggregation UI |
| `neon-postgres-serverless` | Branch-per-PR workflows |
| `database-design` | Schema modeling before studio features |
| `elite-ui-ux-design-system` | Premium shell and dashboards |
| `integrations-master` | Slack alerts, SSO webhooks |

## References

- Supabase Studio (OSS): https://github.com/supabase/supabase/tree/master/apps/studio
- Beekeeper Studio: https://github.com/beekeeper-studio/beekeeper-studio
- Monaco SQL: https://github.com/microsoft/monaco-editor
- TanStack Table: https://tanstack.com/table
