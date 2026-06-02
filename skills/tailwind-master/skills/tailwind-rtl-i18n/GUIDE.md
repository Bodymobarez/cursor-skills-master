---
name: tailwind-rtl-i18n
description: >-
  RTL layouts with Tailwind v4: dir=rtl, logical properties (ms/me/ps/pe), Arabic
  typography, bilingual switching, mirrored icons, and government portal patterns
  (TAMM/UAE style).
---

# Tailwind RTL & i18n (Arabic-first)

## HTML root

```tsx
<html lang="ar" dir="rtl">
```

Locale switch:

```tsx
<html lang={locale} dir={locale === "ar" ? "rtl" : "ltr"}>
```

## Logical properties (always prefer over left/right)

| Avoid | Use (RTL-safe) |
|-------|----------------|
| `ml-4` / `mr-4` | `ms-4` / `me-4` |
| `pl-6` / `pr-6` | `ps-6` / `pe-6` |
| `left-0` | `start-0` |
| `right-0` | `end-0` |
| `text-left` | `text-start` |
| `text-right` | `text-end` |
| `rounded-l-lg` | `rounded-s-lg` |
| `border-l-2` | `border-s-2` |

## Flex direction

```tsx
// row follows dir automatically in modern browsers
<div className="flex items-center gap-3">
  <Icon />
  <span>نص عربي</span>
</div>
```

For forced LTR islands (phone numbers, URLs):

```tsx
<span dir="ltr" className="unicode-bidi-isolate">+971 2 123 4567</span>
```

## Typography

```css
@theme {
  --font-sans: "Noto Sans Arabic", "IBM Plex Sans Arabic", ui-sans-serif, system-ui;
}
```

```tsx
<h1 className="font-sans text-3xl font-bold leading-tight tracking-normal">
```

Arabic: avoid tight `tracking-tight` on body text.

## Mirrored icons

Chevrons/arrows: flip in RTL

```tsx
<Chevron className={cn("size-4", dir === "rtl" && "scale-x-[-1]")} />
```

Or use `rtl:rotate-180` on directional icons only.

## Breadcrumbs (gov portals)

```tsx
<nav aria-label="breadcrumb" className="flex flex-wrap items-center gap-2 text-sm text-muted-foreground">
  <Link href="/">الرئيسية</Link>
  <span className="text-border" aria-hidden>/</span>
  <span className="text-foreground">الخدمة</span>
</nav>
```

## Tailwind + next-intl

```tsx
import { useLocale } from "next-intl";
const locale = useLocale();
```

Load messages server-side; pass `dir` from locale.

## Checklist

```
- [ ] ms/me/ps/pe on all horizontal spacing
- [ ] Icons that imply direction are mirrored or logical
- [ ] Forms: labels text-start, errors below field
- [ ] Modals: close button in logical end corner
- [ ] WCAG: lang attribute matches content
```

## Related

`tailwind-uae-aegov-dls`, `tailwind-dark-mode-theming`
