---
name: supabase-complete
description: >-
  Supabase at staff depth (2026): Postgres + Auth + Row Level Security + Storage + Edge Functions
  (Deno) + Realtime, run correctly. Real RLS policies (with the (select auth.uid()) perf fix),
  storage policies, CLI migrations + local dev (supabase start), Supavisor pooler ports, the
  service_role footgun, and a safe path to production. Use for any Supabase build or RLS task.
---

# Supabase — Complete (Postgres with batteries, secured by RLS)

**Mandate:** Supabase is Postgres you talk to directly from the client — so **Row Level Security is your
backend**. Enable RLS on every table, write explicit policies, keep `service_role` server-only, and manage
schema through migration files (not the dashboard). If RLS is off, your "private" data is a public API.

## When to use / when NOT to use
- **Use** for product apps that want Postgres + auth + storage + realtime fast, especially when the client
  queries the DB directly (PostgREST/`supabase-js`) and you lean on RLS for authorization. Great for
  Next.js/Expo/Flutter apps and internal tools.
- **NOT** when you need a different engine (document → `mongodb-complete`), pure serverless branch-per-PR
  Postgres without the platform extras (→ `neon-postgres-serverless`), or you'll never expose the DB to
  clients and want a thin managed Postgres. Don't fight Supabase by routing everything through a custom API
  *and* disabling RLS — pick one trust model.

