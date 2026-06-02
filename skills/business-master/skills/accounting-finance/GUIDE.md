---
name: accounting-finance
description: >-
  Correct, auditable double-entry accounting at principal depth: the ledger as the single
  source of truth, integer-minor-unit money, idempotent journal posting in one transaction,
  AR/AP, multi-currency (IAS 21), period close/lock, reversals & credit notes, and statements
  derived (never stored). Postgres + TypeScript, copy-paste. Use for anything that touches money.
---

# Accounting & Finance — Production Ledger

**The ledger is the source of truth; balances are an output.** Every balance, statement, and KPI
must be re-derivable by replaying journal lines. If you store a balance you can't recompute from
the journal, you have a bug, not a balance. Money code is judged in an audit, not a demo — build
it correct, immutable, and idempotent from line one.

---

## 1. Mandate & non-negotiable invariants

These are not style preferences. Violating any one of them is a defect:

1. **Double-entry**: for every entry, `Σ debits = Σ credits`. Enforced in the **database**, not hope.
2. **Integer minor units** for money (`bigint` cents/fils), never floats. Currency travels with every amount.
3. **Append-only ledger**: posted entries are immutable. Corrections = **reversing entries / credit notes**, never `UPDATE`/`DELETE`.
4. **Idempotent posting**: a source document (invoice, payment, webhook) posts **exactly one** entry, ever.
5. **Atomicity**: an entry and all its lines commit in one DB transaction or not at all.
6. **Closed periods are sealed**: no posting into a locked period; adjust via the next open period.

## 2. When to use / when NOT

**Use** when building invoicing, billing, payments, payroll, subledgers, revenue recognition,
statements, or any feature where money moves between accounts.
**Do NOT** roll your own ledger if regulated/audited books can be served by QuickBooks/Xero/NetSuite
+ their API — integrate instead. **Do NOT** treat Stripe's balance as your ledger; Stripe is a
*payment processor*, your ledger is the book of record. And do not let an LLM (or this guide)
replace a CPA: implement to the user's standard (**IFRS/GAAP**) and get regulated books reviewed.

## 3. Data model (the spine)

```
account        chart of accounts: code, name, type, normal_balance, parent_id, is_postable
journal_entry  date, currency, memo, source_type, source_id (idempotency), reverses_id, period_id
 └─ journal_line  account_id, debit, credit (minor units), + fx fields   ← Σdebit = Σcredit
invoice / bill   header + lines → post AR/AP, Income/Expense, Tax (one entry each)
payment          method, amount, allocations[] → post Cash/Bank ↔ AR/AP (+ FX gain/loss)
tax_rate         code, percent, kind[VAT|GST|sales], inclusive?, jurisdiction
period           tenant, year, month, status[open|closed]   ← posting gate
```

**Account types & normal balance** drive every report — bake the sign in once:

| Type | Normal balance | ↑ by | Appears on |
|------|----------------|------|------------|
| Asset | Debit | Debit | Balance Sheet |
| Expense | Debit | Debit | P&L |
| Liability | Credit | Credit | Balance Sheet |
| Equity | Credit | Credit | Balance Sheet |
| Income | Credit | Credit | P&L |

> The accounting equation `Assets = Liabilities + Equity` holds *by construction* when debits=credits
> on every entry. That's the whole point of double-entry — correctness is structural, not asserted.

### Canonical postings

```
Issue invoice  $100 + 5% VAT          Customer pays
  Dr Accounts Receivable   105.00       Dr Bank                 105.00
     Cr Sales Income            100.00      Cr Accounts Receivable    105.00
     Cr VAT Payable               5.00
Refund / credit note (NOT an edit)    Vendor bill (AP mirror of invoice)
  Dr Sales Income          100.00       Dr Expense               100.00
  Dr VAT Payable             5.00       Dr VAT Recoverable         5.00
     Cr Accounts Receivable    105.00      Cr Accounts Payable      105.00
```

## 4. Schema with the invariant enforced in Postgres

