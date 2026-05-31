# TIPS calculations (principal, coupons, maturity)

Authoritative formulas match TreasuryDirect: **adjusted principal** = par × **index ratio**; **semi-annual interest** = adjusted principal × (**stated annual rate** ÷ 2).

---

## 1. Inputs and units

| Input | Role |
|--------|------|
| **Par / original principal** | Face amount in dollars. Treasury retail is often **$1,000 per bond**; **shares × 1,000** = principal for a ladder-style portfolio. |
| **`interest_rate` (summary)** | API returns **annual percent as a string**, e.g. `"0.125"` = **0.125%**, not 12.5%. Convert to decimal for formulas: **`r = Double(interest_rate) / 100`**. |
| **`index_ratio` (detail)** | Multiply par to get **inflation-adjusted principal** for that `index_date`. |
| **`dated_date`, `maturity_date` (summary)** | Define the **semi-annual payment schedule** and maturity. |

All JSON values from the API are **strings**; parse numbers explicitly.

---

## 2. Core formulas

```
adjusted_principal = original_principal × index_ratio
semi_annual_coupon = adjusted_principal × (r / 2)    where r = interest_rate / 100
```

**Rounding (31 CFR Part 356 Appendix B):** Interpolated **Ref CPI** and **index ratio** are truncated to **six** decimals, then rounded to **five**. **Cash** coupon (and principal at payment) are rounded to the **nearest cent**. Unrevised CPI only for indexation. See [rounding.md](rounding.md).

**At maturity** (on the maturity payment date), cash paid includes **final coupon + adjusted principal** (subject to Treasury’s **deflation floor**: principal paid is **max(adjusted, original)** at maturity; many implementations track this explicitly when projecting final cash).

---

## 3. Which `index_ratio` to use (two modes)

| Mode | When to use | Detail API pattern |
|------|----------------|---------------------|
| **Payment-date (or on-or-before payment)** | Accrued / realized coupons **on a known date**; historical verification. | Row with `index_date` **on or before** the payment date: filter `cusip:eq:…,index_date:lte:<paymentDate>`, `sort=-index_date`, `page[size]=1`. |
| **Exact calendar date** | When the dataset has a row for that exact date. | `filter=cusip:eq:…,index_date:eq:<YYYY-MM-DD>`. If empty, Treasury may not publish that day—fall back to latest `index_date` for that CUSIP (`sort=-index_date`, `page[size]=1`). |
| **Current / “as of today”** | **Projected** future coupons on tools like tipsladder.com: they use **latest index available at build time**, not the future payment date’s ratio (future CPI unknown). | `index_date:lte:<today>` with `sort=-index_date`, `page[size]=1`. |

For **payment dates after the dataset’s last `index_date`** (future relative to CPI publication), use the **ratio at dataset cutoff**: same as “on-or-before” with cutoff = latest `index_date` in the API for that CUSIP. Document clearly that the result is an **estimate** until CPI catches up.

Reference: `notebook/tips-ladders/documents/tipsladder-computations.md`.

---

## 4. Payment schedule (semi-annual)

TIPS pay **twice per year** on the **15th** in two months determined by the **dated date** (issue/accrual start): the **dated month** and **six months later**. A date is a coupon date only if it falls in those months, is the 15th (as stored in API dates), lies **on or after** `dated_date` and **on or before** `maturity_date`, and matches the 6-month cycle.

Use **`dated_date` and `maturity_date` from summary**, not guessed from CUSIP.

---

## 5. API mapping (minimum calls)

1. **Summary** `GET …/tips_cpi_data_summary?filter=cusip:eq:<CUSIP>&page[size]=1`  
   → `interest_rate`, `dated_date`, `maturity_date`, optional other ladder fields.

2. **Detail** (pick one pattern from §3)  
   → `index_ratio`, `index_date`.

**One row each** is enough per calculation if filters + sort are correct.

---

## 6. Verification and tooling (this repo)

- **Coupon check:** `swift run TIPSyCLI verify-coupon <CUSIP> <shares> <YYYY-MM-DD-payment> <expected$>` — add **`--current-cpi`** to match “index as of today” behavior.
- **Portfolio payout on one date:** `swift run TIPSyCLI payout <YYYY-MM-DD> <holdings.csv>` — CSV columns: `cusip,count` (aggregated by CUSIP). Uses cutoff logic and optional cache for many lines.
- **Algorithm write-up:** `tmp/coupon-payment-algorithm.md`.

---

## 7. Common pitfalls

- Treating API **`interest_rate` as already a decimal** (it is **percent**).
- Using **payment-date** index for **future** dates when reproducing **tipsladder-style** projections—use **as-of** or cutoff ratio instead.
- **Unbounded detail pulls** (`filter=cusip:eq:X` only): one row per calendar day × CUSIP—**always** narrow with `index_date` filters or small pages when you only need one ratio.
- Ignoring **429**: throttle parallel work; retry with backoff on 429/5xx.
