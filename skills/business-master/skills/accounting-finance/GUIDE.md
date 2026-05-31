---
name: accounting-finance
description: >-
  Build correct accounting & finance features. Use for anything involving money,
  ledgers, invoicing, payments, taxes, financial statements, or bookkeeping.
  Covers double-entry, chart of accounts, journals, AR/AP, tax/VAT, multi-currency,
  reconciliation, and P&L / balance sheet / cash-flow reporting.
---

# Accounting & Finance

Money code must be **correct and auditable**. The foundation is **double-entry bookkeeping** —
every transaction posts balanced debits and credits to a ledger.

## Golden rules

1. **Double-entry**: for every entry, Σ debits = Σ credits. Never store a balance you can't
   re-derive from journal lines.
2. **Never use floats for money.** Use integer minor units (cents) or fixed Decimal. Always
   store **currency** with every amount.
3. **Immutable ledger**: posted entries are append-only. Corrections = reversing entries, not
   edits/deletes.
4. **Idempotency** on payments/webhooks (avoid double-charging/double-posting).

## Data model

```
Account (chart of accounts: code, name, type[asset|liability|equity|income|expense], parent)
JournalEntry (date, memo, source_doc, posted_at)
 └─ JournalLine (account_id, debit, credit, currency, fx_rate)   -- entry must balance
Invoice (customer, lines[], subtotal, tax, total, status) → posts AR + Income + Tax
Bill     (vendor, ...) → posts AP + Expense + Tax
Payment (method, amount, allocations[] → invoices/bills) → posts Cash/Bank ↔ AR/AP
TaxRate (name, percent, type[VAT|GST|sales], inclusive?)
```

### Example posting (issue a $100 + 15% VAT invoice)

```
Dr  Accounts Receivable   115.00
    Cr  Sales Income            100.00
    Cr  VAT Payable              15.00
```

When paid:
```
Dr  Bank                  115.00
    Cr  Accounts Receivable     115.00
```

## Build checklist

```
- [ ] 1. Chart of accounts (configurable) + account types
- [ ] 2. Journal engine (post balanced entries; reject unbalanced) in a DB transaction
- [ ] 3. Money type: minor units / Decimal + currency on every amount
- [ ] 4. AR (invoices) + AP (bills) that auto-post journals
- [ ] 5. Payments + allocation/matching to invoices; partial payments
- [ ] 6. Tax/VAT engine (inclusive/exclusive, multiple rates, tax report)
- [ ] 7. Multi-currency: store fx_rate; realized/unrealized gain/loss
- [ ] 8. Bank reconciliation (match statement lines to ledger)
- [ ] 9. Statements: P&L, Balance Sheet, Cash Flow, Trial Balance, Aging (AR/AP)
- [ ] 10. Period close/lock + audit trail
```

## Financial statements (derive, don't store)

- **Trial Balance**: sum debits/credits per account — must net to zero.
- **P&L**: income − expenses over a period.
- **Balance Sheet**: assets = liabilities + equity at a date.
- **Cash Flow**: operating/investing/financing.
- **Aging**: AR/AP bucketed by days overdue.

## Payments / Stripe
For card payments, pair with `stripe-stripe-best-practices` (in backend-api-master). Always make
webhook handlers idempotent and post to the ledger only on confirmed events.

## Anti-patterns
- Floats for money; missing currency; storing balances you can't recompute.
- Editing/deleting posted entries (use reversals).
- Non-atomic posting (entry half-written on crash).
- Tax logic scattered across the codebase instead of one tax engine.
- Ignoring rounding rules (define rounding per line vs total consistently).

> Disclaimer: implement per the user's local accounting standards (IFRS/GAAP) and tax law;
> recommend a professional review for regulated/audited books.
