# Response structure and fields

## Wrapper (JSON)

```json
{
  "data": [ { ... }, ... ],
  "meta": {
    "count": 50,
    "total-count": 1234,
    "total-pages": 25,
    "labels": { "cusip": "CUSIP", ... },
    "dataTypes": { ... },
    "dataFormats": { ... }
  },
  "links": { "self": "...", "first": "...", "prev": null, "next": "...", "last": "..." }
}
```

**Important:** All API field values are strings (including numbers and dates). Nulls may appear as the string `"null"`. Coerce in your client (e.g. parse dates as YYYY-MM-DD, numbers as double/int).

## Summary table (`tips_cpi_data_summary`)

| API field | Type (API) | Meaning |
|-----------|------------|---------|
| `cusip` | STRING | Nine-character CUSIP. Required. |
| `interest_rate` | PERCENTAGE | Coupon rate as **annual percent** in the JSON string, e.g. `"0.125"` = **0.125% per year**. For formulas use **`Double(value) / 100`** to get a decimal (e.g. `0.00125`). |
| `security_term` | STRING | Term label, e.g. `5-Year`, `10-Year`, `30-Year`. |
| `original_auction_date` | DATE | Auction date. |
| `maturity_date` | DATE | Face value paid; interest stops. |
| `additional_issue_date` | DATE | Reopening date, if any. |
| `dated_date` | DATE | Dated date (interest accrual start). |
| `original_issue_date` | DATE | Original issue date. |
| `ref_cpi_on_dated_date` | number | Reference CPI on dated date (index ratio calc). |
| `series` | STRING | Series identifier. |

## Detail table (`tips_cpi_data_detail`)

| API field | Meaning |
|-----------|---------|
| `cusip` | CUSIP. |
| `original_issue_date` | Original issue date. |
| `index_date` | Date for which the index ratio applies. |
| `ref_cpi` | Reference CPI on that date. |
| `index_ratio` | Daily index ratio (adjusted principal = par × index_ratio). |
| `pdf_link`, `xml_link` | URLs to reports, if any. |

Detail rows are per CUSIP per date; use `index_ratio` × par for adjusted principal at `index_date`.
