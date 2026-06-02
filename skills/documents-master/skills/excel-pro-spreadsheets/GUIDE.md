---
name: excel-pro-spreadsheets
description: >-
  Build professional, organized Excel workbooks at staff depth. Pick the right library
  (ExcelJS, SheetJS/xlsx, openpyxl, XlsxWriter), structure multi-sheet models
  (assumptions→calcs→outputs), apply number/date/currency formats, named ranges, data
  validation/dropdowns, conditional formatting, cross-sheet formulas, Excel tables, charts,
  freeze panes, and sheet/cell protection. Covers CSV/formula-injection security, streaming
  for large datasets, and Arabic/RTL sheet direction. Use for any serious .xlsx generation.
---

# Excel Pro — Professional, Structured Workbooks

**A spreadsheet is a small application, not a data dump.** Anyone can dump rows into a sheet; a
professional workbook has a layout a stranger can audit in 30 seconds: inputs you can change,
formulas that recompute live, formats that read correctly, and validation that stops garbage at
the door. Generate workbooks people *trust and edit* — not CSVs renamed `.xlsx`.

---

## 1. Mandate

Produce workbooks that are **structured, formatted, formula-driven, validated, and safe**. Separate
inputs from calculations from outputs. Use real Excel features (named ranges, tables, conditional
formatting, data validation, charts) rather than pre-baking everything into static values. Never
ship a workbook that becomes a formula-injection payload or OOMs the server on a large export.

---

## 2. When to use / when NOT

**Use when:** financial models, reports/dashboards, data exports users will filter and pivot,
templates with input forms, reconciliations, anything tabular that recipients open in Excel/Sheets.

**Use a different tool when:**
- The user wants to **read/parse/fix** an existing `.xlsx`/`.csv` → `anthropic-xlsx` / `blastum-xlsx`.
- The deliverable is a **printed/archival table** → render via `pdf-pro-documents` (PDF/A), not Excel.
- It's **pure data interchange** between systems → CSV/Parquet/JSON, not a styled workbook.
- You need a **slide chart** → `anthropic-pptx`. A **docs table** → `documentation-pro`.

---

## 3. Mental model — layout architecture + engine pipeline

**Workbook architecture (the part juniors skip):**

```
Inputs / Assumptions sheet   → every changeable number lives here (blue font convention)
   ↓ named ranges / cross-sheet refs
Calculations sheet(s)        → formulas only, no hard-coded numbers (black font)
   ↓
Outputs / Dashboard sheet    → summaries, charts, KPIs (the only sheet most readers see)
Raw / Data sheet             → source rows feeding a Table; hidden or at the end
```

Financial-modeling color convention (FAST/“blue = input”): **blue** = hard-coded input, **black**
= formula, **green** = link from another sheet, **red** = external/check. It instantly tells an
auditor what's safe to change.

**Engine pipeline:** build in memory (or stream) → set column models + styles → write formulas as
formula objects (not strings of computed values) → add validation/formatting/charts → protect →
save/stream. Recompute happens **in Excel on open**, so write the *formula*, not the answer.

---

## 4. DECISION MATRIX — pick your library

| Need | ExcelJS (JS) | SheetJS/xlsx (JS) | openpyxl (Py) | XlsxWriter (Py) |
|------|:---:|:---:|:---:|:---:|
| Read **and** write / edit existing | ✅ | ✅ (styling = Pro $) | ✅ best | ❌ write-only |
| Rich styling, fills, borders | ✅ | ◑ Pro | ✅ | ✅ |
| Charts | ◑ limited | ◑ Pro | ✅ | ✅ best (30+) |
| Conditional formatting | ✅ | ◑ Pro | ✅ | ✅ |
| Data validation / dropdowns | ✅ | ◑ | ✅ | ✅ |
| **Streaming write (huge files)** | ✅ `WorkbookWriter` | ◑ | ◑ `write_only` | ✅ `constant_memory` |
| Preserve VBA / edit `.xlsm` | ◑ | ◑ | ✅ only real option | ❌ |
| Sparklines | ❌ | ❌ | ✅ (3.1+) | ❌ |
| Maintenance (2026) | ⚠ stalled since 2023, MIT | CE Apache; advanced = Pro | ✅ active (3.1.5) | ✅ active (3.2.9) |

**Default picks (2026):**
- **Node, styled report** → **ExcelJS** (still the most complete free styling+streaming in JS). Know
  it's been inactive since v4.4.0/2023 with a heavy dependency tree — pin it and audit transitively.
