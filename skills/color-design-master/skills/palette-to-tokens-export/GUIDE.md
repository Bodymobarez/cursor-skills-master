---
name: palette-to-tokens-export
description: >-
  Ship a palette as a single source of truth across platforms at staff depth: W3C DTCG token files
  ($value/$type, group $type inheritance, alias refs), a Style Dictionary v4 pipeline (token.type
  matching, css/variables + outputReferences, Tailwind @theme, TS types, iOS/Android), light/dark via
  $extensions.mode, CI drift detection, and a contrast gate on generated tokens. Use to cross the
  design→engineering boundary without drift.
---

# Palette → Design Tokens Export — One Source, Many Targets, Zero Drift

**Mandate:** there is exactly **one** source of truth for color, and every artifact — CSS, Tailwind, TS
types, Figma, iOS, Android — is a *build output* of it. If CSS and Figma can disagree, you don't have a
token pipeline; you have N copies that will drift, and the drift will ship.

---

## When to use / when NOT to use

- **Use** to turn a finalized palette into production assets, to set up Figma↔code sync, to support
  multi-brand/multi-platform output, or to add a drift gate to CI.
- **NOT** to *design* the palette (`color-artist-engineer`), generate ramps (`oklch-perceptual-palettes`),
  or define the role vocabulary (`semantic-ui-color-roles`). Those produce the source this skill compiles.

---

## The pipeline (read top-to-bottom; everything below the source is generated)

```
tokens/*.tokens.json   (W3C DTCG — THE source of truth; primitives + semantic, dark via $extensions)
        │  Style Dictionary v4 build (registerTransform / formats)
        ▼
   ├── globals.css           :root + [data-theme=dark]  (CSS custom properties)
   ├── tailwind.theme.css     @theme inline snippet      (Tailwind v4)
   ├── tokens.ts              ColorRole union + types     (compile-time safety)
   ├── ios/Colors.swift  ·  android/colors.xml            (native, optional)
   └── Figma Variables        (via Tokens Studio / REST)  ← round-trips back to source
        │  CI: rebuild + git diff  → fail if outputs ≠ committed (no drift)
        │  CI: contrast gate on generated values (wcag-contrast-color-pairs)
```

---

## Decision: how to manage the source

| Approach | Source of truth | Strength | Use when |
|----------|-----------------|----------|----------|
| **Hand-authored CSS vars** | `globals.css` | Zero tooling | Tiny app, one platform, no Figma |
| **Style Dictionary v4** | `*.tokens.json` (DTCG) | Multi-platform, transforms, CI | Real DS, ≥2 targets |
| **Tokens Studio + Figma** | Figma variables → JSON | Designers own source, two-way sync | Design-led orgs |
| **Hybrid (recommended)** | DTCG JSON, Figma syncs in | Code-reviewable + designer-friendly | Most product teams |

Below assumes Style Dictionary v4 — the de-facto standard, and what most token toolchains target.

---

## DTCG source format (W3C Design Tokens)

Use `$value` / `$type`, group-level `$type` inheritance, and `{alias.path}` references. Primitives are
raw; semantic tokens *reference* primitives; dark values ride along in `$extensions`.

```jsonc
// tokens/color.tokens.json
{
  "brand": {
    "$type": "color",
    "600": { "$value": "oklch(0.55 0.18 262)" },
    "400": { "$value": "oklch(0.68 0.14 262)" }
  },
  "neutral": {
    "$type": "color",
    "50":  { "$value": "oklch(0.985 0.004 262)" },
    "600": { "$value": "oklch(0.50 0.012 262)" },
    "900": { "$value": "oklch(0.205 0.010 262)" }
  },
  "color": {
    "$type": "color",
    "primary":          { "$value": "{brand.600}",  "$extensions": { "mode": { "dark": "{brand.400}" } } },
    "primary-foreground": { "$value": "oklch(0.99 0 0)" },
    "background":       { "$value": "{neutral.50}",  "$extensions": { "mode": { "dark": "oklch(0.17 0.015 262)" } } },
    "foreground":       { "$value": "{neutral.900}", "$extensions": { "mode": { "dark": "oklch(0.94 0.01 262)" } } },
    "muted-foreground": { "$value": "{neutral.600}", "$extensions": { "mode": { "dark": "oklch(0.72 0.02 262)" } } },
    "border":           { "$value": "{neutral.50}",  "$extensions": { "mode": { "dark": "oklch(0.30 0.02 262)" } } }
  }
}
```

