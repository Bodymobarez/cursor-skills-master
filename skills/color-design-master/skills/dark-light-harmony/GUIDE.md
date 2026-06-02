---
name: dark-light-harmony
description: >-
  Engineer dark themes as a re-mapped semantic layer (never an inversion) at staff depth: the color
  science (no pure black/halation, accent desaturation, elevation-as-lightness, simultaneous contrast),
  the three-mode toggle (light/dark/system) with a no-flash (FOUC) inline script, color-scheme, paired
  contrast on both themes, and forced-colors mode. Use for any product shipping a dark theme.
---

# Dark & Light Harmony — Re-composition, Not Inversion

**Mandate:** dark mode is a **second mapping of the same semantic layer**, hand-tuned for how the eye
behaves in low luminance. It is never `filter: invert()`, never "the light palette with L flipped." If
your dark theme is a parallel component tree or an algorithmic invert, it's wrong.

---

## When to use / when NOT to use

- **Use** when designing a dark theme alongside light, choosing a theming strategy, killing the
  flash-of-wrong-theme, or fixing a dark mode that "glows" or has invisible cards.
- **NOT** for the underlying ramps (`oklch-perceptual-palettes`) or the role vocabulary
  (`semantic-ui-color-roles`) — this skill is the *transform between the two maps* plus the runtime
  plumbing.

---

## The color science (why naïve inversion fails)

1. **Never pure black bg, never pure white text.** `#000` text-surface causes **halation** — for the
   ~50% of adults with astigmatism, bright text on pure black smears/blooms. Use `oklch(0.16–0.20)` for
   bg and cap text at `oklch(~0.94)`, not 1.0. Lower the contrast *ceiling*, don't max it.
2. **Desaturate accents 15–25% in dark.** On a dark field a saturated hue appears to *glow* and vibrate
   (Bezold–Brücke / simultaneous-contrast effects). Raise **L**, lower **C** to keep the same hue reading
   calm. Identical chroma that looked confident in light looks radioactive in dark.
