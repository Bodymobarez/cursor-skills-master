---
name: data-viz-color-scales
description: >-
  Choose and build data-visualization color scales at staff depth: match scale TYPE to data type
  (categorical / sequential / diverging / cyclic), why perceptually-uniform colormaps (viridis/cividis)
  beat rainbow/jet, OKLCH sequential + diverging generators with monotonic lightness, binning
  (quantize vs threshold), legends, dark-mode re-tuning, and CVD-safe categorical sets. Use for charts,
  heatmaps, choropleths, dashboards.
---

# Data-Viz Color Scales — The Scale Type Must Match the Data

**Mandate:** in a chart, **color is data**, not decoration. The cardinal sin is a mismatch — using a
categorical palette for ordered data, a rainbow for a quantity, or a diverging scale with no meaningful
midpoint. Pick the scale *type* from the data *type* first; aesthetics come after correctness.

---

## When to use / when NOT to use

- **Use** for any chart, heatmap, choropleth, or dashboard where color encodes a value or category.
- **NOT** for UI chrome/brand roles (`semantic-ui-color-roles`) — chart color lives in its own namespace.
  Always pair with `cvd-colorblind-safe` (charts are where CVD failures hurt most) and
  `wcag-contrast-color-pairs` (labels on fills).

---

## Decision: scale type ← data type (get this right or the chart lies)

| Data type | Scale type | Structure | Examples / colormaps |
|-----------|-----------|-----------|----------------------|
| **Nominal** (categories, no order) | **Categorical** | distinct hues, equal L | Okabe-Ito, Tableau10, `schemeCategory10` |
| **Ordinal / quantitative, one direction** | **Sequential** | one hue ramp **or** perceptual multi-hue, monotonic L | viridis, cividis, `schemeBlues` |
| **Quantitative, diverging from a midpoint** | **Diverging** | two sequential joined at a neutral middle | `schemeRdBu`, BrBG, `interpolatePiYG` |
| **Cyclic** (hour, angle, phase) | **Cyclic** | wraps to itself | twilight, `interpolateRainbow` (cyclic-correct) |

