---
name: tailwind-v4-latest
description: >-
  Tailwind CSS v4.3+ at staff-engineer depth (no v5): Oxide/Lightning CSS engine internals,
  CSS-first @theme, automatic content detection, native cascade layers, @property registered
  tokens, color-mix(), container queries, @starting-style, 3D transforms, v3→v4 migration with
  breaking-change war stories, and bundle/perf discipline. Foundation skill — pair with
  tailwind-design-tokens + tailwind-architecture-scale.
---

# Tailwind CSS v4 Latest (v4.3+) — Production Depth

**Mandate:** ship the v4 way. CSS-first, token-driven, zero JS config, tree-shake-safe.
There is **no v5** — v4.x is current (v4.0 Jan 2025, v4.2 Feb 2026, v4.3 line now).

**Full stack hub:** `tailwind-master` (tokens, CVA, shadcn, Radix, RTL, UAE DLS, Next RSC, scale).

---

## 1. Engine internals (know why it's fast)

v4 replaced the JS/PostCSS pipeline with the **Oxide engine (Rust) + Lightning CSS**:

| Metric | v3.4 | v4 | Why it matters |
|--------|------|----|----------------|
| Cold build | ~12s | ~1.8s | CI + Docker layers |
| HMR update | ~340ms | ~5–12ms | feedback loop, focus retention |
| Incremental (no new CSS) | — | microseconds (100×+) | the common case in real dev |
| Prod CSS | ~48KB | ~31KB | smaller = faster paint |

Implications you should exploit:
- **Lightning CSS is built in** → no `autoprefixer`, no `postcss-import`, no `cssnano`. Remove them.
- **Automatic content detection** → Tailwind reads your module graph and respects `.gitignore`. The `content: []` array is gone. You only add `@source` for files **outside** the graph (e.g. a sibling package, MDX, a CMS-driven safelist).
- Built on **modern CSS primitives**: native `@layer`, `@property`, `color-mix()`, logical properties, container queries. v4 emits these — so your floor is evergreen browsers (Safari 16.4+, Chrome 111+, Firefox 128+). If you must support older, stay on v3.

---

## 2. Install (current)

```bash
# Vite (recommended for SPAs / Remotion / Vite apps)
npm install tailwindcss@latest @tailwindcss/vite@latest

# Next.js / PostCSS pipeline
npm install tailwindcss@latest @tailwindcss/postcss@latest
```

Pin a floor: `"tailwindcss": "^4.3.0"`.

### Vite

```ts
// vite.config.ts
import tailwindcss from "@tailwindcss/vite";
export default defineConfig({ plugins: [tailwindcss()] });
```

```css
/* src/index.css */
@import "tailwindcss";
```

### Next.js 15 (App Router)

```js
// postcss.config.mjs
export default { plugins: { "@tailwindcss/postcss": {} } };
```

```css
/* app/globals.css */
@import "tailwindcss";
```

> Delete v3 leftovers: `@tailwind base/components/utilities`, `tailwind.config.js` as the *primary* config, `autoprefixer`, `postcss-import`.

---

## 3. CSS-first configuration (`@theme`)

Config lives in CSS. `@theme` tokens **emit real CSS variables AND generate utilities**.

```css
@import "tailwindcss";

@theme {
  /* color tokens → utilities (bg-brand, text-brand, ring-brand) + var(--color-brand) */
  --color-brand: oklch(0.55 0.2 260);
  --color-brand-foreground: oklch(0.98 0 0);

  /* type, spacing, radius, breakpoints, easing */
  --font-display: "Inter", ui-sans-serif, system-ui, sans-serif;
  --radius-card: 1rem;
  --breakpoint-3xl: 120rem;
  --ease-snappy: cubic-bezier(0.2, 0, 0, 1);
}
```

**`@theme` vs `@theme inline`** — a decision you must make consciously:

| Use | When |
|-----|------|
| `@theme { --color-x: <literal> }` | static value baked at build (marketing, single theme) |
| `@theme inline { --color-x: var(--color-x) }` | value resolved at **runtime** → required for dark mode, multi-tenant, user themes |

If a utility must change at runtime via a `var()`, it **must** be declared `inline` or Tailwind bakes the resolved literal. This is the #1 v4 theming bug.

---

## 4. Native CSS features you should be using

### Cascade layers (`@layer`) — real, not emulated
v4 emits `@layer theme, base, components, utilities;`. This gives deterministic precedence with third-party CSS. To make your own CSS lose to utilities, put it in an earlier layer:

```css
@layer components {
  .prose-callout { /* utilities still override this */ }
}
```

### `@property` registered custom properties
v4 registers theme vars with `@property`, which makes **gradient and custom-property animations** actually interpolate (previously impossible) and improves paint perf on large pages. You get this for free from `@theme`; for custom animated vars:

```css
@property --angle {
  syntax: "<angle>";
  inherits: false;
  initial-value: 0deg;
}
```

### `color-mix()` powers opacity
`bg-brand/40` compiles to `color-mix(in oklab, var(--color-brand) 40%, transparent)` — works on **CSS variables and `currentColor`**, which v3 could not do. Stop hand-writing rgba.

