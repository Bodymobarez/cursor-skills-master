---
name: business-master
description: >-
  Master hub for Business systems & platforms. Use to build CRM, ERP, accounting/
  finance, affiliate/referral programs, and white-label/multi-tenant platforms.
  Bundles 5 specialized skills (in skills/<name>/GUIDE.md). Use this for any
  business-platform, SaaS back-office, CRM, ERP, billing, or white-label task.
---

# Business systems & platforms — Master Hub

Use to build back-office and platform systems: CRM, ERP, accounting/finance, affiliate programs,
and white-label/multi-tenant products.

## How to use this hub

This single skill bundles **all 5 business-platform skills**. Each bundled skill's full
instructions live in `skills/<name>/GUIDE.md` (plus any `scripts/`, `references/` next to it).

**Workflow:**
1. Match the user's request to one or more skills in the list below.
2. Read that skill's `skills/<name>/GUIDE.md` for full instructions before acting.
3. Combine bundled skills when a task spans areas (e.g. ERP + accounting-finance; CRM + integrations).

## Bundled skills

- **crm-builder** — Build a professional CRM: contacts/accounts, sales pipeline & kanban deals, activities/tasks, lead scoring, customer 360, RBAC, multi-tenant, and reporting.  
  → `skills/crm-builder/GUIDE.md`
- **erp-builder** — Build a modular ERP: inventory/warehouse, procurement, sales orders, manufacturing (BOM/MRP), shared master data, ledger posting, multi-currency/company.  
  → `skills/erp-builder/GUIDE.md`
- **accounting-finance** — Correct double-entry accounting: chart of accounts, journals, AR/AP, payments, tax/VAT, multi-currency, reconciliation, and financial statements (P&L, balance sheet, cash flow).  
  → `skills/accounting-finance/GUIDE.md`
- **affiliate-system** — Affiliate/referral program: tracked links, click/conversion attribution, commission models (percent/flat/tiered/recurring), fraud prevention, and payouts.  
  → `skills/affiliate-system/GUIDE.md`
- **white-label-platform** — Make a product white-label & multi-tenant: tenancy models, custom domains + auto TLS, per-tenant theming/branding via CSS variables, white-label emails/docs, and per-tenant billing.  
  → `skills/white-label-platform/GUIDE.md`

## Note

These bundled skills are intentionally not registered as separate Cursor skills (their files are
`GUIDE.md`, not `SKILL.md`) so only this master appears in the skills list. Read the relevant
`GUIDE.md` on demand. Pairs well with `backend-api-master` (auth, integrations, Stripe) and
`charts-and-dashboards` (in `ui-master`) for reporting.
