---
name: elite-ui-ux-design-system
description: >-
  World-class UI/UX redesign system: Apple/VisionOS/Stripe/Linear/Notion/Raycast-grade aesthetics.
  Glassmorphism 2.0, fintech dashboards, AI copilot panels, neo-brutalism accents, Framer Motion,
  design tokens, WCAG AA+, Lighthouse 95+, multi-panel workspaces. Use for premium product
  redesigns — never average UI.
---

# Elite UI/UX Design System

**Mandate:** every screen you touch should feel like a **premium product worth billions** — Stripe, Linear,
Notion, Raycast, Revolut, Vercel, OpenAI Dashboard tier. Not “nice startup UI.” **Analyze → redesign → ship** with
measurable quality (a11y, perf, hierarchy). Average UI is a failure mode.

## When to use / when NOT

| Use | Don't |
|-----|-------|
| Full product redesign, dashboard overhaul, design system uplift | One-off button color tweak only → `color-design-master` |
| New app shell, admin panel, marketing site, SaaS product UI | Backend-only API with no UI |
| “Make it look like Linear/Stripe/Notion” | Pixel-perfect clone of trademarked UI (inspiration only) |

**Pair with:** `tailwind-master` (tokens, shadcn, RTL), `color-design-master`, `figma-grade-design-system`, `award-winning-ui-effects`, `tailwind-design-tokens`.

---

## Design DNA (reference stack)

Blend — don’t copy one product:

| Reference | Steal |
|-----------|-------|
| Apple HIG / visionOS | Spacing, hierarchy, restraint, depth |
| Stripe Dashboard | Trust, data density, calm charts |
| Linear | Speed, keyboard-first, minimal chrome |
| Notion | Blocks, side peek, calm density |
| Raycast / Arc | Command palette, glass, focus |
| Revolut / fintech | Cards, wallet gravity, bold numbers |
| Vercel | Developer polish, status, deploy energy |
| Framer.com | Motion craft, scroll, depth |
| OpenAI / Cursor | Copilot panels, workspace, suggestions |

**Avoid:** gaming UI, neon cyberpunk clichés, excessive blur, clutter, generic “AI purple gradient” everywhere.

---

## Visual style matrix (combine deliberately)

| Layer | Rule |
|-------|------|
| **Apple premium** | Large spacing (8pt grid), clear type scale, one primary action per view |
| **Glassmorphism 2.0** | `backdrop-blur` + subtle border + shadow; max 2–3 glass layers deep |
| **AI copilot** | Right or bottom panel; context actions; never blocks primary task |
| **Fintech** | Tabular numbers, restrained color on money, chart clarity |
| **SaaS dashboard** | Dense but scannable; filters, saved views, empty states |
| **Neo-brutalism** | Sparingly: one bold CTA, occasional hard shadow — not whole pages |
| **Minimalism** | Remove chrome; every widget earns its place |
| **Cyber-future** | Subtle glow on focus, refined motion — not sci-fi skins |

---

## Layout system (multi-panel workspace)

```
┌─────────────────────────────────────────────────────────┐
│ Top bar: breadcrumb · search (⌘K) · context actions · avatar   │
├──────────┬──────────────────────────────────────────────┤
│ Sidebar  │ Main canvas (scroll) + optional right “inspector”      │
│ (nav)    │                                              │
│          │  ┌─────────────┐  ┌──────────────────────────┐ │
│          │  │ Stats/cards │  │ Table / chart / form       │ │
│          │  └─────────────┘  └──────────────────────────┘ │
├──────────┴──────────────────────────────────────────────┤
│ Optional: command palette (modal) · contextual action bar (selection) │
└─────────────────────────────────────────────────────────┘
```

**Rules:**
- Sidebar: collapsible; icons + labels; active state = pill + subtle fill
- **Command palette** (Raycast-style): global search + actions; `⌘K` / `Ctrl+K`
- **Contextual action bar** appears when rows/items selected
- **Inspector** panel for detail without navigation away
- Every page must answer: *what’s the one thing the user does here?*

---

## Color system

### Semantic tokens (implement in CSS / Tailwind `@theme`)

