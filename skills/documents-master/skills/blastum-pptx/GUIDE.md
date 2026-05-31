---
name: blastum-pptx
description: "Presentation creation, editing, and analysis. When Claude needs to work with presentations (.pptx files) for: (1) Creating new presentations, (2) Modifying or editing content, (3) Working with layouts, (4) Adding comments or speaker notes, or any other presentation tasks"
---

# PPTX creation, editing, and analysis

## Quick Reference

| Task | Method | Reference |
|------|--------|-----------|
| **Read text** | `markitdown` | Text extraction |
| **Create from scratch** | HTML2PPTX | [📄 HTML2PPTX Guide](html2pptx.md) |
| **Edit existing** | OOXML | [🔧 OOXML Reference](ooxml.md) |
| **Use template** | Rearrange + Replace | Template workflow |
| **Visual analysis** | Thumbnails | Thumbnail grids |

## Overview

A user may ask you to create, edit, or analyze the contents of a .pptx file. A .pptx file is essentially a ZIP archive containing XML files and other resources that you can read or edit. You have different tools and workflows available for different tasks.

## Reading and analyzing content

### Text extraction
If you just need to read the text contents of a presentation, you should convert the document to markdown:

```bash
# Convert document to markdown
python -m markitdown path-to-file.pptx
```

### Raw XML access
You need raw XML access for: comments, speaker notes, slide layouts, animations, design elements, and complex formatting. For any of these features, you'll need to unpack a presentation and read its raw XML contents.

#### Unpacking a file
`python ooxml/scripts/unpack.py <path-to-pptx>`

**Note**: The unpack.py script is located at `skills/pptx/ooxml/scripts/unpack.py` relative to the project root. If the script doesn't exist at this path, use `find . -name "unpack.py"` to locate it.

#### Key file structures
* `ppt/presentation.xml` - Main presentation metadata and slide references
* `ppt/slides/slide{N}.xml` - Individual slide contents (slide1.xml, slide2.xml, etc.)
* `ppt/notesSlides/notesSlide{N}.xml` - Speaker notes for each slide
* `ppt/comments/modernComment_*.xml` - Comments for specific slides
* `ppt/slideLayouts/` - Layout templates for slides
* `ppt/slideMasters/` - Master slide templates
* `ppt/theme/` - Theme and styling information
* `ppt/media/` - Images and other media files

#### Typography and color extraction
**When given an example design to emulate**: Always analyze the presentation's typography and colors first using the methods below:
1. **Read theme file**: Check `ppt/theme/theme1.xml` for colors (`<a:srgbClr>`) and fonts (`<a:latin>`)
2. **Sample slide content**: Examine `ppt/slides/slide1.xml` for actual font usage (`<a:rPr>`) and colors
3. **Search for patterns**: Use grep to find color (`<a:srgbClr>`, `<a:schemeClr>`) and font references across all XML files

## Creating a new PowerPoint presentation **without a template**

When creating a new PowerPoint presentation from scratch, use the **html2pptx** workflow to convert HTML slides to PowerPoint with accurate positioning.

### Design Principles

**CRITICAL**: Before creating any presentation, analyze the content and choose appropriate design elements:
1. **Consider the subject matter**: What is this presentation about? What tone, industry, or mood does it suggest?
2. **Check for branding**: If the user mentions a company/organization, consider their brand colors and identity
3. **Match palette to content**: Select colors that reflect the subject
4. **State your approach**: Explain your design choices before writing code

**Requirements**:
- ✅ State your content-informed design approach BEFORE writing code
- ✅ Use web-safe fonts only: Arial, Helvetica, Times New Roman, Georgia, Courier New, Verdana, Tahoma, Trebuchet MS, Impact
- ✅ Create clear visual hierarchy through size, weight, and color
- ✅ Ensure readability: strong contrast, appropriately sized text, clean alignment
- ✅ Be consistent: repeat patterns, spacing, and visual language across slides

#### Color Palette Selection

**Choosing colors creatively**:
- **Think beyond defaults**: What colors genuinely match this specific topic? Avoid autopilot choices.
- **Consider multiple angles**: Topic, industry, mood, energy level, target audience, brand identity (if mentioned)
- **Be adventurous**: Try unexpected combinations - a healthcare presentation doesn't have to be green, finance doesn't have to be navy
- **Build your palette**: Pick 3-5 colors that work together (dominant colors + supporting tones + accent)
- **Ensure contrast**: Text must be clearly readable on backgrounds

**Example color palettes** (choose one, adapt it, or create your own):

