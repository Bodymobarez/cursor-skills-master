---
name: wcag-contrast-color-pairs
description: >-
  Dual-standard color contrast at staff depth: WCAG 2.2 ratios (1.4.3/1.4.6/1.4.11) as the legal floor
  PLUS APCA Lc thresholds as the perceptual bar, computed independently with culori + apca-w3 (incl.
  alpha-blended translucent text), the mandatory pair matrix, harmony-safe fixes in OKLCH, and a CI
  gate that hard-fails the build on any AA miss. Use to verify every text/UI pair before shipping.
---

# WCAG Contrast & Color Pairs — Dual-Standard, CI-Enforced

**Mandate:** WCAG 2.2 AA is the **legal floor you must clear**; APCA is the **perceptual bar you should
also clear**. Compute both, in code, in CI — never eyeball "looks fine," and never trust a model's or a
designer's claimed ratio. A pair that isn't tested is a pair that fails.

---

## When to use / when NOT to use

- **Use** to verify body/UI text, button labels, borders, focus rings, links, chart labels, and disabled
  states — on every theme (light *and* dark). Use the moment a palette produces a fg/bg pair.
- **NOT** as a palette *generator* (route to `oklch-perceptual-palettes`) and **not** as a substitute for
  color-blind distinguishability — contrast ≠ CVD-safety (route to `cvd-colorblind-safe`).

---

## WCAG 2.2 — the floor (what auditors and lawsuits check)

Three success criteria carry contrast:

| SC | Name | Applies to | AA |
|----|------|-----------|----|
| **1.4.3** | Contrast (Minimum) | body text | **4.5:1**; large text **3:1** |
| **1.4.6** | Contrast (Enhanced) | body text (AAA) | 7:1; large 4.5:1 |
| **1.4.11** | Non-text Contrast | UI components, states, graphics, **focus indicators** | **3:1** vs adjacent |

Formula: `(L1 + 0.05) / (L2 + 0.05)`, L = relative luminance (sRGB). **Large text** = ≥ 24px regular or
≥ 18.66px (14pt) bold. Luminance-only: hue and saturation contribute nothing.

**Where WCAG 2 is wrong (and you must compensate):** it ignores font size/weight *within* the
normal/large buckets and ignores **polarity** — dark-on-light and light-on-dark are not symmetric, but
WCAG 2 scores them identically. This is why thin light text on dark passes WCAG 2 yet looks broken, and
why orange/red pairs that "pass" are hard to read. That's APCA's job.

---

## APCA — the perceptual bar (the part that's actually current)

APCA (Andrew Somers) outputs a **signed Lc** ("lightness contrast"), magnitude ~0–108, sign = polarity
(positive = dark text on light bg). It models size, weight, and polarity. Status, precisely: APCA was
explored for WCAG 3, **removed from the working draft in July 2023**; WCAG 2.2 is the published
Recommendation (Oct 2023) and remains the legal standard (EN 301 549, Section 508, ADA). WCAG 3 is years
out (~2028–2030). **So: gate on WCAG 2.2; advise with APCA.**

APCA "Bronze" threshold bands (use as minimums):

| Lc | Use case |
|----|----------|
| **90** | Fluent body text best-practice (preferred) |
| **75** | Minimum for columns of body text (~WCAG AA equivalent) |
| **60** | Other content / UI labels / short copy / placeholder you actually want read |
| **45** | Large/heavy text — 36px/400 or 24px/700, headlines |
| **30** | Absolute floor for any text (spot/incidental) |
| **15** | Non-text elements (borders, icons, focus indicators) |

APCA catches what WCAG 2 misses: e.g. pure red `#F00` on black is WCAG ~5.25:1 (AA pass) but APCA ≈ Lc 50
— *below* the Lc 60 body minimum. Anyone who's shipped 14px red on a dark card knows APCA is right here.

---

## Decision: which standard governs which decision

| Situation | Governing standard | Why |
|-----------|--------------------|-----|
| Legal/procurement compliance, audits | **WCAG 2.2 AA** (gate) | The published, enforceable standard |
| Dark-mode text, tinted surfaces, thin/large type | **APCA** (advisory) | WCAG 2 is polarity- and size-blind here |
| Future-proofing a design system | Pass **both** | Survives the WCAG 3 transition |
| Non-text (borders, focus, icons) | WCAG 1.4.11 (3:1) + APCA Lc 15 | Both have a non-text track |

**Policy that ships:** *AA is a hard CI gate; APCA Lc is reported and reviewed, hard-gated only for dark
mode body text.* Don't block a build on a contested perceptual algorithm, but never let it hide a real
legibility problem.

---

## Production: compute both, independently (copy-paste)

