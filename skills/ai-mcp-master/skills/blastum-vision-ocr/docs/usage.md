# vision-ocr Usage

## Decision table

| Situation | Use |
|-----------|-----|
| PDF with embedded text | `extract-pdf.py` (faster, lossless) |
| PDF with embedded text but garbled / < 100 chars/page | `vision-ocr` |
| Scanned / image-only PDF | `vision-ocr` |
| Image file (JPEG, PNG, TIFF, HEIC, WebP, BMP, GIF) | `vision-ocr` |
| Need cloud-quality handwriting recognition | Cloud OCR (Google Vision, AWS Textract) |

## One-time compile

```bash
swiftc ~/.cursor/skills/vision-ocr/scripts/vision-ocr.swift \
  -framework PDFKit -framework Vision -framework Foundation -framework AppKit -framework CoreText -framework ImageIO \
  -o ~/.cursor/skills/vision-ocr/scripts/vision-ocr
```

Requires macOS 13+, Xcode Command Line Tools. Verify: `swiftc --version`

## CLI reference

```
vision-ocr <input> <output-dir> [--dpi 200] [--lang en-US] [--fast] [--pdf <path>]
```

| Option | Default | Notes |
|--------|---------|-------|
| `--dpi` | `200` | PDF rasterization DPI. Use 300 for small or dense text. Higher = slower. |
| `--lang` | `en-US` | BCP-47 language hint passed to Vision. |
| `--fast` | off | Uses `.fast` recognition level. Faster but lower accuracy. |
| `--pdf` | — | If set, write a searchable PDF to `<path>` (page image + invisible text layer; same look, text selectable/searchable). |

## Output format

```
output-dir/
├── page-001.txt      # one file per page (PDFs) or single file (images)
├── page-002.txt
└── manifest.json
```

`manifest.json`:

```json
{
  "accuracy": "accurate",
  "dpi": 200,
  "input_type": "pdf",
  "language": "en-US",
  "page_count": 4,
  "source": "filename.pdf",
  "timestamp": "2026-02-23T..."
}
```

## Supported image formats

JPEG, PNG, TIFF, HEIC (macOS 11+), WebP, BMP, GIF — any format supported by macOS ImageIO.

## Integration with notebook skill

In the notebook acquire workflow, after running `extract-pdf.py`:

```bash
# Check if output is sparse
wc -c documents/{slug}-extracted.txt   # < (page_count × 100) bytes → use OCR

~/.cursor/skills/vision-ocr/scripts/vision-ocr \
  documents/{slug}.pdf \
  documents/{slug}-ocr/

# Set in metadata/{slug}.meta.md:
# ocr_output_dir: documents/{slug}-ocr/
```

For image sources:

```bash
~/.cursor/skills/vision-ocr/scripts/vision-ocr \
  documents/{slug}.jpg \
  documents/{slug}-ocr/
# page-001.txt is the full extracted content
```

## Known limitations

- Handwriting accuracy is lower than printed text.
- Multi-column layouts may produce interleaved lines (Vision reads top-to-bottom, left-to-right per line, not per column).
- Very low DPI scans or heavy noise degrades accuracy; try `--dpi 300` first.
- HEIC requires macOS 11+.
- No table structure recovery — output is plain text lines.
