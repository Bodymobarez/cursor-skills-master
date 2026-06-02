---
name: semantic-ui-color-roles
description: >-
  Map raw ramps to a semantic role layer at staff depth: the primitive→semantic→component tiers, the
  foreground-pairing invariant (fg/bg always travel together), the Radix 12-step scale model, state
  layers via color-mix, chart-series roles, type-safe token names, multi-tenant theming, and a
  stylelint gate banning raw hex in components. Use to stop hex chaos and make the product re-themeable.
---

# Semantic UI Color Roles — Intent Over Value

**Mandate:** components reference **intent** (`bg-primary`, `text-muted-foreground`), never **values**
(`bg-indigo-600`, `text-[#3257d6]`). If you can't re-theme the entire product by swapping one map without
touching a single component, the semantic layer is broken — and that's the only layer that matters.

---

## When to use / when NOT to use

- **Use** when turning a generated palette into something an app consumes: defining the role vocabulary,
  the light/dark maps, chart roles, and the lint that enforces them.
- **NOT** for generating the underlying ramps (`oklch-perceptual-palettes`) or for the file-format export
  (`palette-to-tokens-export`). This skill defines the *contract*; those define the *values* and the
  *artifacts*.

---

## The three tiers (skip the middle one and you lose theming forever)

| Tier | Named by | Example | Referenced in components? |
|------|----------|---------|---------------------------|
| **Primitive** | raw scale position | `--brand-600: oklch(0.55 0.2 262)` | ❌ never |
| **Semantic** | role / intent | `--color-primary`, `--color-surface` | ✅ always |
| **Component** | part (large DS only) | `--btn-bg: var(--color-primary)` | optional |

A rebrand swaps **primitives**. Light/dark/tenant swaps the **semantic→primitive map**. Components touch
**semantic only** and never change. That separation *is* the design system.

---

## The non-negotiable invariant: foreground pairs travel with backgrounds

Every "surface you put text on" ships with its **own** foreground token, and they are validated as a
pair. This is the rule juniors miss and it's why their dark mode breaks.

```
background        → foreground
surface           → on-surface (a.k.a. surface-foreground)
primary           → primary-foreground
accent            → accent-foreground
muted             → muted-foreground
destructive       → destructive-foreground
```

Rule: **you may never set a `bg-*` without knowing its paired `*-foreground`.** A `<Badge>` that hardcodes
white text breaks the instant a tenant ships a pale-yellow brand. Pair, then verify with
`wcag-contrast-color-pairs`.

---

## Naming model: choose role-based or Radix 12-step

| Model | Token shape | Strength | Use when |
|-------|-------------|----------|----------|
| **Role-based (shadcn-style)** | `primary`, `muted`, `border`, `*-foreground` | Tiny vocabulary, fast | Apps, dashboards, most products |
| **Radix 12-step** | `gray-1 … gray-12` per scale, semantics by step | Self-documenting, exhaustive states | Component libraries, dense UIs |
| **Hybrid** | Radix scales *aliased* to roles | Best of both | Mature design systems |

### Radix's 12-step scale — memorize this map (it's the reference standard)

Radix encodes the *use case* into the step number, so you never guess "which gray is the border":

| Step | Purpose |
|------|---------|
| 1 | App background |
| 2 | Subtle background |
| 3 | UI element background (rest) |
| 4 | Hovered UI element background |
| 5 | Active / selected UI element background |
| 6 | Subtle border / separator (non-interactive) |
| 7 | UI element border / focus ring |
| 8 | Hovered UI element border |
| 9 | Solid background (purest, highest chroma) |
| 10 | Hovered solid background |
| 11 | Low-contrast text (secondary, captions) |
| 12 | High-contrast text (headings, body) |