`culori.wcagContrast` for the ratio; `apca-w3` for Lc. Critically, **alpha-blend translucent text against
its actual background first** — `text-foreground/70` on a card is a different pair than the opaque token.

```bash
npm install culori apca-w3 colorparsley
```

```ts
// lib/contrast.ts
import { wcagContrast, rgb, type Color } from "culori";
import { APCAcontrast, sRGBtoY, alphaBlend } from "apca-w3";
import { colorParsley } from "colorparsley";

export interface PairResult {
  fg: string; bg: string;
  wcag: number;        // ratio, 1–21
  apcaLc: number;      // signed Lc
  passAA: boolean;     // 4.5:1
  passAALarge: boolean;// 3:1
  passApcaBody: boolean; // |Lc| ≥ 75
}

/** rgba 0–255 int array (apca-w3 contract); alpha-blends fg over bg when fg is translucent. */
function toRgba255(c: string): [number, number, number, number] {
  const p = rgb(c);
  if (!p) throw new Error(`Unparseable color: ${c}`);
  return [Math.round((p.r ?? 0) * 255), Math.round((p.g ?? 0) * 255), Math.round((p.b ?? 0) * 255), p.alpha ?? 1];
}

export function checkPair(fg: string, bg: string): PairResult {
  const wcag = wcagContrast(fg, bg); // culori blends nothing — pass opaque or pre-blended values

  const bgArr = toRgba255(bg);
  const fgArr = toRgba255(fg);
  // APCA: text first, bg second. Alpha-blend translucent text onto bg before measuring.
  const fgSolid = fgArr[3] < 1 ? alphaBlend(fgArr, bgArr) : fgArr;
  const apcaLc = APCAcontrast(sRGBtoY(fgSolid), sRGBtoY(bgArr)) as number;

  return {
    fg, bg, wcag, apcaLc,
    passAA: wcag >= 4.5,
    passAALarge: wcag >= 3,
    passApcaBody: Math.abs(apcaLc) >= 75,
  };
}
```

Resolve OKLCH/custom-property tokens to concrete sRGB before checking (the values your tokens evaluate to,
per theme) — `formatHex(oklch("oklch(0.62 0.17 262)"))`.

---

## Mandatory pairs — test all of these, per theme

```
foreground          on background          (body)
foreground          on surface             (cards/panels)
muted-foreground    on background          ← the pair that fails most often
primary-foreground  on primary             (button label)
on-accent           on accent
link                on background
error / on-error    on surface / on error
border              vs surface             (≥ 3:1 non-text, 1.4.11)
ring                vs adjacent bg          (≥ 3:1, focus appearance)
data label          on each chart fill      (per series)
placeholder         on input bg             (often below AA — fix or accept consciously)
```

---

## Fixing a failing pair — harmony-safe

Order of operations (preserve brand identity):

1. **Adjust L only, in OKLCH.** Darken text (lower L) or lighten bg (raise L). Hue and chroma stay → the
   brand still reads as the brand.
2. **If a brand accent fails on white:** lower the accent's L for *text* use; keep the vivid version for
   *fills* (large-area 3:1, not 4.5:1). Two tokens, one hue.
3. **Never** "fix" by swapping to a random hue, or by nudging chroma — chroma barely moves WCAG luminance
   and you lose identity.
4. **muted-foreground:** target ≥ 4.5:1, not "looks subtly gray" at 2.8:1. Subtle ≠ illegible.

```css
/* before: fails AA (≈3.1:1) */  --muted-foreground: oklch(0.62 0.02 262);
/* after:  passes AA (≈5.0:1) */ --muted-foreground: oklch(0.50 0.02 262); /* L down only */
```

---

## CI gate — hard-fail the build (this is the whole point)

```ts
// tests/contrast.test.ts (vitest) — fails CI on any AA miss
import { describe, it, expect } from "vitest";
import { checkPair } from "../lib/contrast";

// resolve your tokens per theme to concrete sRGB hex first
const PAIRS = [
  { name: "body/bg",        fg: "#0b1220", bg: "#f8fafc", min: 4.5 },
  { name: "muted/bg",       fg: "#4b5563", bg: "#f8fafc", min: 4.5 },
  { name: "primaryFg/primary", fg: "#ffffff", bg: "#3257d6", min: 4.5 },
  { name: "border/surface", fg: "#cbd5e1", bg: "#ffffff", min: 3.0 }, // non-text 1.4.11
];

describe("WCAG 2.2 AA contrast gate", () => {
  for (const p of PAIRS) {
    it(`${p.name} ≥ ${p.min}:1`, () => {
      const r = checkPair(p.fg, p.bg);
      expect(r.wcag, `got ${r.wcag.toFixed(2)}:1 (APCA Lc ${r.apcaLc.toFixed(0)})`).toBeGreaterThanOrEqual(p.min);
    });
  }
});
```

