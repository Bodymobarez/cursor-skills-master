---
name: ultra-hd-visual-rendering
description: >-
  Make UI render with ultra-high-definition, razor-sharp "8K-grade" visual quality.
  Use when the user wants crisp/retina/high-DPI output, pin-sharp text and icons,
  wide-gamut (P3) color, high-resolution image pipelines, print-grade exports, or
  pixel-perfect rendering on any display. Covers vector-first assets, DPR handling,
  color management, and crisp typography.
---

# Ultra-HD Visual Rendering ("8K-grade" crispness)

Make everything look pin-sharp on any screen — like watching 8K. Crispness comes from
**vector-first assets, correct device-pixel handling, wide-gamut color, and clean typography** —
not from "bigger PNGs".

## 1. Vector-first (resolution-independent = infinitely sharp)
- Prefer **SVG** for icons, logos, illustrations, charts, borders, backgrounds — scales to any DPI
  with zero blur. Optimize with SVGO; inline critical SVGs.
- Use icon systems as SVG (Lucide/Phosphor/Tabler), never icon-font bitmaps or low-res PNGs.
- CSS does the heavy lifting (gradients, shadows, shapes, masks) — all vector, all crisp.

## 2. High-DPI / Retina handling (the core of "8K")
- **Canvas/WebGL**: render at `devicePixelRatio` — set `canvas.width = cssWidth * dpr` and
  `ctx.scale(dpr, dpr)`; otherwise it's blurry on retina.
```js
const dpr = window.devicePixelRatio || 1;
canvas.width = cssW * dpr; canvas.height = cssH * dpr;
canvas.style.width = cssW + "px"; canvas.style.height = cssH + "px";
ctx.scale(dpr, dpr);
```
- **Raster images**: ship `srcset`/`densities` for 1x/2x/3x; use `image-set()` in CSS.
- Prefer **AVIF → WebP → fallback**; serve responsive sizes; never upscale a small raster.
- Use `<img>` `sizes` + `loading`/`decoding` so high-res loads without jank.

## 3. Wide-gamut color (P3) — richer, deeper than sRGB
```css
:root { --brand: #2563eb; }
@supports (color: color(display-p3 1 1 1)) {
  :root { --brand: color(display-p3 0.18 0.36 0.96); } /* punchier on P3 displays */
}
/* modern color: oklch() for perceptually-uniform, vivid ramps */
--accent: oklch(0.72 0.19 256);
```
- Use **OKLCH/OKLAB** for color ramps (perceptually uniform → smooth, no muddy midtones).
- Tag exported images with a color profile; design in P3 where supported, sRGB fallback.

## 4. Razor-sharp typography
- High-quality variable fonts; enable `text-rendering: optimizeLegibility` and
  `-webkit-font-smoothing: antialiased` (use deliberately).
- Use real font features: `font-feature-settings`/`font-variation-settings` (weight, optical size),
  kerning, ligatures. Optical sizing makes large display type crisp.
- Subpixel-safe layout: avoid fractional px on text containers; snap to the grid.
- Fluid, generous type scale; tight tracking on headings, comfortable line-height on body.

## 5. Crisp borders, shadows & effects
- 1px hairlines on retina: use `0.5px` or `1px / dpr`, or SVG strokes (never blurry).
- Layered, soft, realistic shadows (multiple low-opacity layers) instead of one harsh shadow.
- `backdrop-filter` blur for glass; ensure `will-change`/compositing for smooth, sharp results.
- Avoid CSS filters that rasterize at low res on transforms; test on retina + zoom.

## 6. High-res export / print-grade
- Export visuals at 2–4× via headless browser (Playwright `deviceScaleFactor: 3–4`) or
  `html-to-image` with `pixelRatio`. (See `exporting-to-png` / `generating-images`.)
- For print: 300 DPI, CMYK-aware assets, vector where possible, bleed/safe margins.

## Checklist
```
- [ ] SVG-first for icons/illustrations/logos/charts; raster only for photos
- [ ] Canvas/WebGL rendered at devicePixelRatio
- [ ] srcset/image-set + AVIF/WebP responsive images; no upscaling
- [ ] OKLCH/P3 wide-gamut color with sRGB fallback
- [ ] Variable fonts + optical sizing + feature settings; grid-snapped text
- [ ] Hairline-correct borders, layered realistic shadows, tested on retina + zoom
- [ ] 2–4× / 300 DPI exports for hero assets and print
```

## Anti-patterns
- Blurry canvas/WebGL (ignored devicePixelRatio) — the most common "not sharp" bug.
- Upscaling small PNGs or using icon fonts instead of SVG.
- sRGB-only flat color when P3/OKLCH would look far richer.
- One harsh drop-shadow + pure-black; no elevation system.
- Fractional-pixel text positioning causing fuzzy glyphs.
