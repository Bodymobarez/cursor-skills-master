---
name: gs1-barcodes
description: >-
  Work with GS1 standards and retail barcodes. Use for product identification —
  GTIN/EAN-13/UPC-A, SKUs, GS1-128, GS1 DataMatrix, GS1 Digital Link QR, SSCC,
  and check-digit validation. Covers symbology choice, encoding, Application
  Identifiers (AIs), and generation/validation.
---

# GS1 & Retail Barcodes

Generate and validate standards-compliant product/logistics barcodes.

## Identifiers (GS1 keys)

| Key | What | Length |
|-----|------|--------|
| **GTIN** | Global Trade Item Number (product) | GTIN-13 (EAN-13), GTIN-12 (UPC-A), GTIN-8, GTIN-14 |
| **SSCC** | Serial Shipping Container Code (pallet/case) | 18 |
| **GLN** | Global Location Number | 13 |

All end with a **mod-10 check digit** (compute it; never trust input).

```js
function gtinCheckDigit(body) { // body without check digit
  const d = body.split("").map(Number).reverse();
  const sum = d.reduce((s, n, i) => s + n * (i % 2 === 0 ? 3 : 1), 0);
  return (10 - (sum % 10)) % 10;
}
```

## Symbology — pick the right one

| Use case | Barcode |
|----------|---------|
| Retail point-of-sale (consumer unit) | **EAN-13 / UPC-A** (encodes GTIN) |
| Variable data / logistics (batch, expiry, weight) | **GS1-128** or **GS1 DataMatrix** |
| Small items / 2D scanning | **GS1 DataMatrix** |
| Web + POS in one code (modern) | **GS1 Digital Link** (a URL encoded as QR) |
| Outer cases/pallets | **ITF-14** (GTIN-14) / SSCC label |

## Application Identifiers (AIs) for GS1-128 / DataMatrix

```
(01) GTIN  (10) Batch/Lot  (11) Prod date  (17) Expiry (YYMMDD)
(21) Serial  (3103) Net weight kg  (00) SSCC
e.g.  (01)09506000134352(17)260531(10)ABC123
```

## Generation

| Stack | Library |
|-------|---------|
| Node | `bwip-js` (supports EAN-13, UPC-A, GS1-128, GS1 DataMatrix, ITF-14) |
| Python | `python-barcode` (EAN/UPC), `treepoem` (GS1-128/DataMatrix via BWIPP) |
| Browser | `bwip-js` (canvas/SVG) |

```js
import bwipjs from "bwip-js";
await bwipjs.toBuffer({ bcid: "ean13", text: "950600013435", includetext: true, scale: 3 });
// GS1-128 with AIs:
await bwipjs.toBuffer({ bcid: "gs1-128", text: "(01)09506000134352(17)260531(10)ABC123" });
```

## GS1 Digital Link (one code for web + retail)

Encode a URL like `https://id.gs1.org/01/09506000134352` (or your domain) as a QR — scans to a
landing page **and** carries the GTIN for POS. Bridge to `qr-code-generation` for rendering.

## Checklist
```
- [ ] Choose identifier (GTIN/SSCC/GLN) and compute/validate the check digit
- [ ] Pick symbology by use case (EAN-13 retail vs GS1-128/DataMatrix for variable data)
- [ ] Use correct AIs for batch/expiry/serial
- [ ] Generate at sufficient scale/DPI for print; include human-readable text
- [ ] Validate by scanning a printed sample
```

## Anti-patterns
- Inventing GTINs (must derive from a licensed GS1 company prefix for real retail).
- Wrong/absent check digit; wrong symbology for the use case.
- Encoding variable data in EAN-13 (use GS1-128/DataMatrix with AIs).
- Printing 2D codes too small / low DPI to scan.