3. **Elevation = lighter surface, not shadow.** Shadows are nearly invisible on dark backgrounds. Higher
   surfaces get *higher L* (this is Material's overlay model). In light mode the opposite: elevation reads
   via shadow, surface stays white-ish.
4. **Raise low-contrast text L.** `muted-foreground` that passed in light fails in dark if you just
   reuse it — dark gray-on-darker-gray dies. Re-tune for the dark bg and re-verify.
5. **Keep hue H constant** across themes — that's what preserves brand identity through the switch.

---

## The transform recipe (per role)

| Role | Light → Dark transform |
|------|------------------------|
| background | very high L → low L (`0.98 → 0.16`) |
| foreground | very low L → high L but **not 1.0** (`0.20 → 0.94`) |
| surface | white/light, lifts via shadow → **lighter than bg** (`0.20`) |
| surface-raised | subtle | even lighter (`0.24`) |
| primary | brand L → **L up, C down** (`0.55/0.18 → 0.68/0.14`) |
| muted-foreground | mid-dark | **raise L** to clear 4.5:1 on dark bg |
| border | light gray | `~0.30`, C ≤ 0.02 |

```css
:root {                                   /* light */
  color-scheme: light;
  --color-background: oklch(0.98 0.005 262);
  --color-foreground: oklch(0.20 0.02 262);
  --color-surface:    oklch(1 0 0);
  --color-primary:    oklch(0.55 0.18 262);
  --color-muted-foreground: oklch(0.50 0.02 262);
  --color-border:     oklch(0.90 0.01 262);
}
:root[data-theme="dark"] {                /* dark — swap the MAP, not the components */
  color-scheme: dark;                     /* native scrollbars/inputs/UA controls follow */
  --color-background: oklch(0.17 0.015 262);
  --color-foreground: oklch(0.94 0.01 262); /* NOT 1.0 — halation */
  --color-surface:    oklch(0.21 0.015 262); /* lighter than bg = elevation */
  --color-primary:    oklch(0.68 0.14 262);  /* L↑ C↓ — calm, not neon */
  --color-muted-foreground: oklch(0.72 0.02 262); /* raised to keep ≥4.5:1 */
  --color-border:     oklch(0.30 0.02 262);
}
```

`color-scheme` is not optional — it makes form controls, scrollbars, and the UA `<input>` chrome match the
theme, and it's a one-liner that fixes "white scrollbar in dark mode."

---

## Decision: theming strategy

| Strategy | Toggle | SSR-safe | Best for |
|----------|--------|----------|----------|
| `prefers-color-scheme` only | none (OS) | ✅ | Content sites, no manual toggle |
| `.dark` class | JS adds class | ✅ with no-flash script | Tailwind default, most apps |
| `[data-theme]` attribute | JS sets attr | ✅ with no-flash script | Multi-theme (light/dark/dim/tenant) |
| `light-dark()` CSS function | OS + `color-scheme` | ✅ | Simple two-mode, no manual override |

**Recommended:** `[data-theme]` with **three user states — `light` / `dark` / `system`** — persisted to
`localStorage`, defaulting to `system`. "System" must keep following the OS live (don't snapshot it).

---

## The no-flash (FOUC) inline script — non-negotiable for SSR

A flash of the wrong theme on load is the signature of an amateur dark mode. Set the attribute **before
first paint**, synchronously, in `<head>` — before the bundle loads:

```html
<!-- in <head>, before any stylesheet that reads [data-theme]. Render verbatim, not via React. -->
<script>
  (function () {
    try {
      var stored = localStorage.getItem("theme"); // "light" | "dark" | "system" | null
      var system = matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
      var theme = !stored || stored === "system" ? system : stored;
      document.documentElement.setAttribute("data-theme", theme);
      document.documentElement.style.colorScheme = theme;
    } catch (e) {}
  })();
</script>
```

```ts
// theme.ts — the runtime controller; "system" stays live
type Theme = "light" | "dark" | "system";
const mql = matchMedia("(prefers-color-scheme: dark)");

export function applyTheme(t: Theme) {
  localStorage.setItem("theme", t);
  const resolved = t === "system" ? (mql.matches ? "dark" : "light") : t;
  document.documentElement.setAttribute("data-theme", resolved);
  document.documentElement.style.colorScheme = resolved;
}
// keep "system" tracking the OS after load
mql.addEventListener("change", () => {
  if ((localStorage.getItem("theme") ?? "system") === "system") applyTheme("system");
});
```

In Next.js App Router, ship this as a `<script dangerouslySetInnerHTML>` in the root layout `<head>` (or
use `next-themes`, which implements exactly this pattern). Never set the theme in a `useEffect` — that
runs *after* paint and guarantees the flash.

---

## Elevation without shadow (dark)

```tsx
<div className="bg-background">
  <div className="bg-surface border border-border">card</div>
  <div className="bg-surface-raised border border-border">modal / popover</div>
</div>
```

Each level is a step up in L. Optionally add a faint top inner highlight
(`box-shadow: inset 0 1px 0 oklch(1 0 0 / 0.06)`) to mimic a light catching the top edge.

---

## Edge cases & war stories

- **Flash of wrong theme (FOUC).** Caused by deciding the theme in React/after hydration. Fix = the inline
  head script above. This is the single most common dark-mode bug in SSR apps.
- **Hydration mismatch.** If the server renders `data-theme="light"` but the client script sets `dark`,
  React warns. Set the attribute on `<html>` via the inline script (outside React's tree) so the server
  HTML doesn't assert a theme on body content.
- **Invisible shadows.** Card relies on `shadow-md` for separation → vanishes in dark. Add a `border` or a
  lighter `surface` so structure survives both themes.
- **Glowing accents.** Reusing the light primary's chroma in dark → it vibrates. L↑, C↓.
- **Translucent overlays compound.** Stacked `bg-black/40` scrims that looked right in light turn into mud
  in dark. Use a theme-aware overlay token, not a hardcoded black alpha.
- **System + manual precedence.** A user who picked "dark" must stay dark even if the OS flips to light at
  sunset. Only "system" follows the OS. Get the precedence wrong and users rage.
- **Images & illustrations.** Don't `invert()` them. Provide dark-variant assets or add a subtle
  `filter: brightness(.85)` only to decorative imagery, never to photos/logos.

---

## Performance

- Theme switch must be **CSS-only** — flip one attribute, let custom properties cascade. Re-rendering the
  React tree on toggle is a jank smell.
- Don't animate `background-color` on `*` during toggle (paints the whole page repeatedly); if you want a
  transition, scope it and use `@media (prefers-reduced-motion: reduce)` to disable it.

## Testing strategy

- Verify **every pair on both themes** (`wcag-contrast-color-pairs`) — dark almost always exposes a
  `muted-foreground` failure light didn't.
- Visual-regression light **and** dark snapshots (Playwright: toggle `data-theme`, `toHaveScreenshot`).
- Snapshot the page with the inline script's three branches (stored dark / stored light / system) to lock
  the no-flash behavior.

## Observability / debugging

- Log the resolved theme + its source (`stored` vs `system`) once on load; "it's the wrong theme" reports
  are almost always a localStorage/OS precedence confusion.
- A `/dev/tokens` route rendered in both themes side-by-side surfaces mis-tuned dark roles instantly.

## Accessibility / forced-colors

- **Respect `prefers-color-scheme`** as the default — don't force dark on everyone.
- **Honor Windows High Contrast / forced-colors mode.** Under `@media (forced-colors: active)` the OS
  overrides your colors with system colors — *let it*. Use system color keywords (`Canvas`, `CanvasText`,
  `LinkText`, `ButtonText`) for critical affordances and don't pin colors the OS needs to replace. Use
  `forced-color-adjust: none` only on genuinely meaningful swatches (e.g. a color picker), never on text.
- Offer reduced-motion-safe transitions; never gate critical info on the theme.

## Anti-patterns
- `filter: invert(1)` for dark mode.
- Pure `#000` background + pure `#fff` text (halation, harsh).
- Dark primary = neon/over-saturated version of light primary.
- Deciding theme in `useEffect` (guarantees FOUC).
- Shadows-only separation that disappears on dark.
- "Dark" snapshotting the OS once and never tracking changes.
- Fighting forced-colors mode with `!important` colors.

## Agent checklist
```
- [ ] Dark = swapped semantic map, same hues; components untouched
- [ ] bg not pure black; fg not pure white (halation guard)
- [ ] Accents desaturated (L↑ C↓) for dark
- [ ] Elevation via lighter surface, not shadow, in dark
- [ ] color-scheme set per theme
- [ ] No-flash inline <head> script; theme NOT set in useEffect
- [ ] Three modes: light / dark / system, persisted; system tracks OS live
- [ ] Both themes pass contrast (esp. muted-foreground) in CI
- [ ] forced-colors / high-contrast path respected
```

## References
- `color-scheme`: https://developer.mozilla.org/en-US/docs/Web/CSS/color-scheme
- `prefers-color-scheme`: https://developer.mozilla.org/en-US/docs/Web/CSS/@media/prefers-color-scheme
- `light-dark()`: https://developer.mozilla.org/en-US/docs/Web/CSS/color_value/light-dark
- next-themes (reference no-flash impl): https://github.com/pacocoursey/next-themes
- forced-colors / Windows High Contrast: https://developer.mozilla.org/en-US/docs/Web/CSS/@media/forced-colors

## Related
`oklch-perceptual-palettes`, `semantic-ui-color-roles`, `wcag-contrast-color-pairs`,
`tailwind-dark-mode-theming` (tailwind-master)