Two facts worth their weight: **step 9 has the highest chroma** in the scale (it's the "brand" fill), and
**steps 11/12 are guaranteed APCA Lc 60 / Lc 90 over step 2** of the same scale. Most step-9s expect white
foreground — *except* Sky, Mint, Lime, Yellow, Amber, which want dark foreground. Bake that exception in.

---

## Core role set (the minimum that survives real products)

```css
:root {
  /* canvas + text */
  --color-background: var(--neutral-50);
  --color-foreground: var(--neutral-900);
  --color-surface: oklch(1 0 0);            /* card lift above background */
  --color-surface-foreground: var(--neutral-900);
  --color-muted: var(--neutral-100);
  --color-muted-foreground: var(--neutral-600); /* MUST hit 4.5:1 on background */

  /* brand actions */
  --color-primary: var(--brand-600);
  --color-primary-foreground: oklch(0.99 0 0);
  --color-accent: var(--accent-600);
  --color-accent-foreground: oklch(0.99 0 0);

  /* lines + focus */
  --color-border: var(--neutral-200);
  --color-input: var(--neutral-300);
  --color-ring: var(--brand-600);

  /* status — each with a foreground */
  --color-destructive: oklch(0.55 0.20 27);
  --color-destructive-foreground: oklch(0.99 0 0);
  --color-success: oklch(0.55 0.14 150);
  --color-warning: oklch(0.70 0.16 75);
}
```

---

## State layers without a parallel palette (color-mix)

Don't author `primary-hover`, `primary-active`, `primary-subtle` by hand. Derive them so a brand change
propagates automatically:

```css
.btn:hover  { background: color-mix(in oklab, var(--color-primary) 90%, black); }
.btn:active { background: color-mix(in oklab, var(--color-primary) 82%, black); }
.row-hover  { background: color-mix(in oklab, var(--color-primary) 8%, transparent); } /* tinted wash */
```

Opacity is `color-mix` too: `bg-primary/12` → `color-mix(in oklab, var(--color-primary) 12%, transparent)`.
Never maintain a second set of faded hexes.

---

## Type-safe consumption (catch typos at compile time)

```ts
// tokens.ts — generated; the single allow-list of roles
export const COLOR_ROLES = [
  "background", "foreground", "surface", "surface-foreground",
  "primary", "primary-foreground", "accent", "accent-foreground",
  "muted", "muted-foreground", "border", "input", "ring",
  "destructive", "destructive-foreground", "success", "warning",
] as const;
export type ColorRole = (typeof COLOR_ROLES)[number];

export const colorVar = (role: ColorRole) => `var(--color-${role})` as const;
```

```tsx
// components consume roles, never values
<Card className="bg-surface text-surface-foreground border-border" />
<Button className="bg-primary text-primary-foreground" />
<p className="text-muted-foreground" />
```

---

## Chart / data-series roles (a distinct namespace)

Chart colors are categorical and must stay distinguishable — keep them out of the brand-role namespace:

```css
--chart-1: oklch(0.62 0.17 262);
--chart-2: oklch(0.62 0.15 145);
--chart-3: oklch(0.62 0.16 50);
--chart-4: oklch(0.62 0.16 320);
--chart-5: oklch(0.62 0.14 195);
/* same L + similar C; hue spaced ~60°+; cap at 6–8 and order by importance */
```

For sequential/diverging scales and CVD-safety, route to `data-viz-color-scales` and `cvd-colorblind-safe`.

---

## Scale / multi-tenant / white-label

Components are written once; tenancy is one attribute at the root. Swap the **semantic map** (or even just
the primitive anchor), never the components:

```html
<html data-tenant="acme" data-theme="dark" dir="rtl">
```

```css
[data-tenant="acme"]   { --brand-600: oklch(0.50 0.25 28);  --color-primary: var(--brand-600); }
[data-tenant="globex"] { --brand-600: oklch(0.58 0.16 175); --color-primary: var(--brand-600); }
```

For 50+ tenants, generate these blocks from a tenant config at build time and verify each tenant's pairs
in CI — a tenant's pale brand can silently fail `primary-foreground` contrast.

---

## Edge cases & war stories

- **Missing `-foreground` is the #1 dark-mode bug.** A component that hardcodes `text-white` on a brand
  fill works until a tenant/dark map makes the fill light. Always pair.
- **`background` vs `surface` confusion.** `background` is the page canvas; `surface` is the lifted card.
  In light mode surface is often *lighter* (white card on gray page); in dark mode surface is *lighter
  than* background (elevation = lighter, see `dark-light-harmony`). Get this backwards and cards vanish.
- **Status colors need foregrounds too.** `bg-destructive text-white` assumes a dark red; a softer error
  token needs a dark foreground. Define `destructive-foreground`.
- **Over-tokenizing.** 200 component-tier tokens nobody reuses is as bad as hex soup. Add a component
  token only when ≥2 components share it or a part needs independent theming.
- **Aliasing shadcn.** shadcn ships its own `--background`/`--primary` vars — alias them to your semantic
  layer so there's *one* source, not two drifting ones: `:root { --primary: var(--color-primary); }`.

---

## Testing strategy

- **Lint raw values out of components** (stylelint), so the contract can't be bypassed:

```jsonc
// .stylelintrc — fail on hex/rgb/oklch literals in component CSS
{
  "rules": {
    "color-no-hex": true,
    "declaration-property-value-disallowed-list": {
      "/color|background|border|fill|stroke/": ["/oklch\\(/", "/rgb\\(/", "/hsl\\(/"]
    }
  }
}
```

  For Tailwind/TSX, add an ESLint rule (or grep gate) banning `bg-[#…]`, `text-[#…]`, and raw palette
  utilities (`bg-indigo-600`) outside the tokens file.
- **Contrast every pair** (`wcag-contrast-color-pairs`) for every theme × tenant.
- **Render a role matrix** (every role on every surface) in Storybook and visual-regression it; a token
  change can't silently break a role.

## Observability / debugging

- Ship a `/dev/tokens` route that lists every role, its resolved value per theme, and its paired contrast
  — the fastest way to spot a missing or mismapped role.
- A "color looks wrong" bug is almost always a primitive→semantic mismap; print `getComputedStyle` of the
  CSS var on the offending node before touching components.

## i18n / RTL

Color is direction-neutral, but the *roles* attached to position are not: use logical properties
(`border-inline-start-color`, not `border-left-color`) so a `--color-border` on the leading edge flips
correctly in `dir="rtl"`. Gradients/shadows that imply a light source should mirror in RTL.

## Anti-patterns

| Bad | Good |
|-----|------|
| `text-blue-600` in a component | `text-primary` |
| `bg-gray-100` on a card | `bg-surface` |
| New hex per screen | Extend the semantic set in the tokens file |
| `bg-primary` with hardcoded `text-white` | `bg-primary text-primary-foreground` |
| `primary-hover` authored by hand | `color-mix(in oklab, primary 90%, black)` |
| Primitives referenced in TSX | Primitives confined to `:root`/theme files |

## Agent checklist
```
- [ ] Three tiers; components reference semantic only
- [ ] Every bg role has a verified paired *-foreground
- [ ] Naming model chosen (role-based / Radix 12-step / hybrid) and consistent
- [ ] State + opacity layers via color-mix, not parallel hex
- [ ] Chart roles in their own namespace, ≤ 6–8, distinguishable
- [ ] Token names type-safe (generated union)
- [ ] stylelint/eslint gate bans raw values in components
- [ ] Multi-tenant = swap map at root; each tenant's pairs verified in CI
```

## References
- Radix Colors — understanding the 12-step scale: https://www.radix-ui.com/colors/docs/palette-composition/understanding-the-scale
- shadcn/ui theming (CSS-var roles): https://ui.shadcn.com/docs/theming
- Material 3 color roles: https://m3.material.io/styles/color/roles
- CSS `color-mix()`: https://developer.mozilla.org/en-US/docs/Web/CSS/color_value/color-mix

## Related
`oklch-perceptual-palettes`, `wcag-contrast-color-pairs`, `dark-light-harmony`, `palette-to-tokens-export`,
`tailwind-design-tokens` (tailwind-master), `figma-grade-design-system` (ui-master)
