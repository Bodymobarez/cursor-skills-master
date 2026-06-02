---
name: tailwind-cva-components
description: >-
  Build typed, accessible Tailwind v4 components at staff depth: class-variance-authority,
  cn() (clsx + tailwind-merge, configured), compound + default variants, polymorphic Slot,
  RSC client boundaries, focus/a11y, and variant testing. Use for design-system primitives.
---

# Tailwind + CVA Components — Production Patterns

**Stack:** semantic token utilities + `cva` (typed variants) + `cn()` (clsx + tailwind-merge).
This is the shadcn pattern, done correctly and explained.

## Install
```bash
npm install class-variance-authority clsx tailwind-merge
```

## `lib/utils.ts` — `cn()` (and when to extend it)

```ts
import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}
```

`tailwind-merge` resolves conflicts so caller overrides win (`<Button className="bg-red-600">`
beats the variant's `bg-primary`). **If you add custom `@theme` keys** (e.g. `--text-hero`,
`--shadow-glow`), teach tailwind-merge about them or it won't dedupe correctly:

```ts
import { extendTailwindMerge } from "tailwind-merge";
export const twMerge = extendTailwindMerge({
  extend: { classGroups: { "font-size": [{ text: ["hero", "display"] }] } },
});
```

## Reference component (button — copy/paste quality)

```tsx
import { cva, type VariantProps } from "class-variance-authority";
import { Slot } from "@radix-ui/react-slot";
import { cn } from "@/lib/utils";

const buttonVariants = cva(
  // base: layout + a11y focus (v4: outline-hidden + ring-3) + disabled + motion
  "inline-flex items-center justify-center gap-2 rounded-lg font-medium whitespace-nowrap " +
    "transition-colors outline-hidden focus-visible:ring-3 focus-visible:ring-ring/50 " +
    "disabled:pointer-events-none disabled:opacity-50 " +
    "[&_svg]:size-4 [&_svg]:shrink-0 select-none",
  {
    variants: {
      variant: {
        primary:   "bg-primary text-primary-foreground hover:bg-primary/90 active:bg-primary/80",
        secondary: "bg-muted text-foreground hover:bg-muted/80",
        outline:   "border border-border bg-transparent hover:bg-muted",
        ghost:     "hover:bg-muted",
        link:      "text-primary underline-offset-4 hover:underline",
        destructive:"bg-red-600 text-white hover:bg-red-600/90 focus-visible:ring-red-600/40",
      },
      size: { sm: "h-8 px-3 text-sm", md: "h-10 px-4 text-sm", lg: "h-12 px-6 text-base", icon: "size-10" },
    },
    compoundVariants: [
      { variant: "outline", size: "sm", class: "border-2" },
      { variant: "link", size: ["sm", "md", "lg"], class: "h-auto p-0" },
    ],
    defaultVariants: { variant: "primary", size: "md" },
  },
);

export interface ButtonProps
  extends React.ButtonHTMLAttributes<HTMLButtonElement>,
    VariantProps<typeof buttonVariants> {
  asChild?: boolean;
}

export function Button({ className, variant, size, asChild, ...props }: ButtonProps) {
  const Comp = asChild ? Slot : "button";
  return <Comp className={cn(buttonVariants({ variant, size }), className)} {...props} />;
}

export { buttonVariants };  // export so <Link className={buttonVariants()}> reuses styles
```

## Patterns that separate senior from junior

- **`asChild` + `Slot`** → polymorphism without duplicate styles (render a `<Link>` that looks like a button).
- **Export the `variants` fn** so non-button elements (anchors, `next/link`) reuse the exact styles.
- **`compoundVariants`** for combinations (outline+sm = thicker border) instead of branching in JSX.
- **`defaultVariants`** so callers can omit props.
- **Slot patterns for icons**: `[&_svg]:size-4` styles children without prop plumbing.
- **Caller override is sacred**: always `cn(variants(), className)` last so consumers can patch.

## RSC boundary (Next.js App Router)
A pure CVA component (no hooks) is a **Server Component** — keep it server-side. Add `"use client"`
only when it needs state/handlers or wraps a Radix primitive. Don't blanket-`"use client"` your UI kit;
it kills streaming and bloats the client bundle.

## Accessibility baked into the base
- `outline-hidden` (v4) removes the UA outline **safely** + you supply `focus-visible:ring-3`.
- Never `outline-none` (true removal = WCAG 2.4.7 failure).
- Disabled: `disabled:opacity-50 disabled:pointer-events-none` and rely on the native `disabled` attr (not `aria-disabled` alone) for real buttons.

## Testing variants (don't ship blind)
- Render a **matrix** of `variant × size × state` in Storybook (or a test route).
- Snapshot/visual-regression the matrix (Playwright `toHaveScreenshot`) so a token change can't silently break a variant.
- Unit test that `cn()` override wins: `expect(render(<Button className="bg-red-600"/>)).toHaveClass("bg-red-600")`.

## File structure
```
components/ui/{button,input,card,dialog,...}.tsx   # one primitive per file, cva + variants
lib/utils.ts                                       # cn()
```

## Anti-patterns
- String concat `className={"base " + (x ? "a" : "b")}` → use `cn()`/cva (conflict-safe, readable).
- Boolean prop explosion (`isPrimary`, `isLarge`) → use a `variant`/`size` enum.
- Re-declaring button styles on every `<a>` → export and reuse `buttonVariants`.
- `"use client"` on the whole kit → only where interactivity lives.
- Variants with raw hex → use semantic token utilities (`tailwind-design-tokens`).

## References
- CVA: https://cva.style/docs · tailwind-merge: https://github.com/dcastil/tailwind-merge

## Related
`tailwind-shadcn-ui`, `tailwind-radix-headless`, `tailwind-design-tokens`, `vercel-composition-patterns` (ui-master)