```sql
create table account (
  id            bigint generated always as identity primary key,
  tenant_id     uuid not null,
  code          text not null,
  name          text not null,
  type          text not null check (type in ('asset','liability','equity','income','expense')),
  normal_balance text generated always as
                 (case when type in ('asset','expense') then 'debit' else 'credit' end) stored,
  is_postable   boolean not null default true,           -- parent/rollup accounts are not postable
  unique (tenant_id, code)
);

create table journal_entry (
  id          bigint generated always as identity primary key,
  tenant_id   uuid not null,
  entry_date  date not null,
  currency    char(3) not null,                          -- ISO 4217
  memo        text,
  source_type text not null,                             -- 'invoice'|'payment'|'manual'|...
  source_id   text not null,
  reverses_id bigint references journal_entry(id),
  posted_at   timestamptz not null default now(),
  posted_by   uuid not null,
  unique (tenant_id, source_type, source_id)             -- IDEMPOTENCY: one entry per source doc
);

create table journal_line (
  id         bigint generated always as identity primary key,
  tenant_id  uuid not null,
  entry_id   bigint not null references journal_entry(id),
  account_id bigint not null references account(id),
  debit      bigint not null default 0 check (debit  >= 0),   -- minor units, never negative
  credit     bigint not null default 0 check (credit >= 0),
  constraint debit_xor_credit check ((debit = 0) <> (credit = 0))  -- exactly one side; no zero lines
);
create index on journal_line (tenant_id, account_id, entry_id);    -- account ledger / balance scans

-- Balanced check at COMMIT, so multi-line inserts in one txn are validated once, fully built.
create or replace function assert_entry_balanced() returns trigger language plpgsql as $$
declare d bigint; c bigint; eid bigint := coalesce(new.entry_id, old.entry_id);
begin
  select coalesce(sum(debit),0), coalesce(sum(credit),0) into d, c
  from journal_line where entry_id = eid;
  if d <> c then
    raise exception 'unbalanced entry %: debit % <> credit %', eid, d, c using errcode='check_violation';
  end if;
  return null;
end $$;

create constraint trigger journal_line_balanced
  after insert or update or delete on journal_line
  deferrable initially deferred                          -- ← the magic: fires at COMMIT, not per-row
  for each row execute function assert_entry_balanced();
```

`DEFERRABLE INITIALLY DEFERRED` is the staff-level move: you insert N lines in any order and the
balance check runs **once, at commit**, when the entry is complete. A per-row `BEFORE` trigger
would reject the first line every time.

## 5. Idempotent posting (TypeScript, one transaction)

```ts
type Line = { accountId: number; debit?: bigint; credit?: bigint };

/** Posts a balanced entry exactly once. Safe to retry: a duplicate source doc no-ops. */
export async function postEntry(
  c: PoolClient,                                  // already inside withTenant() — RLS scopes tenant
  e: { date: string; currency: string; memo?: string; sourceType: string; sourceId: string;
       postedBy: string; lines: Line[] },
): Promise<number> {
  const debit  = e.lines.reduce((s, l) => s + (l.debit  ?? 0n), 0n);
  const credit = e.lines.reduce((s, l) => s + (l.credit ?? 0n), 0n);
  if (debit !== credit) throw new Error(`unbalanced: ${debit} != ${credit}`);
  if (debit === 0n)     throw new Error("empty entry");

  // assertPeriodOpen(c, e.date)  ← reject posting into a closed period (see §7)
  const ins = await c.query(
    `insert into journal_entry (tenant_id, entry_date, currency, memo, source_type, source_id, posted_by)
     values (current_setting('app.tenant_id')::uuid, $1,$2,$3,$4,$5,$6)
     on conflict (tenant_id, source_type, source_id) do nothing
     returning id`,
    [e.date, e.currency, e.memo ?? null, e.sourceType, e.sourceId, e.postedBy],
  );
  if (ins.rowCount === 0) {                       // already posted → return the existing id, no double-post
    const r = await c.query(
      `select id from journal_entry
       where tenant_id = current_setting('app.tenant_id')::uuid and source_type=$1 and source_id=$2`,
      [e.sourceType, e.sourceId]);
    return r.rows[0].id;
  }
  const entryId = ins.rows[0].id;
  for (const l of e.lines)
    await c.query(
      `insert into journal_line (tenant_id, entry_id, account_id, debit, credit)
       values (current_setting('app.tenant_id')::uuid, $1,$2,$3,$4)`,
      [entryId, l.accountId, (l.debit ?? 0n).toString(), (l.credit ?? 0n).toString()]);
  return entryId;                                 // COMMIT happens in withTenant(); balance trigger fires here
}
```