- **Node, just parsing / many formats** → **SheetJS CE** (styling/charts/streaming-write are paid Pro).
- **Python, edit existing or formulas/charts/sparklines** → **openpyxl**.
- **Python, generate huge files fast** → **XlsxWriter** (`constant_memory`), or pandas → XlsxWriter engine.
- **Emerging JS** (watch, pre-1.0): `hucre` (zero-dep, ESM, edge) and `xlsx-kit` (TS streaming) — promising, not yet battle-tested for production.

---

## 5. Production code

### 5a. ExcelJS — a real model sheet (formats, validation, conditional fmt, table, named range, protect, RTL)

```js
// npm i exceljs@4   (pin: inactive since 2023; audit deps)
import ExcelJS from "exceljs";

export async function buildModel(rows, { rtl = false } = {}) {
  const wb = new ExcelJS.Workbook();
  wb.creator = "finance-bot";
  wb.calcProperties.fullCalcOnLoad = true; // force Excel to recompute formulas on open

  // ── Assumptions sheet ─────────────────────────────────────────────
  const a = wb.addWorksheet("Assumptions", { properties: { tabColor: { argb: "FF1F4E78" } } });
  a.getCell("A1").value = "VAT rate";
  a.getCell("B1").value = 0.05;
  a.getCell("B1").numFmt = "0.00%";
  a.getCell("B1").font = { color: { argb: "FF0000CC" } };   // blue = input
  a.getCell("B1").name = "VATRate";                          // workbook-scoped named range

  // ── Model sheet ───────────────────────────────────────────────────
  const ws = wb.addWorksheet("Model", {
    views: [{ state: "frozen", xSplit: 1, ySplit: 1, rightToLeft: rtl }], // freeze + RTL direction
  });
  ws.columns = [
    { header: "Item",     key: "item", width: 34 },
    { header: "Qty",      key: "qty",  width: 10, style: { numFmt: "#,##0" } },
    { header: "Unit",     key: "unit", width: 14, style: { numFmt: '#,##0.00 "AED"' } },
    { header: "Net",      key: "net",  width: 16, style: { numFmt: '#,##0.00 "AED"' } },
    { header: "Gross",    key: "gross",width: 16, style: { numFmt: '#,##0.00 "AED"' } },
    { header: "Status",   key: "stat", width: 14 },
  ];
  const head = ws.getRow(1);
  head.font = { bold: true, color: { argb: "FFFFFFFF" } };
  head.fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FF1F4E78" } };
  head.alignment = { vertical: "middle", horizontal: rtl ? "right" : "left" };

  rows.forEach((r, i) => {
    const n = i + 2;
    ws.addRow({ item: r.item, qty: r.qty, unit: r.unit, stat: r.status });
    ws.getCell(`D${n}`).value = { formula: `B${n}*C${n}` };            // Net = Qty*Unit (black=formula)
    ws.getCell(`E${n}`).value = { formula: `D${n}*(1+VATRate)` };      // Gross via named range
    ws.getCell(`F${n}`).dataValidation = {                            // dropdown
      type: "list", allowBlank: false, formulae: ['"Draft,Approved,Paid"'],
      showErrorMessage: true, errorTitle: "Invalid", error: "Pick from the list",
    };
  });

  // Conditional formatting: flag negative/zero nets
  ws.addConditionalFormatting({
    ref: `D2:D${rows.length + 1}`,
    rules: [{
      type: "cellIs", operator: "lessThanOrEqual", formulae: ["0"], priority: 1,
      style: { font: { color: { argb: "FF9C0006" } },
               fill: { type: "pattern", pattern: "solid", bgColor: { argb: "FFFFC7CE" } } },
    }],
  });

  // A real Excel Table (filterable, striped, structured refs)
  ws.addTable({
    name: "Lines", ref: "A1",
    headerRow: true, style: { theme: "TableStyleMedium2", showRowStripes: true },
    columns: ws.columns.map((c) => ({ name: String(c.header), filterButton: true })),
    rows: rows.map((r) => [r.item, r.qty, r.unit, null, null, r.status]),
  });

  // Protect structure: lock formulas, leave inputs editable
  ws.getColumn("F").eachCell((c) => (c.protection = { locked: false }));
  await ws.protect("model-secret", { selectLockedCells: true, formatColumns: false });

  return wb.xlsx.writeBuffer();
}
```

### 5b. ExcelJS — streaming writer for large datasets (constant memory)