If you remember one thing: **never use a categorical palette for ordered data** (readers can't rank hues)
and **never use a sequential/rainbow for unordered categories** (implies a false order).

---

## Why viridis beats rainbow/jet (the senior argument)

The classic "jet"/rainbow colormap is **not perceptually uniform** — it has bright bands (cyan, yellow)
and dark valleys, so equal data steps look like *unequal* jumps, inventing features that aren't in the
data and hiding ones that are. It also collapses under CVD. **viridis/cividis/magma/inferno** were built
to be (a) perceptually uniform in lightness, (b) monotonic (so they read as ordered), and (c) CVD-safe.
Use them (or build your own in OKLCH) for any quantitative encoding. **cividis** is specifically optimized
for deuteranopia/protanopia — the safest default for sequential.

---

## Production: build scales in OKLCH (copy-paste)

Monotonic lightness is what makes a sequential scale readable; OKLCH gives it for free.

```bash
npm install culori
```

```ts
// scales.ts
import { interpolate, formatHex, type Oklch } from "culori";

/** Sequential: monotonic lightness ramp at (roughly) one hue. n discrete stops. */
export function sequential(hue: number, n: number, lo = 0.96, hi = 0.32, chroma = 0.13): string[] {
  // ease lightness; let chroma peak in the middle so mid values aren't washed
  return Array.from({ length: n }, (_, i) => {
    const t = i / (n - 1);
    const l = lo + (hi - lo) * t;
    const c = chroma * Math.sin(Math.PI * t); // 0 at ends, peak mid
    return formatHex({ mode: "oklch", l, c, h: hue } as Oklch)!;
  });
}

/** Diverging: two sequential arms meeting at a near-neutral midpoint. Symmetric lightness. */
export function diverging(hueLow: number, hueHigh: number, n: number): string[] {
  const mid = { mode: "oklch", l: 0.95, c: 0.01, h: hueLow } as Oklch; // near-neutral center
  const low = interpolate([{ mode: "oklch", l: 0.40, c: 0.15, h: hueLow } as Oklch, mid], "oklch");
  const high = interpolate([mid, { mode: "oklch", l: 0.40, c: 0.15, h: hueHigh } as Oklch], "oklch");
  return Array.from({ length: n }, (_, i) => {
    const t = i / (n - 1);
    return formatHex(t < 0.5 ? low(t * 2) : high((t - 0.5) * 2))!;
  });
}

export const tempScale = diverging(250 /*cool blue*/, 30 /*warm red*/, 9); // classic anomaly map
```

Or use **d3-scale-chromatic** for battle-tested colormaps without hand-rolling:

```ts
import { interpolateViridis, schemeRdBu, schemeTableau10 } from "d3-scale-chromatic";
import { scaleSequential, scaleDiverging, scaleOrdinal } from "d3-scale";

const heat = scaleSequential(interpolateViridis).domain([0, 100]);        // quantitative
const anomaly = scaleDiverging<string>((t) => interpolateRdBu(t)).domain([-5, 0, 5]); // pivot at 0
const series = scaleOrdinal(schemeTableau10);                              // categorical
```

---

## Binning: continuous vs classed (and the threshold trap)

| Method | Use | Gotcha |
|--------|-----|--------|
| **Continuous** (`scaleSequential`) | smooth fields, no class boundaries | hard to read exact values from legend |
| **Quantize** (equal value ranges) | even, intuitive | skewed data → most points in one bin |
| **Quantile** (equal counts) | skewed data | bin widths vary; legend must show them |
| **Threshold** (chosen breaks) | meaningful cutoffs (e.g. AQI) | document the breaks; don't hide them |

For diverging data, **the midpoint must be the real pivot** (0, the mean, the target) — and the domain
should usually be **symmetric** around it, or the neutral color lands at the wrong value and misleads.

---

## Categorical: rules that keep series readable

- **Cap at 6–8.** Beyond that, hues stop being distinguishable — group, facet, or use direct labels.
- **Equal lightness, hue-spaced** so no series looks "more important" by being darker (unless that's the
  message). Build with `oklch-perceptual-palettes` at one L, hues ~60°+ apart.
- **Order by importance/value, not rainbow.** The first series should be the most important, in the
  strongest color.
- **Default to Okabe-Ito** for CVD-safety (`cvd-colorblind-safe`); reserve a saturated brand hue for the
  "focus" series and mute the rest.

---

## Contrast, legends & dark mode

- **Labels on fills:** data labels inside bars/segments must hit 4.5:1 against the fill (or use a halo /
  place outside) — `wcag-contrast-color-pairs`.
- **Legends:** for sequential/diverging show the *continuous* bar with tick values; for classed scales show
  the bins with their ranges. A legend that omits the breaks is unreadable.
- **Dark mode:** don't reuse the light scale. Re-tune: sequential low end goes *dark* (not white), high end
  stays vivid but L-capped; keep the scale monotonic against the dark canvas. Verify the lightest stop
  still separates from the chart background.

---

## Edge cases & war stories

- **Rainbow/jet on a scientific heatmap.** Invents banding; reviewers "see" features that are artifacts.
  Switch to viridis — the data often looks completely different (correctly).
- **Diverging scale, no real midpoint.** A red→white→blue scale on all-positive data implies a pivot that
  doesn't exist. Use sequential instead.
- **12 categories, 12 hues.** By series 6 nobody can match line to legend. Reduce, facet, or label lines
  directly at their ends.
- **Choropleth with too many classes.** 9 quantize bins on skewed population data → the whole map is one
  color. Use quantile bins and say so in the legend.
- **Hue + size double-encoding.** Encoding the same variable as both color and bubble size is redundant;
  encoding *different* variables that way is fine but needs two legends.

---

## Testing strategy

- **Monotonic-lightness test** for sequential scales (same check as `oklch-perceptual-palettes`): assert L
  decreases/increases without reversal — a non-monotonic sequential scale is a bug.
- **CVD gate** (`cvd-colorblind-safe`): run `findCvdCollisions` on categorical sets; simulate sequential/
  diverging scales and confirm they stay ordered under deuteranopia.
- **Snapshot legends** so a scale change can't silently desync the legend.

## Accessibility / i18n

- WCAG 1.4.1: never rely on color alone — **direct-label** lines/segments, use patterns for choropleths,
  and provide a data table fallback. Direct labels are also language-neutral.
- Verify the whole chart under a deuteranopia emulation; verify label contrast on every fill.

## Observability / debugging

- Render the scale as a strip with sample values beneath it during development — banding and reversals are
  obvious visually, invisible in code.
- Log the resolved domain/breaks; "the map is all one color" is almost always a domain/binning mismatch,
  not a color bug.

## Anti-patterns
- Rainbow/jet for quantitative data.
- Categorical palette for ordered data (or vice-versa).
- Diverging scale with no meaningful, symmetric midpoint.
- > 8 categorical hues.
- Legend without value ticks / bin ranges.
- Reusing the light-mode scale unchanged in dark mode.
- Color as the only encoding (no labels/patterns).

## Agent checklist
```
- [ ] Scale TYPE matches data type (categorical/sequential/diverging/cyclic)
- [ ] Quantitative uses a perceptually-uniform colormap (viridis/cividis or OKLCH-built)
- [ ] Sequential lightness is monotonic (tested); diverging midpoint is the real pivot, symmetric domain
- [ ] Categorical ≤ 6–8, equal L, ordered by importance, CVD-safe (Okabe-Ito default)
- [ ] Binning method chosen + disclosed in legend (quantize/quantile/threshold)
- [ ] Labels on fills pass 4.5:1; legend shows ticks/ranges
- [ ] Dark-mode scale re-tuned; CVD + 1.4.1 verified
```

## References
- viridis/cividis rationale: https://www.youtube.com/watch?v=xAoljeRJ3lU and https://bids.github.io/colormap/
- ColorBrewer (sequential/diverging/qualitative): https://colorbrewer2.org
- d3-scale-chromatic: https://github.com/d3/d3-scale-chromatic
- Okabe-Ito CUD palette: https://jfly.uni-koeln.de/color/
- culori interpolation: https://culorijs.org/api/

## Related
`oklch-perceptual-palettes`, `cvd-colorblind-safe`, `wcag-contrast-color-pairs`, `semantic-ui-color-roles`,
`charts-data-visualization` (ui-master)