**Money type rule:** keep amounts as `bigint` minor units end-to-end. Use a `Money { amount: bigint, currency }`
value object; format only at the display edge (`Intl.NumberFormat`). Never `number`, never `JSON.parse`
a float. In Postgres, `bigint` for amounts; `numeric(18,8)` only for **rates** (FX, tax %, qty).

## 6. Statements — derive, never store

```sql
-- Trial balance (must net to zero across all accounts → proof the books balance)
select a.code, a.name, a.type,
       sum(jl.debit)  as debit,
       sum(jl.credit) as credit,
       sum(jl.debit) - sum(jl.credit) as net_debit
from journal_line jl join account a on a.id = jl.account_id
group by a.id order by a.code;
```

- **P&L** = income − expenses over a period (filter `entry_date` ∈ range, types income/expense).
- **Balance Sheet** = balances of asset/liability/equity **as of** a date; assets = liabilities + equity.
- **Cash Flow** = movement of cash/bank accounts, classified operating/investing/financing.
- **AR/AP Aging** = unsettled invoice/bill balances bucketed by days overdue (0–30/31–60/…).

Performance: for high-volume ledgers, keep a **`account_balance` rollup** (per account, per period)
updated in the same transaction as the post, and reconcile it nightly against a full replay. The
journal stays the source of truth; the rollup is a cache you can rebuild. Partition `journal_line`
by period/year once it passes tens of millions of rows.

## 7. Edge cases that separate correct from "looks correct"

**Multi-currency (IAS 21).** Store the **transaction-currency** amount, the **functional-currency**
amount, and the rate used. Monetary items (AR/AP/Bank) are retranslated at the closing rate; the
delta is FX gain/loss:

```
Settle a 1,000 USD receivable booked @3.6725 AED, paid when rate is 3.6700 (functional = AED):
  Dr Bank (AED)                3,670.00
  Dr FX Loss                       2.50
     Cr Accounts Receivable (AED)   3,672.50
```
Add `amount_txn bigint`, `amount_func bigint`, `fx_rate numeric(18,8)` to `journal_line`; post the
**realized** gain/loss on settlement and an **unrealized** revaluation entry at period close (reversed next period).

**Period close.** A `period(status)` gate; `assertPeriodOpen()` rejects posts into `closed`. Closing
moves net income to **Retained Earnings** and locks the month. Year-end zeros income/expense into equity.

**Refunds / corrections.** Issue a **credit note** (a new, linked entry) or a **reversal**
(`reverses_id` → swap debits/credits of the original). Never edit a posted entry — auditors verify the
chain. Clawbacks (e.g. affiliate, chargebacks) are reversing entries too.

**Rounding.** Pick one rule and apply everywhere: compute tax **per line**, round per line (banker's
or half-up — match local law), then sum; or compute on the total. Mismatched rules cause 1-cent
drift that fails reconciliation. For splitting an amount N ways, use **largest-remainder** so the
parts sum exactly to the whole.

## 8. Security, multi-tenant & audit

- **Tenant isolation** on every money table via Postgres RLS (`tenant_id` + `FORCE ROW LEVEL SECURITY`).
  This is the #1 way money leaks across customers — make it structural. Full pattern: **`multi-tenant-isolation`**.
