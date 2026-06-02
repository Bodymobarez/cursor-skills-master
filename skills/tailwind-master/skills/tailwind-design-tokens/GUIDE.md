---
name: tailwind-design-tokens
description: >-
  Production design-token architecture on Tailwind v4 at staff depth: 3-tier hierarchy
  (primitive → semantic → component), OKLCH tonal scales, @property registration, color-mix
  opacity, @theme inline runtime theming, multi-brand/white-label, DTCG + Style Dictionary
  pipeline, type-safe token names, and contrast enforced in CI. Use with tailwind-v4-latest.
---

# Tailwind Design Tokens (v4) — Production Architecture

**Tokens are the source of truth; utilities are an output.** A token changes once → the whole
product retheme without touching a single component. If you can't retheme without find-and-replace,
your token layer is broken.

---

## 1. Three tiers (never skip the semantic tier)

| Tier | Names by | Example | Referenced in components? |
|------|----------|---------|---------------------------|
| **Primitive** | raw value | `--brand-600: oklch(0.55 0.2 260)` | ❌ never |
| **Semantic** | intent/role | `--color-primary`, `--color-surface` | ✅ always |
| **Component** | part | `--btn-bg: var(--color-primary)` | optional (large DS) |

Why: a rebrand swaps **primitives**; light/dark/tenant swaps the **semantic→primitive map**;
components reference **semantic** only and never change. This is the entire game.

---

## 2. OKLCH tonal scales (perceptually uniform)

Build scales in **OKLCH** (Oklab-based) — equal L steps look equally light across hues, which HSL/HEX
cannot guarantee. Tailwind v4, Radix Colors, and serious DS's all moved to it.

```css
:root {
  /* primitive ramp — fixed hue (H), descending L, chroma tapering at the ends */
  --brand-50:  oklch(0.97 0.02 260);
  --brand-100: oklch(0.93 0.04 260);
  --brand-200: oklch(0.88 0.07 260);
  --brand-300: oklch(0.80 0.10 260);
  --brand-400: oklch(0.70 0.14 260);
  --brand-500: oklch(0.62 0.17 260);
  --brand-600: oklch(0.55 0.20 260);  /* primary anchor */
  --brand-700: oklch(0.47 0.18 260);
  --brand-800: oklch(0.40 0.15 260);
  --brand-900: oklch(0.32 0.11 260);
  --brand-950: oklch(0.24 0.08 260);
}
```

Neutrals: keep chroma ≤ 0.02 and lock a single hue so grays don't drift into "rainbow gray".
(For ramp math, contrast science, and AI palette generation, route to **`color-design-master`**.)

---

## 3. Semantic layer + runtime theming

```css
/* light (default) */
:root {
  --color-background: var(--brand-50);
  --color-foreground: oklch(0.20 0.02 260);
  --color-surface:    oklch(0.99 0 0);
  --color-primary:    var(--brand-600);
  --color-primary-foreground: oklch(0.99 0 0);
  --color-muted:           oklch(0.94 0.01 260);
  --color-muted-foreground: oklch(0.45 0.02 260);
  --color-border:     oklch(0.88 0.02 260);
  --color-ring:       var(--brand-600);
}

/* dark — swap the map, NOT the components */
.dark, [data-theme="dark"] {
  --color-background: oklch(0.16 0.02 260);
  --color-foreground: oklch(0.95 0.01 260);
  --color-surface:    oklch(0.20 0.02 260);
  --color-primary:    var(--brand-400);   /* L up, C down for dark — see color-design-master */
  --color-muted:           oklch(0.30 0.02 260);
  --color-muted-foreground: oklch(0.72 0.02 260);
  --color-border:     oklch(0.32 0.02 260);
  color-scheme: dark;                       /* native form controls follow */
}
```

Expose to utilities at **runtime** with `@theme inline` (mandatory for theming — see tailwind-v4-latest §3):

