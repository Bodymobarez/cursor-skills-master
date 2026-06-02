---
name: cvd-colorblind-safe
description: >-
  Design color-vision-deficiency-safe UI at staff depth: why distinguishability ≠ contrast, CVD types
  and ~8%/0.5% prevalence, the never-rely-on-color-alone rule (WCAG 1.4.1), simulation in linear RGB
  (Brettel/Viénot/Machado matrices, SVG feColorMatrix, @cantoo/color-blindness), the Okabe-Ito safe
  palette, ΔE-after-simulation gating in CI, and fixes for red/green status + traffic-light dashboards.
---

# Color-Vision-Deficiency-Safe Color — Distinguishable, Not Just High-Contrast

**Mandate:** ~**8% of men and ~0.5% of women** have a color vision deficiency (mostly red-green). A pair
can pass WCAG contrast and still be **indistinguishable** to them — contrast measures *lightness*
difference, CVD-safety measures *can you tell these two colors apart*. They are different tests. Pass both.

---

## When to use / when NOT to use

- **Use** for status colors (success/error/warning), chart series, maps, color-coded tables, anything
  where **color carries meaning**. Use it *after* contrast, as a second, independent gate.
- **NOT** as a contrast checker (`wcag-contrast-color-pairs`) — they answer different questions. And not
  for purely decorative color that encodes nothing.

---

## The types & what breaks

| Type | Missing/weak cone | Prevalence (♂) | Confuses |
|------|-------------------|----------------|----------|
| **Deuteranomaly** | weak M (green) | ~5% | red↔green (most common) |
| **Deuteranopia** | no M (green) | ~1% | red↔green |
| **Protanomaly / Protanopia** | weak/no L (red) | ~1–2% | red↔green; red darkens |
| **Tritanopia / Tritanomaly** | S (blue) | <0.01% | blue↔green, yellow↔pink (rare) |
| **Achromatopsia** | all/none | very rare | all hue (lightness only) |

Design target: **deuteranopia + protanopia** cover the overwhelming majority. If it survives those plus a
grayscale (achromatopsia) check, it survives.

---

## The one rule that matters: never encode meaning by hue alone (WCAG 1.4.1)

Hue is a *redundant* channel, never the *only* one. Pair every color signal with at least one of:

- **Lightness difference** (CVD preserves lightness — a dark/light pair stays distinguishable).
- **Shape / icon** (✓ success, ✕ error, ! warning — the icon *is* the signal; color reinforces).
- **Text label** (the status word).
- **Pattern / texture** (hatching on charts/maps).
- **Position / direction** (up/down arrow for finance, not just green/red).

A traffic-light dashboard that's *only* red/amber/green is a 1.4.1 failure and unusable for ~1 in 12 men.

---

## Decision: how to make a set CVD-safe

| Approach | When | Trade-off |
|----------|------|-----------|
| **Vary lightness, not just hue** | status, 2–3 categories | simplest, robust; limited count |
| **Use a proven safe palette (Okabe-Ito)** | categorical charts ≤8 | done for you; fixed hues |
| **Simulate + measure ΔE, iterate** | custom brand sets | rigorous; needs tooling |
| **Add non-color channel** | always, on top | the real fix; required by 1.4.1 |

---

## The Okabe-Ito palette (8 colors, CVD-safe, memorize it)

The Color Universal Design palette — distinguishable across deuter/protan/tritan. Use it as the default
categorical set; it's what serious data viz reaches for.

```ts
export const OKABE_ITO = {
  black:         "#000000",
  orange:        "#E69F00",
  skyBlue:       "#56B4E9",
  bluishGreen:   "#009E73",
  yellow:        "#F0E442",
  blue:          "#0072B2",
  vermillion:    "#D55E00",
  reddishPurple: "#CC79A7",
} as const;
// For status: orange/blue beat red/green. up=blue/▲, down=orange/▼.
```

For status colors specifically: the red/green pair is the worst possible choice. Prefer **blue (positive)
/ orange (negative)** or keep red/green but make them differ strongly in *lightness* and always add an
icon.

---

## Production: simulate CVD and gate distinguishability

CVD simulation is a **3×3 matrix multiply in *linear* RGB** (Brettel-Viénot-Mollon 1997 / Viénot 1999 /
Machado 2009). Do not run it in gamma-encoded sRGB — that's the #1 implementation bug.

Use a vetted library rather than copying matrices:

```bash
npm install @cantoo/color-blindness culori
```

```ts
// cvd.ts — flag any pair that collapses under simulated CVD
import { deuteranopia, protanopia, tritanopia } from "@cantoo/color-blindness";
import { differenceCiede2000, rgb } from "culori";

const dE = differenceCiede2000(); // perceptual color difference; ΔE < ~10 ≈ "looks the same"

type Sim = (hex: string) => string;
const SIMS: Record<string, Sim> = { deuteranopia, protanopia, tritanopia };

export interface CvdFinding { type: string; a: string; b: string; dE: number; }

/** Returns pairs that become hard to tell apart (ΔE < threshold) under any common CVD. */
export function findCvdCollisions(palette: string[], threshold = 12): CvdFinding[] {
  const findings: CvdFinding[] = [];
  for (const [type, sim] of Object.entries(SIMS)) {
    const simmed = palette.map(sim);
    for (let i = 0; i < simmed.length; i++)
      for (let j = i + 1; j < simmed.length; j++) {
        const d = dE(simmed[i], simmed[j]);
        if (d < threshold) findings.push({ type, a: palette[i], b: palette[j], dE: +d.toFixed(1) });
      }
  }
  return findings;
}
```

