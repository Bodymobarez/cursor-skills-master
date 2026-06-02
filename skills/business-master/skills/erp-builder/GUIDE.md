---
name: erp-builder
description: >-
  Build a modular ERP at principal depth: a shared core (master data + ledger) with loosely
  coupled modules (inventory, procurement, sales, manufacturing). Covers perpetual inventory
  valuation (FIFO/AVG/standard), every stock move posting a balanced journal, 3-way match,
  document state machines, gapless legal numbering, multi-company/currency, RLS. Postgres + TS.
---

# ERP Builder — Modular Monolith on One Ledger

**An ERP is a suite of modules sharing one set of master data and one ledger.** Get the shared core
right and modules are easy; get it wrong and you'll have three definitions of "Product," reconciliation
that never ties out, and a rewrite in year two. Design the core first. Start as a **modular monolith**
(clear module boundaries, one DB, one deploy) — you can carve out services later; you cannot un-spaghetti
a distributed mess.

---

## 1. Mandate
1. **One source of truth** for master data — modules reference Product/Partner/UoM, never copy them.
2. **Everything posts to the ledger.** Receiving stock, shipping, invoicing, payroll → balanced journal
   entries via **`accounting-finance`**. Finance is a *consequence* of operations, not a parallel system.
3. **Stock move + its journal entry are one atomic transaction.** Inventory and GL never disagree.
4. **Documents are state machines**; posted documents are immutable (reverse, don't edit).
5. **Legal sequences are gapless**, per-type, per-year, per-company.
6. **Tenant/company isolation** is structural (RLS) — see **`multi-tenant-isolation`**.

## 2. When to use / when NOT
**Use** to build inventory/procurement/sales/manufacturing/finance that must stay in lockstep.
**Strongly consider NOT building from scratch:** **Odoo**, **ERPNext/Frappe**, or NetSuite already
implement valuation, MRP, tax, and localizations that take years to get right. Build custom only for a
genuine differentiator or a niche the suites don't serve — and even then, build *on* or *around* one.
Surface this to the user before writing a greenfield ledger.

## 3. Architecture

```
CORE (shared, owns its tables, everyone reads):
  Organizations/Companies · Users & RBAC · Master Data (Product, Partner, UoM, Tax, Currency)
  General Ledger (Account, JournalEntry → JournalLine)            ← accounting-finance
MODULES (own their tables, depend on core, post to GL via a ledger service):
  Inventory/Warehouse · Procurement · Sales · Manufacturing (BOM/MRP) · HR/Payroll · CRM (→ crm-builder)
```

**Coupling rule:** modules talk to the core and to each other through **service interfaces / domain
events** (`StockReceived`, `InvoicePosted`), not by reaching into each other's tables. That boundary
discipline is what lets you later split a module into a service without a rewrite.

## 4. Master data model

```
Product   sku, name, type[stockable|consumable|service], uom_id, cost_method[FIFO|AVG|STD], track[none|lot|serial]
Partner   role[customer|supplier|both], addresses[], payment_terms, tax_id, currency
Warehouse → Location[]                       StockQuant (product, location, lot, qty_on_hand)  ← live balance
StockMove product, qty, uom, src_loc, dst_loc, state, lot, unit_cost, valuation_layer_id
PurchaseOrder → line[] → Receipt → VendorBill        (3-way match: PO ⇄ Receipt ⇄ Bill)
SalesOrder    → line[] → Delivery → Invoice          (ATP/credit-limit checks)
BOM (product, component[]) ; ManufacturingOrder → consume components, produce output
sequence(company, doc_type, year, next_value)        ← gapless legal numbering
```

## 5. Inventory valuation — decision matrix (pick ONE, apply everywhere)

| Method | How cost flows | Pros | Cons | Use when |
|--------|----------------|------|------|----------|
| **FIFO** | Oldest layer consumed first (layer ledger) | Audit-clean, matches physical flow, IFRS-friendly | Must track layers | Default; regulated/audited inventory |
| **Weighted average (AVG)** | Running `avg_cost` recomputed per receipt | Simple, smooths price swings | Less precise COGS | High-volume fungible goods |
| **Standard cost (STD)** | Fixed cost + variance accounts | Stable margins, great for mfg | Needs periodic revaluation | Manufacturing, planning-heavy |
| ~~LIFO~~ | Newest first | (tax games) | **Banned under IFRS** | Avoid unless US-GAAP + a reason |

**Perpetual, not periodic.** Maintain stock value continuously via a **valuation-layer ledger** (FIFO)
or running average — never "count once a quarter and plug the difference." Each consumption posts COGS
at the layer/average cost.

### Stock move + journal in one transaction (the core ERP invariant)

```ts
/** Receive goods: increase StockQuant AND post the inventory journal — atomically. */
export async function receiveStock(c: PoolClient, m: {
  productId: number; qty: bigint; unitCost: bigint; locationId: number; lot?: string;
  receiptId: string;                 // idempotency key
}) {
  // 1) record the move + FIFO valuation layer
  await c.query(
    `insert into stock_move (tenant_id, product_id, qty, dst_loc, unit_cost, state, source_id)
     values (current_setting('app.tenant_id')::uuid, $1,$2,$3,$4,'done',$5)
     on conflict (tenant_id, source_id) do nothing`,
    [m.productId, m.qty.toString(), m.locationId, m.unitCost.toString(), m.receiptId]);
  // 2) StockQuant live balance (upsert)
  await c.query(
    `insert into stock_quant (tenant_id, product_id, location_id, lot, qty_on_hand)
     values (current_setting('app.tenant_id')::uuid,$1,$2,$3,$4)
     on conflict (tenant_id, product_id, location_id, lot)
       do update set qty_on_hand = stock_quant.qty_on_hand + excluded.qty_on_hand`,
    [m.productId, m.locationId, m.lot ?? '', m.qty.toString()]);
  // 3) GL: Dr Inventory / Cr GR-IR (goods-received-not-invoiced). SAME transaction → never out of sync.
  const value = m.qty * m.unitCost;
  await postEntry(c, {                 // postEntry from accounting-finance
    date: today(), currency: 'USD', sourceType: 'receipt', sourceId: m.receiptId, postedBy: actor(),
    lines: [
      { accountId: ACC.INVENTORY,  debit:  value },
      { accountId: ACC.GR_IR,      credit: value },   // cleared when the vendor bill arrives (3-way match)
    ],
  });
}
```

Selling later posts `Dr COGS / Cr Inventory` at the consumed layer cost and `Dr AR / Cr Revenue / Cr VAT`
for the sale. The GR-IR account is the hinge of **3-way match**: PO sets expectation, Receipt debits
Inventory & credits GR-IR, Vendor Bill clears GR-IR & credits AP — quantities/prices must reconcile or
the bill blocks for review.

## 6. Document state machine & gapless numbering

Every business document moves through explicit states; only legal transitions are allowed, and posted
docs are immutable:

```
draft → confirmed → done → (cancelled)        # reversal/credit-note for posted docs, never edit
```

**Gapless legal sequences** — tax authorities require unbroken numbering per document type/year. Naive
`max(num)+1` races; a plain Postgres `SEQUENCE` leaves **gaps** on rollback (illegal in many jurisdictions).
Use a row you lock and increment in the posting transaction:

```sql
-- gapless: the SELECT ... FOR UPDATE serializes allocation; number is consumed only if the txn commits
create or replace function next_doc_number(p_company int, p_type text, p_year int)
returns text language plpgsql as $$
declare n bigint;
begin
  insert into doc_sequence (company_id, doc_type, year, next_value)
  values (p_company, p_type, p_year, 1)
  on conflict (company_id, doc_type, year) do nothing;

  update doc_sequence set next_value = next_value + 1
  where company_id=p_company and doc_type=p_type and year=p_year
  returning next_value - 1 into n;

  return format('%s/%s/%06s', p_type, p_year, n);   -- e.g. INV/2026/000042
end $$;
```

Allocate the number **inside** the same transaction that posts the document, so a rollback un-consumes it.
Trade-off: this serializes high-volume issuance per (type, year) — fine for invoices; if you need extreme
throughput and law permits gaps, fall back to a native sequence.

## 7. Multi-company / multi-currency & consolidation
- **Multi-company**: `company_id` on transactional rows; inter-company sales post mirrored AR/AP in each
  company; eliminate inter-company balances on consolidation. Each company has its own sequences and books.
- **Multi-currency**: transact in the partner's currency, store functional-currency amounts + FX rate,
  post realized/unrealized FX gain/loss (see **`accounting-finance`** §7). Consolidate to group currency
  at period-end rates.

## 8. Performance & scale
- **StockQuant is the hot path.** Read live balances from a maintained `stock_quant` table, not by summing
  all moves every time. Reconcile quant vs move-sum nightly.
- **Concurrent stock decrements race** (two orders, last unit). Guard with row locks / conditional update
  `set qty = qty - $1 where qty >= $1` and check `rowCount`, or serialize per product+location.
- **MRP** (demand explosion through BOMs) is batch, not request-path — run it as a job, persist suggestions.
- **Partition** big move/journal tables by period once they pass tens of millions of rows; index `(tenant_id, company_id, date)`.

## 9. Security & multi-tenant
- RLS + `FORCE` on every table; resolve tenant/company server-side (**`multi-tenant-isolation`**).
- **Approval workflows / segregation of duties**: PO above a threshold needs approval; the requester
  ≠ approver. Model `create`/`approve`/`post` as distinct permissions.
- **Immutable audit trail** on master-data and posted-document changes (who/when/before/after).

## 10. Testing & observability
- **Inventory↔GL reconciliation test**: after a sequence of receipts/sales, `Σ stock value = Inventory
  GL balance`. This is the single highest-value ERP test.
- **State-machine tests**: illegal transitions rejected; posted docs reject edits.
- **Gapless test**: concurrent issuance produces no gaps and no duplicates.
- **Observe**: alert on negative stock, quant-vs-moves divergence, GR-IR aging (received-not-billed),
  and unposted operational events.

## 11. i18n / localization
- **E-invoicing & VAT** (ZATCA clearance, UAE Peppol, EU ViDA, Arabic invoices) → **`einvoicing-compliance`**.
- Per-jurisdiction tax via the single tax engine; localized UoM, date/number formats, and RTL document layout.

## 12. Anti-patterns
- **Modules writing their own GL logic** instead of one ledger service → books drift from operations.
- **Non-atomic** stock-move-then-journal → inventory and GL disagree after a crash.
- **Editing posted/locked documents** → use reversals/credit notes.
- **Duplicating product/partner** per module → conflicting master data.
- **Periodic (not perpetual) valuation** → COGS is a quarter-end guess.
- **Native `SEQUENCE` for legal invoice numbers** → gaps on rollback (illegal in many countries).
- **Summing all moves for on-hand qty** on every read → use maintained quants.
- **Mixing companies/tenants** without strict isolation.

## 13. Agent checklist
```
- [ ] Modular monolith: shared core (master data + GL) + loosely coupled modules via services/events
- [ ] One valuation method chosen and applied everywhere; perpetual valuation layers/avg
- [ ] Every stock move posts a balanced journal in the SAME transaction (GR-IR for 3-way match)
- [ ] Documents are state machines; posted docs immutable (reverse, don't edit)
- [ ] Gapless per-type/year/company numbering allocated inside the posting txn
- [ ] Multi-company/currency with FX gain/loss via accounting-finance
- [ ] StockQuant maintained; concurrent decrement guarded; MRP runs as a job
- [ ] RLS + FORCE + approval workflow + audit trail
- [ ] Inventory↔GL reconciliation test green
```

## 14. References (2026-current)
- IAS 2 Inventories (FIFO/AVG; LIFO prohibited): https://www.ifrs.org
- Odoo dev docs (valuation, double-entry inventory): https://www.odoo.com/documentation/latest/developer.html
- ERPNext/Frappe (open ERP architecture): https://docs.frappe.io/erpnext
- Postgres sequences & locking: https://www.postgresql.org/docs/current/functions-sequence.html

## Related
`accounting-finance`, `multi-tenant-isolation`, `einvoicing-compliance`, `crm-builder`,
`marketplace-master` (vendors/orders), `charts-and-dashboards` (ui-master)
