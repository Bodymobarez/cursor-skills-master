---
name: pdf-pro-documents
description: >-
  Produce professional, structured, accessible PDFs at staff depth. Pick the right engine
  (Puppeteer/Playwright HTML→PDF, @react-pdf/renderer, WeasyPrint, Typst, LaTeX, pdf-lib),
  build real typographic hierarchy, paginating tables, TOC, running headers/footers + page
  numbers, branding/templates, embedded fonts with Arabic/RTL shaping, PDF/A archival and
  PDF/UA tagged accessibility, merge/split/stamp/watermark, fillable forms, and
  encryption/permissions. Use for any serious PDF generation or manipulation task.
---

# PDF Pro — Professional, Accessible Document Generation

**A PDF is a typeset artifact, not a screenshot.** If your output can't be selected, searched,
tagged for a screen reader, paginated without orphaned headers, or archived for 10 years, you
shipped an image with a `.pdf` extension. Choose an engine by the *document*, build structure
first, and treat PDF/UA + PDF/A as acceptance criteria — not afterthoughts.

---

## 1. Mandate

Own the full lifecycle: **generate → structure → brand → tag → secure → validate**. Every PDF you
emit must have selectable text, a logical reading order, an embedded font subset, a document
title in metadata, and a declared language. Accessible and archivable by default; encryption and
watermarking on demand. You are responsible for the *bytes*, not just the visual.

---

## 2. When to use / when NOT

**Use when:** invoices, reports, statements, certificates, contracts (pair with `contracts-pro`),
data exports, letters, catalogs, anything that must print/paginate/archive or be legally retained.

**Use a different tool when:**
- The user wants a **Word doc** → `anthropic-docx` / `blastum-docx` (DOCX is editable; PDF is final).
- The user wants a **slide deck** → `anthropic-pptx` / `sentry-presentation-creator`.
- It's a **one-off Markdown → styled PDF** → `blastum-markdown-to-pdf` (pandoc + WeasyPrint) is faster than wiring an engine.
- You only need to **extract/read** text or tables from existing PDFs → `anthropic-pdf`.
- The "PDF" is really a **web page** the user will read on screen → ship HTML; don't force pagination.

---

## 3. Mental model — the four generation strategies

PDF tooling splits into four families. Pick the family first, the library second.

```
A. HTML/CSS → PDF (browser)     Puppeteer / Playwright  → Chrome's print engine
B. HTML/CSS → PDF (print lib)   WeasyPrint              → native PDF/UA + PDF/A, no browser
C. Component / declarative       @react-pdf/renderer     → React → PDF (flexbox layout engine)
D. Typesetting / markup          Typst, LaTeX            → best pagination + math + native PDF/A/UA
E. Manipulation (post-process)   pdf-lib / @cantoo, qpdf → merge, stamp, forms, encrypt
```

- **A (Puppeteer)** wins on *fidelity*: real CSS, web fonts, JS charts (Chart.js/ECharts), `@page`
  rules. It loses on *accessibility/archival* — Chrome tags content but does **not** emit valid
  PDF/UA metadata, and any Ghostscript/PDF-A pass strips the tags.
- **B (WeasyPrint)** wins on *correctness*: it writes real PDF/A and PDF/UA-1/UA-2 variants from
  HTML+CSS with no headless browser. Slightly weaker CSS support (no JS), but it's the pragmatic
  choice for **accessible, archival, server-side** PDFs.
- **C (@react-pdf)** wins when your stack is React and you want type-safe, component-driven
  documents rendered the same on client and server. It is **not** a browser — no CSS cascade, a
  flexbox subset, and RTL/Arabic needs manual handling.
- **D (Typst/LaTeX)** wins on *typography and pagination* (footnotes, TOC, widow/orphan control,
  math) and Typst now emits **native PDF/A + PDF/UA-1**. Best for long structured docs and where
  validators must pass automatically.
- **E (pdf-lib/qpdf)** is the finishing stage: merge, split, watermark, fill forms, set metadata,
  encrypt. Compose it after A–D.

---

## 4. DECISION MATRIX — pick your engine

