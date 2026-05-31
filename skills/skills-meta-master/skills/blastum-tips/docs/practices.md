# Throttling, pagination, errors

## Rate limits

API returns **429 Too Many Requests** when rate limited. No official numbers; treat as “reasonable use,” avoid bursts.

**Recommendations:**
- **Throttle:** Limit request rate (e.g. max N/sec or N/min). Space paginated/bulk requests.
- **Many CUSIPs:** Cap parallelism; cache repeated “ratio at cutoff” per CUSIP.
- **Retry with backoff:** On 429 or 5xx, retry after delay (e.g. exponential: 1s, 2s, 4s), max retries.
- **Retry-After:** If the API adds this header, honor it.
- **Caching:** Cache summary (and optionally detail); dataset updates monthly.

## Pagination patterns

- **Default:** No params → first 100 rows, page 1.
- **Fixed page:** Set `page[size]` and `page[number]`.
- **Fetch all (total unknown):** Request page 1 with chosen `page[size]`. If rows returned < `page[size]`, last page. Else increment `page[number]` and repeat until a page returns fewer rows.
- **Fetch all (total known):** Parse `meta.total-pages` (or `meta.total-count`), loop `page[number]` from 1 to total.
- **Large exports:** Prefer one request with large `page[size]` if allowed; else “fetch until short page” and throttle between pages.

## Date and number handling

- **Dates:** API returns YYYY-MM-DD strings. Use same format in filter values.
- **Numbers:** interest_rate, ref_cpi_on_dated_date, index_ratio, ref_cpi are strings; parse to double/int in your client. **security_term** is a label string (e.g. `5-Year`, `10-Year`, `30-Year`).

## Error handling

- **Non-200:** API may return 400, 403, 404, 405, 429, 500 with body like `{"error":"...","message":"..."}`. Implement retry for 429/5xx.
- **Decoding:** Response must match wrapper (`data` array). Wrong filter/sort field names can yield 400 or malformed/empty data.
