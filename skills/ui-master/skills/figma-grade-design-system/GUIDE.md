---
name: figma-grade-design-system
description: >-
  Design and generate Figma-grade (and better) design systems directly in code.
  Use when the user wants top-tier design quality, a design system that rivals/
  beats Figma, design-to-code, component libraries with variants, design tokens,
  auto-layout reasoning, or a polished UI kit. Produces structured tokens,
  variant-driven components, and design specs an engineer/designer would ship.
---

# Figma-Grade Design System (in code)

Bring Figma's design power into the codebase — and exceed it by making the system **live,
typed, and shippable** (tokens → components → product) instead of static frames.

> Philosophy: Figma describes design; **code is the design**. A token changes once and the entire
> product updates. Components have real variants/states, real a11y, real motion. That's better
> than a Figma file because it can't drift from production.

## 1. Token architecture (3 tiers — the spine of the system)

```
PRIMITIVE (raw)        SEMANTIC (intent)         COMPONENT (scoped)
--blue-600:#2563eb  →  --color-action:var(--blue-600)  →  --button-bg:var(--color-action)
--space-4:1rem      →  --space-md:var(--space-4)        →  --card-pad:var(--space-md)
```
- Never reference primitives in components — always go through semantic tokens (enables theming,
  dark mode, brand swaps, white-label in one place).
- Emit in **W3C Design Tokens** JSON + CSS variables + Tailwind theme. Single source → all targets.
- Token groups: color, spacing (4/8 scale), radius, typography (type scale), shadow/elevation,
  motion (durations/easings), z-index, breakpoints, opacity, blur.

## 2. Type scale & spacing (the things that separate pro from amateur)

- **Modular type scale** (ratio 1.2–1.333): e.g. 12·14·16·20·24·32·40·56·72. Define line-height,
  letter-spacing, and font-weight per step. Use **fluid type** with `clamp()` for responsive.
- **8-point grid** for spacing; optical alignment for icons/text; consistent rhythm.
- Contrast & hierarchy via size + weight + color token, not random values.

## 3. Components: variant-driven (Figma "variants/props" → code)

Model components as **variant × state** matrices, like Figma component properties:
```
Button: variant{primary|secondary|ghost|destructive} × size{sm|md|lg}
        × state{default|hover|active|focus|disabled|loading}
```
- Build with **CVA (class-variance-authority) + Tailwind** or styled tokens; types enforce valid combos.
- Headless behavior from **Radix UI / React Aria** (a11y, focus, keyboard) + your token styling.
- Every interactive state designed (not just default): hover, focus-visible ring, active, disabled,
  loading, empty, error. This is where "polished" lives.
- Document with stories (Storybook) — your living, better-than-Figma spec.

## 4. Recommended stack (2026)
- **Tailwind v4** (CSS-first `@theme` tokens) or vanilla CSS variables.
- **shadcn/ui** as a base, then re-skin with your tokens (don't ship default shadcn look — elevate it).
- **Radix/React Aria** (headless) + **CVA** (variants) + **Framer Motion** (motion).
- Tokens pipeline: **Style Dictionity / Tokens Studio** or a small custom emitter.

## 5. Design quality checklist (the "Figma-beating" bar)
```
- [ ] 3-tier tokens; components only use semantic/component tokens
- [ ] Modular type scale + fluid clamp() + 8pt spacing grid
- [ ] Every component: all variants × all states designed (incl. focus-visible, loading, empty, error)
- [ ] Consistent elevation/shadow system + radius scale
- [ ] Motion tokens (durations/easings) applied consistently; reduced-motion honored
- [ ] Dark mode + theming via token swap (no hardcoded colors)
- [ ] WCAG AA contrast on every token pair; 44px touch targets
- [ ] Pixel-perfect alignment (optical), no magic numbers
- [ ] Storybook/specs as the living design source of truth
```

## 6. Design-to-code & Figma interop
- Import Figma tokens via **Tokens Studio** export or the Figma Variables REST API → map to your
  3-tier tokens. Generate components from the token set, not by eyeballing screenshots.
- When given a screenshot/mock: extract palette, type scale, spacing rhythm, radii, shadows first
  → rebuild as tokens+components (don't hardcode one-off values).

## Anti-patterns
- Hardcoded hex/px in components instead of tokens (system can't evolve/theme).
- Only the default state styled; ignoring focus/loading/empty/error.
- Shipping default shadcn/Bootstrap look as "the design" (it's a starting point, not the finish).
- Inconsistent spacing/type (no scale) — the #1 amateur tell.
- Treating a Figma file as truth while code drifts — make code the source of truth.
