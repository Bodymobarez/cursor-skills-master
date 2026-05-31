# Markdown Exporter Guide

## Installation

```bash
uv tool install md-exporter
```

Verify: `markdown-exporter -h`

All dependencies (including pandoc) are bundled — no external installs needed.

## Common Pattern

```bash
markdown-exporter <tool> <input_file> <output_file> [options]
```

Input is always a markdown file path. Output is a file path (or directory for `md_to_codeblock`).

### Global Option

`--strip-wrapper` — removes surrounding code fence (triple backticks) from input before processing. Available on most tools.

## Tool Details

### Document Converters

**md_to_docx** — Markdown to Word
```bash
markdown-exporter md_to_docx input.md output.docx [--template template.docx] [--strip-wrapper]
```
`--template` applies custom DOCX styling (fonts, headings, spacing).

**md_to_pdf** — Markdown to PDF
```bash
markdown-exporter md_to_pdf input.md output.pdf [--strip-wrapper]
```

**md_to_html** — Markdown to HTML file
```bash
markdown-exporter md_to_html input.md output.html [--strip-wrapper]
```

**md_to_html_text** — Markdown to HTML on stdout (no output file)
```bash
markdown-exporter md_to_html_text input.md
```

**md_to_png** — Markdown to PNG images (one per page)
```bash
markdown-exporter md_to_png input.md output.png [--compress] [--strip-wrapper]
```
`--compress` bundles all pages into a ZIP.

**md_to_md** — Save markdown to file
```bash
markdown-exporter md_to_md input.md output.md
```

**md_to_ipynb** — Markdown to Jupyter Notebook
```bash
markdown-exporter md_to_ipynb input.md output.ipynb [--strip-wrapper]
```

### Presentation

**md_to_pptx** — Markdown to PowerPoint (input must use [Pandoc slide syntax](https://pandoc.org/MANUAL.html#slide-shows))
```bash
markdown-exporter md_to_pptx input.md output.pptx [--template template.pptx]
```

### Table Converters

These tools extract markdown tables from the input file.

**md_to_xlsx** — Tables to Excel
```bash
markdown-exporter md_to_xlsx input.md output.xlsx [--force-text True|False] [--strip-wrapper]
```
`--force-text` (default True) forces all cells to text type.

**md_to_csv** — Tables to CSV
```bash
markdown-exporter md_to_csv input.md output.csv [--strip-wrapper]
```

**md_to_json** — Tables to JSON/JSONL
```bash
markdown-exporter md_to_json input.md output.json [--style jsonl|json_array] [--strip-wrapper]
```
Default style is `jsonl` (one object per line).

**md_to_xml** — Tables to XML
```bash
markdown-exporter md_to_xml input.md output.xml [--strip-wrapper]
```

**md_to_latex** — Tables to LaTeX
```bash
markdown-exporter md_to_latex input.md output.tex [--strip-wrapper]
```

### Code Extraction

**md_to_codeblock** — Extract fenced code blocks to individual files
```bash
markdown-exporter md_to_codeblock input.md output_dir [--compress]
```
`--compress` outputs a ZIP file instead of a directory. Supports Python, JS, Bash, HTML, CSS, YAML, Ruby, Java, PHP, JSON, XML, SVG, Markdown.

## Notes

- Multiple tables/code blocks in one file produce numbered output files automatically.
- Python 3.11+ required.
- Source: [bowenliang123/markdown-exporter](https://github.com/bowenliang123/markdown-exporter)
