---
name: accounting-system-complete
description: >-
  Build a COMPLETE accounting application A→Z with full menus/modules: Chart of Accounts, fiscal
  periods, GL/journals, AR (customers/invoices/receipts/aging), AP (vendors/bills/payments), banking +
  reconciliation, tax/VAT, fixed assets & depreciation, inventory/COGS link, multi-currency, budgeting,
  period/year-end close, and financial statements (TB/P&L/Balance Sheet/Cash Flow) + reports/roles/audit.
  Use to design the full system & navigation. The ledger engine lives in accounting-finance.
---

# Complete Accounting System (A→Z, full menus)

**Mandate:** ship a real, auditable accounting **application** — every module, screen, and report a
bookkeeper/accountant expects — sitting on the double-entry ledger from **`accounting-finance`**. This
skill is the **system & navigation**; that skill is the **posting engine**. Money is always integer
minor units; every business document posts a **balanced** journal entry or it doesn't happen.

> Implement to the user's standard (IFRS/GAAP + local tax law) and recommend a professional review for
> regulated/audited books. This is engineering guidance, not accounting/legal advice.

## When to use / when NOT

| Use | Don't |
|-----|-------|
| Build a full accounting/bookkeeping product or ERP finance module | Just need the ledger math → `accounting-finance` |
| Need the complete menu/IA + module list + posting flows | Only invoicing/VAT → `einvoicing-compliance` |
| AR/AP, banking, assets, close, statements | Pure payments capture → `payments-master` |

## Module map (the full menu tree)

```
Dashboard            KPIs: cash, AR/AP aging, P&L MTD/YTD, runway
General Ledger
  ├ Chart of Accounts (COA)      assets/liab/equity/income/expense, hierarchical codes
  ├ Journals / Manual entries    balanced, periods, reversals, recurring, templates
  └ Trial Balance
Sales / Receivables (AR)
  ├ Customers (+ statements, credit limit)
  ├ Quotes → Sales Orders → Invoices (+ e-invoice → einvoicing-compliance)
  ├ Receipts / Payments received  (allocation/matching)
  ├ Credit notes / refunds
  └ AR Aging (0–30/31–60/61–90/90+)
Purchases / Payables (AP)
  ├ Vendors
  ├ Purchase Orders → Bills (+ 3-way match → erp-builder)
  ├ Payments made / batch payments
  ├ Debit notes
  └ AP Aging
Banking & Cash
  ├ Bank/cash accounts, transfers
  ├ Bank feeds / statement import (CSV/OFX/MT940)
  └ Bank reconciliation
Tax
  ├ Tax codes/rates, VAT engine (→ einvoicing-compliance)
  └ VAT return / filing report
Fixed Assets
  ├ Asset register, categories
  └ Depreciation runs (SL/DB/units), disposals
Inventory / COGS (link erp-builder)   valuation → COGS postings
Budgeting & Forecast                  budget vs actual by account/period/dimension
Period Close
  ├ Lock periods, accruals/prepayments, FX revaluation
  └ Year-end close → retained earnings rollover
Reports
  ├ Trial Balance, General Ledger detail
  ├ Profit & Loss (Income Statement)
  ├ Balance Sheet
  ├ Cash Flow (indirect/direct)
  ├ AR/AP aging, Tax, Customer/Vendor statements
  └ Dimensional (cost center / project / branch)
Settings
  └ Fiscal years/periods, currencies, numbering, roles/permissions, audit log
```

## Architecture decisions

| Decision | Options | Recommend |
|----------|---------|-----------|
| Source of truth | documents-as-truth vs **ledger-as-truth** | **Ledger** — every doc posts a journal; statements are derived |
| Statements | stored vs **derived from GL** | Derived (never store a balance you can recompute) |
| Dimensions | extra accounts vs **tags (cost center/project/branch)** | Tags on journal lines + GIN index |
| Periods | soft vs **hard lock** | Hard lock; post-close only via adjusting period |
| Numbering | native sequence vs **gapless** | Gapless per `accounting-finance`/`erp-builder` (legal) |
| Multi-entity | one ledger + entity dim vs **ledger-per-entity** | Per-entity ledgers + consolidation view |

## Core data model (system layer; ledger detail in accounting-finance)

```sql
-- Chart of accounts (hierarchical, typed)
CREATE TABLE accounts (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_id     uuid NOT NULL,
  code          text NOT NULL,                 -- '1100'
  name          text NOT NULL,
  type          text NOT NULL CHECK (type IN ('asset','liability','equity','income','expense')),
  parent_id     bigint REFERENCES accounts(id),
  is_postable   boolean NOT NULL DEFAULT true,  -- headers are not postable
  currency      char(3),                        -- null = entity currency
  UNIQUE (tenant_id, code)
);

CREATE TABLE fiscal_periods (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_id  uuid NOT NULL,
  starts_on  date NOT NULL, ends_on date NOT NULL,
  status     text NOT NULL CHECK (status IN ('open','closed','adjusting')) DEFAULT 'open',
  EXCLUDE USING gist (tenant_id WITH =, daterange(starts_on, ends_on, '[]') WITH &&) -- no overlap
);

-- A business document references the journal entry it produced (audit trail both ways)
CREATE TABLE ar_invoices (
  id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_id    uuid NOT NULL,
  customer_id  bigint NOT NULL,
  number       text NOT NULL,                 -- gapless
  issue_date   date NOT NULL,
  currency     char(3) NOT NULL,
  total_minor  bigint NOT NULL CHECK (total_minor >= 0),
  status       text NOT NULL CHECK (status IN ('draft','posted','paid','void')) DEFAULT 'draft',
  journal_id   bigint REFERENCES journal_entries(id),  -- set when posted
  UNIQUE (tenant_id, number)
);
```