### Container queries (core, no plugin)
```html
<div class="@container">
  <article class="grid @md:grid-cols-2 @xl:grid-cols-3 gap-6">
```
Named containers: `@container/sidebar` → `@md/sidebar:flex`. This is the modern replacement for viewport breakpoints in component libraries.

### `@starting-style` entry animations (no JS)
```html
<div class="opacity-0 transition-opacity starting:opacity-0 [&.open]:opacity-100">
```
Use the `starting:` variant for enter transitions on `popover`/`dialog`/conditionally-rendered nodes.

### Misc v4 wins
- `not-*` variant: `not-hover:opacity-70`
- 3D transforms: `rotate-x-*`, `rotate-y-*`, `perspective-*`, `transform-3d`
- Gradient API: `bg-linear-*`, `bg-conic-*`, `bg-radial-*`, OKLCH interpolation `bg-linear-to-r/oklch`

---

## 5. Custom variants & utilities

```css
@custom-variant dark (&:where(.dark, .dark *));
@custom-variant hocus (&:hover, &:focus-visible);
@custom-variant aria-current (&[aria-current="page"]);

@utility container {            /* functional utility, tree-shake-safe */
  margin-inline: auto;
  padding-inline: 2rem;
  max-width: 80rem;
}

@plugin "@tailwindcss/forms";
@plugin "@tailwindcss/typography";
```

> Prefer `@utility` (tree-shaken) over `@apply` (not tree-shaken — see `tailwind-architecture-scale`).

---

## 6. v3 → v4 migration (with the breakages that actually bite)

```bash
npx @tailwindcss/upgrade   # Node 20+, dedicated branch, review diff, run visual tests
```

The automated tool handles most syntax. **Manually verify these — they cause silent visual regressions:**

| v3 | v4 | Failure mode if missed |
|----|-----|------------------------|
| `@tailwind` directives | `@import "tailwindcss"` | nothing compiles |
| `theme.extend` (JS) | `@theme { }` | tokens missing |
| `content: []` | auto-detect / `@source` | classes purged in prod only |
| default `border` = gray-200 | `border` = `currentColor` | borders change color sitewide |
| `ring` = 3px blue | `ring` = 1px currentColor; use `ring-3` + `ring-<color>` | focus rings vanish/shrink |
| `shadow-sm` (old) | `shadow-xs` | shadows look wrong |
| `shadow` (old default) | `shadow-sm` | — |
| `outline-none` | `outline-hidden` (a11y-safe) | true `outline:none` removes focus |
| `bg-opacity-50` / `text-opacity-*` | `bg-black/50` (color-mix) | opacity ignored |
| `bg-gradient-to-r` | `bg-linear-to-r` | gradient drops |
| `flex-grow/shrink` | `grow/shrink` | — |

Docs: https://tailwindcss.com/docs/upgrade-guide

---

## 7. Performance & correctness checklist (agent must follow)

```
- [ ] tailwindcss ^4.3 (never v3 on greenfield, never reference "v5")
- [ ] Single @import "tailwindcss"; no @tailwind directives
- [ ] @theme tokens; @theme inline for ANY runtime-themed value
- [ ] @source ONLY for files outside the module graph (sibling pkg, CMS safelist)
- [ ] NO dynamic class strings (`bg-${c}-500`) — Oxide can't see them → purged. Map to full classnames.
- [ ] NO @apply for reuse — extract a component or use @utility (tree-shaking)
- [ ] Removed autoprefixer / postcss-import / cssnano (Lightning CSS handles it)
- [ ] Migrated shadow/ring/outline/border classnames after upgrade
- [ ] border-* always specifies a color token
- [ ] cn() + tailwind-merge on every variant component
- [ ] CSS bundle size tracked in CI (regression = misconfig)
```

---

## 8. Strongest-setup reading order

1. `tailwind-design-tokens` — token architecture + `@property`/`color-mix` theming
2. `tailwind-cva-components` — typed variant components
3. `tailwind-architecture-scale` — large-app, bundle, monorepo, testing
4. `tailwind-shadcn-ui` **or** `tailwind-uae-aegov-dls`
5. `tailwind-rtl-i18n` (Arabic/RTL) · `tailwind-nextjs-rsc` (Next)

## Anti-patterns (opinionated)

- Greenfield on v3, or documenting a non-existent v5.
- Keeping `tailwind.config.ts` as the source of truth instead of `@theme`.
- Dynamic class construction — the single most common "works in dev, broken in prod" bug.
- `@apply` to "clean up" markup → kills tree-shaking, bloats bundle (real cases: 450KB → 142KB after removal).
- Runtime CSS-in-JS (styled-components/Emotion) alongside Next.js RSC.
- Hand-written rgba instead of `/opacity` (color-mix).

## References
- v4 announcement: https://tailwindcss.com/blog/tailwindcss-v4
- Docs: https://tailwindcss.com/docs
- Upgrade: https://tailwindcss.com/docs/upgrade-guide

## Related
All `tailwind-master` skills; `figma-grade-design-system` (ui-master); `color-design-master`.
