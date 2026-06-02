---
name: color-artist-engineer
description: >-
  The orchestration + harmony-strategy skill at staff depth: harmony types as OKLCH hue math, the
  chroma budget (not just 60-30-10), brief capture, cultural/sector color semantics, a typed palette
  spec, the full design→verify→token pipeline across the other skills, and a triage table for fixing
  clashing/muddy/neon palettes. Start here for any brand/UI color work, then route to the specialists.
---

# Color Artist-Engineer — Harmony You Can Defend in a PR

**Mandate:** be **artist** (mood, harmony, culture) *and* **engineer** (OKLCH math, measured contrast,
re-themeable tokens) in one pass. A palette that "feels right" but fails AA is broken; a palette that
passes AA but feels like a tax form is also broken. Ship both.

---

## When to use / when NOT to use

- **Use** as the entry point: "harmonize my colors," "the palette feels off," brand refresh (color only),
  dashboard theme, extract a palette from a logo/screenshot. This skill decides *strategy* and *routes*.
- **NOT** the place for the math itself — ramps go to `oklch-perceptual-palettes`, verification to
  `wcag-contrast-color-pairs`, roles to `semantic-ui-color-roles`, output to `palette-to-tokens-export`.
  For a *full* brand kit (logo, type, voice) escalate to `brand-identity-creator` (ui-master).

---

## The dual mandate (keep both columns true at once)

| Artist asks | Engineer answers |
|-------------|------------------|
| Does it feel trustworthy / premium / playful? | Does `foreground` hit 4.5:1 on `background`? |
| Is there one hero, or six fighting? | Is there one `primary` token + one `accent`? |
| Does it reference the brand's world? | Is every value an OKLCH ramp step, not a random hex? |
| Does dark mode keep the mood? | Did dark re-tune L/C, or just invert? |

If you can't answer the right column in numbers, you haven't finished.

---

## Step 1 — Brief (capture or infer before touching color)

| Field | Examples |
|-------|----------|
| Sector | fintech, health, gov, luxury, kids, dev-tool |
| Mood | calm · authoritative · bold · playful · clinical |
| Audience | B2B UAE gov · Gen-Z consumer · enterprise admin |
| Anchor | logo hex, hero photo, "competitor to avoid" |
| Constraints | WCAG AA, dark mode, RTL, no purple-pink AI cliché |
| Surface mix | content-heavy (lots of neutral) vs marketing (more color) |

---

## Step 2 — Harmony strategy = OKLCH hue math (not vibes)

Harmony is **relationships between hue angles** at controlled chroma. Pick the relationship to the brand
hue `H`, then *prove* it with ramps.

| Harmony | Hue relationship (OKLCH H°) | Reads as | Best for |
|---------|-----------------------------|----------|----------|
| **Monochromatic** | one H, vary L/C | refined, quiet | luxury, minimal SaaS |
| **Analogous** | H ± 20–40° | natural, cohesive | wellness, content, calm |
| **Complementary** | H + 180° | energetic, high-tension CTA | sports, bold consumer |
| **Split-complementary** | H + 150° & H + 210° | balanced vibrance | most products (safe default) |
| **Triadic** | H, H+120°, H+240° | playful, vivid | creative tools, kids |
| **Tetradic** | two complementary pairs | rich but risky | dense dashboards (use sparingly) |

**Default to split-complementary** for product UI: a confident brand + a distinct accent without the
clash of true complements. Rule of thumb: **1 dominant hue, 1 support, 1 accent — not six equal heroes.**

---

## Step 3 — The chroma budget (the upgrade over plain 60-30-10)

60-30-10 governs *area*; the **chroma budget** governs *saturation × area*, which is what actually causes
"too loud." Large areas get low chroma; small areas can spend high chroma.

- **60% surface** — neutrals, C ≤ 0.02. The room.
- **30% brand** — primary at moderate C (0.08–0.14 over big areas like nav/headers).
- **10% accent** — the only place high chroma (0.15–0.22) is allowed: CTAs, badges, focus.

Heuristic: `area × chroma` should be roughly constant. If a big panel is vivid, either shrink it or drop
its chroma. "Everything screams" = you overspent the budget on the 60/30 layers.

---

## Step 4 — A typed palette spec (the artifact you hand to engineering)

Capture the decision as data, not a screenshot — this is what the rest of the pipeline consumes:

```ts
// palette.spec.ts
export interface PaletteSpec {
  brand: string;
  harmony: "mono" | "analogous" | "complementary" | "split-complementary" | "triadic" | "tetradic";
  rationale: string;            // 2–3 sentences: why these hues for this brand
  primaryHue: number;           // OKLCH H
  accentHue: number;            // derived from harmony above
  neutralHue: number;           // usually = primaryHue (tinted neutrals)
  peakChroma: { brand: number; accent: number }; // gamut-aware caps
  constraints: { minContrast: "AA" | "AAA"; darkMode: boolean; rtl: boolean; avoid: string[] };
}

export const acme: PaletteSpec = {
  brand: "Acme Pay",
  harmony: "split-complementary",
  rationale: "Fintech trust → deep indigo primary; warm amber accent signals approval/CTA without the " +
             "red/green ambiguity finance users fear; cool tinted neutrals keep dense tables calm.",
  primaryHue: 262,
  accentHue: 70,                // 262 + ~168 ≈ split-complement toward gold
  neutralHue: 262,
  peakChroma: { brand: 0.17, accent: 0.16 },
  constraints: { minContrast: "AA", darkMode: true, rtl: true, avoid: ["purple-pink gradient", "neon green"] },
};
```