All tables carry `tenant_id` under RLS — see **`multi-tenant-isolation`**.

## Posting flows (document → balanced journal)

```ts
// Posting an AR invoice (subtotal + VAT). Money in minor units. Idempotent + balanced.
// Dr Accounts Receivable; Cr Revenue; Cr VAT Output Payable
async function postInvoice(tx: Tx, inv: Invoice) {
  const lines = [
    { accountCode: "1100", debit: inv.total },                 // AR (incl. tax)
    { accountCode: "4000", credit: inv.subtotal },             // Revenue
    { accountCode: "2200", credit: inv.taxAmount },            // VAT output
  ];
  // postEntry enforces sum(debit) === sum(credit) and period is open (accounting-finance)
  const journalId = await postEntry(tx, {
    tenantId: inv.tenantId, date: inv.issueDate, memo: `INV ${inv.number}`,
    idempotencyKey: `invoice:${inv.id}:post`, lines,
  });
  await tx.updateInvoice(inv.id, { status: "posted", journalId });
}
```

| Document | Debit | Credit |
|----------|-------|--------|
| AR invoice | AR | Revenue + VAT output |
| Customer receipt | Bank | AR (allocate to invoices) |
| AP bill | Expense/Inventory + VAT input | AP |
| Vendor payment | AP | Bank |
| Depreciation run | Depreciation expense | Accumulated depreciation |
| FX revaluation | FX gain/loss | Monetary account |

## Financial statements (derived, never stored)

```sql
-- Trial Balance for a period: balances from posted journal lines only
SELECT a.code, a.name, a.type,
       SUM(jl.debit_minor)  AS debit,
       SUM(jl.credit_minor) AS credit
FROM journal_lines jl
JOIN journal_entries je ON je.id = jl.entry_id AND je.status = 'posted'
JOIN accounts a ON a.id = jl.account_id
WHERE je.tenant_id = $1 AND je.entry_date <= $2
GROUP BY a.id ORDER BY a.code;
```

- **P&L** = income − expense over a date range; **Balance Sheet** = asset/liability/equity as-of a date
  (income/expense rolled into retained earnings for prior closed years).
- **Cash Flow** (indirect): net income ± non-cash (depreciation) ± working-capital deltas.

## Edge cases & gotchas
- **Backdating** into a closed period → block; force an adjusting-period entry.
- **Multi-currency**: store txn currency + rate; revalue monetary balances at close (IAS 21) → FX gain/loss.
- **Partial receipts/payments**: allocation table; an invoice is `paid` only when allocated ≥ total.
- **Voiding a posted document** → post a **reversing** entry, never delete (immutable audit).
- **Rounding**: VAT rounding rules vary by jurisdiction; round tax per line/per invoice per local law.

## Security / scale / testing / observability
- **Security**: RLS per tenant; period lock + role checks server-side; immutable, append-only audit log of every post/void.
- **Scale**: partition `journal_lines` by period; materialized monthly balances for fast statements (refresh on close); index `(tenant_id, account_id, entry_date)`.
- **Testing**: invariant tests — every entry balances; TB debits == credits; Balance Sheet balances (A = L + E); reversal nets to zero; reconciliation matches bank to GL.
- **Observability**: unbalanced-entry alarm (should be impossible), unreconciled-bank aging, close-checklist completion, period-lock breaches.

## Anti-patterns
- Storing computed balances as the truth (drift) — derive from the GL.
- Editing/deleting posted entries — reverse instead.
- Floats for money; missing currency; tax computed on the client.
- One giant "transactions" table with no double-entry — you cannot produce a Balance Sheet from it.
- Letting the UI enforce period locks/permissions instead of the DB/server.

## Agent checklist
```
- [ ] COA + typed accounts + fiscal periods (no overlap, hard lock)
- [ ] Every document posts a balanced, idempotent journal via accounting-finance
- [ ] AR/AP with allocation + aging; banking + reconciliation
- [ ] Tax via einvoicing-compliance; fixed assets depreciation; multi-currency + revaluation
- [ ] Period & year-end close → retained earnings rollover
- [ ] Statements (TB/P&L/BS/Cash Flow) derived from posted GL only
- [ ] RLS + roles + append-only audit; invariant tests in CI
```

## References
- IFRS: https://www.ifrs.org · IAS 21 (FX) · IAS 16 (assets) · local GAAP/tax authority docs.
- VAT/e-invoicing specifics → `einvoicing-compliance`.

## Related
`accounting-finance` (ledger engine — read first), `erp-builder` (inventory/COGS, 3-way match),
`einvoicing-compliance` (VAT/ZATCA/Peppol), `multi-tenant-isolation`, `payments-master` (receipts/payouts),
`ui-master` → `charts-and-dashboards` (reports UI).
