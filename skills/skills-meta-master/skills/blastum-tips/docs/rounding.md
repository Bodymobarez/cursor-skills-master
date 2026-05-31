# Treasury rounding (31 CFR Part 356, Appendix B)

Authoritative rules for **marketable** TIPS in the Uniform Offering Circular (*Formulas and Tables*). Use when reconciling **computed** index ratios or **cash** amounts to Treasury’s published values.

**eCFR:** [Appendix B to Part 356](https://www.ecfr.gov/current/title-31/subtitle-B/chapter-II/subchapter-A/part-356/appendix-Appendix%20B%20to%20Part%20356)

---

## Reference CPI and index ratio

- **Interpolation:** Ref CPI for a calendar day is linear between month-start Ref CPIs.
- **Precision:** Truncate intermediate values for Ref CPI and Index Ratio to **six** decimal places, then **round to five** decimal places (“normal” rounding at that step).
- **Publication:** Ref CPI and Index Ratio for a date are expressed to **five** decimals.
- **CPI revisions:** Treasury uses the **previously reported (unrevised)** CPI for principal and interest; later BLS revisions do not rewrite past payments.

---

## Coupon (semi-annual interest)

- **Formula:** `(stated annual rate ÷ 2) × inflation-adjusted principal` on the payment date (half-year is not day-counted for a regular six-month period).
- **Cash:** The dollar amount is rounded to the **nearest cent** (normal rounding). Appendix B illustrates this on a worked example (payment shown to cents).

---

## Accrued interest (settlement)

- **$1,000 par:** Accrued interest is rounded to **five** decimal places using **normal rounding procedures**, then scaled for other par amounts (Appendix B §I.D.4).
- **Inflation-protected pricing (yield ↔ price):** Worked examples in Appendix B **Section III** carry **per $100** **real price**, **inflation-adjusted price**, **accrued interest**, and **adjusted accrued interest** to **six** decimal places in the examples—distinct from the $1,000 accrued-interest rule.

---

## STRIPS (stripped inflation-protected interest components)

- Adjusted value and payment formulas in Appendix B **Section V** round to **two** decimal places with **no intermediate rounding** in the stated formulas.

---

## TIPSy3 implementation

`TreasuryRounding` in the package:

- **`normalizeIndexRatio(_:)`** — truncate to 6 decimals, round to 5 (for API `index_ratio` or locally computed ratios).
- **`roundPaymentToCents(_:)`** — nearest cent for coupon and maturity cash totals.

Fiscal Data API strings should already match Treasury’s published ratios; normalization makes behavior **idempotent** for five-decimal inputs and corrects extra floating-point precision.
