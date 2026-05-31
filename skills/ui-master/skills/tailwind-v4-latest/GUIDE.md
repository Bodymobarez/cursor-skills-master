---
name: tailwind-v4-latest
description: >-
  Use Tailwind CSS at the latest version (v4.x, currently v4.3+). Use for new
  projects, upgrades from v3, setup with Next.js/Vite/PostCSS, CSS-first @theme
  config, Oxide engine, breaking changes, shadcn/ui compatibility, and v4.3
  utilities. There is no Tailwind v5 — v4 is the current major release.
---

# Tailwind CSS v4 Latest (v4.3+)

**Always use Tailwind v4.x** — there is **no v5**. Latest stable line: **v4.3+** (Oxide engine, CSS-native config).

> Default stack: **Tailwind v4 + React + Vite or Next.js 15**. Pair with `figma-grade-design-system` for tokens.

## Install (latest)

```bash
npm install tailwindcss@latest @tailwindcss/vite@latest
# or PostCSS:
npm install tailwindcss@latest @tailwindcss/postcss@latest
```

Pin in `package.json`: `"tailwindcss": "^4.3.0"` (or `@latest` on greenfield).

## Setup by bundler

### Vite (recommended)

```ts
// vite.config.ts
import tailwindcss from "@tailwindcss/vite";
export default defineConfig({ plugins: [tailwindcss()] });
```

```css
/* src/index.css */
@import "tailwindcss";
```

### Next.js 15

```bash
npm install tailwindcss @tailwindcss/postcss
```

```js
// postcss.config.mjs
export default { plugins: { "@tailwindcss/postcss": {} } };
```

```css
/* app/globals.css */
@import "tailwindcss";
```

Remove v3 leftovers: `postcss-import`, `autoprefixer`, `@tailwind base/components/utilities`.

### CLI

```bash
npx @tailwindcss/cli -i ./src/input.css -o ./dist/output.css
```

## Configuration: CSS-first (`@theme`) — not `tailwind.config.js`

v4 config lives in **CSS**, not a huge JS file:

```css
@import "tailwindcss";

@theme {
  /* colors → utilities: bg-brand, text-brand */
  --color-brand: oklch(0.55 0.2 260);
  --color-brand-foreground: oklch(0.98 0 0);

  /* fonts → font-display */
  --font-display: "Inter", ui-sans-serif, system-ui, sans-serif;

  /* spacing/radius extensions */
  --radius-card: 1rem;

  /* breakpoints (optional override) */
  --breakpoint-3xl: 120rem;
}

/* scan paths (replaces content[] in old config) */
@source "../app/**/*.{tsx,ts}";
@source "../components/**/*.{tsx,ts}";
```

- Design tokens from `brand-identity-creator` map directly into `@theme`.
- Dark mode: `@variant dark (&:where(.dark, .dark *));` or `prefers-color-scheme` strategy in docs.

## Upgrade v3 → v4

```bash
npx @tailwindcss/upgrade
```
Requires **Node 20+**. Run in a branch; review diff; test UI.

### Manual breaking changes (must know)

| v3 | v4 |
|----|-----|
| `@tailwind base;` … | `@import "tailwindcss";` |
| `tailwind.config.js` `theme.extend` | `@theme { --color-* … }` |
| `content: [...]` | `@source "path/**/*.tsx"` |
| `bg-opacity-50` | `bg-black/50` |
| `flex-grow` / `flex-shrink` | `grow` / `shrink` |
| `shadow-sm` (old small) | `shadow-xs` (scale renamed) |
| `shadow` (old default) | `shadow-sm` |
| `outline-none` (a11y ring) | `outline-hidden` |
| `ring` (3px default) | `ring-3` + explicit `ring-color` |
| `bg-gradient-to-r` | `bg-linear-to-r` |
| Default `border` color gray-200 | `currentColor` — add `border-gray-200` explicitly |
| `space-y-*` on inline layouts | prefer `flex flex-col gap-*` |

Full list: https://tailwindcss.com/docs/upgrade-guide

## v4.3+ new utilities (use them)

- **Scrollbars**: `scrollbar-thin`, `scrollbar-thumb-*`, `scrollbar-track-*`
- **Container size queries**: `@container-size` for height-aware container queries
- **`zoom-*`**: CSS `zoom` property utilities
- **`tab-*`**: tab character width
- **Stacked `@variant`**: compound variants in CSS
- **Functional utilities** with defaults in `@utility`

## Custom utilities & plugins

```css
@utility container {
  margin-inline: auto;
  padding-inline: 2rem;
  max-width: 80rem;
}

@plugin "@tailwindcss/forms";
@plugin "@tailwindcss/typography";
```

## shadcn/ui + v4

- Init shadcn with **Tailwind v4** template (CLI tracks latest).
- CSS variables in `:root` / `.dark` still work; align with `@theme` colors.
- Components use `cn()` + tailwind-merge — keep `tailwind-merge` updated.
- After upgrade: re-check `ring`, `shadow`, `border` class names against v4 renames.

## Project checklist (agent must follow)

```
- [ ] tailwindcss@^4.3 (not v3, not imaginary v5)
- [ ] @import "tailwindcss" in global CSS (no @tailwind directives)
- [ ] @theme tokens; @source paths cover all template files
- [ ] Vite plugin OR @tailwindcss/postcss (not old tailwindcss PostCSS plugin alone)
- [ ] Removed autoprefixer/postcss-import unless needed for non-Tailwind CSS
- [ ] Updated shadow/ring/outline class names if migrating v3 markup
- [ ] borders specify color (border-border or border-gray-200)
- [ ] Prefer gap over space-y where layout broke after upgrade
```

## Anti-patterns

- Creating new projects on **Tailwind v3** or documenting **v5** (doesn't exist).
- Keeping `tailwind.config.ts` as primary config without migrating to `@theme`.
- Using `bg-opacity-*` / `text-opacity-*` (removed).
- Assuming `ring` still means 3px blue halo (v4 default changed).
- Skipping `npx @tailwindcss/upgrade` on large v3 codebases.

## Related skills

- `converting-css-to-tailwind` / `converting-css-modules-to-tailwind` — class migration
- `figma-grade-design-system` — tokens → `@theme`
- `using-ui-stack` — design-system discipline with Tailwind