| Palette | Colors |
|---------|--------|
| **Classic Blue** | Navy (#1C2833), slate (#2E4053), silver (#AAB7B8), white (#F4F6F6) |
| **Teal & Coral** | Teal (#5EA8A7), coral (#FE4447), white (#FFFFFF) |
| **Bold Red** | Red (#C0392B), orange (#F39C12), yellow (#F1C40F) |
| **Deep Purple** | Purple (#B165FB), emerald (#40695B), white (#FFFFFF) |
| **Forest Green** | Green (#4E9F3D), dark green (#1E5128), white (#FFFFFF) |
| **Warm Blush** | Mauve (#A49393), blush (#EED6D3), cream (#FAF7F2) |

**Tip**: Match colors to your content's topic, industry, and mood rather than using defaults.

#### Visual Details Options

**Key patterns for creative layouts:**
- **Typography**: Size contrast, all-caps headers, monospace for data
- **Borders**: Thick single-side borders, corner brackets, L-shaped accents
- **Charts**: Monochrome with accent colors, horizontal bars, minimal grids
- **Layouts**: Two-column preferred, full-bleed images, sidebar navigation
- **Backgrounds**: Solid color blocks, gradients, split designs

See [📄 HTML2PPTX Guide](html2pptx.md) for complete styling syntax and examples.

### Layout Tips
**When creating slides with charts or tables:**
- **Two-column layout (PREFERRED)**: Use a header spanning the full width, then two columns below - text/bullets in one column and the featured content in the other. This provides better balance and makes charts/tables more readable. Use flexbox with unequal column widths (e.g., 40%/60% split) to optimize space for each content type.
- **Full-slide layout**: Let the featured content (chart/table) take up the entire slide for maximum impact and readability
- **NEVER vertically stack**: Do not place charts/tables below text in a single column - this causes poor readability and layout issues

### Workflow
1. **MANDATORY - READ ENTIRE FILE**: Read [📄 HTML2PPTX Guide](html2pptx.md) completely from start to finish. **NEVER set any range limits when reading this file.** Read the full file content for detailed syntax, critical formatting rules, and best practices before proceeding with presentation creation.
2. Create an HTML file for each slide with proper dimensions (e.g., 720pt × 405pt for 16:9)
 - Use `<div>`, `<h1>`-`<h6>`, `<p>` for all text content
 - Use `class="placeholder"` for areas where charts/tables will be added (render with gray background for visibility)
 - **CRITICAL**: Rasterize gradients and icons as PNG images FIRST using Sharp, then reference in HTML
 - **LAYOUT**: For slides with charts/tables/images, use either full-slide layout or two-column layout for better readability
3. Create and run a JavaScript file using the [`html2pptx.js`](scripts/html2pptx.js) library to convert HTML slides to PowerPoint and save the presentation
 - Use the `html2pptx()` function to process each HTML file
 - Add charts and tables to placeholder areas using PptxGenJS API
 - Save the presentation using `pptx.writeFile()`
4. **Visual validation**: Generate thumbnails and inspect for layout issues
 - Create thumbnail grid: `python scripts/thumbnail.py output.pptx workspace/thumbnails --cols 4`
 - Read and carefully examine the thumbnail image for:
 - **Text cutoff**: Text being cut off by header bars, shapes, or slide edges
 - **Text overlap**: Text overlapping with other text or shapes
 - **Positioning issues**: Content too close to slide boundaries or other elements
 - **Contrast issues**: Insufficient contrast between text and backgrounds
 - If issues found, adjust HTML margins/spacing/colors and regenerate the presentation
 - Repeat until all slides are visually correct

## Editing an existing PowerPoint presentation

When edit slides in an existing PowerPoint presentation, you need to work with the raw Office Open XML (OOXML) format. This involves unpacking the .pptx file, editing the XML content, and repacking it.

### Workflow
1. **MANDATORY - READ ENTIRE FILE**: Read [🔧 OOXML Reference](ooxml.md) (~500 lines) completely from start to finish. **NEVER set any range limits when reading this file.** Read the full file content for detailed guidance on OOXML structure and editing workflows before any presentation editing.
2. Unpack the presentation: `python ooxml/scripts/unpack.py <path-to-pptx>`
3. Edit the XML files (primarily `ppt/slides/slide{N}.xml` and related files)
4. **CRITICAL**: Validate immediately after each edit and fix any validation errors before proceeding: `python ooxml/scripts/validate.py --original <original-pptx> <unpacked-dir>`
5. Pack the final presentation: `python ooxml/scripts/pack.py <unpacked-dir> <output-pptx>`

## Creating a new PowerPoint presentation **using a template**

When you need to create a presentation that follows an existing template's design, you'll need to duplicate and re-arrange template slides before then replacing placeholder context.

### Workflow
1. **Extract template content**: `python -m markitdown template.pptx > template-content.md`
2. **Create thumbnails**: `python scripts/thumbnail.py template.pptx`
3. **Analyze and inventory**: Create `template-inventory.md` with slide descriptions and 0-based indices
4. **Map content to slides**: Select appropriate template slides for each content section

3. **Create outline**: Map content to appropriate template slides (0-based indexing)
4. **Rearrange slides**: `python scripts/rearrange.py template.pptx working.pptx 0,34,34,50,52`

5. **Extract text inventory**: `python scripts/inventory.py working.pptx text-inventory.json`
6. **Generate replacements**: Create `replacement-text.json` with proper paragraph formatting (see [🔧 OOXML Reference](ooxml.md) for details)
7. **Apply replacements**: `python scripts/replace.py working.pptx replacement-text.json output.pptx`

## Creating Thumbnail Grids

To create visual thumbnail grids of PowerPoint slides for quick analysis and reference:

```bash
python scripts/thumbnail.py template.pptx [output_prefix]
```

**Features**:
- Creates: `thumbnails.jpg` (or `thumbnails-1.jpg`, `thumbnails-2.jpg`, etc. for large decks)
- Default: 5 columns, max 30 slides per grid (5×6)
- Custom prefix: `python scripts/thumbnail.py template.pptx my-grid`
 - Note: The output prefix should include the path if you want output in a specific directory (e.g., `workspace/my-grid`)
- Adjust columns: `--cols 4` (range: 3-6, affects slides per grid)
- Grid limits: 3 cols = 12 slides/grid, 4 cols = 20, 5 cols = 30, 6 cols = 42
- Slides are zero-indexed (Slide 0, Slide 1, etc.)

**Use cases**:
- Template analysis: Quickly understand slide layouts and design patterns
- Content review: Visual overview of entire presentation
- Navigation reference: Find specific slides by their visual appearance
- Quality check: Verify all slides are properly formatted

**Examples**:
```bash
# Basic usage
python scripts/thumbnail.py presentation.pptx

# Combine options: custom name, columns
python scripts/thumbnail.py template.pptx analysis --cols 4
```

## Converting Slides to Images

To visually analyze PowerPoint slides, convert them to images using a two-step process:

1. **Convert PPTX to PDF**:
 ```bash
 soffice --headless --convert-to pdf template.pptx
 ```

2. **Convert PDF pages to JPEG images**:
 ```bash
 pdftoppm -jpeg -r 150 template.pdf slide
 ```
 This creates files like `slide-1.jpg`, `slide-2.jpg`, etc.

Options:
- `-r 150`: Sets resolution to 150 DPI (adjust for quality/size balance)
- `-jpeg`: Output JPEG format (use `-png` for PNG if preferred)
- `-f N`: First page to convert (e.g., `-f 2` starts from page 2)
- `-l N`: Last page to convert (e.g., `-l 5` stops at page 5)
- `slide`: Prefix for output files

Example for specific range:
```bash
pdftoppm -jpeg -r 150 -f 2 -l 5 template.pdf slide # Converts only pages 2-5
```

## Code Style Guidelines
**IMPORTANT**: When generating code for PPTX operations:
- Write concise code
- Avoid verbose variable names and redundant operations
- Avoid unnecessary print statements

## Dependencies

Required dependencies (should already be installed):

- **markitdown**: `pip install "markitdown[pptx]"` (for text extraction from presentations)
- **pptxgenjs**: `npm install -g pptxgenjs` (for creating presentations via html2pptx)
- **playwright**: `npm install -g playwright` (for HTML rendering in html2pptx)
- **react-icons**: `npm install -g react-icons react react-dom` (for icons)
- **sharp**: `npm install -g sharp` (for SVG rasterization and image processing)
- **LibreOffice**: `sudo apt-get install libreoffice` (for PDF conversion)
- **Poppler**: `sudo apt-get install poppler-utils` (for pdftoppm to convert PDF to images)
- **defusedxml**: `pip install defusedxml` (for secure XML parsing)

## Additional Resources

For complete implementation details:
- [🔧 OOXML Reference](ooxml.md) - Technical patterns for PowerPoint XML manipulation
- [📄 HTML2PPTX Guide](html2pptx.md) - JavaScript workflow for creating presentations
- [Presentation Scripts](scripts/) - Utility scripts for presentation processing