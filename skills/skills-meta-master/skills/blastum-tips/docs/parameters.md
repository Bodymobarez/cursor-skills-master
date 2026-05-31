# Request parameters

## Filter (`filter=`)

Format: `field:operator:value`. Multiple filters: comma-separated in one param: `filter=field1:op:value1,field2:op:value2`.

| Operator | Meaning | Example |
|----------|---------|---------|
| `lt` | Less than | `maturity_date:lt:2030-01-01` |
| `lte` | Less than or equal | `original_auction_date:lte:2020-12-31` |
| `gt` | Greater than | `interest_rate:gt:0.5` |
| `gte` | Greater than or equal | `maturity_date:gte:2025-06-15` |
| `eq` | Equal | `cusip:eq:912810RA8` |
| `in` | In list | `security_term:in:(5-Year,10-Year,30-Year)` |

**Dates:** YYYY-MM-DD (ISO 8601). **`in` values:** Comma-separated inside parentheses; use API label values, e.g. `security_term:in:(5-Year,10-Year)`. For `security_term`, numeric values like `(5,10,30)` may return no rows—prefer **year labels** (`verify-params` in this repo tests this).

**Many CUSIPs:** One `cusip:eq` per security (throttled concurrency), or paginate **summary** on `maturity_date` windows to build a universe before selective **detail** calls.

## Sort (`sort=`)

Ascending: field name. Descending: prefix `-`. Multiple: comma-separated, e.g. `sort=-maturity_date,cusip`.

## Pagination

| Parameter | Default | Meaning |
|-----------|---------|---------|
| `page[size]` | 100 | Rows per page (integer). |
| `page[number]` | 1 | Page index (1-based). |

## Fields (`fields=`)

Optional. Comma-separated field names. Omit = all fields. Invalid names can cause errors.

## Format (`format=`)

`json` (default), `csv`, or `xml`. Use `Accept: application/json` for JSON.
