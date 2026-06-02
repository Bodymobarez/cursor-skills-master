---
name: tailwind-dark-mode-theming
description: >-
  Dark mode and multi-theme with Tailwind v4: class vs media, @variant dark,
  semantic token swapping, data-theme, system preference, and reduced-motion.
---

# Dark Mode & Multi-Theme (v4)

## Strategy picker

| Strategy | When |
|----------|------|
| **class** `.dark` on `<html>` | User toggle (default for SaaS/gov) |
| **media** `prefers-color-scheme` | Marketing sites, no toggle |
| **data-theme** | 3+ themes (light/dark/high-contrast/tenant) |

## class strategy (recommended)

```css
@import "tailwindcss";

@custom-variant dark (&:where(.dark, .dark *));
```

Or Tailwind v4 default dark variant — verify project `globals.css` docs.

```tsx
// theme-provider.tsx
"use client";
useEffect(() => {
  document.documentElement.classList.toggle("dark", theme === "dark");
}, [theme]);
```

## Semantic swap (correct)

```css
:root {
  --color-surface: oklch(0.99 0 0);
  --color-on-surface: oklch(0.2 0 0);
}
.dark {
  --color-surface: oklch(0.15 0 0);
  --color-on-surface: oklch(0.95 0 0);
}
```

Components: `bg-surface text-on-surface` — **no** `dark:bg-gray-900` on every element.

## data-theme (multi-theme)

```css
[data-theme="contrast"] {
  --color-primary: oklch(0.75 0.2 260);
  --color-border: oklch(0.5 0 0);
}
```

## System + manual

```ts
const systemDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
// respect localStorage override first
```

## Images & elevation

- Dark UI: lower shadow opacity; prefer `border border-border` over heavy shadow
- Logos: provide `dark:hidden` / `hidden dark:block` variants

## Reduced motion

```css
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: 0.01ms !important;
    transition-duration: 0.01ms !important;
  }
}
```

Pair with `tailwind-master` award effects only when motion allowed.

## Testing

Use `dark-mode-testing` skill (ui-master): screenshot light + dark, check contrast.

## Anti-patterns

- 500 lines of `dark:` utilities duplicating light styles
- Gray text `#888` on black (fails WCAG)
- Forgetting `color-scheme: dark` on html for native inputs

```css
.dark { color-scheme: dark; }
```

## Related

`tailwind-design-tokens`, `tailwind-shadcn-ui`
