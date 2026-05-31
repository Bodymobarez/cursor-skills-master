---
name: brand-identity-creator
description: >-
  Create a complete brand identity end-to-end — logo, color system, typography,
  voice, and a full brand book. Use when the user wants a brand, visual identity,
  logo, brand guidelines, style guide, rebrand, or design system foundations.
  Produces SVG logos, design tokens (CSS/Tailwind/JSON), and a BRAND.md guideline
  doc, and orchestrates logo image generation when a raster/AI logo is requested.
---

# Brand Identity Creator

Build a cohesive, professional brand identity: **strategy → logo → color → type → voice →
brand book → deliverable assets**. Output is production-ready (SVG + design tokens + docs), not
just mockups.

## When to use

- "Make me a brand / visual identity / logo / brand guidelines / style guide."
- Rebrands, naming a design system's visual foundation, or a startup launch kit.

## Deliverables (what you produce)

1. **Brand strategy brief** — positioning, audience, personality, keywords, competitors.
2. **Logo suite** — primary (SVG), simplified/mark-only, monochrome, favicon, clear-space rules.
3. **Color system** — primary/secondary/accent + neutrals, semantic tokens, WCAG contrast pairs.
4. **Typography** — display + body pairing (Google Fonts), scale, weights, usage.
5. **Voice & tone** — 3–5 principles + do/don't examples.
6. **Brand book** — `BRAND.md` tying it all together.
7. **Design tokens** — `tokens.css`, `tailwind` snippet, and `tokens.json`.

---

## Workflow

```
- [ ] 1. Strategy brief — interview or infer: what, who, personality, 5 keywords, avoid-list.
- [ ] 2. Pick a visual direction (style + mood) aligned to industry.
- [ ] 3. Design the logo (SVG-first; generate raster/AI variant if requested).
- [ ] 4. Build the color system (with contrast checks).
- [ ] 5. Choose the type pairing + scale.
- [ ] 6. Define voice & tone.
- [ ] 7. Emit tokens (CSS/Tailwind/JSON) + BRAND.md + asset files.
```

### Step 1 — Strategy brief

Capture (ask if missing): brand name, one-line description, industry, target audience, 3–5
personality adjectives (e.g. *trustworthy, modern, bold*), competitors to differentiate from,
and an **avoid-list** (e.g. "no AI purple/pink gradients" for finance).

### Step 2 — Visual direction

Map personality + industry → a style and mood. Examples:

| Industry / vibe | Style direction | Color mood | Type mood |
|---|---|---|---|
| Fintech / trust | Minimal, geometric | Deep blue + green accent | Grotesque sans + clean sans |
| Wellness / calm | Soft, organic | Sage + warm neutrals + gold | Elegant serif + humanist sans |
| Dev tool / bold | Brutalist/technical | Near-black + electric accent | Mono + grotesque |
| Luxury / editorial | Exaggerated minimal | Black/cream + 1 accent | High-contrast serif |

> If `ui-ux-pro-max` is available in this master, use its style/color/typography databases to
> ground these choices.

### Step 3 — Logo design

**SVG-first (preferred — scalable, editable, versionable):**
- Build the mark as clean SVG paths (a wordmark, a monogram, or an abstract mark).
- Provide variants: **primary**, **mark-only**, **monochrome (black & white)**, **favicon**.
- Define **clear space** (min padding = height of a key glyph) and **min size**.

```svg
<!-- example primary wordmark scaffold -->
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 240 64" role="img" aria-label="BrandName">
  <rect x="0" y="0" width="64" height="64" rx="14" fill="#2563EB"/>
  <path d="M20 44V20h10a8 8 0 0 1 0 16H24" fill="none" stroke="#fff" stroke-width="6"/>
  <text x="80" y="42" font-family="Inter, sans-serif" font-size="32" font-weight="700"
        fill="#0F172A">Brand</text>
</svg>
```

**AI/raster logo** (when the user wants a rich illustrative logo): orchestrate the
`generating-images` skill (in `documents-master`) or any available image tool. Prompt recipe:

```text
"<style> logo for <brand>, <personality keywords>, <symbol idea>, flat vector, solid
background, centered, no text" (then add the wordmark in SVG for crispness)
```

Always still ship a **vector wordmark** for UI/favicon use even if the mark is AI-generated.

### Step 4 — Color system

- Define **primary, secondary, accent (CTA)**, plus a **neutral ramp** (50→900) and **semantic**
  colors (success/warning/error/info).
- **Verify contrast**: body text vs background ≥ 4.5:1; large text/UI ≥ 3:1 (WCAG AA).
- Provide HEX + the token name for each.

### Step 5 — Typography

- Pick a **pairing**: a display/heading face + a body face (default to Google Fonts for easy
  embedding). Provide the `@import`/link, the **type scale** (e.g. 12/14/16/20/24/32/48), and
  weight usage.

### Step 6 — Voice & tone

3–5 principles, each with a one-line rule + a do/don't example. e.g. *"Confident, not arrogant —
‘Ship faster.’ not ‘The undisputed #1 platform.’"*

### Step 7 — Emit deliverables

**`tokens.css`**
```css
:root {
  --color-primary: #2563EB;
  --color-accent:  #10B981;
  --color-bg:      #0F172A;
  --color-text:    #F8FAFC;
  --font-display: "Sora", sans-serif;
  --font-body:    "Inter", sans-serif;
  --radius: 14px;
}
```

**`tokens.json`** (for design tools / Style Dictionary) and a **Tailwind** `theme.extend` snippet
mirroring the same values.

**`BRAND.md`** structure:
```markdown
# <Brand> — Brand Guidelines
## 1. Brand at a glance (positioning, personality, keywords)
## 2. Logo (variants, clear space, min size, misuse examples)
## 3. Color (palette, tokens, contrast pairs, usage ratios)
## 4. Typography (pairing, scale, weights, do/don't)
## 5. Voice & tone (principles + examples)
## 6. Assets (file list & where to use each)
```

---

## Pre-delivery checklist

```
- [ ] Logo works at 16px (favicon) and on light AND dark backgrounds
- [ ] Monochrome logo version exists
- [ ] All text/bg color pairs pass WCAG AA (4.5:1 body, 3:1 large/UI)
- [ ] Type pairing has a clear hierarchy; fonts are embeddable/licensed
- [ ] Tokens exported in CSS + JSON (+ Tailwind if relevant)
- [ ] BRAND.md complete with misuse examples
- [ ] No industry anti-patterns (e.g. generic AI gradients for finance/legal)
```

## Anti-patterns

- Raster-only logo with no vector → breaks at scale and as favicon.
- Color palette without contrast verification.
- More than 2 type families without reason.
- "Brand" delivered as a single image with no tokens/docs (not reusable).
- Trend-chasing that fights the brand's personality.
