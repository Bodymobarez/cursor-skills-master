---
name: tailwind-nextjs-rsc
description: >-
  Next.js 15 App Router with Tailwind v4: @tailwindcss/postcss, globals.css, RSC-safe
  styling (no runtime CSS-in-JS), layouts, fonts, and performance.
---

# Next.js 15 + Tailwind v4 + RSC

## Install

```bash
npx create-next-app@latest my-app --typescript --tailwind --app
# or add to existing:
npm install tailwindcss @tailwindcss/postcss
```

```js
// postcss.config.mjs
const config = { plugins: { "@tailwindcss/postcss": {} } };
export default config;
```

```css
/* app/globals.css */
@import "tailwindcss";
@source "../../app/**/*.{tsx,ts}";
@source "../../components/**/*.{tsx,ts}";
```

Remove v3: `@tailwind base`, `tailwind.config.ts` as primary config.

## App structure

```
app/
  layout.tsx      # import "./globals.css"
  page.tsx
components/
  ui/             # client components with Radix
lib/utils.ts
```

## RSC rules

| OK on Server | Client only (`"use client"`) |
|--------------|------------------------------|
| Tailwind `className` on server components | Radix Dialog, Select, Dropdown |
| Static markup | `useState`, `useEffect` for theme |
| `next/font` | React Hook Form |

**Do not use** styled-components / Emotion runtime on App Router.

## Fonts

```tsx
import { Inter, Noto_Sans_Arabic } from "next/font/google";

const inter = Inter({ subsets: ["latin"], variable: "--font-sans" });
const arabic = Noto_Sans_Arabic({ subsets: ["arabic"], variable: "--font-arabic" });

<html className={`${inter.variable} ${arabic.variable}`}>
```

```css
@theme {
  --font-sans: var(--font-sans), ui-sans-serif, system-ui;
}
```

## Layouts + metadata

```tsx
export const metadata = { title: "App" };
export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="ar" dir="rtl" suppressHydrationWarning>
      <body className="min-h-screen bg-background font-sans text-foreground antialiased">
        {children}
      </body>
    </html>
  );
}
```

`suppressHydrationWarning` on `<html>` when using theme class toggle.

## Performance

- Prefer Server Components for static UI shells
- `import dynamic()` for heavy client widgets only
- Tailwind v4 Oxide: fast HMR — no separate PurgeCSS config

## Env checklist

```
- [ ] globals.css imported once in root layout
- [ ] @source covers app + components + ui package paths
- [ ] postcss only @tailwindcss/postcss
- [ ] Client boundary only where hooks/Radix needed
```

## Related

`tailwind-shadcn-ui`, `fullstack-stacks-master`, `vercel-react-best-practices` (ui-master)
