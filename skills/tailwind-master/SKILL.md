---
name: tailwind-master
description: >-
  Master hub for Tailwind CSS v4.3+ — the complete production stack. Use for setup
  (Vite/Next/PostCSS), CSS-first @theme tokens, design tokens (3-tier/DTCG),
  CVA + cn() + tailwind-merge, shadcn/ui, Radix headless, RTL/Arabic, dark mode
  & multi-theme, UAE AEGov Design System, Next.js 15 RSC, plugins (forms/typography),
  large-scale architecture & bundle perf, CSS/CSS Modules migration, and v3→v4 upgrades.
  No Tailwind v5 — v4 is current.
  Bundles 13 specialized skills (in skills/<name>/GUIDE.md). Use for any Tailwind task.
---

# Tailwind CSS — Master Hub (v4.3+ full stack)

Use for **any** Tailwind work — from greenfield setup to enterprise design systems,
government portals (UAE DLS), and shadcn/Radix component libraries.

**There is no Tailwind v5.** Latest: **v4.3+** (Oxide engine, CSS-native config).

## Recommended stack (2026)

```
Design Tokens (JSON/DTCG or Figma)
    → @theme / @theme inline in globals.css
    → Tailwind v4 utilities
    → CVA variants + cn(tailwind-merge)
    → Radix primitives (a11y)
    → shadcn/ui patterns (optional)
    → Next.js 15 / Vite + React 19
```

## How to use this hub

1. Match the request to a skill below.
2. Read that skill's `skills/<name>/GUIDE.md` before coding.
3. Combine skills for full builds (e.g. tokens + shadcn + RTL + UAE DLS).

## Bundled skills

- **tailwind-v4-latest** ⭐ — Install, Vite/Next/CLI, `@import "tailwindcss"`, `@theme`, `@source`, Oxide, v3→v4 upgrade, breaking changes, v4.3 utilities.  
  → `skills/tailwind-v4-latest/GUIDE.md`
- **tailwind-design-tokens** ⭐ — 3-tier tokens, OKLCH scales, `@property`/`color-mix()`, `@theme inline` runtime dark/multi-brand, DTCG/Style Dictionary, contrast in CI (WCAG+APCA).  
  → `skills/tailwind-design-tokens/GUIDE.md`
- **tailwind-architecture-scale** ⭐ — Large apps & monorepos: `@apply` tree-shaking trap, dynamic-class pitfalls, `@source`, cascade-layer ordering, DS package structure, CSS bundle budgets in CI, visual regression.  
  → `skills/tailwind-architecture-scale/GUIDE.md`
- **tailwind-cva-components** ⭐ — class-variance-authority, `cn()` + `clsx` + `tailwind-merge`, compound variants, polymorphic `Slot`, component API patterns.  
  → `skills/tailwind-cva-components/GUIDE.md`
- **tailwind-shadcn-ui** — shadcn/ui init on v4, `components.json`, CSS variables ↔ `@theme`, registry components, forms with RHF + Zod.  
  → `skills/tailwind-shadcn-ui/GUIDE.md`
- **tailwind-radix-headless** — Radix UI + Tailwind styling, focus rings, portals, forms, dialogs, data attributes `data-[state=open]`.  
  → `skills/tailwind-radix-headless/GUIDE.md`
- **tailwind-rtl-i18n** — RTL Arabic/Hebrew, logical properties (`ms-`/`me-`, `ps-`/`pe-`), `dir`, bilingual layouts, Noto Arabic, gov portal patterns.  
  → `skills/tailwind-rtl-i18n/GUIDE.md`
- **tailwind-dark-mode-theming** — `class` vs `media` strategy, semantic tokens, `[data-theme]`, prefers-reduced-motion, contrast WCAG.  
  → `skills/tailwind-dark-mode-theming/GUIDE.md`
- **tailwind-uae-aegov-dls** — UAE Design System 3.0: `@aegov/design-system`, `@aegov/design-system-react`, Tailwind 4 plugins, WCAG 2.2, federal branding.  
  → `skills/tailwind-uae-aegov-dls/GUIDE.md`
- **tailwind-nextjs-rsc** — Next.js 15 App Router + Tailwind v4 + RSC-safe styling, `@tailwindcss/postcss`, layouts, no runtime CSS-in-JS.  
  → `skills/tailwind-nextjs-rsc/GUIDE.md`
- **tailwind-plugins-ecosystem** — `@tailwindcss/forms`, `typography`, container queries, custom `@utility`, `@plugin`, DaisyUI vs shadcn decision.  
  → `skills/tailwind-plugins-ecosystem/GUIDE.md`
- **converting-css-to-tailwind** — Plain CSS → v4 utilities, selectors, media, animations.  
  → `skills/converting-css-to-tailwind/GUIDE.md`
- **converting-css-modules-to-tailwind** — `.module.css` → utilities, `styles.xxx` removal.  
  → `skills/converting-css-modules-to-tailwind/GUIDE.md`

## Default workflow (agent)

| Task | Read first | Then |
|------|------------|------|
| New app | `tailwind-v4-latest` | `tailwind-design-tokens` |
| Component library | `tailwind-design-tokens` | `tailwind-cva-components` → `tailwind-radix-headless` |
| shadcn project | `tailwind-v4-latest` | `tailwind-shadcn-ui` |
| Gov UAE portal | `tailwind-uae-aegov-dls` | `tailwind-rtl-i18n` |
| Migrate v3 | `tailwind-v4-latest` | conversion guides |
| Next.js product | `tailwind-nextjs-rsc` | `tailwind-shadcn-ui` |

## Pairs well with

`ui-master` (brand-identity, figma-grade-design-system, forms, a11y testing),
`fullstack-stacks-master` (TypeScript/Next stack), `code-quality-master` (UI review).

## Note

Bundled skills use `GUIDE.md` (not `SKILL.md`) so only this master appears in Cursor's skills list.