```js
import ExcelJS from "exceljs";
// WorkbookWriter flushes rows to disk as they're committed → ~tens of MB heap for millions of rows.
export async function streamBig(filename, source /* async iterable of arrays */) {
  const wb = new ExcelJS.stream.xlsx.WorkbookWriter({ filename, useStyles: true });
  const ws = wb.addWorksheet("Data");
  ws.columns = [{ header: "ID", width: 12 }, { header: "Amount", width: 16, style: { numFmt: "#,##0.00" } }];
  for await (const row of source) {
    ws.addRow(row).commit();   // commit() releases the row from memory
  }
  await ws.commit();
  await wb.commit();
}
```

### 5c. openpyxl — model + chart + sparkline + sanitized data + RTL

```python
# pip install openpyxl  (3.1.5, 2026)  — read/write, editing, formulas, charts, sparklines
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment
from openpyxl.worksheet.datavalidation import DataValidation
from openpyxl.formatting.rule import CellIsRule
from openpyxl.chart import BarChart, Reference
from openpyxl.workbook.defined_name import DefinedName

def sanitize(v):
    # CSV/formula-injection guard: neutralize cells that Excel would evaluate as a formula.
    if isinstance(v, str) and v[:1] in ("=", "+", "-", "@", "\t", "\r"):
        return "'" + v
    return v

def build_model(rows, rtl=False):
    wb = Workbook()
    ws = wb.active
    ws.title = "Model"
    ws.sheet_view.rightToLeft = rtl          # RTL sheet direction (Arabic)
    ws.freeze_panes = "B2"                    # freeze header row + first column

    headers = ["Item", "Qty", "Unit", "Net", "Gross", "Status"]
    ws.append(headers)
    for c in ws[1]:
        c.font = Font(bold=True, color="FFFFFF")
        c.fill = PatternFill("solid", fgColor="1F4E78")
        c.alignment = Alignment(horizontal="right" if rtl else "left")

    wb.defined_names["VATRate"] = DefinedName("VATRate", attr_text="Model!$H$1")
    ws["H1"] = 0.05; ws["H1"].number_format = "0.00%"; ws["H1"].font = Font(color="0000CC")

    for i, r in enumerate(rows, start=2):
        ws.cell(i, 1, sanitize(r["item"]))
        ws.cell(i, 2, r["qty"]).number_format = "#,##0"
        ws.cell(i, 3, r["unit"]).number_format = '#,##0.00 "AED"'
        ws.cell(i, 4, f"=B{i}*C{i}").number_format = '#,##0.00 "AED"'        # formula, not value
        ws.cell(i, 5, f"=D{i}*(1+VATRate)").number_format = '#,##0.00 "AED"'
        ws.cell(i, 6, sanitize(r["status"]))

    last = len(rows) + 1
    dv = DataValidation(type="list", formula1='"Draft,Approved,Paid"', allow_blank=False)
    ws.add_data_validation(dv); dv.add(f"F2:F{last}")

    ws.conditional_formatting.add(
        f"D2:D{last}",
        CellIsRule(operator="lessThanOrEqual", formula=["0"],
                   fill=PatternFill("solid", fgColor="FFC7CE")))

    chart = BarChart(); chart.title = "Net by item"
    data = Reference(ws, min_col=4, min_row=1, max_row=last)
    cats = Reference(ws, min_col=1, min_row=2, max_row=last)
    chart.add_data(data, titles_from_data=True); chart.set_categories(cats)
    ws.add_chart(chart, "H3")

    ws.protection.sheet = True; ws.protection.password = "model-secret"
    wb.save("model.xlsx")
```

### 5d. XlsxWriter / pandas — huge file, low memory

```python
import xlsxwriter
# constant_memory streams each row out; trades random access for ~flat memory on millions of rows.
wb = xlsxwriter.Workbook("big.xlsx", {"constant_memory": True})
ws = wb.add_worksheet("Data")
money = wb.add_format({"num_format": '#,##0.00 "AED"'})
for r, (id_, amt) in enumerate(source):
    ws.write_string(r, 0, str(id_)); ws.write_number(r, 1, amt, money)
wb.close()
# Or: df.to_excel("out.xlsx", engine="xlsxwriter") then polish with workbook/worksheet handles.
```

---

## 6. Edge cases & gotchas

- **Formulas as strings vs values**: write `{ formula: "A2*B2" }` (ExcelJS) / `"=A2*B2"` (openpyxl).
  If you precompute and write the number, the workbook won't recalc when inputs change.