```css
@theme inline {
  --color-background: var(--color-background);
  --color-foreground: var(--color-foreground);
  --color-surface: var(--color-surface);
  --color-primary: var(--color-primary);
  --color-primary-foreground: var(--color-primary-foreground);
  --color-muted: var(--color-muted);
  --color-muted-foreground: var(--color-muted-foreground);
  --color-border: var(--color-border);
  --color-ring: var(--color-ring);
  --radius-lg: 0.75rem;
  --font-sans: "Inter", ui-sans-serif, system-ui, sans-serif;
}
```

---

## 4. `@property` + `color-mix()` (v4 superpowers)

Register animatable/typed tokens so they interpolate and paint efficiently:

```css
@property --color-primary {
  syntax: "<color>";
  inherits: true;
  initial-value: oklch(0.55 0.2 260);
}
```

Opacity comes from `color-mix` automatically: `bg-primary/12` →
`color-mix(in oklab, var(--color-primary) 12%, transparent)`. Use `/opacity` everywhere; never
maintain a parallel set of faded hexes.

---

## 5. Multi-brand / white-label (one codebase, N brands)

```html
<html data-tenant="acme" class="dark">
```

```css
[data-tenant="acme"] { --brand-600: oklch(0.50 0.25 30); --color-primary: var(--brand-600); }
[data-tenant="globex"] { --brand-600: oklch(0.58 0.16 175); --color-primary: var(--brand-600); }
```

Switch one attribute at the root → entire UI re-themes, zero component edits, zero rebuild.

---

## 6. DTCG pipeline (enterprise / Figma sync)

Single source → many targets. Don't hand-maintain CSS + Figma + native separately.

```
Figma Variables / tokens.json (W3C DTCG)
   → Style Dictionary build
   → outputs: globals.css (vars) · tailwind @theme snippet · TS token types · iOS/Android
   → CI diff: fail build if Figma export ≠ committed tokens (no drift)
```

```jsonc
// tokens/color.json (DTCG)
{ "color": {
  "primary":    { "$type": "color", "$value": "oklch(0.55 0.2 260)" },
  "background": { "$type": "color", "$value": "oklch(0.97 0.02 260)" }
}}
```

Type-safe usage:

```ts
// generated token-names.ts
export type ColorToken = "primary" | "background" | "surface" | "muted" | "border";
```

---

## 7. Contrast enforced by construction (not by hope)

- **WCAG 2.2 AA is the legal floor**: 4.5:1 body, 3:1 large/UI/borders, focus ring ≥ 3:1.
- **APCA** (signed Lc, font-size/weight aware) as the stricter perceptual check — especially for
  dark mode and text on tinted surfaces where WCAG 2 passes can look weak.
- Gate it in CI: `axe-core` in unit tests + Lighthouse in CI, **hard-fail on any AA miss**.
- When a brand color fails AA: restrict to large-text/non-text role, move to a darker surface, or
  negotiate a 10% L/C shift — never ship the failing pair. (Full method: `color-design-master`.)

---

## 8. shadcn alignment

shadcn ships `:root`/`.dark` CSS vars — alias them to your semantic layer so there's **one** source:

```css
:root { --background: var(--color-background); --primary: var(--color-primary); --border: var(--color-border); }
```

---

## Agent checklist
```
- [ ] No raw hex/oklch literals in TSX (one-off marketing hero excepted)
- [ ] Primitives live only in :root/theme files; components use semantic utilities
- [ ] @theme inline for every runtime-themed token
- [ ] color-scheme set per theme; dark swaps the map, not 300 dark: utilities
- [ ] /opacity (color-mix) instead of parallel faded colors
- [ ] Contrast verified in CI (AA floor) + APCA sanity check
- [ ] DTCG single source if Figma + multi-platform
```

## Anti-patterns
- `bg-purple-500` / `text-[#3F51B5]` scattered in components (value-named, un-rethemable).
- Tokens duplicated in `tailwind.config.js` **and** CSS (v4 = CSS only).
- Light/dark as two parallel component trees instead of a swapped semantic map.
- Skipping the semantic tier ("just use primitives") — kills theming forever.

## References
- OKLCH/Oklab background; DTCG: https://www.designtokens.org
- Tailwind v4 theme: https://tailwindcss.com/docs/theme

## Related
`tailwind-v4-latest`, `tailwind-dark-mode-theming`, `color-design-master`, `figma-grade-design-system` (ui-master)
