---
name: tailwind-v4-latest
description: >-
  Tailwind CSS v4.3+ (no v5): Vite/Next/PostCSS/CLI, @import tailwindcss, @theme,
  @theme inline, @source, @custom-variant, Oxide engine, v3→v4 upgrade, breaking
  changes, shadcn, plugins. Foundation skill — pair with tailwind-design-tokens.
---

# Tailwind CSS v4 Latest (v4.3+)

**Always Tailwind v4.x** — **no v5 exists**. Latest line: **v4.3+** (Rust Oxide engine).

**Full stack hub:** use `tailwind-master` for tokens, shadcn, Radix, RTL, UAE DLS, Next.js.

## Install

```bash
npm install tailwindcss@latest @tailwindcss/vite@latest
# PostCSS (Next.js):
npm install tailwindcss@latest @tailwindcss/postcss@latest
```

Pin: `"tailwindcss": "^4.3.0"`

## Setup

### Vite

```ts
import tailwindcss from "@tailwindcss/vite";
export default defineConfig({ plugins: [tailwindcss()] });
```

```css
@import "tailwindcss";
@source "../src/**/*.{tsx,ts,jsx,js}";
```

### Next.js 15

```js
// postcss.config.mjs
export default { plugins: { "@tailwindcss/postcss": {} } };
```

```css
/* app/globals.css */
@import "tailwindcss";
@source "../../app/**/*.{tsx,ts}";
@source "../../components/**/*.{tsx,ts}";
```

### CLI

```bash
npx @tailwindcss/cli -i ./src/input.css -o ./dist/output.css --watch
```

## Configuration: CSS-first

**No primary `tailwind.config.js`** — use CSS:

```css
@import "tailwindcss";

@theme {
  --color-brand: oklch(0.55 0.2 260);
  --font-sans: "Inter", ui-sans-serif, system-ui;
  --radius-card: 1rem;
  --breakpoint-3xl: 120rem;
}

/* Runtime theming (dark / multi-tenant) */
@theme inline {
  --color-primary: var(--color-primary);
  --color-background: var(--color-background);
}

@source "../app/**/*.{tsx,ts}";
```

## Custom variants

```css
@custom-variant dark (&:where(.dark, .dark *));
@custom-variant hocus (&:hover, &:focus-visible);
```

## Upgrade v3 → v4

```bash
npx @tailwindcss/upgrade   # Node 20+, use a branch
```

| v3 | v4 |
|----|-----|
| `@tailwind base/components/utilities` | `@import "tailwindcss"` |
| `theme.extend` in JS | `@theme { }` |
| `content: []` | `@source "path"` |
| `bg-opacity-50` | `bg-black/50` |
| `flex-grow` | `grow` |
| old `shadow-sm` | `shadow-xs` |
| old default `shadow` | `shadow-sm` |
| `outline-none` | `outline-hidden` + focus ring |
| default `ring` | `ring-3` + `ring-color` |
| `bg-gradient-to-r` | `bg-linear-to-r` |
| default border gray | `border` uses `currentColor` — set `border-border` |

Docs: https://tailwindcss.com/docs/upgrade-guide

## v4.3+ utilities

- `scrollbar-thin`, `scrollbar-thumb-*`
- `@container` / `@container-size`
- `zoom-*`
- `@utility` for custom utilities
- `@plugin` for official/third-party plugins

## Production checklist

```
- [ ] tailwindcss ^4.3 (not v3, not "v5")
- [ ] @import "tailwindcss" only
- [ ] @theme + semantic tokens (@theme inline if runtime themes)
- [ ] @source includes app, components, node_modules UI libs
- [ ] Vite plugin OR @tailwindcss/postcss
- [ ] Removed legacy autoprefixer-only pipeline for Tailwind
- [ ] Shadow/ring/outline classes audited post-migration
- [ ] border-* includes color token
- [ ] cn() + tailwind-merge on components
```

## Stack completion (strongest setup)

After this skill, read in order:

1. `tailwind-design-tokens`
2. `tailwind-cva-components`
3. `tailwind-shadcn-ui` OR `tailwind-uae-aegov-dls`
4. `tailwind-rtl-i18n` (if Arabic)
5. `tailwind-nextjs-rsc` (if Next)

## Anti-patterns

- New projects on v3
- Documenting fictional v5
- Raw hex in components instead of `@theme` tokens
- `bg-opacity-*` / `text-opacity-*`
- Keeping JS config as sole source of truth
- Runtime CSS-in-JS with Next.js RSC

## Related

All skills in `tailwind-master`; `figma-grade-design-system` (ui-master)
