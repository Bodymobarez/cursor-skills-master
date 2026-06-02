---
name: tailwind-plugins-ecosystem
description: >-
  Tailwind v4 plugins and extensions: @tailwindcss/forms, typography, container
  queries, custom @utility, @plugin directive, and when to use DaisyUI vs shadcn.
---

# Tailwind v4 Plugins & Ecosystem

## Official plugins (v4 CSS import)

```css
@import "tailwindcss";
@plugin "@tailwindcss/forms";
@plugin "@tailwindcss/typography";
```

### forms
Normalizes inputs; pair with semantic borders:

```html
<input class="border-border rounded-md focus:ring-3 focus:ring-primary/40" />
```

### typography
Prose for CMS/legal content:

```html
<article class="prose prose-neutral dark:prose-invert max-w-none">
```

Prefer **semantic article tokens** over raw `prose-zinc` in product UI.

## Container queries (v4)

```html
<div class="@container">
  <div class="@md:flex @md:flex-row flex-col gap-4">
```

Height-aware (v4.3+): `@container-size` when documented in project Tailwind version.

## Custom utilities

```css
@utility scrollbar-thin {
  scrollbar-width: thin;
}
```

## Third-party: when to use

| Tool | Use case |
|------|----------|
| **shadcn/ui** | Owned React DS, SaaS/admin |
| **@aegov/design-system** | UAE federal sites |
| **DaisyUI** | Rapid HTML prototypes, fewer React deps |
| **Headless UI** | Alternative to Radix (Tailwind Labs) |
| **Flowbite** | Marketing + Tailwind blocks |

**Production SaaS default:** shadcn + Radix + tokens, not DaisyUI.

## tailwind-merge extend

If custom utilities conflict:

```ts
import { extendTailwindMerge } from "tailwind-merge";
export const twMerge = extendTailwindMerge({ extend: { classGroups: { ... } } });
```

## v4.3 utilities to know

- `scrollbar-*`
- `zoom-*`
- `tab-*` (tab width)
- Stacked `@variant`

## Related

`tailwind-v4-latest`, `tailwind-shadcn-ui`