```css
/* Primitives — OKLCH preferred (color-design-master) */
--surface-canvas: oklch(0.99 0.005 260);
--surface-raised: oklch(1 0 0 0 / 0.98 0.01 260);
--surface-glass: oklch(1 0 0 0 / 0.72 0.02 260); /* over blur */
--text-primary: oklch(0.18 0.02 260);
--text-secondary: oklch(0.45 0.02 260);
--accent: oklch(0.55 0.14 250);
--accent-muted: oklch(0.55 0.14 250 / 0.15);
--border-subtle: oklch(0.88 0.01 260 / 0.6);
--shadow-elevated: 0 8px 32px oklch(0.2 0.02 260 / 0.08);

/* Dark */
.dark {
  --surface-canvas: oklch(0.14 0.02 260);
  --surface-raised: oklch(0.18 0.02 260);
  --text-primary: oklch(0.96 0.01 260);
  --accent: oklch(0.72 0.12 250);
}
```

**Rules:**
- Light: premium white canvas, soft gray cards, glass only on overlays/command palette
- Dark: graphite (not pure `#000`), rich contrast, reduced glow
- **No raw hex in components** — semantic tokens only
- Financial: green/red only for semantic gain/loss; never decorative rainbow charts

### Glassmorphism 2.0 (controlled)

```tsx
// Glass panel — use sparingly
<div className="rounded-2xl border border-border-subtle/60 bg-surface-glass/80 backdrop-blur-xl shadow-elevated">
```

- Blur: `backdrop-blur-md` to `xl` max on large panels
- Border: 1px `white/10` (dark: `white/8`) + inner highlight
- **Never** glass-on-glass-on-glass (max 2 layers)

---

## Typography

| Role | Stack | Size (desktop) | Weight |
|------|-------|----------------|--------|
| Display | SF Pro Display, Geist, fallback Inter | 32–40px | 600–700 |
| H1 | Same | 24–28px | 600 |
| H2 | Same | 18–20px | 600 |
| Body | Inter, IBM Plex Sans, Geist Sans | 14–16px | 400–450 |
| Label / UI | Same | 12–13px | 500 |
| Mono | Geist Mono, IBM Plex Mono | 12–13px | 400 |

**Rules:** `font-feature-settings: "tnum"` on financial data; line-height 1.5 body, 1.2 headings; max ~70ch for prose blocks.

---

## Animation system (Framer Motion)

**Feel expensive = spring physics, not linear tweens everywhere.**

```tsx
import { motion, AnimatePresence } from "framer-motion";

const springSnappy = { type: "spring", stiffness: 380, damping: 32 };
const springSoft = { type: "spring", stiffness: 260, damping: 28 };

// Page enter
<motion.main
  initial={{ opacity: 0, y: 8 }}
  animate={{ opacity: 1, y: 0 }}
  transition={springSoft}
/>

// Card hover — subtle lift
<motion.div whileHover={{ y: -2 }} transition={springSnappy} />

// List stagger
<motion.ul variants={{ show: { transition: { staggerChildren: 0.04 } } }}>
```

