---
name: oklch-perceptual-palettes
description: >-
  Generate perceptually-uniform, gamut-safe color ramps in OKLCH at staff depth: the chroma-arc
  principle, eased lightness curves, hue-dependent gamut clamping (culori clampChroma/toGamut),
  P3 wide-gamut fallbacks, relative-color-syntax derivations, and a build-time scale generator with
  monotonicity tests. The engineering foundation under every harmonious palette. Use before tokens.
---

# OKLCH Perceptual Palettes — Production Ramp Engineering

**Mandate:** a color scale is a *function*, not a vibe. Equal perceptual steps, locked hue, chroma that
never falls out of gamut, and the same generator for every brand. If you're hand-picking nine grays in
HEX, you've already lost — they will not look evenly spaced and they will drift in hue.

---

## When to use / when NOT to use

- **Use** when building a tonal scale (50→950), neutrals, semantic ramps, chart series, or when fixing
  a "muddy"/"neon"/"uneven" palette. Use it as the layer *below* `palette-to-tokens-export`.
- **NOT** for one-off marketing hero gradients (use whatever looks good, it's not a system), and not as
  a contrast checker — generating in OKLCH does **not** guarantee WCAG pass (route to
  `wcag-contrast-color-pairs`).

---

## Why OKLCH (and why not the others)

OKLCH is the cylindrical form of **Oklab** (Björn Ottosson, 2020). It fixes CIELAB/LCH's hue-shift bugs
(the infamous blue→purple drift when you change lightness) and gives a genuinely perceptually-uniform
**L**: `L 0.6` looks equally light in yellow and in blue. HSL lies — `hsl(60 100% 50%)` (yellow) is far
brighter than `hsl(240 100% 50%)` (blue) at the same "lightness".

| Space | Perceptually uniform L | Hue stable across L | Gamut-aware | Verdict |
|-------|------------------------|---------------------|-------------|---------|
| **OKLCH** | ✅ | ✅ | ✅ (chroma reducible) | **Author here** |
| LCH (CIE) | ~ | ❌ blue hue shift | ✅ | Legacy; OKLCH supersedes |
| HSL | ❌ | ❌ | ❌ | Never for ramps |
| HEX/RGB | ❌ | ❌ | n/a | Output only, never authoring |

Channels: `oklch(L C H)` → **L** 0–1, **C** 0–~0.4 (unbounded in theory, hue/gamut-capped in practice),
**H** 0–360. `--brand-600: oklch(0.55 0.20 260)`.

### Browser support (2026 — all evergreen, ship it)

| Feature | Chrome | Firefox | Safari |
|---------|--------|---------|--------|
| `oklch()` | 111 | 113 | 15.4 |
| `color-mix()` | 111 | 113 | 16.2 |
| Relative color `oklch(from …)` | 119 | 128 | 16.4 |
| `color(display-p3 …)` | 111 | 113 | 10 |

---

## The two curves that make a scale (the actual senior knowledge)

A ramp is **two independent curves over the steps**: a lightness curve and a chroma curve. Beginners
vary L linearly and hold C constant. Both are wrong.

1. **Lightness is eased, not linear.** Human discrimination is finer at the light end, so you want more,
   tighter steps near white and fewer near black. A linear L produces washed-out lights and a crushed
   dark end.
2. **Chroma follows an arc — peak in the mid-tones, taper at both ends.** This is the single most
   important rule. Max representable chroma lives around L 0.55–0.70; at L→1 and L→0 the sRGB gamut
   pinches to a point, so high chroma there is *impossible* and the browser will clip it (turning your
   pale tint muddy or your dark shade flat). Taper C toward both ends and the ramp stays clean.

```
C ▲           ___
  │        _/      \_           ← peak chroma ~step 500–600
  │     _/             \_
  │   /                   \_
  │ _/                       \__
  └────────────────────────────▶ step  (50 … 950)
```

---

## Production scale generator (copy-paste, `culori` v4)

`culori` is what Tailwind v4 and Radix use internally. `clampChroma` reduces **only chroma** (preserving
L and H) until the color is representable — exactly the gamut-mapping algorithm the CSS Color 4 spec
recommends.

```bash
npm install culori
```

```ts
// scripts/build-ramp.ts
import { oklch, formatHex, formatCss, clampChroma, type Oklch } from "culori";

export interface RampStep {
  step: number;
  oklch: string; // formatted CSS, gamut-mapped to sRGB
  hex: string;   // fallback for legacy / email
}

const STEPS = [50, 100, 200, 300, 400, 500, 600, 700, 800, 900, 950] as const;

// Eased lightness — denser near white, looser near black. Tune per brand, keep monotonic.
const L_CURVE = [0.971, 0.936, 0.885, 0.808, 0.704, 0.616, 0.541, 0.466, 0.394, 0.314, 0.235];

// Chroma arc — fraction of peakChroma per step. Peaks at 500–600, tapers to the ends.
const C_CURVE = [0.18, 0.36, 0.54, 0.76, 0.93, 1.0, 0.94, 0.82, 0.68, 0.52, 0.40];

/**
 * Build a perceptually-uniform, gamut-safe ramp at a fixed hue.
 * @param hue        OKLCH hue 0–360
 * @param peakChroma max chroma at the arc apex (≈0.17 for blue/violet; ≤0.13 for yellow/green — see gotchas)
 */
export function buildRamp(hue: number, peakChroma = 0.17): RampStep[] {
  return STEPS.map((step, i) => {
    const desired: Oklch = { mode: "oklch", l: L_CURVE[i], c: peakChroma * C_CURVE[i], h: hue };
    const safe = clampChroma(desired, "oklch", "rgb"); // reduce C until in sRGB; keep L + H
    const hex = formatHex(safe);
    const css = formatCss(safe);
    if (!hex || !css) throw new Error(`Unrepresentable step ${step} at hue ${hue}`);
    return { step, oklch: css, hex };
  });
}

export function rampToCss(name: string, ramp: RampStep[]): string {
  return ramp.map((s) => `  --${name}-${s.step}: ${s.oklch};`).join("\n");
}
```

```ts
// usage
const brand = buildRamp(262, 0.17);   // indigo
const neutral = buildRamp(262, 0.012); // tinted neutral — same hue, chroma crushed (see below)
console.log(`:root {\n${rampToCss("brand", brand)}\n${rampToCss("neutral", neutral)}\n}`);
```

---

## Neutrals: tinted, never dead gray

Lock the neutral hue to the brand hue and crush chroma to **0.004–0.015**. This gives grays that feel
*of the brand* (warm or cool) without "rainbow gray" drift. `C = 0` is acceptable but reads sterile;
a whisper of brand chroma is the senior move.

| | L | C | H |
|---|---|---|---|
| neutral-50 | 0.985 | 0.004 | brandH |
| neutral-500 | 0.616 | 0.012 | brandH |
| neutral-950 | 0.205 | 0.010 | brandH |

Rule: **C ≤ 0.015 on neutrals**. Above that, large gray surfaces visibly tint and fight the brand.

---

## Deriving states with relative color syntax (runtime, no preprocessor)

Hover/active/subtle states should be *derived*, not hand-listed. Relative color syntax computes in OKLCH
at paint time:

```css
.btn        { background: var(--brand-600); }
.btn:hover  { background: oklch(from var(--brand-600) calc(l - 0.04) c h); }
.btn:active { background: oklch(from var(--brand-600) calc(l - 0.08) calc(c - 0.02) h); }
/* tinted wash for selected rows */
.row-selected { background: oklch(from var(--brand-600) 0.96 0.03 h); }
```

**Gotcha that wastes an afternoon:** you **cannot use `%` inside `calc()` in relative color** — write
`calc(l - 0.08)`, never `calc(l - 8%)`. And relative syntax is Chrome 119+/Safari 16.4+/FF 128+ — if you
support older, precompute with the generator above and emit static custom properties.

---

## P3 / wide gamut (the part everyone gets wrong)

The CSS Color 4 spec says browsers should gamut-map via OKLCH chroma reduction, **but Chrome and Safari
still naïvely *clip* RGB**, which darkens and dulls out-of-gamut colors instead of mapping them. So:

- **Author and clamp in sRGB by default** (the `clampChroma(…, "rgb")` above). This is your safe floor.
- **Opt into P3 explicitly** for displays that have it, where you can push chroma higher:

```css
:root { --brand-600: oklch(0.55 0.18 262); } /* sRGB-safe */
@media (color-gamut: p3) {
  :root { --brand-600: oklch(0.55 0.24 262); } /* richer, only painted on P3 panels */
}
```

Generate the P3 variant by clamping to the `p3` gamut instead of `rgb`:
`toGamut("p3", "oklch")(color)`.

---

## Edge cases & war stories

- **Hue-dependent chroma ceiling.** Max chroma is *not* constant across hue. Blue/violet (H≈260–290)
  reaches C≈0.20+; yellow/green (H≈100–130) tops out near C≈0.10–0.13 at high L. A fixed `peakChroma`
  across hues makes your yellow look washed while your blue screams. Either clamp (the generator does)
  or set `peakChroma` per hue family.
- **The gamut cliff at mid-L.** A color that's in-gamut at L 0.5 can fall *out* at L 0.6 with the same C.
  Always clamp every step; never trust a hand-typed `oklch()` literal at high chroma.
- **Yellow's lightness illusion.** Pure yellow is intrinsically light; you physically cannot make a dark,
  saturated yellow (it becomes olive/brown). Don't force a `yellow-900` to be vivid — accept low chroma.
- **Hue is circular.** `H 359` and `H 1` are 2° apart, not 358°. Interpolate hue on the short arc or your
  "evenly spaced" chart hues will bunch up.
- **`oklch.com` vs your build.** The picker shows the *requested* color; the browser may clip it. Always
  verify the rendered hex (`formatHex(clampChroma(...))`), not the value you typed.

---

## Performance

- **Precompute at build time.** Generating ramps in JS at runtime, or stacking deep `calc()` relative-color
  chains, costs paint time. Emit static custom properties from the generator; reserve relative color for a
  handful of interaction states.
- Custom properties are essentially free to read; the cost is in *recomputation* on theme switch. Swap a
  small semantic map (`semantic-ui-color-roles`), not 11 primitive steps × N hues, on toggle.

---

## Testing strategy (gate the generator, not vibes)

```ts
// ramp.test.ts (vitest)
import { describe, it, expect } from "vitest";
import { oklch, inGamut } from "culori";
import { buildRamp } from "../scripts/build-ramp";

const isRgb = inGamut("rgb");

describe("brand ramp", () => {
  const ramp = buildRamp(262, 0.17);
  it("is monotonically decreasing in lightness", () => {
    const Ls = ramp.map((s) => oklch(s.oklch)!.l);
    for (let i = 1; i < Ls.length; i++) expect(Ls[i]).toBeLessThan(Ls[i - 1]);
  });
  it("never leaves the sRGB gamut", () => {
    for (const s of ramp) expect(isRgb(oklch(s.oklch)!)).toBe(true);
  });
  it("keeps a single hue (no drift)", () => {
    const hues = ramp.map((s) => oklch(s.oklch)!.h ?? 262);
    for (const h of hues) expect(Math.abs(h - 262)).toBeLessThan(1.5);
  });
});
```

---

## Observability / debugging

- Render the full ramp as swatches with L/C/H printed under each — eyeballing 11 swatches catches a bad
  curve faster than reading numbers.
- When a step looks "off", print `clampChroma(...)` vs the requested value: if they differ, you hit the
  gamut and the requested chroma was impossible.
- Squint test (or 8px blur): a good ramp shows a smooth lightness gradient with no "step" jumping out.

---

## Anti-patterns

- Constant chroma across all steps → muddy lights, clipped darks.
- Linear lightness → washed-out top, crushed bottom.
- Picking 9 grays by hand in HEX → uneven + hue drift.
- One fixed `peakChroma` for every hue → inconsistent vividness (yellow vs blue).
- Trusting a hand-typed high-chroma `oklch()` without gamut-clamping.
- `%` inside `calc()` in relative color syntax → silently invalid.
- Shipping P3 chroma as the only value (no sRGB fallback) → dull on most monitors.

## Agent checklist
```
- [ ] Ramp generated by a function (two curves), not hand-picked
- [ ] Lightness eased + monotonic; chroma arced + tapered at both ends
- [ ] Every step gamut-clamped (clampChroma to sRGB) — verified in CI
- [ ] Neutrals: locked hue, C ≤ 0.015
- [ ] States derived via relative color or precomputed (no % in calc)
- [ ] P3 variant behind @media (color-gamut: p3), sRGB as the floor
- [ ] Monotonic-L + in-gamut + hue-lock tests passing
- [ ] Handed off to wcag-contrast-color-pairs before shipping pairs
```

## References
- MDN `oklch()` + relative color: https://developer.mozilla.org/en-US/docs/Web/CSS/color_value/oklch
- Ottosson, Oklab: https://bottosson.github.io/posts/oklab/
- Evil Martians, "OKLCH in CSS": https://evilmartians.com/chronicles/oklch-in-css-why-quit-rgb-hsl
- culori API (clampChroma/toGamut/inGamut): https://culorijs.org/api/
- Interactive picker: https://oklch.com

## Related
`wcag-contrast-color-pairs`, `semantic-ui-color-roles`, `palette-to-tokens-export`, `data-viz-color-scales`,
`tailwind-design-tokens` (tailwind-master)