> DTCG note (2026): the formal **Color Module** (designtokens.org, 2025.10) defines a structured color
> object, but every shipping tool still accepts a CSS color *string* in `$value`. Author OKLCH strings for
> human-readability and let the build emit hex fallbacks where needed.

---

## Style Dictionary v4 config (copy-paste)

v4 matches tokens by **`token.type` / `$type`** (not the old v3 CTI `attributes.category`). `outputReferences`
preserves `var(--…)` aliasing in the CSS output so semantic tokens stay re-themeable.

```ts
// style-dictionary.config.ts
import StyleDictionary from "style-dictionary";
import { formatHex, oklch } from "culori";

// Emit a hex fallback alongside the oklch value for legacy targets.
StyleDictionary.registerTransform({
  name: "color/hex-fallback",
  type: "value",
  filter: (t) => t.$type === "color" && typeof t.$value === "string" && t.$value.startsWith("oklch"),
  transform: (t) => t.$value, // keep oklch for CSS; native transforms below convert to hex
});

export default {
  source: ["tokens/**/*.tokens.json"],
  platforms: {
    css: {
      transformGroup: "css",
      buildPath: "src/styles/",
      files: [{
        destination: "tokens.css",
        format: "css/variables",
        options: { outputReferences: true }, // keep var(--brand-600) refs, don't flatten
      }],
    },
    ts: {
      transformGroup: "js",
      buildPath: "src/",
      files: [{ destination: "tokens.ts", format: "javascript/es6" }],
    },
    ios: {
      transformGroup: "ios-swift",
      buildPath: "ios/",
      files: [{ destination: "Colors.swift", format: "ios-swift/class.swift" }],
    },
  },
};
```

```bash
npx style-dictionary build --config ./style-dictionary.config.ts
```

For **dark mode**, run the build twice with a mode-resolving parser (apply `$extensions.mode.dark` over the
base), emitting a `:root` block and a `[data-theme="dark"]` block — or keep two source files
(`semantic.light.tokens.json` / `semantic.dark.tokens.json`) and merge. Either way: **same primitives,
swapped semantic refs**.

---

## Tailwind v4 `@theme inline` (the bridge)

Tailwind v4 reads CSS variables; expose your generated tokens so utilities (`bg-primary`, `text-muted-foreground`)
exist at runtime and re-theme on `[data-theme]` swap:

```css
@import "tailwindcss";
@import "./tokens.css"; /* generated :root + [data-theme=dark] */

@theme inline {
  --color-background: var(--color-background);
  --color-foreground: var(--color-foreground);
  --color-surface: var(--color-surface);
  --color-primary: var(--color-primary);
  --color-primary-foreground: var(--color-primary-foreground);
  --color-muted: var(--color-muted);
  --color-muted-foreground: var(--color-muted-foreground);
  --color-border: var(--color-border);
  --color-ring: var(--color-ring);
}
```

---

## Type-safe token names (generated, not hand-listed)

```ts
// generated by a custom SD format or a postbuild script reading the DTCG source
export const COLOR_TOKENS = [
  "primary", "primary-foreground", "background", "foreground",
  "muted", "muted-foreground", "border", "ring",
] as const;
export type ColorToken = (typeof COLOR_TOKENS)[number];
```

Now `colorVar("primry")` is a compile error, not a runtime mystery.

---

## CI drift gate (the reason this pipeline exists)

Rebuild on every PR and fail if the committed outputs don't match — this is what guarantees Figma, CSS, and
types never silently diverge:

```yaml
# .github/workflows/tokens.yml
- run: npx style-dictionary build --config ./style-dictionary.config.ts
- run: git diff --exit-code -- src/styles/tokens.css src/tokens.ts
  # non-zero exit = generated output drifted from source → block merge
```

Then run the **contrast gate** (`wcag-contrast-color-pairs`) against the *generated* values so a token edit
that breaks AA can't merge.

---

## Figma handoff / sync

| Token | Figma variable | Notes |
|-------|----------------|-------|
| `color.primary` | `Color/Brand/Primary` | mode: Light/Dark collection |
| `color.background` | `Color/Surface/Background` | |
| `brand.600` | `Color/Primitives/Brand/600` | primitives hidden from non-DS designers |

