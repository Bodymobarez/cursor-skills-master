---
name: tailwind-shadcn-ui
description: >-
  shadcn/ui on Tailwind v4: CLI init, components.json, registry, CSS variables
  aligned with @theme, cn(), forms (RHF + Zod), and post-upgrade checklist.
---

# shadcn/ui + Tailwind v4

shadcn is **copy-paste components** (not npm package) — you own the code.

## Init (greenfield)

```bash
npx shadcn@latest init
```

Choose: **Next.js**, **Tailwind v4**, **CSS variables**, **RSC** if applicable.

`components.json` essentials:

```json
{
  "style": "new-york",
  "rsc": true,
  "tsx": true,
  "tailwind": {
    "config": "",
    "css": "app/globals.css",
    "baseColor": "neutral",
    "cssVariables": true
  },
  "aliases": {
    "components": "@/components",
    "utils": "@/lib/utils",
    "ui": "@/components/ui"
  }
}
```

## globals.css alignment (v4)

```css
@import "tailwindcss";

@theme inline {
  --color-background: var(--background);
  --color-foreground: var(--foreground);
  --color-primary: var(--primary);
  --color-primary-foreground: var(--primary-foreground);
  --color-muted: var(--muted);
  --color-border: var(--border);
  --radius-lg: var(--radius);
}

:root {
  --background: oklch(1 0 0);
  --foreground: oklch(0.15 0 0);
  --primary: oklch(0.45 0.2 260);
  --primary-foreground: oklch(0.98 0 0);
  --muted: oklch(0.96 0.01 260);
  --border: oklch(0.9 0.01 260);
  --radius: 0.5rem;
}

.dark {
  --background: oklch(0.15 0 0);
  --foreground: oklch(0.95 0 0);
  /* ... */
}
```

## Add components

```bash
npx shadcn@latest add button card dialog form input label select toast
```

## Forms stack

```bash
npm install react-hook-form @hookform/resolvers zod
npx shadcn@latest add form
```

Pattern: Zod schema → `zodResolver` → `<FormField>` + semantic Tailwind on inputs.

## v4 class renames after add

Re-scan generated components for:

- `shadow-sm` → may need `shadow-xs` per v4 scale
- `outline-none` → `outline-hidden` + `focus-visible:ring-3`
- `ring` → explicit `ring-3 ring-ring`
- `bg-gradient-to-r` → `bg-linear-to-r`

## When NOT shadcn

| Use shadcn | Use alternatives |
|------------|------------------|
| SaaS, admin, dashboards | Marketing-only static site |
| Need owned components | `@aegov/design-system-react` (UAE gov) |
| Fast iteration | Full MUI/Chakra (heavier) |

## Related

`tailwind-cva-components`, `tailwind-nextjs-rsc`, `advanced-forms-architecture` (ui-master)
