# TIPS — index

## Quick reference

| Item | Value |
|------|--------|
| Base | `https://api.fiscaldata.treasury.gov/services/api/fiscal_service` |
| Summary path | `/v1/accounting/od/tips_cpi_data_summary` |
| Detail path | `/v1/accounting/od/tips_cpi_data_detail` |
| Auth | None |
| Official docs | https://fiscaldata.treasury.gov/api-documentation/ |
| Dataset | https://fiscaldata.treasury.gov/datasets/tips-cpi-data/ |

**Coupon (after one summary row + one detail row):**  
`r = Double(interest_rate) / 100` (API stores **percent**).  
`index_ratio` → normalize: truncate to **6** decimals, round to **5** (31 CFR §356 App. B).  
`adjusted_principal = par × index_ratio`  
`semi_annual_interest = round_to_cents(adjusted_principal × (r / 2))`

**Default detail fetch for ratio as of date D:**  
`filter=cusip:eq:<CUSIP>,index_date:lte:<D>&sort=-index_date&page[size]=1` → use `index_ratio` from first row.

## Topics

- [Endpoints & headers](api.md) — full paths, GET, `Accept`
- [Parameters](parameters.md) — `filter`, `sort`, `page[size|number]`, `fields`, `format`
- [Response fields](response-fields.md) — `data` / `meta`; summary vs detail columns
- [Operations](practices.md) — 429, pagination, parsing strings
- [Query examples](examples.md) — filters, ladder window, on-or-before ratio, batches
- [Calculations](calculations.md) — schedule, index modes, maturity, pitfalls
- [Rounding](rounding.md) — Ref CPI / index ratio (6→5 decimals), coupon cash to cents, STRIPS (31 CFR 356 App. B)
- [Portfolios & batch](portfolios-and-batch.md) — CUSIP sets, caching, repo modules

## Repo helpers (TIPSy3)

- `swift run TIPSyCLI verify-params` — filter/sort smoke tests  
- `swift run TIPSyCLI verify-coupon …` — add `--current-cpi` for as-of-today index  
- `swift run TIPSyCLI payout <date> <holdings.csv>` — aggregated payout by payment date  
