---
name: qr-code-generation
description: >-
  Generate and decode QR codes professionally. Use when the user wants QR codes —
  URLs, vCards, Wi-Fi, payments, event tickets, dynamic/trackable QR, styled/
  branded QR with logos, or batch generation. Covers libraries, error correction,
  styling, dynamic redirects, and scanning/decoding.
---

# QR Code Generation

Generate, style, decode, and track QR codes for web/mobile/print.

## Library by stack

| Stack | Library |
|-------|---------|
| Node/JS | `qrcode` (generate), `jsQR` / `@zxing/library` (decode) |
| Browser styled | `qr-code-styling` (logos, gradients, shapes) |
| Python | `qrcode[pil]` (generate), `opencv`/`pyzbar` (decode) |
| Go | `skip2/go-qrcode` |

## Static QR (basic)

```js
import QRCode from "qrcode";
await QRCode.toFile("out.png", "https://example.com", {
  errorCorrectionLevel: "M",   // L 7% / M 15% / Q 25% / H 30%
  margin: 2, width: 512,
  color: { dark: "#0F172A", light: "#FFFFFF" },
});
// also: QRCode.toString(data, { type: "svg" })  → crisp, scalable, print-ready
```

> Prefer **SVG** for print/branding (infinite scale). Use **error correction H (30%)** when
> placing a logo so the code still scans with the center covered.

## Encoded payload formats (use exact syntax)

```
URL:     https://example.com
vCard:   BEGIN:VCARD\nVERSION:3.0\nFN:Name\nTEL:+1...\nEMAIL:..\nEND:VCARD
Wi-Fi:   WIFI:T:WPA;S:<ssid>;P:<password>;;
Email:   mailto:x@y.com?subject=..&body=..
SMS:     SMSTO:+123:message
Geo:     geo:30.0444,31.2357
Event:   BEGIN:VEVENT\nSUMMARY:..\nDTSTART:..\nDTEND:..\nEND:VEVENT
Payment: follow the local scheme (e.g. EMVCo merchant QR string)
```

## Styled / branded QR (logo in center)

Use `qr-code-styling` (browser/Node) — set high error correction, then overlay a logo at ≤ 20%
of the code size, keep quiet zone (≥ 4 modules), and ensure strong dark/light contrast.

```js
import QRCodeStyling from "qr-code-styling";
new QRCodeStyling({ width: 512, height: 512, data: url,
  qrOptions: { errorCorrectionLevel: "H" },
  image: "/logo.png",
  imageOptions: { imageSize: 0.2, margin: 4 },
  dotsOptions: { type: "rounded", color: "#2563EB" },
});
```

## Dynamic / trackable QR (recommended for marketing)

Encode a **short redirect URL you control** (not the final destination):
```
QR → https://qr.yoursite.com/abc123 → 302 → real destination
```
Benefits: change destination without reprinting, and **log scans** (ts, geo, device) for
analytics. Store `code → destination` and a `scans` table.

## Checklist
```
- [ ] Pick payload format; validate the encoded string
- [ ] Error correction: M default; H if adding a logo
- [ ] SVG for print, PNG for screen; keep quiet zone (≥4 modules)
- [ ] Test contrast + scan on a real phone before shipping/printing
- [ ] Dynamic redirect + scan logging if tracking is needed
- [ ] Decoding path (camera) — see camera-ai-vision for live scanning
```

## Anti-patterns
- Logo too big / low error correction → won't scan.
- No quiet zone (border) → scanners fail.
- Inverted colors (light dark-modules on dark bg) → many readers fail.
- Encoding a long URL directly when you need to edit it later (use a dynamic redirect).