| Pattern | Use |
|---------|-----|
| Page transition | Opacity + 8px Y, 200–300ms spring |
| Modal / sheet | Scale 0.96→1 + fade |
| Hover | 1–2px lift OR border brighten (not both heavy) |
| Loading | Skeleton shimmer + pulse; no spinners alone on full page |
| Reduced motion | `prefers-reduced-motion: reduce to opacity only |

**Respect `prefers-reduced-motion`** — see `tailwind-dark-mode-theming`.

---

## Component system (redesign checklist)

Redesign with **tokens + CVA** (`tailwind-cva-components`). Every component:

| Component | Elite bar |
|-----------|-----------|
| Button | Primary: one per view; pill or rounded-lg; clear focus ring; loading state |
| Input | 44px min height touch; floating labels optional; error inline |
| Select / Combobox | Radix; match input height; chevron motion |
| Table | Sticky header, zebra optional, row hover, bulk actions, empty state |
| Card | 16–24px padding, subtle border, hover elevation |
| Modal / Dialog | Focus trap, `max-w` + scroll, glass or solid surface |
| Tooltip | Delay 400ms; concise; not blocking clicks |
| Menu | Sections, shortcuts shown, destructive separated |
| Nav | Collapsible groups, badges for counts |
| Charts | Recharts/Visx — restrained palette, tooltips, no chartjunk |
| Widgets | KPI cards: label, value, delta, sparkline optional |

---

## Dashboard experience (required on every dashboard)

Every dashboard screen includes:

1. **Smart statistics** — 3–6 KPI cards; comparison (vs prior period); sparkline optional
2. **Interactive charts** — brush/zoom where useful; legend clear; accessible colors
3. **Dynamic cards** — layout responds to breakpoints; drag optional (advanced)
4. **Live updates** — optimistic UI + subtle toast; skeleton on refresh regions only
5. **Activity timeline** — who/what/when; filterable
6. **AI insights** — copilot panel: “why metric moved”, suggested actions (dismissible)
7. **Search everywhere** — `⌘K` command palette searches nav + data + actions

**Empty states:** illustration or icon + one-line copy + primary CTA — never blank tables.

---

## Mobile experience

| Breakpoint | Behavior |
|------------|----------|
| `<640px` | Single column; bottom nav or hamburger; tables → cards or horizontal scroll |
| `640–1024px` | Sidebar collapses to icons; 2-column grids → 1 |
| `≥1024px` | Full workspace layout |

**Touch:** 44px min targets; no hover-only affordances; bottom sheets for filters on mobile.

**Target: responsive score 100%** = no horizontal scroll on primary flows; readable text without zoom.

---

## Accessibility (WCAG 2.2 AA+)

```
- [ ] Contrast: 4.5:1 text, 3:1 large UI, 3:1 non-text (1.4.11)
- [ ] Focus visible: ring-3 ring-accent/40 (v4 pattern)
- [ ] Keyboard: all actions reachable; logical tab order; escape closes overlays
- [ ] Screen readers: labels, live regions for toasts, table headers scoped
- [ ] Motion: reduced-motion path exists
- [ ] Charts: not color-only meaning (patterns + labels)
```

Run **axe** in CI on critical routes.

---

## Performance (Lighthouse 95+)

| Tactic | Target |
|--------|--------|
| LCP | < 2.5s — hero text/image optimized, font subset |
| CLS | < 0.1 — reserve space for skeletons/async |
| INP | < 200ms — defer heavy chart until visible |
| Bundle | Route-level code split; dynamic import charts |
| Images | AVIF/WebP, explicit dimensions, lazy below fold |

**Glass:** limit blurred area (large blur = GPU cost on scroll).

---

## Redesign workflow (per screen)

Never jump straight to pixels. For **each** screen:

```
1. ANALYZE — List UX weaknesses (clutter, weak hierarchy, unclear CTA, a11y gaps)
2. WIREFRAME — Structure only (blocks, priority, states: empty/loading/error)
3. TOKENS — Map surfaces/text to semantic tokens only
4. BUILD — Components from system; Framer Motion for motion
5. VERIFY — axe + keyboard pass + responsive breakpoints + Lighthouse spot-check
6. POLISH — Micro-interactions, copy, perceived performance
```

**Quality gate question:** “Would a Stripe/Linear designer sign this off?” If no, iterate.

---

## Anti-patterns (average UI)

- Purple/blue gradient on every screen
- 12px padding on cards
- Five equal-weight buttons in a row
- Glass on every nested div
- Spinner full-page for partial updates
- Tables without empty/loading/error states
- Charts with 10 series and no legend
- Hover-only critical actions
- Ignoring dark mode and RTL

---

## Agent checklist

```
- [ ] Design DNA applied; not generic “modern clean UI”
- [ ] Semantic color + type tokens; glass used sparingly
- [ ] Multi-panel layout + command palette considered
- [ ] Framer Motion springs; reduced-motion respected
- [ ] Dashboard has KPIs, charts, timeline, search, AI insight slot
- [ ] Mobile/tablet/desktop layouts verified
- [ ] WCAG AA+ + Lighthouse 95+ targets considered
- [ ] No average UI shipped
```

## References

- Apple HIG: https://developer.apple.com/design/human-interface-guidelines/
- Framer Motion: https://www.framer.com/motion/
- WCAG 2.2: https://www.w3.org/TR/WCAG22/
- Radix + shadcn: `tailwind-shadcn-ui` in tailwind-master

## Related

`figma-grade-design-system`, `tailwind-design-tokens`, `award-winning-ui-effects`, `color-design-master`, `tailwind-v4-latest`