| Need | Puppeteer/Playwright | WeasyPrint | @react-pdf | Typst | pdf-lib/qpdf |
|------|:---:|:---:|:---:|:---:|:---:|
| Pixel-perfect CSS / web fonts | ✅ best | ◑ good | ❌ subset | ◑ | — |
| JS charts (Chart.js/ECharts) | ✅ | ❌ | ❌ | ❌ | — |
| **Native PDF/UA-1 tagging** | ❌ (best-effort) | ✅ | ❌ | ✅ | — |
| **Native PDF/A archival** | ❌ (needs GS) | ✅ A-1…A-4 | ❌ | ✅ A-2/3/4 | — |
| Long-doc pagination / TOC / footnotes | ◑ | ◑ | ◑ | ✅ best | — |
| No browser / low memory on server | ❌ (heavy) | ✅ | ✅ | ✅ | ✅ |
| React/TS stack, client+server parity | ◑ | ❌ | ✅ | ❌ | — |
| Merge/split/stamp/forms/encrypt | ❌ | ◑ forms | ❌ | ❌ | ✅ |
| Arabic/RTL shaping | ✅ (HarfBuzz) | ✅ (HarfBuzz) | ◑ manual | ✅ | — |

**Default picks (2026):** accessible/archival server PDFs → **WeasyPrint** or **Typst**;
marketing-grade fidelity + charts → **Puppeteer**; React product → **@react-pdf**; any
post-processing → **@cantoo/pdf-lib** (+ **qpdf** for encryption).

**Variant matrix — which PDF/A·UA to target** (per PDF Association *Conforming to both PDF/A & PDF/UA*):

| Document goal | Target | Notes |
|---|---|---|
| Accessible only | PDF/UA-1 (ISO 14289-1) | Based on PDF 1.7; what most regulations cite (Section 508, EN 301 549). |
| Archival only | PDF/A-2b or A-3b | A-3 allows embedded files (e-invoices: Factur-X/ZUGFeRD). |
| Accessible **and** archival (PDF 1.7) | **PDF/A-2/3 + PDF/UA-1** | Do **not** combine PDF/A-1 + UA-1. |
| Accessible + archival (PDF 2.0) | **PDF/A-4 + PDF/UA-2** | PDF/UA-2 = ISO 14289-2 (2024); MathML + namespaces. Validators reject PDF 2.0 files claiming any 1.x subset. |
| "u" suffix (A-2u/A-3u) | Unicode-mapped text | Prefer over "b" so text is reliably extractable. |

---

## 5. Production code

### 5a. Puppeteer → tagged PDF with running header/footer + page numbers

```js
import puppeteer from "puppeteer"; // v24.x (2026)
import { PDFDocument } from "@cantoo/pdf-lib";

export async function htmlToAccessiblePdf(html, { title, lang = "en" }) {
  const browser = await puppeteer.launch({
    headless: true,
    // tag the structure tree at the Chrome level (also enabled by page.pdf({tagged:true}))
    args: ["--export-tagged-pdf", "--no-sandbox"],
  });
  try {
    const page = await browser.newPage();
    // Bake <html lang> + <title> into the markup — both are REQUIRED for PDF/UA.
    await page.setContent(html, { waitUntil: "networkidle0" });
    await page.evaluate(() => document.fonts.ready); // never print before webfonts load

    const pdf = await page.pdf({
      format: "A4",
      tagged: true,             // Puppeteer ≥ 21.10: emits a structure tree
      printBackground: true,    // backgrounds/colors are off by default — almost always wrong
      preferCSSPageSize: true,  // respect @page size/margins from CSS when present
      margin: { top: "28mm", bottom: "22mm", left: "18mm", right: "18mm" },
      displayHeaderFooter: true,
      headerTemplate: `<div style="font-size:8px;width:100%;padding:0 18mm;color:#666">
        <span class="title"></span></div>`,
      footerTemplate: `<div style="font-size:8px;width:100%;padding:0 18mm;color:#666;
        display:flex;justify-content:space-between">
        <span>${escapeHtml(title)}</span>
        <span>Page <span class="pageNumber"></span> / <span class="totalPages"></span></span>
      </div>`,
    });
    // Chrome tags content but omits PDF/UA metadata (Title, Lang, DisplayDocTitle, XMP UA id).
    // Patch what pdf-lib can, then finish UA conformance with veraPDF/exiftool (see §10/§11).
    const doc = await PDFDocument.load(pdf);
    doc.setTitle(title);
    doc.setLanguage(lang);
    return await doc.save();
  } finally {
    await browser.close();
  }
}
const escapeHtml = (s) => s.replace(/[&<>"]/g, (c) =>
  ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
```

