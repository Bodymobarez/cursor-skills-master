---
name: crm-builder
description: >-
  Build a production CRM at principal depth: contacts/accounts, configurable pipelines & kanban
  deals, weighted forecasting, typed activities, lead scoring, customer 360, dedup/merge, and
  record-level permissions enforced in SQL (not the UI). Covers extensible custom fields,
  aggregate reporting (no N+1), automation, and multi-tenant RLS. Postgres + TypeScript.
---

# CRM Builder — Pipeline, People, Permissions

**A CRM is a permissioned graph of people, companies, and deals, plus a timeline of everything that
happened.** The two things teams get wrong: (1) hard-coding the sales process so it can't match how the
business actually sells, and (2) enforcing "who can see what" in the UI while the API leaks every record.
Model the pipeline as data and enforce visibility at the query layer.

---

## 1. Mandate
1. **Pipelines/stages are configurable data**, never enum constants in code.
2. **Record visibility is enforced in SQL** (RLS + ownership predicate), never only in the frontend.
3. **Activities are typed records**, not free text — you can't report on a notes blob.
4. **Custom fields without migrations** (JSONB) so customers extend the schema themselves.
5. **Reports are aggregate queries**, never N+1 loops in app code.
6. **Multi-tenant isolation is structural** (see **`multi-tenant-isolation`**).

## 2. When to use / when NOT
**Use** for sales/lead/deal/customer-360 systems. **Don't** rebuild Salesforce/HubSpot for an org that
just needs a shared pipeline — a configured SaaS CRM is cheaper. Build custom when the CRM is your
product, deeply embedded in your domain, or needs data ownership a SaaS won't give. **Don't** conflate a
CRM (relationships/pipeline) with an ERP (inventory/ledger) — link them (`crm-builder` ⇄ `erp-builder`).

## 3. Core data model

```
Organization (tenant) ─ User (role: admin|manager|rep, team_id)
Contact   person: emails[], phones[], owner_id, account_id, tags[], custom_fields jsonb
Account   company: domain, industry, size, owner_id, custom_fields jsonb     Contact M:N Account
Lead      unqualified inbound: source, status, score → converts to Contact + Deal
Pipeline → Stage[]  (ordered position, default_probability, is_won, is_lost)
Deal      pipeline_id, stage_id, amount(minor units)+currency, owner_id, expected_close, custom_fields
Activity  type[call|email|meeting|note|task], related_to (polymorphic), due_at, completed_at, owner_id
```

```sql
-- Custom fields: JSONB + GIN so customers extend without migrations and you can still query/filter fast.
alter table contact add column custom_fields jsonb not null default '{}';
create index on contact using gin (custom_fields jsonb_path_ops);
-- query: where custom_fields @> '{"industry":"fintech"}'
```

Polymorphic activities: store `(related_type, related_id)` (+ optional typed FKs for hot paths) so a
single timeline query assembles a record's history.

## 4. Pipeline & weighted forecast

Stages own a default probability; the **weighted pipeline** is the forecast finance trusts:

```sql
-- Forecast by stage: weighted value = Σ(amount × stage probability) for open deals
select s.name as stage, count(*) as deals,
       sum(d.amount) as gross,
       round(sum(d.amount * s.default_probability) / 100.0) as weighted   -- minor units
from deal d
join stage s on s.id = d.stage_id
where d.status = 'open' and d.expected_close between $1 and $2
group by s.id, s.name, s.position
order by s.position;
```

Track **stage-entered timestamps** (a `deal_stage_history` row per transition) to compute *velocity*
(avg days in stage), *conversion* (stage→stage rate), and *aging* (deals stuck too long). Kanban drag =
a stage transition that writes history + can fire automation — not just an `UPDATE stage_id`.

## 5. Record-level permissions (enforce in SQL, layer on RLS)

RLS already removed other tenants' rows. Ownership scopes *within* the tenant:

| Role | Sees |
|------|------|
| **rep** | own records + their team's (configurable) |
| **manager** | their team's records |
| **admin** | the whole tenant |

```sql
-- visibility predicate appended to every list query (composes with the RLS tenant filter)
where (
     current_setting('app.role') = 'admin'
  or owner_id = current_setting('app.user_id')::uuid
  or (current_setting('app.role') = 'manager'
      and owner_id = any (current_setting('app.team_member_ids')::uuid[]))
)
```

Push this into a reusable query scope (or a Postgres view / RLS *restrictive* policy) so no endpoint can
forget it. For sharing rules and deep hierarchies (territories, account teams), graduate to a policy
engine / ReBAC — see **`multi-tenant-isolation`** §6. **Never** rely on hiding a button in React.

