---
name: blastum-vision-ocr
description: Extracts text from scanned PDFs and images using Apple Vision OCR (macOS Live Text engine). No dependencies or API keys. Outputs per-page text files. Use when a PDF has no embedded text, when OCR output is preferred over pdfplumber, or when extracting text from photos or image files (JPEG, PNG, TIFF, HEIC, WebP).
---

# vision-ocr

On-device OCR using Apple's Vision framework (`VNRecognizeTextRequest`) — the same engine as Live Text in Photos.

## When to use

- PDF with no embedded text (scanned/image-only)
- Embedded text is sparse or garbled (< 100 chars/page average after `extract-pdf.py`)
- Input is an image file (receipt, whiteboard photo, document photo, etc.)

See [docs/usage.md](docs/usage.md) for full decision table, options, and output format.

## Quick start

```bash
# One-time compile (skip if binary already exists)
swiftc ~/.cursor/skills/vision-ocr/scripts/vision-ocr.swift \
  -framework PDFKit -framework Vision -framework Foundation -framework AppKit \
  -o ~/.cursor/skills/vision-ocr/scripts/vision-ocr

# Run
~/.cursor/skills/vision-ocr/scripts/vision-ocr <input> <output-dir>
```

See [scripts/README.md](scripts/README.md) for compile details and examples.