> Reality check: Puppeteer's `tagged:true` is **best-effort PDF/UA**, not conformant. If the
> requirement is real PDF/UA-1, generate with **WeasyPrint or Typst** instead and use Puppeteer
> only when you need CSS/JS fidelity. (Playwright is equivalent: `page.pdf({ tagged: true })`.)

### 5b. WeasyPrint → native PDF/UA-1 (the pragmatic accessible path)

```python
# pip install weasyprint  (v69.x, 2026)
from weasyprint import HTML

# <html lang="..."> and a <title> are mandatory for PDF/UA. Headings must be hierarchical (h1→h2…).
HTML(string=html, base_url=".").write_pdf(
    "report.pdf",
    pdf_variant="pdf/ua-1",   # also: pdf/a-2b, pdf/a-3b (e-invoice), pdf/a-4, pdf/ua-2
    pdf_tags=True,            # write the accessibility structure tree
    pdf_forms=True,           # interactive AcroForm fields from <input>/<select>
)
```

### 5c. Typst → PDF/A + PDF/UA in one command (best pagination/typography)

```bash
# Typst 0.14+ enforces conformance and errors out on a missing title or broken heading order.
typst compile contract.typ contract.pdf --pdf-standard a-2b,ua-1
# Combine archival + accessible (PDF 1.7 lineage). Always re-validate with veraPDF afterwards.
```

### 5d. @react-pdf/renderer → paginating table + Arabic/RTL

```jsx
// npm i @react-pdf/renderer@4   (4.5.x, 2026)
import {
  Document, Page, View, Text, StyleSheet, Font, renderToBuffer,
} from "@react-pdf/renderer";

// Register a font that actually contains Arabic glyphs + ligatures; default fonts render ☐☐☐.
Font.register({
  family: "Noto",
  fonts: [
    { src: "fonts/NotoSans-Regular.ttf" },
    { src: "fonts/NotoSans-Bold.ttf", fontWeight: "bold" },
    { src: "fonts/NotoSansArabic-Regular.ttf" }, // script substitution picks this for Arabic
  ],
});
Font.registerHyphenationCallback((w) => [w]); // never split Arabic/CJK words

const RLM = "\u200F"; // wrap mixed AR/Latin/number strings so the BiDi engine orders them right
const ar = (s) => `${RLM}${s}${RLM}`;

const s = StyleSheet.create({
  page: { padding: 36, fontFamily: "Noto", fontSize: 10 },
  h1: { fontSize: 18, fontWeight: "bold", marginBottom: 8 },
  row: { flexDirection: "row", borderBottomWidth: 0.5, borderColor: "#ccc" },
  rowRtl: { flexDirection: "row-reverse" }, // react-pdf has NO `direction` prop — flip manually
  cell: { padding: 6, flexGrow: 1, flexBasis: 0 },
  thead: { backgroundColor: "#1F4E78", color: "#fff", fontWeight: "bold" },
  pageNo: { position: "absolute", bottom: 18, left: 0, right: 0, textAlign: "center", color: "#888" },
});

function Invoice({ rtl, rows }) {
  const dir = rtl ? s.rowRtl : s.row;
  return (
    <Document title="Invoice INV-2026-001" language={rtl ? "ar" : "en"}>
      <Page size="A4" style={s.page}>
        <Text style={s.h1}>{rtl ? ar("فاتورة") : "Invoice"}</Text>
        {/* `fixed` repeats this header row on EVERY page when the table breaks */}
        <View style={[dir, s.thead]} fixed>
          <Text style={s.cell}>{rtl ? ar("الوصف") : "Description"}</Text>
          <Text style={s.cell}>{rtl ? ar("المبلغ") : "Amount"}</Text>
        </View>
        {rows.map((r, i) => (
          <View key={i} style={dir} wrap={false}> {/* keep a row intact across a page break */}
            <Text style={s.cell}>{rtl ? ar(r.desc) : r.desc}</Text>
            <Text style={s.cell}>{r.amount}</Text>
          </View>
        ))}
        <Text style={s.pageNo} fixed
          render={({ pageNumber, totalPages }) => `${pageNumber} / ${totalPages}`} />
      </Page>
    </Document>
  );
}

export const buildInvoice = (props) => renderToBuffer(<Invoice {...props} />);
```

