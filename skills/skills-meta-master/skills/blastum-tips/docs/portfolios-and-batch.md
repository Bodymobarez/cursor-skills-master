# Portfolios, CUSIP sets, and batch API use

The Fiscal Data TIPS/CPI API is **row-oriented**: summary is **one row per security**, detail is **one row per CUSIP per `index_date`**. There is **no single call** that returns arbitrary multi-CUSIP detail for different dates per line in all cases—**design around sets**.

---

## 1. Define the “set”

| Goal | How to build the set |
|------|----------------------|
| **Known holdings** | Unique CUSIPs from a portfolio CSV or user list. **Aggregate shares per CUSIP** before calling APIs. |
| **Ladder / maturity window** | **Summary** only: `filter=maturity_date:gte:<start>,maturity_date:lte:<end>` (+ optional `security_term:in:(5-Year,10-Year,30-Year)`). Paginate until all rows fetched. |
| **Single-name deep history** | **Detail** with `cusip:eq:…` + optional `index_date` bounds; paginate by `page[number]`. |

---

## 2. Multiple CUSIPs: recommended patterns

### 2.1 Parallel per-CUSIP (arbitrary holdings)

For a **fixed list of CUSIPs**, the robust approach is **one request per CUSIP** (summary and/or detail) run **concurrently with a concurrency limit**, not unbounded blast (avoids **429**).

This repo’s **`APIClient.fetchSummary(cusips:)`** / **`fetchDetail(cusips:)`** uses **parallel tasks per CUSIP**—acceptable for moderate N; for large N add **semaphores / queues** and backoff.

### 2.2 One summary sweep + selective detail

1. Paginate **summary** to get all securities in a maturity range (fewer calls than per-CUSIP summary when building universes).
2. For **calculations**, request **detail** only for CUSIPs that actually need a ratio (holdings ∩ universe).

### 2.3 `cusip:in:(…)` (if supported)

The API supports `in` for some fields. **Verify** against production for `cusip`—behavior can differ by dataset. If `cusip:in:(A,B,C)` is **not** reliable, stay with **parallel `cusip:eq`** requests.

Run parameter checks: `swift run TIPSyCLI verify-params` (summary filters exercised).

---

## 3. Batch calculations (same payment date)

For **many CUSIPs on the same payment date**:

1. Load **`interest_rate`, `dated_date`, `maturity_date`** per CUSIP (summary; can batch per §2).
2. For each CUSIP that **actually pays** on that date (`PaymentSchedule` logic: semi-annual months + maturity):
   - Fetch **one detail row** for the appropriate **index_date strategy** (exact payment date, on-or-before payment, or **cutoff** if payment > dataset).
3. **Cache by CUSIP** the “ratio at cutoff” when multiple future payments are projected—avoid repeating identical detail calls (see **`PayoutContext.detailAtCutoff`** in `CouponCalculator`).

---

## 4. Rate limits and fairness

- **429**: exponential backoff, jitter, cap retries.
- **Cache** summary rows (refresh monthly when dataset updates).
- **Detail** for “latest” ratio: cache per (CUSIP, cutoff day).

---

## 5. Fields to persist per CUSIP (calculation-ready)

From **summary**: `cusip`, `interest_rate`, `dated_date`, `maturity_date`, `original_auction_date`, `security_term`.

From **detail** (per use): `index_date`, `index_ratio`, optionally `ref_cpi`.

---

## 6. Related code (this repo)

- `Sources/TIPSy/APIClient.swift` — base URL, detail/summary, `indexDateOnOrBefore`, `fetchLatestIndexDate`.
- `Sources/TIPSy/CouponCalculator.swift` — coupon + maturity payout, `PayoutContext`.
- `Sources/TIPSy/PaymentSchedule.swift` — payment-month rules.
- `Sources/TIPSyCLI/main.swift` — `fetch`, `verify-coupon`, `payout`.
