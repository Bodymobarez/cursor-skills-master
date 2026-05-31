# vision-ocr script

Single-file Swift CLI. No Swift packages or external dependencies.

## Requirements

- macOS 13+ (Apple Silicon or Intel)
- Xcode Command Line Tools: `xcode-select --install`

## Compile

```bash
swiftc vision-ocr.swift \
  -framework PDFKit -framework Vision -framework Foundation -framework AppKit -framework CoreText -framework ImageIO \
  -o vision-ocr
```

Or from repo root:

```bash
swiftc .cursor/skills/vision-ocr/scripts/vision-ocr.swift \
  -framework PDFKit -framework Vision -framework Foundation -framework AppKit -framework CoreText -framework ImageIO \
  -o .cursor/skills/vision-ocr/scripts/vision-ocr
```

The binary is gitignored; only the `.swift` source is committed.

## Supported inputs

| Format | Extension |
|--------|-----------|
| PDF (image-only or mixed) | `.pdf` |
| JPEG | `.jpg`, `.jpeg` |
| PNG | `.png` |
| TIFF | `.tif`, `.tiff` |
| HEIC | `.heic` |
| WebP | `.webp` |
| BMP | `.bmp` |
| GIF | `.gif` |

## Examples

```bash
# Scanned PDF, default settings
./vision-ocr scan.pdf ./out/

# High-resolution PDF with small text
./vision-ocr dense.pdf ./out/ --dpi 300

# Image file
./vision-ocr receipt.jpg ./out/

# French document, fast mode
./vision-ocr doc.pdf ./out/ --lang fr-FR --fast

# Also write a searchable PDF (same appearance, invisible text layer for search/select)
./vision-ocr scan.pdf ./out/ --pdf ./out/scan-searchable.pdf
```

## Output

```
out/
├── page-001.txt
├── page-002.txt   # PDFs only
└── manifest.json
```

With `--pdf <path>`: a searchable PDF is written to `<path>` (page image + invisible text layer; selectable and searchable in Preview/Adobe).