```ts
// example: catch a red/green status collision before it ships
findCvdCollisions(["#16a34a", "#dc2626", "#2563eb"]);
// → [{ type: "deuteranopia", a: "#16a34a", b: "#dc2626", dE: 6.3 }, ...]  ← red & green merge
```

### Page-level simulation for manual QA (SVG feColorMatrix)

Drop a dev-only filter to *see* the whole app as a dichromat. Must run in linear RGB:

```html
<svg style="position:absolute;width:0;height:0">
  <filter id="deuteranopia" color-interpolation-filters="linearRGB">
    <feColorMatrix type="matrix" values="0.367 0.861 -0.228 0 0
                                          0.280 0.673  0.047 0 0
                                         -0.012 0.043  0.969 0 0
                                          0     0      0     1 0"/>
  </filter>
</svg>
<style>html.sim-deuter { filter: url(#deuteranopia); }</style>
```

Chrome DevTools → Rendering → "Emulate vision deficiencies" does the same without code — use it in review.

---

## Daltonization (compensation) — when you can't change the palette

If the palette is fixed (legacy brand), *daltonization* shifts confusable colors apart for CVD users
(heuristic `2·I − M_sim`). It's a fallback, not a substitute for redundant encoding — prefer fixing the
palette and adding non-color cues.

---

## Edge cases & war stories

- **"It passed contrast but two lines look identical."** Classic: a green and a red series each pass 4.5:1
  on white, but under deuteranopia they're the same brownish tone. Contrast ≠ distinguishability.
- **Red/green diff/finance.** Git diffs, stock tickers, heatmaps — the worst offenders. Add +/− symbols,
  arrows, or switch to blue/orange. `--color-success` and `--color-destructive` should differ in
  *lightness*, not only hue.
- **Tinted "subtle" status backgrounds.** A pale-green "success" row and pale-red "error" row look
  identical to a deuteranope — add an icon in the cell.
- **Maps relying on a green→red choropleth.** Use a CVD-safe diverging scale (`data-viz-color-scales`) and
  patterns for choropleth.
- **Simulating in sRGB instead of linear.** Produces wrong colors and false confidence. Always linear RGB.

---

## Testing strategy (CI gate)

```ts
// cvd.test.ts (vitest)
import { describe, it, expect } from "vitest";
import { findCvdCollisions } from "../lib/cvd";

describe("status + chart colors survive CVD", () => {
  it("status colors are distinguishable under deuteranopia/protanopia", () => {
    const status = ["#0072B2" /*success-blue*/, "#D55E00" /*error-orange*/, "#E69F00" /*warning*/];
    expect(findCvdCollisions(status)).toEqual([]);
  });
});
```

Add an axe check for `1.4.1 Use of Color` patterns in component tests, and a manual deuteranopia-emulation
screenshot in visual review.

---

## Accessibility / i18n

- WCAG **1.4.1 Use of Color (A)** is the governing SC — color may not be the *only* visual means of
  conveying info, indicating an action, or distinguishing an element.
- Combine with `wcag-contrast-color-pairs` (1.4.3/1.4.11) — CVD-safe and contrast-pass are both required.
- Icon/shape signals are language-neutral (good for i18n); don't rely on a color *name* in copy ("click the
  green button").

## Observability / debugging

- Log CVD collision findings in CI with the offending hex pair and ΔE; treat new collisions as regressions.
- Keep the dev-tools vision-deficiency emulator in your QA checklist for every color-coded view.

## Anti-patterns
- Encoding state with hue only (no icon/label/lightness).
- Red/green as the primary positive/negative signal.
- Running the simulation matrix in gamma sRGB instead of linear RGB.
- Treating a contrast pass as a CVD pass.
- "Subtle" tinted status rows with no secondary cue.
- Rainbow/jet chart palettes (collapse badly under CVD — see `data-viz-color-scales`).

## Agent checklist
```
- [ ] Every color-coded signal has a non-color channel (icon/label/shape/lightness)
- [ ] Status uses blue/orange or lightness-separated red/green + icons
- [ ] Categorical charts use Okabe-Ito (or a simulated-and-cleared custom set)
- [ ] findCvdCollisions() run on status + chart palettes; zero collisions
- [ ] Simulation done in LINEAR RGB (vetted lib), not sRGB
- [ ] WCAG 1.4.1 verified; CVD gate in CI; manual deuteranopia screenshot reviewed
```

## References
- Okabe & Ito, Color Universal Design: https://jfly.uni-koeln.de/color/
- WCAG 1.4.1 Use of Color: https://www.w3.org/WAI/WCAG22/Understanding/use-of-color.html
- DaltonLens (accurate CVD math + SVG filters): https://daltonlens.org/cvd-simulation-svg-filters/
- Machado et al. 2009 (physiologically-based model): https://www.inf.ufrgs.br/~oliveira/pubs_files/CVD_Simulation/CVD_Simulation.html
- `@cantoo/color-blindness`: https://www.npmjs.com/package/@cantoo/color-blindness

## Related
`wcag-contrast-color-pairs`, `data-viz-color-scales`, `semantic-ui-color-roles`, `color-artist-engineer`
