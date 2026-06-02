---
name: tailwind-architecture-scale
description: >-
  Tailwind v4 at scale (staff/principal): design-system package structure, monorepo @source,
  cascade-layer ordering with third-party CSS, the @apply tree-shaking trap, dynamic-class
  pitfalls, CSS bundle budgets in CI, visual regression, and migration governance. Use for
  large codebases, component libraries, and multi-app monorepos.
---

# Tailwind v4 — Architecture & Scale

For codebases where many engineers, multiple apps, and a shared design system meet. The failure
modes here are **bundle bloat, purge surprises, and cascade conflicts** — all preventable.

---

## 1. The `@apply` tree-shaking trap (most important)

`@apply` inlines utilities into a custom class. At scale this **defeats Oxide tree-shaking** and
bloats CSS (documented real case: **450KB → 142KB** after removing `@apply`). Rules:

| Need | Do | Not |
|------|----|-----|
| Reuse a utility combo 3+ times | **Extract a component** (class string on the element) | `@apply` a `.btn` class |
| Genuinely reusable primitive (button base) | `@utility name { ... }` (v4 tree-shakes it) | `.btn { @apply ... }` |
| One-off | inline utilities | new CSS class |

> Heuristic: if it has props/variants → React component (`tailwind-cva-components`). If it's a static
> utility with no variants → `@utility`. `@apply` is almost never the right answer in v4.

---

## 2. Dynamic class names — the silent prod break

Oxide statically scans source text. It **cannot see** constructed strings:

```tsx
// ❌ purged in production (works in dev because all classes existed once)
<div className={`bg-${color}-500 text-${size}`} />

// ✅ full class names, mapped
const TONE = { brand: "bg-brand-500", danger: "bg-red-500" } as const;
<div className={TONE[tone]} />
```

If you *must* allow arbitrary runtime classes (CMS, theming UI), use an explicit **safelist** via a
dedicated `@source` file containing the full class names, and document why.

---

## 3. Content detection & monorepo `@source`

v4 auto-detects via the module graph + `.gitignore`. You add `@source` only for files **outside** it:

```css
@import "tailwindcss";

/* app's own files: auto-detected, nothing needed */

/* shared UI package consumed from node_modules or a sibling workspace: */
@source "../../packages/ui/src/**/*.{ts,tsx}";

/* MDX / CMS-driven content with classes not in the graph: */
@source "../content/**/*.mdx";
```

Pitfall: a shared component library installed from `node_modules` whose classes only appear there —
without `@source` pointing at it, those utilities get purged. Symptom: **library looks unstyled in the consuming app only.**

---

## 4. Cascade layer ordering with third-party CSS

v4 emits `@layer theme, base, components, utilities;`. Third-party stylesheets (a date picker, a rich
text editor) are usually **unlayered**, and unlayered CSS beats layered CSS — so vendor styles can
override your utilities unexpectedly. Fix by importing them into an explicit early layer:

```css
@layer vendor {
  @import "some-datepicker/dist/style.css";
}
/* declare order so utilities still win where you want */
@layer theme, base, vendor, components, utilities;
```

---

## 5. Design-system package structure (monorepo)

```
packages/ui/
  src/
    styles/theme.css        # @theme tokens (single source) — exported
    lib/utils.ts            # cn()
    components/{button,...}.tsx
  package.json              # exports "./styles/theme.css" and components
apps/web/
  app/globals.css           # @import "tailwindcss"; @import "@acme/ui/styles/theme.css";
                            # @source "../../packages/ui/src/**/*.{ts,tsx}";
```

- Tokens defined **once** in the package; every app imports them → guaranteed consistency.
- Components ship as source (tree-shaken per app) or pre-built; either way apps add `@source`.
- Version the package; a token change is a semver-meaningful event.

---

## 6. CSS bundle budget in CI (treat like JS budget)

A sudden CSS size jump = a misconfiguration (dynamic classes, `@apply`, bad `@source`). Catch it:

```yaml
# CI step (concept)
- run: npm run build
- run: |
    SIZE=$(gzip -c dist/assets/*.css | wc -c)
    echo "CSS gzip: $SIZE bytes"
    test "$SIZE" -lt 51200   # hard fail >50KB gzip; tune per app
```

Add `prettier-plugin-tailwindcss` (class sorting) + `eslint-plugin-tailwindcss` to catch issues in review.

---

## 7. Visual regression (design systems must have it)

Token/variant changes ripple everywhere. Protect with screenshots:

```ts
// Playwright
test("button matrix", async ({ page }) => {
  await page.goto("/__ui/buttons");
  await expect(page).toHaveScreenshot("buttons.png", { maxDiffPixelRatio: 0.01 });
});
```

Run on PRs; a diff forces an intentional review of design changes.

---

## 8. Migration governance (v3 → v4 across many apps)

- Migrate the **shared UI package first**, pin it, then bump apps one at a time.
- Codemod with `npx @tailwindcss/upgrade` per app on a branch; gate merge on visual-regression pass.
- Track the breaking-change list (border/ring/shadow/outline/opacity/gradient) in the PR template.

## Agent checklist
```
- [ ] No @apply for reuse; components or @utility instead
- [ ] No dynamic class strings; safelist documented if unavoidable
- [ ] @source covers every shared/library/CMS path outside the module graph
- [ ] Vendor CSS wrapped in an explicit @layer with declared order
- [ ] Tokens defined once in a shared package; apps import them
- [ ] CSS gzip budget enforced in CI; class-sort + lint plugins on
- [ ] Visual-regression on the component matrix
```

## Anti-patterns
- "Let's make a `.card` with `@apply` to keep JSX clean" → bundle bloat + lost colocation.
- Per-app duplicated `@theme` → drift between apps.
- Trusting dev rendering for purge correctness (always verify a prod build).
- Shipping a DS without visual regression → silent breakage on token edits.

## References
- Large-project practices & @apply pitfalls; v4 performance: https://tailwindcss.com/blog/tailwindcss-v4

## Related
`tailwind-v4-latest`, `tailwind-cva-components`, `tailwind-design-tokens`, `fullstack-stacks-master`