### 5e. pdf-lib + qpdf → merge, watermark, encrypt (post-processing)

```js
import { PDFDocument, StandardFonts, rgb, degrees } from "@cantoo/pdf-lib"; // maintained fork, 2.7.x

export async function mergeAndWatermark(buffers, mark = "CONFIDENTIAL") {
  const out = await PDFDocument.create();
  for (const bytes of buffers) {
    const src = await PDFDocument.load(bytes); // load({ password }) opens encrypted inputs
    const pages = await out.copyPages(src, src.getPageIndices());
    pages.forEach((p) => out.addPage(p));
  }
  const font = await out.embedFont(StandardFonts.HelveticaBold);
  for (const p of out.getPages()) {
    const { width, height } = p.getSize();
    p.drawText(mark, {
      x: width / 2 - 170, y: height / 2, size: 60, font,
      color: rgb(0.85, 0.1, 0.1), opacity: 0.12, rotate: degrees(45),
    });
  }
  return await out.save();
}
```

```bash
# Encryption + permissions: pdf-lib does NOT write encryption — use qpdf (AES-256).
qpdf --encrypt "$USER_PW" "$OWNER_PW" 256 \
     --print=low --modify=none --extract=n --accessibility=y -- in.pdf out.pdf
# Keep --accessibility=y so screen readers still work on protected files.
```

---

## 6. Edge cases & gotchas

- **Backgrounds vanish** in Puppeteer/Chrome unless `printBackground: true`. The #1 "my PDF looks blank-white" bug.
- **Fonts not loaded** → fallback glyphs/garbled text. Always `await document.fonts.ready` (Puppeteer) or embed a full subset.
- **Header/footer overlap body**: Chrome's `headerTemplate` lives in the *margin box*; if the margin is too small it clips. Size `margin.top/bottom` to the template height.
- **`headerTemplate` ignores external CSS** and renders at a tiny default font — inline all styles, set explicit `font-size`.
- **Chrome ordered-list tags**: lists inside `<ol>` were mis-tagged until Chrome M146 — verify with a checker if you rely on list semantics.
- **react-pdf is not CSS**: no `gap` on older versions, no `position: sticky`, flexbox subset only. Don't paste web CSS and expect parity.
- **Emoji / color fonts** rarely embed correctly — substitute SVG or a monochrome glyph.
- **Page-break control**: in HTML use `break-inside: avoid` / `break-before: page`; in react-pdf use `wrap={false}` and `break`.
- **PDF/A strips dynamic content**: no JavaScript, no external references, all fonts embedded, defined color spaces — a Ghostscript PDF/A pass over a Puppeteer file **removes the tag tree**.

---

## 7. Performance (large documents)

