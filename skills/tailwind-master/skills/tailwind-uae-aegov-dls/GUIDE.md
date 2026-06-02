---
name: tailwind-uae-aegov-dls
description: >-
  UAE Federal Design System (AEGov DLS 3.0) with Tailwind CSS 4: @aegov/design-system
  plugin, @aegov/design-system-react, installation, WCAG 2.2, RTL, entity branding,
  and TAMM-style government portals.
---

# UAE AEGov Design System + Tailwind v4

Official: https://designsystem.gov.ae — **built on Tailwind CSS 4.x**.

## Packages

| Package | Use |
|---------|-----|
| `@aegov/design-system` | Tailwind plugin (HTML/vanilla) |
| `@aegov/design-system-react` | React + Radix + Tailwind (recommended) |

```bash
npm install @aegov/design-system-react
# includes tailwindcss, forms, typography plugins
```

## CSS setup (v4)

```css
@import "tailwindcss";
@plugin "@tailwindcss/forms";
@plugin "@tailwindcss/typography";
@plugin "@aegov/design-system";
```

React projects also import package styles per docs:

```css
@import "../node_modules/@aegov/design-system-react/dist/styles/tailwind.css";
```

## Content paths

Ensure Tailwind scans DLS components:

```css
@source "../node_modules/@aegov/design-system-react/**/*.{js,ts,jsx,tsx}";
@source "../app/**/*.{tsx,ts}";
```

## Compliance checklist (federal)

```
- [ ] DLS 3.0 components (don't reinvent gov buttons/cards)
- [ ] WCAG 2.2 AA contrast on primary text
- [ ] RTL Arabic as default or equal citizen with EN
- [ ] Entity branding within DLS theming rules (not full rebrand)
- [ ] UAE Pass / auth patterns per service guidelines
```

## TAMM vs DLS

| TAMM production (legacy) | Greenfield UAE gov |
|--------------------------|-------------------|
| Custom `ui-lib` CSS vars | `@aegov/design-system` |
| Webpack SPA 4.x | Next.js + Tailwind v4 |
| `--ui-lib-indigo-*` | DLS semantic tokens |

New projects: **DLS + Tailwind v4**, not copying TAMM `ui-lib` unless maintaining legacy.

## RTL

DLS supports bilingual federal sites. Pair with `tailwind-rtl-i18n`.

## Resources

- Install: https://designsystem.gov.ae/docs/installation
- GitHub: https://github.com/TDRA-ae/aegov-dls
- React: https://github.com/TDRA-ae/aegov-dls-react

## Related

`tailwind-rtl-i18n`, `tailwind-design-tokens`, `backend-api-master` (UAE Pass integrations)
