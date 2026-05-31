---
name: crm-builder
description: >-
  Build a professional CRM (customer relationship management) system. Use when
  the user wants to build a CRM, contact/lead management, sales pipeline, deals,
  activities, or customer 360. Covers data model, pipeline/kanban, activities &
  tasks, lead scoring, RBAC, multi-tenant, reporting, and integrations.
---

# CRM Builder

Build a production-grade CRM. Cover the data model first, then pipeline, activities,
automation, permissions, and reporting.

## Core data model

```
Organization (tenant)
 └─ User (roles: admin, manager, rep)
Contact      — person (name, emails[], phones[], owner, tags, custom_fields)
Account      — company (domain, industry, size, owner)  ⟷ Contacts (M:N)
Lead         — unqualified inbound (source, status, score) → converts to Contact+Deal
Deal/Opportunity — pipeline_id, stage_id, amount, currency, probability, close_date, owner
Pipeline → Stage[] (ordered, with default probability)
Activity     — call/email/meeting/note (related_to: contact|deal|account, due_at, done)
Task         — assignee, due_at, priority, status
```

Add `custom_fields` (JSONB) on Contact/Account/Deal so users extend without migrations.

## Build checklist

```
- [ ] 1. Multi-tenant model (org_id on every row) + RBAC (admin/manager/rep, record ownership)
- [ ] 2. Contacts/Accounts CRUD + dedup (match on email/domain) + import (CSV) + tags
- [ ] 3. Pipelines & stages (configurable) + Deals with drag-drop kanban
- [ ] 4. Activities & tasks timeline on each record (calls, emails, notes, meetings)
- [ ] 5. Lead capture (web form/API) → lead scoring → convert to contact+deal
- [ ] 6. Automation: stage-change triggers, task auto-create, email templates
- [ ] 7. Reporting: pipeline value by stage, win rate, activities per rep, forecast
- [ ] 8. Integrations: email (IMAP/Gmail/Graph), calendar, webhooks; see integrations-pro
- [ ] 9. Audit log + soft deletes + activity feed
```

## Key features done right

- **Pipeline kanban**: drag deals between stages; stage controls default probability; weighted
  forecast = Σ(amount × probability).
- **Lead scoring**: rule-based (demographic + behavioral) score 0–100; threshold → MQL/SQL.
- **Customer 360**: one screen — profile + deals + open tasks + full activity timeline.
- **Dedup/merge**: detect duplicate contacts (email) / accounts (domain); merge keeping history.
- **Permissions**: reps see own + team records; managers see team; admins see all. Enforce at
  the query layer (row-level), not just UI.

## Recommended stack

- Backend: Postgres (JSONB for custom fields), Node/NestJS or Django/DRF or Laravel.
- Frontend: React/Next + a table + kanban (dnd-kit). Pair with `charts-and-dashboards` for reports.
- Search: Postgres FTS or Meilisearch/Typesense for contact search.

## Anti-patterns
- No multi-tenant isolation (org_id missing on a table → data leak).
- Hard-coded pipeline stages (must be configurable per org).
- Storing activities only as free text (model them as typed records for reporting).
- Building reports by N+1 queries instead of aggregate SQL.