Plus a **runtime** axe pass in component/E2E tests so dynamic states are covered:

```ts
// Playwright + @axe-core/playwright
import AxeBuilder from "@axe-core/playwright";
const results = await new AxeBuilder({ page }).withTags(["wcag2aa", "wcag22aa"]).analyze();
expect(results.violations.filter((v) => v.id === "color-contrast")).toEqual([]);
```

Run both light and dark themes (toggle `data-theme`/`.dark`, re-run).

---

## Edge cases & war stories

- **Translucent text/overlays.** `text-foreground/60`, scrim gradients, glassmorphism — measure the
  *composited* color, not the token. The `alphaBlend` step above is mandatory; skipping it is the #1
  false-pass.
- **The large-text loophole.** 3:1 is only legal if the text is *actually* ≥24px / ≥18.66px-bold at every
  breakpoint. Responsive type that shrinks to 16px on mobile reverts to the 4.5:1 rule. Audit the smallest
  rendered size.
- **Disabled controls are exempt** from 1.4.3 — but "exempt" ≠ "invisible." Users must still perceive
  state; keep disabled text legible-ish and rely on more than contrast (cursor, opacity, label).
- **Logotypes/decorative** text are exempt; don't waste effort forcing brand wordmarks to 4.5:1.
- **Gradient/photo backgrounds.** Contrast varies across the area — test the worst pixel, or add a
  scrim/text-shadow/`backdrop` so the *minimum* local contrast passes.
- **Orange/yellow trap.** WCAG 2 is famously generous to mid-bright oranges; APCA flags them. Trust APCA
  for these.

---

## Charts, data labels & CVD (don't rely on color alone)

- Data labels *inside* filled bars/segments: 4.5:1 against the fill, or use an outline/halo, or place
  labels outside.
- Never encode meaning by color alone (WCAG 1.4.1) — add pattern, label, shape, or direct annotation.
  Verify in a deuteranopia simulation (`cvd-colorblind-safe`).

## Focus indicators

WCAG 2.4.11 (Focus Appearance) + 1.4.11: the focus ring needs ≥ 3:1 against **both** the component and the
adjacent background. A `ring-primary/40` that vanishes on a tinted surface is a fail — test it on every
surface it can land on, light and dark.

## i18n / RTL

Contrast is direction-agnostic, but **dark mode and high-contrast OS modes** change everything — always
test the OS forced-colors / Windows High Contrast path (`@media (forced-colors: active)`) and don't pin
colors that the OS needs to override. Gov targets (UAE Federal DLS, EN 301 549) require **WCAG 2.2 AA**
minimum — pair with `tailwind-uae-aegov-dls`.

## Observability / debugging

- Emit a **contrast report** artifact in CI (JSON → HTML table of every pair, ratio, Lc, pass/fail) and
  attach it to the PR. A reviewer should see the matrix without running anything.
- When a pair regresses, diff the resolved token hex between branches — a contrast failure is almost always
  an upstream token L change.

## Anti-patterns
- Eyeballing contrast ("#888 on #999 looks fine").
- Trusting an LLM's or designer's stated ratio without recomputing.
- Measuring opaque tokens when the UI renders them translucent.
- Using APCA Lc and WCAG ratios interchangeably (different scales, not convertible).
- Claiming 3:1 large-text pass for text that shrinks below the large threshold.
- Fixing contrast by changing hue (kills brand) instead of L.
- Testing only light mode.

## Agent checklist
```
- [ ] Every mandatory pair computed in code (WCAG + APCA), both themes
- [ ] Translucent fg alpha-blended onto real bg before measuring
- [ ] WCAG 2.2 AA is a hard CI gate (unit + axe runtime)
- [ ] APCA Lc reported; gated for dark-mode body text
- [ ] Non-text 1.4.11 (borders/focus) ≥ 3:1 verified on every surface
- [ ] Failing pairs fixed by L-only OKLCH shift, not hue swaps
- [ ] Contrast report artifact attached to PR
- [ ] forced-colors / high-contrast path not broken
```

## References
- WCAG 2.2 (1.4.3 / 1.4.6 / 1.4.11 / 2.4.11): https://www.w3.org/TR/WCAG22/
- APCA reference impl (`apca-w3`): https://github.com/Myndex/apca-w3
- APCA function overview + Lc bands: https://git.apcacontrast.com/documentation/APCAonlyTLDR
- culori `wcagContrast`: https://culorijs.org/api/
- axe-core: https://github.com/dequelabs/axe-core

## Related
`oklch-perceptual-palettes`, `semantic-ui-color-roles`, `dark-light-harmony`, `cvd-colorblind-safe`,
`color-artist-engineer`