## 6. Lead scoring & conversion
Rule-based score 0–100 = **demographic fit** (title, company size, industry match to ICP) + **behavioral
intent** (email opens, pricing-page visits, demo request), with time decay so stale activity fades.
Threshold → MQL → SQL → routed to a rep. Keep weights as **config rows**, not code, so RevOps tunes
without a deploy. (For ML lead scoring, route to `analytics-master`; rule-based is the right default and
explainable.) **Convert** = create Contact (+Account) + Deal, carry source/campaign for attribution,
keep the Lead's activity timeline.

## 7. Dedup & merge (data quality is the product)
- **Prevent**: unique-ish match on normalized email (Contact) / domain (Account) at create/import time.
- **Detect**: fuzzy match (`pg_trgm` similarity on name + exact email/domain) surfaced as suggestions.
- **Merge**: pick a survivor, **re-parent** all child rows (deals, activities) to it, union tags/custom
  fields, keep an audit record. Do it in one transaction; never silently drop the loser's history.

```sql
create extension if not exists pg_trgm;
-- candidate duplicate accounts within the tenant
select a.id, b.id, similarity(a.name, b.name) sim
from account a join account b on a.id < b.id and a.domain = b.domain
where similarity(a.name, b.name) > 0.6 order by sim desc;
```

## 8. Reporting & performance
- **Aggregate in SQL** (GROUP BY / window functions), never fetch rows and loop. Win rate, pipeline by
  stage, activities per rep, forecast — all one query each.
- **Timeline N+1 is the classic CRM killer**: load a record's activities with one query + index on
  `(tenant_id, related_type, related_id, due_at desc)`, not a query per activity.
- **Search**: Postgres FTS / `pg_trgm` for small/medium; Meilisearch/Typesense when contact search must
  be instant across millions.
- Index every foreign key and the ownership/stage columns used in filters; `tenant_id` leads them all.

## 9. Automation & integrations
- **Stage-change triggers**: on enter "Negotiation" → create a task, notify, send a templated email.
  Build on a small event bus (`DealStageChanged`) so rules are decoupled and testable.
- **Email/calendar sync** (Gmail/Graph IMAP, CalDAV): log threads as activities against the matching
  contact; two-way where possible. **Webhooks** for inbound leads. Heavy integration detail →
  `integrations-master` / `communications-master`.

## 10. Security & multi-tenant
- RLS + `FORCE`; tenant resolved server-side (**`multi-tenant-isolation`**).
- **PII everywhere** (this is a database of humans): consent flags, export/delete on request (GDPR/PDPL),
  field-level access for sensitive data, audit log of who viewed/exported contacts.
- Soft-delete with a recycle window; full purge on tenant offboarding.

## 11. Testing & observability
- Test the **visibility predicate** directly: a rep query never returns another rep's private records.
- Test **merge** preserves all child rows and history; **convert** carries source/timeline.
- Test forecast math against fixtures. Observe: stuck-deal aging, sync failures, import error rates,
  duplicate-rate trend.

## 12. i18n / RTL
Localized names/addresses (no "first/last" assumptions), `Intl` date/number/currency formatting,
RTL layouts for Arabic; store contact locale and send templated emails in it.

## 13. Anti-patterns
- **Hard-coded pipeline stages** — must be per-tenant configurable.
- **Permissions only in the UI** — the API leaks records. Enforce in SQL.
- **Activities as free-text notes** — unreportable; model typed records.
- **N+1 reports / N+1 timelines** — aggregate and batch.
- **A `tenant_id`-less table** — cross-tenant leak (#1 SaaS bug).
- **Silent dedupe that drops history** — always re-parent and audit.
- **Custom fields as 100 nullable columns** — use JSONB + GIN.

## 14. Agent checklist
```
- [ ] Pipelines/stages configurable; stage history written on transition
- [ ] Visibility = RLS tenant filter + ownership/role predicate in SQL (tested)
- [ ] Activities typed + polymorphic timeline; indexed (tenant, related, due_at)
- [ ] custom_fields jsonb + GIN; no column-per-field sprawl
- [ ] Weighted forecast + win rate + velocity as aggregate SQL (no N+1)
- [ ] Lead scoring weights as config; convert carries source + timeline
- [ ] Dedup detect + transactional merge that re-parents children
- [ ] PII: consent, export/delete, audit; soft delete + offboarding purge
```

## 15. References (2026-current)
- Postgres JSONB & GIN: https://www.postgresql.org/docs/current/datatype-json.html
- pg_trgm fuzzy matching: https://www.postgresql.org/docs/current/pgtrgm.html
- dnd-kit (kanban DnD): https://docs.dndkit.com
- Lead qualification (MQL/SQL) frameworks — current vendor playbooks (HubSpot/Salesforce docs)

## Related
`multi-tenant-isolation`, `erp-builder`, `accounting-finance`, `charts-and-dashboards` (ui-master),
`integrations-master`, `communications-master`
