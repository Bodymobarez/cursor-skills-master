---
name: erp-builder
description: >-
  Build a professional ERP (enterprise resource planning) system. Use when the
  user wants ERP modules — inventory, procurement, sales orders, manufacturing,
  HR, or finance integration. Covers modular architecture, double-entry-aware
  data model, inventory/stock, orders, multi-warehouse, multi-currency, and RBAC.
---

# ERP Builder

Build a modular ERP. ERPs are **module suites sharing one ledger and master data** — design the
shared core first, then add modules.

## Architecture: modular monolith (recommended start)

```
Core: Organizations, Users/RBAC, Master Data (Products, Partners, UoM, Tax, Currency)
Modules (each owns its tables, shares core + posts to Ledger):
  • Inventory/Warehouse   • Purchasing/Procurement   • Sales/Orders
  • Manufacturing (BOM/MRP)  • Accounting/Finance (ledger)  • HR/Payroll
  • CRM (link to crm-builder)
```

Keep modules loosely coupled (service boundaries) so you can split to services later.

## Master data model

```
Product (sku, name, type[stockable|service], uom_id, cost_method[FIFO|AVG], tracking[lot|serial])
Partner (customer/supplier, addresses, payment_terms, tax_id)
Warehouse → Location[] ; StockMove (product, qty, from_loc, to_loc, state, lot)
PurchaseOrder → lines → Receipt → Bill
SalesOrder → lines → Delivery → Invoice
BOM (product, components[]) ; ManufacturingOrder
GL: Account, JournalEntry → JournalLine (debit/credit, must balance)  ← see accounting-finance
```

## Build checklist

```
- [ ] 1. Core: tenant, RBAC, master data (products, partners, UoM, tax, currency)
- [ ] 2. Inventory: multi-warehouse, stock moves, valuation (FIFO/AVG), lot/serial
- [ ] 3. Procurement: PO → receive → vendor bill (3-way match: PO/receipt/bill)
- [ ] 4. Sales: SO → deliver → invoice; credit limit checks
- [ ] 5. Accounting hook: every stock/invoice event posts a balanced journal entry
- [ ] 6. Manufacturing (if needed): BOM, MO, component consumption, MRP suggestions
- [ ] 7. Multi-currency + multi-company; document numbering sequences per type
- [ ] 8. Approvals workflow (PO/expense thresholds) + audit trail
- [ ] 9. Reporting/dashboards (stock valuation, P&L, order status) via charts-and-dashboards
```

## Principles

- **Single source of truth**: master data shared; modules never duplicate product/partner.
- **Everything posts to the ledger**: receiving stock, invoicing, payroll → journal entries
  (keeps finance accurate automatically). Use `accounting-finance` for ledger rules.
- **Stock valuation** must be consistent (pick FIFO or weighted-average and apply everywhere).
- **Document flow with states** (draft → confirmed → done → cancelled) + immutable posted docs.
- **Sequences**: gapless, per-type, per-year numbering for legal docs.

## Recommended stack
- Postgres (transactions are critical), Django/DRF or NestJS or Laravel; React/Next UI.
- Consider building on **ERPNext/Frappe** or **Odoo** if the user wants a head start (mention it).

## Anti-patterns
- Letting modules write their own GL logic instead of one ledger service.
- No transactions around multi-table posting (stock move + journal must be atomic).
- Editing posted/locked documents (use reversals/credit notes instead).
- Mixing tenants/companies without strict isolation.