- **Reuse the browser, not the page.** Launching Chromium per request is the dominant cost. Keep a pool (see §9); `browser.newPage()` per job, `page.close()` after.
- **Cap concurrency** to ~CPU cores; each Chromium tab is memory-hungry. Backpressure with a queue.
- **Stream big outputs**: `page.createPDFStream()` (Puppeteer) instead of buffering 200 MB in memory.
- **WeasyPrint / Typst** have far lower per-doc overhead than a browser — prefer them for high-volume batch (statements, payroll).
- **Subset fonts** (don't embed full CJK/Arobic faces, ~10–20 MB each). react-pdf/Typst subset automatically; for HTML use `unicode-range` + subsetted `@font-face`.
- **Rasterize late, never early**: keep text as text. Converting to images bloats size and kills accessibility + search.
- **Cache** static assets/logos as data URIs or via a local file server to avoid per-render network fetches.

---

## 8. Security

- **HTML→PDF is an SSRF/LFI vector.** Chrome/WeasyPrint will fetch `file://`, internal URLs, and
  cloud metadata endpoints if your template includes attacker-controlled `<img src>`/`<link>`.
  Run headless with `--no-sandbox` **only** inside a locked-down container; block private IP
  ranges; disable `file://`; sanitize all user HTML (DOMPurify) before `setContent`.
- **Template injection**: never string-concatenate user data into HTML/JS. Escape (see `escapeHtml`)
  or render via a templating engine with autoescaping.
- **Encryption ≠ redaction.** Drawing a black box over text leaves the text selectable underneath.
  True redaction removes the content stream (use a redaction tool / `qpdf` + content removal), then
  flatten.
- **Permissions are advisory**: PDF "no-print/no-copy" flags are honored by polite viewers only.
  For real confidentiality use AES-256 with a strong user password (`qpdf … 256`).
- **Strip metadata** you didn't intend to ship (author, file paths, producer) before release.
- **Embedded files (PDF/A-3)**: validate/scan attachments; they're a malware carrier.

---

## 9. Scale / automation / batch

```js
// Browser pool — the single most important production pattern for HTML→PDF at scale.
import puppeteer from "puppeteer";
import genericPool from "generic-pool";

const pool = genericPool.createPool({
  create: () => puppeteer.launch({ headless: true, args: ["--no-sandbox"] }),
  destroy: (b) => b.close(),
}, { min: 1, max: Math.max(2, require("os").cpus().length) });

export async function renderInPool(html, opts) {
  const browser = await pool.acquire();
  try {
    const page = await browser.newPage();
    try { /* setContent + page.pdf(...) */ } finally { await page.close(); }
  } finally { await pool.release(browser); }
}
```

- **Serverless**: bundle `@sparticuz/chromium` + `puppeteer-core` for Lambda/Cloud Functions; or
  prefer **WeasyPrint/Typst** (no Chromium) to fit memory/cold-start limits.
- **Queue + idempotency**: drive batch jobs (10k statements) through a queue (SQS/BullMQ), key each
  job by document id so retries don't double-bill. Pair with `devops-master`.
- **Templating**: separate *data* (JSON) from *layout* (HTML/Typst template) so non-engineers can
  edit branding without redeploys.

---

## 10. Testing & validation

- **veraPDF** — the industry validator for **PDF/A and PDF/UA** conformance. Gate it in CI:

```bash
verapdf --flavour ua1 report.pdf   # exits non-zero on any UA-1 violation
verapdf --flavour 2b  report.pdf   # PDF/A-2b
```

- **PAC 2024** (PDF Accessibility Checker) for a human-readable UA report; **Acrobat Pro**
  "Accessibility Check" as a cross-check.
- **`pdfinfo file.pdf`** → confirm `Tagged: yes`, page count, PDF version; `pdffonts` → confirm every
  font is `emb yes` (embedded).
- **Visual regression**: render to PNG (`pdftoppm`) and diff against a golden with `pixelmatch` so a
  CSS/template change can't silently break layout.
- **Text assertions**: extract with `pdf-parse`/`pdftotext` and assert key strings exist (totals,
  legal lines) — proves text is selectable, not rasterized.

---

## 11. Accessibility (PDF/UA) & i18n / RTL Arabic

**PDF/UA-1 checklist** (what a tagged PDF must have):
- Every content element tagged with a semantic role: `H1…Hn`, `P`, `L/LI`, `Table/TR/TH/TD`, `Figure`.
- **Figures need `/Alt`** (alternative text); decorative graphics marked as **Artifacts**.
- **Logical reading order** independent of visual position; no content outside the tag tree.
- **Document Title** in metadata **and** `ViewerPreferences /DisplayDocTitle true` (show title, not filename).
- **Language** declared (`/Lang`), per-element overrides for mixed-language runs.
- **Headings hierarchical** (no H1→H3 jump). Typst/WeasyPrint will error or warn on violations.

Finish Puppeteer output's UA metadata (Chrome omits the XMP UA identifier):

```bash
# Inject the PDF/UA-1 identifier into XMP (Chrome/Puppeteer don't). exiftool-vendored works in Node too.
exiftool -XMP-pdfuaid:part=1 -Title="Q2 Report" -Language=en report.pdf
verapdf --flavour ua1 report.pdf   # confirm it now passes
```

**Arabic / RTL:**
- **Embed an Arabic-capable font** (Noto Sans Arabic, IBM Plex Sans Arabic, Cairo) — shaping +
  ligatures (initial/medial/final forms) come from HarfBuzz in WeasyPrint/Typst/Chrome.
- **HTML/WeasyPrint/Puppeteer**: set `dir="rtl"` and `lang="ar"`; the BiDi algorithm handles mixed
  Arabic + Latin + digits. This is the **easiest correct path** for Arabic PDFs.
- **react-pdf**: no native RTL. Flip with `flexDirection: "row-reverse"`, `textAlign: "right"`, and
  wrap mixed strings in RLM (`\u200F…\u200F`). For heavy RTL, use the HTML route or a helper lib.
- **Numbers/currency** in Arabic docs: keep Western digits LTR inside RTL text via BiDi marks so
  `AED 1,500` doesn't scramble.
- **i18n**: externalize strings; never hard-code; format dates/numbers per-locale (`Intl`).

---

## 12. Anti-patterns

- **Screenshot PDFs** — `page.screenshot()` into an image, or CSS `* { color: …; -webkit-print-color-adjust }` hacks that rasterize text. Kills search, a11y, size.
- **Treating Puppeteer `tagged:true` as PDF/UA-compliant.** It isn't — validate or use WeasyPrint/Typst.
- **No `<title>` / no `lang`** → instant PDF/UA failure and a window title that shows the filename.
- **Re-launching Chromium per request** → CPU/memory meltdown under load. Pool it.
- **Black-box "redaction"** that leaves selectable text underneath → data leak.
- **Full-font embedding** (no subset) → 20 MB invoices.
- **Combining PDF/A-1 + PDF/UA-1**, or claiming a 1.x subset on a PDF 2.0 file → validators reject it.
- **Building tables as absolutely-positioned divs** → they don't paginate; headers don't repeat.

---

## 13. Agent checklist

```
- [ ] Engine chosen from the matrix (fidelity vs UA/A vs stack), not by habit
- [ ] <title> + lang set; DisplayDocTitle true
- [ ] printBackground:true (Puppeteer) / pdf_tags:true (WeasyPrint) / right --pdf-standard (Typst)
- [ ] Fonts embedded + subset; document.fonts.ready awaited before render
- [ ] Tables paginate; header row repeats (fixed / thead); rows don't split awkwardly
- [ ] Running header/footer + "Page X / Y"
- [ ] Figures have Alt; decorative = artifact; reading order logical
- [ ] PDF/A or PDF/UA variant correct per the variant matrix; validated with veraPDF in CI
- [ ] Arabic/RTL: RTL-capable font embedded, dir=rtl (HTML) or row-reverse+RLM (react-pdf)
- [ ] Security: user HTML sanitized, SSRF/file:// blocked, metadata stripped, AES-256 if confidential
- [ ] Batch: browser pool + queue + idempotency; or WeasyPrint/Typst for high volume
```

---

## 14. References (2026)

- @react-pdf/renderer 4.5.x — https://react-pdf.org/ · repo https://github.com/diegomura/react-pdf
- Puppeteer `page.pdf` (tagged) — https://pptr.dev/api/puppeteer.pdfoptions · Playwright `page.pdf` — https://playwright.dev/docs/api/class-page#page-pdf
- WeasyPrint 69 API (pdf_variant / pdf_tags / pdf_forms) — https://doc.courtbouillon.org/weasyprint/stable/api_reference.html
- Typst PDF standards (`--pdf-standard`) — https://typst.app/docs · accessibility https://typst-in-production.com/pdf-accessibility/
- @cantoo/pdf-lib (maintained fork, encryption load) — https://www.npmjs.com/package/@cantoo/pdf-lib · pdf-lib docs https://pdf-lib.js.org
- qpdf (encryption/permissions) — https://qpdf.readthedocs.io
- PDF/UA-1 ISO 14289-1; PDF/UA-2 ISO 14289-2:2024 — https://www.iso.org/standard/82278.html
- PDF Association — "Conforming to both PDF/A & PDF/UA" — https://pdfa.org · WTPDF (Well-Tagged PDF)
- veraPDF validator — https://verapdf.org · PAC accessibility checker — https://pac.pdf-accessibility.org

---

## 15. Related

`anthropic-pdf` (read/extract), `blastum-markdown-to-pdf` (Markdown→PDF quick path),
`contracts-pro` (legal docs → PDF), `documentation-pro` (docs sites), `excel-pro-spreadsheets`
(tabular data source), `generating-images` (figures/branding). Cross-master: `devops-master`
(serverless/queues), `ui-master` + `color-design-master` (brand/templates), `business-master`
(e-invoicing: Factur-X in PDF/A-3).
