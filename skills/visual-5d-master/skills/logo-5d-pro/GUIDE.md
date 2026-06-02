---
name: logo-5d-pro
description: >-
  Design premium logos at principal depth: concept & grids → clean vector mastery (optically balanced
  SVG, minimal anchors) → tasteful 3D/extruded/glass/metallic treatments → realistic mockups → a full
  brand export pack (favicon → billboard, monochrome, clear-space, dark/light). Ships real, optimized
  SVG. "5D" treatments are dimensional renders DERIVED from a flawless 2D mark — the vector is the
  source of truth, never the other way around.
---

# Logo 5D Pro

## Mandate

Deliver a mark that is **flawless as flat vector first**, then dimensionalize it tastefully. A logo
must survive a 16px favicon, a one-color fax, an embossed business card, and a 14-meter billboard —
**the same geometry**. The "5D" glass/metal/extrude treatment is a *derived presentation*, not the
logo. If the mark only works as a glossy 3D render, you don't have a logo; you have an illustration.

**Honesty on "5D":** here it means **photoreal depth + 3D form + cinematic lighting + (subtle) motion**
applied as premium treatments of a clean 2D mark. There is no "5D logo format". The canonical asset is
an **optimized SVG**; 3D/PNG/animation are exports from it.

## When to use / NOT use

- **Use** for logo/wordmark/monogram design, brand mark systems, app icons, and premium logo
  presentation (3D/glass/metal renders, animated reveals, mockups).
- **NOT** for: full brand color systems (→ `color-design-master`), UI component libraries (→
  `ui-master`/`tailwind-master`), or raster hero art (→ `image-5d-pro`). Logo type pairing/usage in a
  product UI → `ui-master` brand-identity.

## Mental model — pipeline (vector is upstream of everything)

```
DISCOVERY     brief · positioning · audience · competitors · "logo must do X in N contexts"
  ↓
CONCEPT       sketches · 3–4 distinct directions (not 1 idea in 4 colors)
  ↓
VECTOR        construction grid · golden/√2 geometry · optical correction · minimal anchors  ← SOURCE OF TRUTH
  ↓
SYSTEM        lockups (horizontal/stacked/icon) · clear-space · min-size · mono · dark/light
  ↓
TREATMENT     5D: extrude / bevel / glass / metallic / motion  (DERIVED renders only)
  ↓
MOCKUP        realistic context: signage, app icon, merch, screen, packaging
  ↓
EXPORT PACK   favicon → billboard · SVG/PNG/PDF · all lockups · guidelines
```

## Vector mastery (the craft that separates pro from "auto-traced")

- **Construct on a grid**: circles, golden ratio, √2, consistent stroke weights, shared radii. The
  geometry should be *explainable*, not vibes.
- **Optical > mathematical**: a true circle looks smaller than a square of equal height — overshoot
  curves/points slightly so they *read* aligned. Mathematically-centered often looks off-center.