Tokens Studio (Figma plugin) reads/writes DTCG JSON — point it at the same `tokens/` directory so designers
edit the *same source*. Round-trip rule: JSON is canonical; Figma is a view that syncs back via PR.

---

## `PALETTE.md` deliverable (human-readable companion)

```markdown
# Palette — {{Brand}}
**Harmony:** analogous · **Rationale:** {{2–3 sentences}}
## Swatches  | Role | OKLCH | HEX | step |
## Contrast matrix  | fg | bg | WCAG | APCA Lc | AA |
## 60-30-10 usage  · ## Dark-mode notes  · ## CVD check
```

---

## Edge cases & war stories

- **Reference resolution order.** Semantic tokens referencing primitives in *another file* fail if the
  build doesn't load both via `source`. Glob the whole `tokens/` dir; don't list files individually.
- **OKLCH in native targets.** iOS/Android don't speak `oklch()`. Register a value transform that converts
  to the platform's color type (sRGB hex / `UIColor`) at build — keep OKLCH only in the CSS branch.
- **Naming collisions.** `color.primary` and a primitive `primary` flatten to clashing CSS var names.
  Namespace primitives (`brand-600`, not `primary`) and reserve role names for the semantic tier.
- **`outputReferences` + dark mode.** If you flatten references, dark mode breaks (the var that should
  re-point is baked to a literal). Keep `outputReferences: true`.
- **v3→v4 migration.** Custom transforms keyed on `token.attributes.category` silently no-op in v4 — switch
  filters to `token.type` / `$type`.

## Performance / security / scale

- **Build caching:** token builds are fast, but in a monorepo cache the `style-dictionary build` step on
  the `tokens/` hash so unrelated PRs don't rebuild.
- **Security:** don't ship *unreleased* brand colors (next rebrand, embargoed tenant) in the public CSS
  bundle — gate them behind a build flag; CSS custom properties are world-readable in devtools.
- **Multi-brand scale:** emit one output set per brand (`platforms.css.buildPath = build/${brand}/`) from a
  shared primitive base + brand override file; verify each brand's contrast matrix in CI.

## Observability / debugging

- Style Dictionary logs unresolved references and collisions — treat any warning as a build failure
  (`--verbose`, fail on warn).
- Diff the generated `tokens.css` in PRs; a color review *is* the diff. If the diff is unreadable, your
  source granularity is wrong.

## i18n / RTL

Color tokens are direction-neutral; ship them once. If you also export spacing/radius, keep those logical
(`*-inline-start`) — but color stays the same across `dir`.

## Anti-patterns
- Hand-maintaining CSS **and** Figma **and** native separately (drift guaranteed).
- Value-named product tokens (`color-blue-500`) instead of role names in the semantic output.
- Flattening references (losing re-themeability).
- No CI drift gate ("we'll keep them in sync manually").
- Shipping JSON + CSS that disagree because only one was regenerated.
- Emitting `oklch()` to iOS/Android without a conversion transform.

## Agent checklist
```
- [ ] One DTCG source ($value/$type, group $type, {alias} refs)
- [ ] Style Dictionary v4 matching on token.type/$type
- [ ] css/variables with outputReferences: true (refs preserved)
- [ ] Dark mode via $extensions.mode or paired source files (same primitives)
- [ ] Tailwind @theme inline bridge emitted
- [ ] Type-safe token union generated, not hand-written
- [ ] CI drift gate: rebuild + git diff --exit-code
- [ ] Contrast gate on generated values (both themes)
- [ ] Native targets get hex via transform (no raw oklch)
```

## References
- W3C DTCG format: https://www.designtokens.org / https://tr.designtokens.org/format/
- Style Dictionary v4 (formats/transforms, token.type): https://styledictionary.com/reference/hooks/formats/
- Tokens Studio (Figma): https://tokens.studio/
- Tailwind v4 `@theme`: https://tailwindcss.com/docs/theme

## Related
`semantic-ui-color-roles`, `oklch-perceptual-palettes`, `wcag-contrast-color-pairs`,
`tailwind-design-tokens` (tailwind-master), `brand-identity-creator` (ui-master)
