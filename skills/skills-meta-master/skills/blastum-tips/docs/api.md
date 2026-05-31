# Endpoints and base URL

**Base:** `https://api.fiscaldata.treasury.gov/services/api/fiscal_service`

| Endpoint | Path | Use for |
|----------|------|---------|
| Summary | `/v1/accounting/od/tips_cpi_data_summary` | One row per TIPS security: CUSIP, terms, dates, reference CPI on dated date. Ladders, listing securities. |
| Detail | `/v1/accounting/od/tips_cpi_data_detail` | One row per CUSIP per date: reference CPI and daily index ratio. Index ratios on specific dates. |

**Full URLs:**
- Summary: `https://api.fiscaldata.treasury.gov/services/api/fiscal_service/v1/accounting/od/tips_cpi_data_summary`
- Detail: `https://api.fiscaldata.treasury.gov/services/api/fiscal_service/v1/accounting/od/tips_cpi_data_detail`

**Authentication:** None. No API key or registration.

**Method:** GET only.

**Headers:** Send `Accept: application/json`. Optional: `User-Agent`, `Cache-Control: no-cache`.