- **Minimal anchor points**: every extra node is a future kink. Aim for the fewest points that
  describe the curve; place them at curvature extrema (12/3/6/9 o'clock on a circle).
- **Even optical weight**: counters, joints, and apertures balanced so the mark has no heavy/thin
  surprise at small size. Trap ink-traps / overshoots where strokes meet.
- **One path per shape, real geometry** — no stray sub-paths, no transforms baking, no embedded raster.

### Reference: clean, optimized SVG monogram (copy/paste quality)

```svg
<!-- 64×64 viewBox, currentColor so it inherits text color; mono by default -->
<svg width="64" height="64" viewBox="0 0 64 64" role="img"
     aria-label="Acme logo" xmlns="http://www.w3.org/2000/svg">
  <title>Acme</title>
  <!-- single-color mark; geometry on an 8px grid, curves at extrema, minimal anchors -->
  <path fill="currentColor" fill-rule="evenodd"
        d="M32 6 56 50H40l-8-15-8 15H8L32 6Zm0 17 6 11H26l6-11Z"/>
</svg>
```

Why this is "right": `currentColor` (re-themable, instant mono), `viewBox` square with no hardcoded
colors, `fill-rule="evenodd"` for the counter, `<title>` + `role`/`aria-label` for a11y, and a tiny
path. Run **SVGO** before shipping (strip metadata/editor cruft, round coords) — but keep the
`viewBox`, `title`, and ARIA.

### Two-color / gradient variant (with a hard mono fallback)

```svg
<svg width="64" height="64" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="Acme">
  <title>Acme</title>
  <defs>
    <linearGradient id="acme-g" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#6E56CF"/><stop offset="1" stop-color="#3E63DD"/>
    </linearGradient>
  </defs>
  <path fill="url(#acme-g)" d="M32 6 56 50H40l-8-15-8 15H8L32 6Z"/>
</svg>
```

Always also export a **single-fill mono** version (replace `url(#acme-g)` with `currentColor`) — many
contexts (engraving, embroidery, one-color print, dark UI) demand it.

## 5D treatments — derived, tasteful, never the source

| Treatment | Looks | Build with | Don't |
|-----------|-------|-----------|-------|
| **Extrude / 3D** | depth, premium tech | Blender (extrude the SVG curve), Spline, Three.js `ExtrudeGeometry` | bevel so heavy the mark warps |
| **Bevel / emboss** | tactile, physical | SVG `feSpecularLighting` (light), or 3D for hero | muddy edges at small size |
| **Glass / glassmorph** | modern, depth, refraction | 3D (transmission material) or layered SVG blur | illegible mark behind frost |
| **Metallic / chrome / gold** | luxury | 3D PBR (metalness 1, low roughness, HDRI) | gradient "fake chrome" that reads cheap |
| **Liquid / gradient mesh** | vibrant, fluid | SVG/Canvas/Three shaders | clashing with brand palette |
| **Motion reveal** | brand sting, launch | Lottie (web), Remotion `@remotion/three` (video), CSS | gratuitous spin with no idea |

Light SVG bevel without a 3D pipeline (good for hero web headers; keep flat mark canonical):

```svg
<svg width="200" height="200" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="Acme">
  <title>Acme</title>
  <defs>
    <filter id="emboss" x="-20%" y="-20%" width="140%" height="140%">
      <feGaussianBlur in="SourceAlpha" stdDeviation="0.8" result="blur"/>
      <feSpecularLighting in="blur" surfaceScale="3" specularConstant="0.9"
        specularExponent="18" lighting-color="#ffffff" result="spec">
        <feDistantLight azimuth="225" elevation="55"/>
      </feSpecularLighting>
      <feComposite in="spec" in2="SourceAlpha" operator="in" result="specClip"/>
      <feComposite in="SourceGraphic" in2="specClip" operator="arithmetic"
        k1="0" k2="1" k3="1" k4="0"/>
    </filter>
  </defs>
  <path filter="url(#emboss)" fill="#3E63DD" d="M32 6 56 50H40l-8-15-8 15H8L32 6Z"/>
</svg>
```

Premium metallic/extruded hero → render in 3D (PBR metal + HDRI + 3-point light); the workflow,
materials, and a copy-paste R3F/Three setup live in **`3d-render-motion-graphics`**. Always render the
3D treatment from the **same canonical vector** so it can never drift from the flat mark.

## Brand system — lockups, clear-space, min-size

- **Lockups**: primary (icon + wordmark horizontal), stacked, icon-only, wordmark-only — each
  optically spaced (not just "place side by side").
- **Clear-space**: define in terms of the mark itself (e.g. "padding = height of the counter / the
  cap-height of the wordmark") so it scales. Encode it in the guidelines.
- **Min-size**: state a hard floor (e.g. icon ≥ 16px digital / 8mm print) below which only the
  simplified/mono mark is allowed. Provide a **simplified favicon mark** if the full mark muddies at
  16px.
- **Color modes**: full-color, 1-color (brand), mono black, mono white (knockout), and approved
  on-photo treatment. Each as its own file.

## Mockups (sell it in context, honestly)

- Show the mark on **realistic** surfaces: signage, app icon grid, business card, apparel, packaging,
  vehicle, screen UI, embossed/foil. Use real mockup PSDs/3D, with correct perspective + material.
- Render app-icon on the actual OS grid (iOS squircle / Android adaptive safe zone) — don't ship a
  square logo into a squircle and let it clip.
- Keep one **flat, unstyled** presentation alongside the glamour shots so reviewers judge the mark,
  not the lighting.

## Edge cases / gotchas

- **iOS squircle / Android adaptive**: icons get masked — design within the safe zone, supply
  foreground/background layers for Android adaptive icons.
- **Knockout/reverse**: thin elements vanish on dark — provide a thickened/mono-white variant.
- **Hairlines** at small size disappear in print/screen — enforce min stroke.
- **Gradients in print**: can band/shift across processes — always ship a spot/solid fallback.
- **`currentColor` + external `<defs>`**: inline SVG only; gradients referenced by `id` can collide if
  two SVGs share an id on one page — namespace ids.
- **Embroidery/engraving**: needs a single-color, low-detail version — design it, don't auto-reduce.

## Performance / cost

- **SVGO** every shipped SVG (often 40–70% smaller); inline tiny critical logos to save a request;
  `<use>`/sprite for repeated marks.
- Favicons: ship **SVG favicon** + PNG fallbacks + `apple-touch-icon` (180px) — not a heavy multi-res
  .ico for modern targets.
- 3D treatments are render-cost; bake hero stills/Lottie once rather than shipping a live WebGL logo
  on every page load.
- Animation: **Lottie** (vector, tiny, scalable) for web/app; pre-rendered video only where Lottie
  can't (heavy 3D).

## Rights / licensing / trademark & brand safety

- **Originality/clearance**: run a trademark + reverse-image search; avoid lookalikes and clichés
  (swoosh, generic globe). A logo is a legal asset — don't ship a collision.
- **Fonts**: license the typeface for logo use **and** consider **converting the wordmark to
  outlines** (so you're not embedding/redistributing the font) — but verify the foundry license
  permits logo/outline use.
- **AI-assisted marks**: treat AI output as *ideation only* — redraw as clean vector you own;
  AI-generated logos may not be protectable/ may collide. Disclose per client policy.
- **Deliver ownership**: hand over source + a rights/IP statement; clarify the client owns the final
  mark.

## Consistency / scale

- **One source SVG → all exports** via a build script (below). Never hand-edit per-format copies.
- **Brand guidelines** doc: construction, clear-space, min-size, color modes, misuse examples
  (don't stretch/recolor/rotate/add-effects), and the approved 5D treatment specs.
- **Token the palette** with `color-design-master` so logo colors == product colors (no drift).

Batch-export script (one truth → the whole pack):

```bash
# requires: npm i -g svgo  +  brew install librsvg (rsvg-convert)  +  optional inkscape
svgo logo.svg -o dist/logo.min.svg                                   # optimize source
for s in 16 32 48 180 192 512 1024; do                               # favicons → app icons
  rsvg-convert -w $s -h $s dist/logo.min.svg -o dist/icon-$s.png
done
rsvg-convert -w 4000 dist/logo.min.svg -o dist/logo-billboard.png    # large-format raster
rsvg-convert -f pdf  dist/logo.min.svg -o dist/logo.pdf              # print/vector PDF
# mono + knockout variants are separate source SVGs (currentColor → #000 / #fff), same pipeline
```

## QA / review

```
- [ ] Mark is flawless as FLAT vector first; 3D is derived, not load-bearing
- [ ] Works at 16px favicon AND billboard from the SAME geometry
- [ ] Mono (black), knockout (white), 1-color, full-color all provided + tested
- [ ] Optical balance checked (not just mathematical centering); minimal anchors; SVGO'd
- [ ] Clear-space + min-size defined relative to the mark; app-icon safe zones respected
- [ ] Trademark/lookalike cleared; fonts licensed/outlined; ownership documented
- [ ] Tested on dark/light, on photo, in actual app-icon grids
```

## Delivery specs (formats / sizes)

| Asset | Format | Notes |
|-------|--------|-------|
| **Canonical** | optimized **SVG** (mono + color) | `viewBox`, `currentColor`, `<title>`, no raster |
| **Print/vector** | **PDF** + **EPS** | outlined fonts; CMYK + spot (Pantone) callouts |
| **Favicon** | SVG favicon + PNG 16/32/48 + ICO fallback | + `apple-touch-icon` 180 |
| **App icon** | PNG 1024 master → platform sizes; Android adaptive layers | iOS squircle / Android safe zone |
| **Raster/web** | PNG (transparent) @1×/2×/3×, optional WebP/AVIF | sRGB or Display-P3 (tagged) |
| **Large-format** | high-res PNG/PDF | from vector; DPI per printer × size |
| **Motion** | **Lottie JSON** (web/app) · ProRes 4444 / WebM (video) | from the canonical mark |
| **Guidelines** | PDF | construction, clear-space, min-size, misuse, color modes |

## Accessibility & i18n / RTL

- **SVG a11y**: `role="img"` + `<title>` (and `aria-label`); decorative duplicates `aria-hidden`.
- **Contrast**: the mark (and any tagline text) must clear ~3:1 (graphical) / 4.5:1 (text) against its
  background; provide knockout for dark surfaces. Verify with `wcag-contrast-color-pairs`.
- **i18n/RTL**: provide RTL-aware lockups for Arabic/Hebrew markets (mirror the *layout*, not the
  logo glyph); supply localized wordmark versions where the brand name transliterates; never bake an
  un-translatable tagline into the mark.
- **Motion**: respect `prefers-reduced-motion` for animated logos — serve a static mark.

## Anti-patterns

- Designing the 3D/glass render first and back-deriving a flat mark — backwards; the vector is upstream.
- One concept recolored 4 ways presented as "4 directions".
- Auto-traced raster, stray sub-paths, baked transforms, embedded PNG inside the "SVG".
- Gradient-only logo with no mono/knockout fallback; hairlines that die at 16px.
- Fake chrome gradients instead of real PBR; gratuitous spin animations with no concept.
- Hand-editing each export format instead of building from one source; shipping un-SVGO'd files.
- Skipping trademark clearance; embedding an unlicensed font instead of outlining.

## Agent checklist

```
- [ ] 3–4 genuinely distinct concepts before refining one
- [ ] Canonical = optimized SVG (currentColor, viewBox, title/ARIA), SVGO'd
- [ ] Optical correction + minimal anchors verified at 16px and huge
- [ ] System complete: lockups, clear-space, min-size, mono, knockout, dark/light
- [ ] 5D treatment derived from the SAME vector (3D via 3d-render-motion-graphics)
- [ ] Full export pack from ONE source via script; guidelines included
- [ ] Trademark cleared; fonts licensed/outlined; a11y + RTL handled
```

## References (2026-current)

- SVG `currentColor`/accessibility: https://developer.mozilla.org/en-US/docs/Web/SVG
- SVGO: https://github.com/svg/svgo · rsvg-convert (librsvg): https://gitlab.gnome.org/GNOME/librsvg
- Apple app icon / Human Interface Guidelines: https://developer.apple.com/design/human-interface-guidelines/app-icons
- Android adaptive icons: https://developer.android.com/develop/ui/views/launch/icon_design_adaptive
- Lottie: https://lottiefiles.com/ · SVG filters (lighting): https://developer.mozilla.org/en-US/docs/Web/SVG/Element/feSpecularLighting

## Related

`3d-render-motion-graphics` (metal/glass/extrude renders + motion), `image-5d-pro`,
`cinematic-5d-video-production` (this master); `color-design-master`, `ui-master` (brand-identity),
`tailwind-master` (token the palette).
