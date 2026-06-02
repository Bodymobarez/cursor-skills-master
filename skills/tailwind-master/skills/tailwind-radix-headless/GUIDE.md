---
name: tailwind-radix-headless
description: >-
  Style Radix UI primitives with Tailwind v4: data-state attributes, focus rings,
  portals, Dialog/Sheet/Dropdown/Select/Toast, forms, and WCAG patterns without
  runtime CSS-in-JS.
---

# Radix UI + Tailwind v4

Radix = **behavior + a11y**; Tailwind = **look**. Zero runtime style injection.

## Install (per primitive)

```bash
npm install @radix-ui/react-dialog @radix-ui/react-dropdown-menu @radix-ui/react-select
```

Or full set via `@aegov/design-system-react` (gov) / shadcn (pre-wired).

## Styling with data attributes

```tsx
<Dialog.Overlay className="fixed inset-0 bg-black/50 data-[state=open]:animate-in data-[state=closed]:animate-out" />
<Dialog.Content className="fixed left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2 rounded-lg bg-background p-6 shadow-lg data-[state=open]:zoom-in-95" />
```

Common attributes: `data-[state=open]`, `data-[state=closed]`, `data-[disabled]`, `data-[highlighted]`, `data-[side=bottom]`.

## Focus (v4)

```css
/* base for all interactive primitives */
focus-visible:outline-hidden focus-visible:ring-3 focus-visible:ring-primary/40
```

Never `outline-none` without visible focus substitute.

## Portal + z-index scale

Define token layer in `@theme`:

```css
@theme {
  --z-dropdown: 50;
  --z-modal: 100;
  --z-toast: 200;
}
```

```tsx
className="z-[var(--z-modal)]"
```

## Select / Combobox

- Trigger: `flex h-10 w-full items-center justify-between rounded-md border border-border bg-background px-3`
- Content: `max-h-60 overflow-auto rounded-md border bg-popover p-1 shadow-md`
- Item: `data-[highlighted]:bg-muted cursor-default rounded-sm px-2 py-1.5`

## Dialog vs Sheet

| Pattern | Use |
|---------|-----|
| Dialog | Confirmations, short forms |
| Sheet (Dialog side panel) | Filters, mobile nav, multi-field |

## RSC note

Radix primitives need **`"use client"`** in Next.js App Router. Keep server parents; import client leaf components only.

## Related

`tailwind-cva-components`, `tailwind-shadcn-ui`, `accessibility-auditing` (ui-master)