---

## Step 5 — Run the pipeline (orchestration)

```
PaletteSpec
  → oklch-perceptual-palettes   build brand + accent + neutral ramps (gamut-clamped)
  → semantic-ui-color-roles     map ramp steps → primary/surface/muted/border/... (+ -foreground pairs)
  → wcag-contrast-color-pairs   verify every pair (WCAG AA gate + APCA), both themes
  → dark-light-harmony          re-map for dark (L↑ C↓ accents, lighter surfaces)
  → cvd-colorblind-safe         confirm status/chart colors survive deuteranopia
  → palette-to-tokens-export    emit DTCG/CSS/Tailwind/types + PALETTE.md
```

If using an LLM to draft, insert `ai-color-harmony-prompting` before the ramp step — but **validate its
output here** (recompute contrast, check gamut). The model proposes; you dispose.

---

## Cultural & sector color semantics (i18n — don't skip)

Color meaning is not universal; shipping the wrong one is a brand error, not a taste one.

| Color | Western default | Watch-outs |
|-------|-----------------|------------|
| Red | error, danger, loss | China/luck & celebration; finance: loss (West) vs up-markets (East Asia) |
| Green | success, go, money | Islam: sacred/positive (good for gov MENA); some contexts: inexperience |
| White | clean, default surface | mourning in parts of East Asia |
| Gold/amber | premium, reward | strong positive in Gulf/MENA gov & luxury |
| Purple | creative, premium | royalty/mourning regionally; the "AI startup" cliché if + pink |

For UAE/MENA gov work: blue-teal trust + gold accent reads formal and culturally safe; validate against
`tailwind-uae-aegov-dls`. Color is direction-neutral, but mirror **gradients/shadows** (implied light
source) in `dir="rtl"`.

---

## Fixing palette disasters (triage table)

| Symptom | Root cause | Fix |
|---------|-----------|-----|
| Too many brand colors | no hierarchy | collapse to primary + accent + neutrals; demote the rest |
| Muddy UI | neutrals too close in L, or mid-chroma bg | spread L ≥ 0.08/step; raise bg L to 0.97+, drop C |
| Neon fatigue | chroma overspent on large areas | cap area C ≤ 0.04; lower C *before* L |
| Clashing | random complementary at full chroma | move to split-complementary; equalize L |
| Dark mode glows | reused light chroma | desaturate accents 15–25%, L up |
| Chart rainbow | default categorical palette | equally-spaced OKLCH hues, same L, ≤ 6–8, CVD-checked |
| Brand hex fails AA | brand chosen for fills, used as text | keep vivid for fills; make a darker text variant (same hue) |

---

## Edge cases & war stories

- **The brand color that fails AA as text.** Marketing picked a bright brand; it can't be body text or a
  button label on white. Don't repaint the brand — create a darker same-hue token for text/labels and keep
  the vivid one for large fills (3:1). Two tokens, one identity.
- **"Make it pop" with no budget left.** Popping is *contrast of chroma*, not more chroma everywhere. Calm
  the 60/30 layers so the 10% accent pops by comparison.
- **Logo-derived palettes.** Extract the dominant hue, then *build a ramp* from it — don't sample 8 pixels
  off the logo and call it a palette. Derive neutrals from the brand hue, not pure gray.
- **Six stakeholders, six favorite colors.** Resolve with the spec + contrast matrix, not opinions: "this
  one fails AA on our surface" ends debates faster than "I prefer the other blue."

---

## Testing / observability

- The deliverable **is** the proof: palette story + swatch table (name/OKLCH/HEX/role) + contrast matrix
  (WCAG + APCA, pass/fail) + a both-themes screenshot. If a reviewer can't see the matrix, it's not done.
- Gate the generated tokens in CI (`wcag-contrast-color-pairs`); a "harmony" tweak that breaks AA must fail
  the build, not surprise QA.

## Anti-patterns
- Hex from a color picker with no ramp logic behind it.
- `#666` on `#777` "because it looks fine."
- Copying Tailwind `blue-500` as every startup's brand.
- Six saturated heroes with no dominant.
- Inverting the light palette for dark.
- Ignoring sector/cultural meaning (red = celebration vs error mismatch).
- Calling it done without a contrast matrix.

## Agent checklist
```
- [ ] Brief captured (sector/mood/audience/anchor/constraints)
- [ ] Harmony chosen as explicit OKLCH hue relationship
- [ ] Chroma budget respected (high chroma only in the 10% accent layer)
- [ ] Typed PaletteSpec produced as the source artifact
- [ ] Pipeline run: ramps → roles → contrast → dark → CVD → tokens
- [ ] Cultural/sector semantics checked for the audience
- [ ] Deliverables: story + swatches + WCAG/APCA matrix + both-theme shots
```

## References
- Interaction Design Foundation — color theory: https://www.interaction-design.org/literature/topics/color-theory
- Refactoring UI (color chapter, practical hierarchy): https://www.refactoringui.com/
- Material 3 color system: https://m3.material.io/styles/color/system/overview

## Related
`oklch-perceptual-palettes`, `wcag-contrast-color-pairs`, `semantic-ui-color-roles`, `dark-light-harmony`,
`cvd-colorblind-safe`, `data-viz-color-scales`, `ai-color-harmony-prompting`, `palette-to-tokens-export`;
`brand-identity-creator` (ui-master)
