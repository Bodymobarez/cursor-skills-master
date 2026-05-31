# Sample patterns (language-agnostic)

## Simple summary and detail

- **All summary:** GET summary endpoint, no filters. Parse `data` array.
- **Detail for one CUSIP:** GET detail with `filter=cusip:eq:912810RA8`.

## Filter by CUSIP and date range

- Single CUSIP: `filter=cusip:eq:912810RA8`
- Maturity in range (e.g. 2028–2032): `filter=maturity_date:gte:2028-01-01,maturity_date:lte:2032-12-31`
- Auction on or after date: `filter=original_auction_date:gte:2020-01-01`

## Sort and page size

- Maturity descending, 10 per page: `sort=-maturity_date` and `page[size]=10`
- Multiple sort: `sort=-maturity_date,cusip`

## Filter by term (5, 10, or 30 years)

- 10- and 30-year only: `filter=security_term:in:(10-Year,30-Year)`

## Fetch all pages (until short page)

1. Set `page[size]` (e.g. 100), `page[number]=1`.
2. Request; append `data` to results.
3. If number of items in `data` < `page[size]`, stop. Else increment `page[number]`, goto 2.

## Summary + detail for one CUSIP (ladder)

1. GET summary with `filter=cusip:eq:<cusip>`. Take first (or only) row for security terms/dates.
2. GET detail with `filter=cusip:eq:<cusip>`, optional `sort=index_date`. Use rows for index ratios by date.

## Throttled client with retry on 429

- Before each request: wait until at least min_interval since last request.
- On 429 (or 5xx): sleep(backoff), retry up to K times. Backoff e.g. exponential: 1s, 2s, 4s.

## Index ratio on a specific date

GET detail with `filter=cusip:eq:<cusip>,index_date:eq:2025-06-15`. Use first result’s `index_ratio` (and optionally `ref_cpi`).

## Ladder maturities in a window, sorted by maturity

Summary with `filter=maturity_date:gte:<start>,maturity_date:lte:<end>`, `sort=maturity_date`, `page[size]=500`. Parse `data` for ladder.

## Index ratio “on or before” a date (coupon math)

For a given CUSIP and valuation/payment date `D`, use the latest published ratio that is still on or before `D`:

- `filter=cusip:eq:<CUSIP>,index_date:lte:<D>`
- `sort=-index_date`
- `page[size]=1`

Use the row’s `index_ratio` and `index_date`. This matches **accrual as of** `D` when the dataset has no row exactly on `D`.

## “As of today” / dataset cutoff (projections)

- **Today:** same as above with `D = today` (YYYY-MM-DD).
- **Future payment after last CPI in API:** use **on-or-before** with `D` = latest `index_date` for that CUSIP (`filter=cusip:eq:…`, `sort=-index_date`, `page[size]=1`).

## Many CUSIPs (holdings set)

1. **Deduplicate** holdings → list of CUSIPs + shares (or aggregate shares per CUSIP).
2. **Summary:** parallel `cusip:eq` per CUSIP (throttled), *or* one maturity-window paginated summary if building the universe from scratch.
3. **Detail:** one constrained **detail** call per CUSIP per calculation (not full history unless needed).

## Semi-annual coupon (after summary + detail)

With `r = Double(interest_rate) / 100` from summary and `index_ratio` from detail:

```
adjusted_principal = principal_dollars * index_ratio
coupon = adjusted_principal * (r / 2)
```

At **maturity payment**, cash includes final coupon **plus** adjusted principal (Treasury deflation floor: `max(adjusted, par)` at maturity).