- **Cached results**: ExcelJS/openpyxl don't compute formula *results*; some viewers show blank until
  Excel recalculates. Set `fullCalcOnLoad`/`calcChain` or write a cached value when a non-Excel
  consumer must read it.
- **Dates**: Excel stores dates as serial numbers. Write real `Date`/`datetime` objects + a date
  `numFmt`; writing a string `"2026-06-01"` makes it text you can't sum or sort.
- **Leading-zero IDs / long numbers** (phone, IBAN, SKU `007`, 16-digit card): force **text** format
  or they lose zeros / become `1.23E+15`.
- **Number format ≠ value**: `0.05` + `"0.00%"` shows `5.00%`; don't also multiply by 100.
- **Merged cells** break sorting/filtering and screen readers — avoid in data ranges; use centered headers sparingly.
- **Named-range scope**: workbook vs worksheet scope changes how a formula resolves across sheets.
- **openpyxl memory** is ~50× file size in normal mode; use `read_only`/`write_only` for big files.
- **`.xlsm` macros**: only openpyxl preserves them (`keep_vba=True`); XlsxWriter/most others drop them.

---

## 7. Performance (large data)

- **Stream, don't accumulate**: ExcelJS `stream.xlsx.WorkbookWriter` + `row.commit()`; openpyxl
  `Workbook(write_only=True)`; XlsxWriter `{"constant_memory": True}`.
- **Styles cost memory**: openpyxl stores style per cell — reuse named styles; XlsxWriter shares
  formats. In ExcelJS streaming, set `useStyles: true` only if you actually style.
- **Do heavy aggregation upstream** (SQL / pandas / Polars) and write a compact result, rather than
  pushing a million raw rows into a styled sheet.
- **Charts over 10k points** bloat the file and choke Excel — pre-aggregate before charting.
- **Avoid whole-column formats/CF** (`A:A`); scope to the used range to keep the file small.

---

## 8. Security

- **CSV / formula injection (CWE-1236)** is the #1 spreadsheet vuln. Any user-controlled value
  starting with `= + - @`, TAB, or CR can become a live formula (`=cmd|'/c calc'!A1`,
  `=HYPERLINK("evil…")`, `=WEBSERVICE(...)` exfiltration) when the file is opened. **Sanitize on
  export**: prefix such values with `'` (see `sanitize()` above) or set the cell to text and strip
  control chars. Apply to **CSV too** — CSV has no styling but the same injection risk.
- **Don't trust formulas from user input.** If users supply expressions, validate against an allow-list.
- **Protection is not encryption.** Sheet/workbook "protection" is trivially removable; for real
  confidentiality, encrypt the file (Excel's OOXML AES via `msoffcrypto-tool` / `secure-spreadsheet`) or deliver over an authenticated channel.
- **Strip PII / hidden data** before sending: hidden sheets/columns, comments, defined names,
  document properties, and **cached pivot data** often leak the full source table.
- **External links / DDE**: remove `=WEBSERVICE`, `=RTD`, DDE links and external workbook refs from generated output.

---

## 9. Scale / automation / batch

- **Template + data**: keep a styled `.xlsx` template and inject data (openpyxl loads & edits it;
  docxtemplater has an XLSX module) so design changes don't touch code.
- **Batch generation**: drive from a queue; stream each workbook to object storage; key by report id
  for idempotent retries. Pair with `devops-master`.
- **Serverless**: openpyxl/XlsxWriter are lightweight and fit Lambda; ExcelJS works but mind the
  dependency size/cold start.
- **Separate compute from formatting**: SQL/pandas/Polars produce the numbers; the Excel library
  only lays them out. Easier to test and far faster.

---

## 10. Testing & validation

- **Round-trip read-back**: write, then re-open with openpyxl/ExcelJS and assert cell values,
  `number_format`, formulas, and named ranges — catches silent format drift.
- **Open in real Excel / LibreOffice headless** (`libreoffice --headless --convert-to xlsx`) in CI to
  catch corruption a library accepts but Excel rejects.
- **Formula correctness**: assert the *formula text*, and (where a non-Excel reader needs results)
  recompute with `libreoffice`/`formulas` lib and compare.
- **Injection tests**: feed `=1+1`, `@SUM(...)`, `-2+3`, `+cmd`, leading TAB — assert each is
  neutralized (stored as text, leading `'`).
- **Schema/lint**: validate the input dataset (column count/types) before generation so a bad feed fails loud, not in the sheet.

---

## 11. Accessibility & i18n / RTL Arabic

- **RTL sheet direction**: ExcelJS `views: [{ rightToLeft: true }]`; openpyxl `ws.sheet_view.rightToLeft = True`;
  XlsxWriter `ws.right_to_left()`. This flips column order A→right for Arabic/Hebrew workbooks.
- **Arabic content**: set cell alignment `right`; keep Western digits readable inside Arabic text via
  appropriate number formats; choose a font present on the reader's machine (Excel substitutes, but
  Arial/Calibri cover Arabic adequately).