## Mental model
Two trust zones. **Client zone:** browser/mobile holds the `anon` key + a user JWT; every query runs as that
user and is filtered by RLS — the key is *meant* to be public. **Server zone:** your backend/Edge Functions
hold the `service_role` key, which **bypasses RLS entirely** (it's a superuser-equivalent). The entire
security model is: RLS policies define what the client zone can do; the service_role key never leaves the
server zone. Get those two facts right and Supabase is safe; get either wrong and it's an incident.

---

## 1. Setup + local dev (the CLI is the source of truth)

```bash
# Install + scaffold. Develop locally in Docker; the cloud project mirrors it via migrations.
brew install supabase/tap/supabase     # or npx supabase@latest
supabase init                          # creates supabase/ (config.toml, migrations/, functions/)
supabase start                         # boots Postgres + Studio + Auth(GoTrue) + Storage + Realtime + Edge runtime locally
supabase status                        # prints local URLs + anon/service_role keys + DB url

# Link to the hosted project and push schema
supabase login
supabase link --project-ref <ref>
supabase db push                       # apply local migrations to the linked remote
```

`supabase start` gives you the **entire stack on localhost** — develop and test against real Postgres + RLS,
not mocks. `supabase db reset` rebuilds the local DB from migrations + `seed.sql` (idempotent seed).

---

## 2. Schema via migrations (never click-ops production)

```bash
supabase migration new create_posts        # new timestamped SQL file in supabase/migrations/
# ...edit the file...
supabase db reset                           # locally: replays ALL migrations + seed (clean-room test)
supabase db diff -f add_index               # capture changes you made in Studio into a migration file
supabase gen types typescript --local > src/database.types.ts   # typed client from the live schema
```

```sql
-- supabase/migrations/20260602_create_posts.sql
create table public.posts (
  id          uuid primary key default gen_random_uuid(),
  author_id   uuid not null references auth.users (id) on delete cascade,
  title       text not null check (char_length(title) between 1 and 200),
  body        text,
  published   boolean not null default false,
  created_at  timestamptz not null default now()
);
create index posts_author_created_idx on public.posts (author_id, created_at desc);
alter table public.posts enable row level security;   -- ALWAYS, in the same migration as the table
```

---

## 3. Row Level Security — your actual backend

**Default-deny:** with RLS enabled and no policy, *nothing* is allowed (even reads). Write one policy per
intended action, naming the role and the `using`/`with check` clauses explicitly.

```sql
-- Read: anyone can see PUBLISHED posts; authors see their own drafts too
create policy "read published or own"
  on public.posts for select
  to authenticated, anon
  using ( published = true or author_id = (select auth.uid()) );

-- Insert: a user may only create rows they own (WITH CHECK guards the NEW row)
create policy "insert own"
  on public.posts for insert
  to authenticated
  with check ( author_id = (select auth.uid()) );

-- Update/Delete: only the owner (USING gates which rows; WITH CHECK gates the result)
create policy "modify own"
  on public.posts for update
  to authenticated
  using ( author_id = (select auth.uid()) )
  with check ( author_id = (select auth.uid()) );

create policy "delete own"
  on public.posts for delete
  to authenticated
  using ( author_id = (select auth.uid()) );
```

> **Performance fix that matters at scale:** wrap auth calls as `(select auth.uid())` not bare `auth.uid()`.
> The subselect lets Postgres evaluate it **once per query** (initPlan) instead of **once per row** — on a
> large table this is the difference between a fast scan and a timeout. Same for `(select auth.jwt())`.

```sql
-- USING vs WITH CHECK (the distinction people get wrong):
--   USING       → which EXISTING rows the operation can see/touch (select/update/delete)
--   WITH CHECK  → whether the NEW/updated row is allowed to exist  (insert/update)
-- For multi-tenant, gate on a tenant claim and index the column:
create policy "tenant isolation" on public.invoices for all to authenticated
  using ( org_id = (select auth.jwt() ->> 'org_id')::uuid )
  with check ( org_id = (select auth.jwt() ->> 'org_id')::uuid );
create index invoices_org_idx on public.invoices (org_id);
```

Test RLS in CI by querying **as a user** (anon key + a signed JWT), asserting you only see allowed rows —
RLS bugs are silent until exploited.

---

## 4. Auth (GoTrue) + client usage

```ts
// Browser/server: anon key + the user's JWT. Every query runs AS that user → RLS applies.
import { createClient } from "@supabase/supabase-js";
import type { Database } from "./database.types";

export const supabase = createClient<Database>(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!   // PUBLIC by design — safe ONLY because RLS is on
);

const { data, error } = await supabase.from("posts").select("*").eq("published", true);
// This hits PostgREST; RLS filters rows server-side. No anon key = no bypass.
```

- **Auth providers:** email/password, magic link, OTP, OAuth (Google/GitHub/Apple…), SAML/SSO (paid), MFA.
- Use the helpers (`@supabase/ssr`) for Next.js so the JWT is read from cookies on the server and refreshed
  correctly — don't hand-roll session handling.
- New users land in `auth.users`. Mirror profile data into `public.profiles` via a trigger so your own
  tables can reference it and RLS can join on it:

```sql
create function public.handle_new_user() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, email) values (new.id, new.email);
  return new;
end; $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();
```

---

## 5. Storage + policies (RLS for files)

Storage objects live in Postgres too (`storage.objects`) — so you secure files with the **same RLS model**.

```sql
-- Private "avatars" bucket: a user may only touch files under a folder named after their uid
create policy "own avatar folder"
  on storage.objects for all to authenticated
  using ( bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text )
  with check ( bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text );
```
```ts
await supabase.storage.from("avatars").upload(`${userId}/profile.png`, file, { upsert: true });
// Private buckets: hand out short-lived signed URLs, never make the bucket public for user data.
const { data } = await supabase.storage.from("avatars").createSignedUrl(`${userId}/profile.png`, 60);
```

---

## 6. Edge Functions (Deno) + Realtime

```ts
// supabase/functions/charge/index.ts — Deno runtime. `supabase functions serve` locally, then deploy.
import { createClient } from "jsr:@supabase/supabase-js@2";

Deno.serve(async (req) => {
  const auth = req.headers.get("Authorization") ?? "";
  // Forward the caller's JWT so DB access still runs UNDER RLS (use anon key + the user token):
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: auth } } }
  );
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return new Response("unauthorized", { status: 401 });
  // ... business logic; only use SERVICE_ROLE_KEY here if you INTENTIONALLY need to bypass RLS ...
  return Response.json({ ok: true });
});
```
```bash
supabase functions new charge
supabase functions serve charge                 # local, hot-reload (oneshot policy for instant changes)
supabase secrets set STRIPE_KEY=sk_live_xxx     # function env (server-side secrets)
supabase functions deploy charge
```

```ts
// Realtime: subscribe to row changes (Postgres logical replication) — note RLS also applies to realtime
supabase.channel("posts")
  .on("postgres_changes", { event: "INSERT", schema: "public", table: "posts" },
      (payload) => console.log("new post", payload.new))
  .subscribe();
```

---

## 7. Connections & pooler (the production-scale gotcha)

Supabase fronts Postgres with **Supavisor**. Use the right port for the runtime:

| Port | Mode | Use for | Caveats |
|---|---|---|---|
| `5432` (direct) | direct to Postgres | **migrations**, admin, long-lived sessions needing `SET`/`LISTEN` | limited by instance `max_connections` |
| `6543` | **transaction** pooling | serverless/edge, many short-lived connections | no session state; disable prepared-statement cache (`?pgbouncer=true`) |
| (session pooler) | session pooling | long-lived servers wanting multiplexing | one server conn per client session |

```bash
# Serverless (Vercel/Lambda/Workers) — transaction pooler, prepared statements OFF
DATABASE_URL="postgresql://postgres.<ref>:<pwd>@<region>.pooler.supabase.com:6543/postgres?pgbouncer=true"
# Migrations / Prisma migrate — DIRECT connection
DIRECT_URL="postgresql://postgres.<ref>:<pwd>@<region>.pooler.supabase.com:5432/postgres"
```
Serverless functions opening **direct** :5432 connections will exhaust `max_connections` under load → use
:6543. ORMs (Prisma/Drizzle) need the direct URL for migrations and the pooled URL at runtime.

---

## 8. Going to production
- RLS enabled + policies reviewed on **every** public table (the dashboard's Security Advisor flags
  unprotected tables — fix all of them).
- `service_role` only in server/Edge env, never shipped to a client bundle. Rotate keys if exposed.
- Migrations applied via `supabase db push` in CI, not by editing prod in Studio.
- Backups/PITR enabled (Pro+); custom SMTP for auth emails (the default sender is rate-limited and not for
  production volume → wire Resend/SES via `email-server-complete`).
- Set `statement_timeout` for the `authenticated`/`anon` roles so a heavy client query can't hog a connection.

---

## Edge cases & war stories
- **RLS off = public dump.** The classic Supabase breach: a table without RLS (or `enable rls` forgotten in
  the migration) is fully readable with the public anon key. Default-deny + Security Advisor catches it.
- **`service_role` in the browser.** Someone uses it client-side "to make a query work" → RLS bypassed for
  every visitor. It must never be in `NEXT_PUBLIC_*` or any client bundle.
- **`auth.uid()` per-row blowup.** Policies with bare `auth.uid()` re-evaluate per row; at 100k rows the
  query times out. `(select auth.uid())` fixes it.
- **Serverless connection storm.** Direct :5432 from Lambda → `remaining connection slots are reserved`.
  Switch to :6543 transaction pooler with `pgbouncer=true`.
- **Prepared statement errors under PgBouncer.** Transaction mode + prepared statements → "prepared statement
  already exists". Add `?pgbouncer=true` (and Prisma's `directUrl` for migrations).
- **Dashboard drift.** Editing schema in Studio on prod, with no migration → local and prod diverge, next
  `db push` conflicts. Always `db diff` changes into a migration file.

## Performance
- Index every column used in RLS predicates (tenant/org/owner). `(select auth.*)` for once-per-query eval.
- `explain (analyze)` policies on big tables. Narrow `select` columns; paginate with keyset, not `OFFSET`.
- Realtime is logical replication — don't subscribe to ultra-hot tables broadly; scope channels/filters.

## Security
- RLS on every public table; default-deny; explicit `to <role>` + `using`/`with check`. service_role
  server-only. Signed URLs for private storage. `SECURITY DEFINER` functions must `set search_path = ''`.
  Custom SMTP for auth mail. MFA for sensitive apps.

## Scale & reliability
- Transaction pooler (:6543) for serverless; session pooler for long servers; direct only for migrations.
- Pro plan + PITR; read replicas (paid) for read-heavy; monitor connection count vs `max_connections`.

## Testing
- `supabase db reset` in CI replays migrations + seed. Test RLS *as a user* (anon key + signed JWT), assert
  forbidden rows are invisible. pgTAP for in-DB policy unit tests.

## Observability
- Dashboard: Reports (API/db/auth/storage), Logs Explorer, Security & Performance Advisors. Alert on
  connection saturation and slow queries; export logs to your stack.

## Cost notes
- Free tier pauses inactive projects; Pro ($25/mo) for prod + PITR + no pausing. Egress, storage, Edge
  invocations, and Realtime messages are metered — watch broad realtime subscriptions and large media egress.

## Anti-patterns
- Tables without RLS / `service_role` on the client (the two cardinal sins).
- Disabling RLS "temporarily" to debug and forgetting to re-enable.
- Editing prod schema in the dashboard instead of migrations.
- Direct :5432 connections from serverless. Bare `auth.uid()` in hot-table policies.
- Public buckets for user-private files instead of signed URLs.

## Agent checklist
```
- [ ] `supabase init` + local dev via `supabase start`; schema only via migration files
- [ ] enable row level security on every public table IN the creating migration
- [ ] Explicit policies per action; (select auth.uid()/jwt()); USING vs WITH CHECK correct
- [ ] RLS predicate columns indexed (tenant/org/owner)
- [ ] anon key client-side only because RLS is on; service_role server/Edge only
- [ ] Storage policies on storage.objects; private buckets + signed URLs
- [ ] Edge Functions forward the user JWT (RLS preserved); secrets via `supabase secrets set`
- [ ] Serverless → pooler :6543 (?pgbouncer=true); migrations → direct :5432
- [ ] Prod: Security Advisor clean, PITR on, custom SMTP, statement_timeout set
- [ ] RLS tested as a user in CI; types generated with `supabase gen types`
```

## References (2026-current)
- CLI & local dev: https://supabase.com/docs/guides/local-development
- RLS: https://supabase.com/docs/guides/database/postgres/row-level-security (perf: https://supabase.com/docs/guides/troubleshooting/rls-performance-and-best-practices)
- Auth: https://supabase.com/docs/guides/auth · SSR: https://supabase.com/docs/guides/auth/server-side
- Storage: https://supabase.com/docs/guides/storage · Edge Functions: https://supabase.com/docs/guides/functions
- Realtime: https://supabase.com/docs/guides/realtime · Connection pooling (Supavisor): https://supabase.com/docs/guides/database/connecting-to-postgres

## Related
`systems-platforms-foundation`, `neon-postgres-serverless`, `email-server-complete` (this hub) ·
`backend-api-master` (auth/API), `tailwind-master`/`ui-master` (app UI).