- **RBAC/segregation of duties**: the person who *creates* a payment shouldn't be the one who *approves*
  it. Model `create`/`approve`/`post`/`void` as distinct permissions; enforce at the query/service layer.
- **Immutable audit log**: who posted/approved/voided what, when, with before/after. The ledger's
  append-only design already gives you a financial audit trail — keep it that way (no `UPDATE`).
- **PII**: bank/IBAN/tax IDs are sensitive — encrypt at rest, restrict columns, log access.

## 9. Testing & observability

- **Property test the invariant**: generate random balanced entries → assert trial balance nets to 0;
  generate unbalanced → assert the DB **rejects** it. This is your highest-value test.
- **Golden-ledger fixtures**: a known sequence of invoices/payments/refunds → assert exact statement
  outputs. Re-run on every change.
- **Idempotency test**: post the same `source_id` twice → exactly one entry.
- **Observe**: alert if `Σdebit ≠ Σcredit` anywhere (should be impossible → means corruption), if the
  rollup cache diverges from replay, or if unmatched payments age. Track posting latency and failed-post rate.

## 10. i18n / localization (VAT & Arabic invoices)

VAT is a **tax engine**, not scattered `* 1.05`. One module owns rate lookup (by jurisdiction/date),
inclusive vs exclusive, reverse charge, and zero-rated/exempt. GCC standard rates (2026): **KSA 15%,
UAE 5%, Bahrain 10%, Oman 5%; Qatar & Kuwait: no VAT yet.** Tax-compliant invoices, QR codes, hash
chains, Arabic RTL layout, and the GCC/EU e-invoicing mandates live in **`einvoicing-compliance`** —
route there for ZATCA / UAE Peppol / EU ViDA. Format money with `Intl.NumberFormat(locale, {style:'currency'})`;
right-align numerals and mirror invoice layout for `dir="rtl"`.

## 11. Anti-patterns
- **Floats for money** (`0.1 + 0.2`), or amounts without currency. Non-negotiable defect.
- **Storing a balance you can't re-derive** from journal lines.
- **Editing/deleting posted entries** instead of reversing — destroys auditability.
- **Non-atomic posting** (entry without its lines on crash) — wrap in one transaction.
- **No idempotency key** on payment/webhook posting → double-charge, double-post.
- **Tax math sprinkled across the codebase** instead of one engine.
- **Treating the payment processor's dashboard as the ledger.** Stripe ≠ book of record.
- **Posting into closed periods** to "fix" last month.

## 12. Agent checklist
```
- [ ] Money = bigint minor units + currency everywhere; no floats reach money paths
- [ ] journal_line has debit_xor_credit CHECK + DEFERRABLE balanced constraint trigger
- [ ] Every source doc posts via on-conflict-do-nothing idempotency key
- [ ] Posting is one DB transaction; period-open gate enforced
- [ ] Reversals/credit notes for corrections — zero UPDATE/DELETE on posted rows
- [ ] Statements derived from journal (trial balance nets to 0 in a test)
- [ ] RLS + FORCE on all money tables (see multi-tenant-isolation)
- [ ] FX: amount_txn + amount_func + rate; realized + unrealized handled
- [ ] Tax via single engine; e-invoicing via einvoicing-compliance
- [ ] Property test: balanced posts succeed, unbalanced rejected by DB
```

## 13. References (2026-current)
- IFRS / IAS 21 (foreign exchange): https://www.ifrs.org
- Martin Fowler — Money & Accounting patterns: https://martinfowler.com/eaaCatalog/money.html
- Postgres deferred constraint triggers: https://www.postgresql.org/docs/current/sql-createtrigger.html
- Modern ledger design (double-entry at scale): https://www.tigerbeetle.com/ · https://docs.formance.com

## Related
`einvoicing-compliance`, `multi-tenant-isolation`, `erp-builder`, `affiliate-system`,
`stripe-stripe-best-practices` (backend-api-master), `charts-and-dashboards` (ui-master)