- **Locale-aware formats**: currency/date/number formats are locale-sensitive — `#,##0.00 "AED"`,
  `[$-ar-AE]`-prefixed formats, or culture-neutral patterns. Don't hard-code `$`.
- **Spreadsheet accessibility** (often ignored): give sheets meaningful **tab names**, add header
  rows, set the **print title rows**, name ranges, and avoid merged cells in data — screen readers
  navigate tables by row/column headers. Add `Alt text` to charts/images where the library allows.
- **Externalize labels** for multi-language exports; generate per-locale headers from a dictionary.

---

## 12. Anti-patterns

- **CSV renamed `.xlsx`** / a single flat sheet with no inputs, formats, or validation.
- **Hard-coded results instead of formulas** → workbook can't be audited or re-run.
- **Dates/numbers as text** → no sums, no sorting, broken charts.
- **No injection sanitization** on user data → weaponized spreadsheet.
- **One mega-sheet** mixing inputs, calcs, and outputs → un-auditable; use the layered layout.
- **Loading millions of rows in normal mode** → OOM; stream instead.
- **Treating sheet protection as security** → it's a speed bump, not a lock.
- **Whole-column conditional formatting / formats** → bloated, slow files.
- **Relying on ExcelJS being maintained** — it's stalled; pin the version and audit its deps.

---

## 13. Agent checklist

```
- [ ] Library chosen from matrix (read/edit? styling? charts? streaming? Python/JS?)
- [ ] Layered layout: Assumptions → Calculations → Outputs (+ Raw); blue=input/black=formula
- [ ] Formulas written as formulas (+ fullCalcOnLoad); not precomputed values
- [ ] Number/date/currency formats set; IDs forced to text; dates are real dates
- [ ] Named ranges + cross-sheet refs instead of magic cell coordinates
- [ ] Data validation/dropdowns on input cells; conditional formatting on key metrics
- [ ] Real Excel Table for tabular data (filter, structured refs); freeze panes set
- [ ] CSV/formula-injection sanitization on ALL user-supplied values (xlsx AND csv)
- [ ] Protection where needed (locked formulas, editable inputs); encrypt if confidential
- [ ] Large data streamed (WorkbookWriter / write_only / constant_memory)
- [ ] RTL direction + alignment + locale formats for Arabic; meaningful tab names
- [ ] Round-trip read-back test + open-in-LibreOffice CI check
```

---

## 14. References (2026)

- ExcelJS — https://github.com/exceljs/exceljs (v4.4.0; inactive — pin & audit)
- SheetJS / xlsx — https://docs.sheetjs.com (CE Apache-2.0; styling/streaming = Pro)
- openpyxl 3.1.x — https://openpyxl.readthedocs.io · performance/optimized modes https://openpyxl.readthedocs.io/en/stable/performance.html
- XlsxWriter 3.2.x — https://xlsxwriter.readthedocs.io · constant_memory https://xlsxwriter.readthedocs.io/working_with_memory.html
- OWASP CSV/Formula Injection — https://owasp.org/www-community/attacks/CSV_Injection · CWE-1236 https://cwe.mitre.org/data/definitions/1236.html
- Emerging: hucre https://github.com/productdevbook/hucre · xlsx-kit https://github.com/baseballyama/xlsx-kit (pre-1.0)
- ECMA-376 / OOXML SpreadsheetML — https://ecma-international.org/publications-and-standards/standards/ecma-376/

---

## 15. Related

`anthropic-xlsx` / `blastum-xlsx` (read/edit/analyze existing), `pdf-pro-documents` (print/archive a
table as PDF/A), `documentation-pro` (reference tables), `generating-images` (export a chart).
Cross-master: `business-master` (financial models, accounting, ERP exports, VAT/ZATCA),
`analytics-master` (dashboards), `devops-master` (batch pipelines/serverless).
