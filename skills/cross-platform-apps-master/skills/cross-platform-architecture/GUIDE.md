---
name: cross-platform-architecture
description: >-
  Pick the right cross-platform strategy and monorepo shape at staff depth: Expo
  universal (Expo Router + React Native Web) + Tauri/Electron for desktop vs Flutter vs
  native-per-platform vs Capacitor/PWA, with pnpm + Turborepo, shared business-logic/types/
  design-system/api-client packages, .native/.web/.ios/.android file resolution, realistic
  code-sharing percentages, and the state/data layer. Use before writing a single screen.
---

# Cross-Platform Architecture — Choosing the Strategy & Monorepo

**Mandate:** Decide *how much code is shared and where it splits* before any UI exists. The
strategy (one codebase vs per-platform) and the monorepo boundaries are the two decisions you
cannot cheaply reverse — everything else is an implementation detail.

---

## When to use / NOT use

**Use this skill when** you are starting a product that must run on ≥2 surfaces (web + mobile, or
mobile + desktop, or all three), or when an existing single-surface app is about to grow a second
surface. Also use it to *audit* a stack that has drifted into copy-paste between repos.

**Do NOT use it when** you ship exactly one surface and have no concrete plan for a second within
~12 months. A premature monorepo + abstraction layer is pure tax: you pay the indirection cost now
for optionality you may never exercise. Ship the single app, keep the domain logic framework-free,
and graduate to a monorepo when the second surface is funded.

---

## Mental model: share the *core*, split the *shell*

Every app is three concentric rings. Share inward, split outward:

```
            ┌─────────────────────────────────────────┐
            │  PLATFORM SHELL  (split, per-surface)    │  navigation chrome, window/tray,
            │  ┌───────────────────────────────────┐  │  push registration, file system,
            │  │  UI COMPONENTS (mostly shared)     │  │  native modules
            │  │  ┌─────────────────────────────┐  │  │
            │  │  │  CORE (100% shared)         │  │  │  domain logic, validation (zod),
            │  │  │  types · api-client · state │  │  │  api client, types, formatting,
            │  │  └─────────────────────────────┘  │  │  feature flags, analytics events
            │  └───────────────────────────────────┘  │
            └─────────────────────────────────────────┘
```

- **Core** (zod schemas, domain functions, API client, query keys, state machines): no React, no
  `react-native`, no `next`. Pure TypeScript. This is **100% shareable** and the highest-leverage
  code you own. Protect its purity with lint rules.
- **UI**: shareable across React Native + React Native Web (one component tree), *not* shareable
  with Flutter or SwiftUI. 60–90% if you commit to RN-everywhere.
- **Shell**: always per-surface. Don't fight it.

The single biggest architecture mistake is letting platform concerns (`Platform.OS`, `window`,
`fs`, `Dimensions`) leak into the Core ring. Once that happens, the Core stops being portable and
every consumer inherits the leak.

---

## Decision matrix: pick the strategy

| Strategy | Surfaces covered | Realistic code share | Native fidelity | Team skills | Pick when… |
|----------|------------------|----------------------|-----------------|-------------|-----------|
| **Expo universal** (Expo Router + RN Web) **+ Tauri/Electron shell** | iOS, Android, Web, Desktop | **70–90%** | High on mobile; web = DOM; desktop = web | TS/React | You're a React shop and want *all* surfaces from one codebase. **Default for most teams in 2026.** |
| **Flutter** | iOS, Android, Web, Desktop (multi-window preview in 3.44) | **85–95%** | High (own renderer, Impeller) | Dart | Pixel-identical UI across surfaces matters more than web SEO/DOM; team can adopt Dart. |
| **Native per platform** (Swift/SwiftUI + Kotlin/Compose) | iOS, Android (+ separate web) | **0–30%** (share via KMP) | Highest possible | Swift + Kotlin | Platform-defining apps, heavy OS integration, or perf/UX ceiling that RN/Flutter can't hit. |
| **Capacitor** (web app in native webview) | iOS, Android, Web (+ Electron) | **90%+** | Low–medium (WKWebView/Chrome) | Web | Content/CRUD app, existing SPA, fast time-to-store, few native-feel requirements. |
| **PWA only** | Web + installable | 100% (one app) | Lowest (no stores, limited iOS APIs) | Web | Reach > native feel; no App Store gatekeeping; internal tools. iOS PWA limits still bite. |

**The honest defaults (2026):**
- React team, all surfaces → **Expo universal + a Tauri or Electron desktop shell**. See `unified-one-codebase`.
- Need a desktop *companion* to an RN app, not full universal → ship RN mobile natively + a small **Tauri** app that reuses the Core packages (not the RN UI).
- UI must be byte-identical and brand-controlled everywhere, no DOM needed → **Flutter 3.44**.
- "We have a Next.js app and need it in the stores next month" → **Capacitor**.

Anti-fragile rule: **don't mix two UI frameworks for the same screens.** A Flutter mobile app + React web app is two products. That's a valid choice, but be honest that your share drops to the Core ring only (types via codegen, not components).

---

## Monorepo: pnpm workspaces + Turborepo

pnpm for the workspace (content-addressed store, strict `node_modules`, fast, handles RN/Expo's
peer-dep reality better than npm), Turborepo for task orchestration + remote caching.

```
my-app/
├── package.json            # workspaces root, private:true
├── pnpm-workspace.yaml
├── turbo.json
├── tsconfig.base.json
├── apps/
│   ├── mobile/             # Expo (iOS + Android), Expo Router
│   ├── web/                # Next.js OR Expo web export
│   └── desktop/            # Tauri (preferred) or Electron shell
└── packages/
    ├── core/               # @acme/core — pure TS: domain, zod, state machines
    ├── api/                # @acme/api — typed client (tRPC/openapi-fetch), query keys
    ├── ui/                 # @acme/ui — RN + RN Web components (design system)
    ├── config/             # @acme/config — eslint, tsconfig, tailwind preset
    └── types/              # @acme/types — shared types if not colocated in core
```

```yaml
# pnpm-workspace.yaml
packages:
  - "apps/*"
  - "packages/*"
```

```jsonc
// turbo.json — cache builds, lint, typecheck; never cache dev/long-running
{
  "$schema": "https://turbo.build/schema.json",
  "tasks": {
    "build":     { "dependsOn": ["^build"], "outputs": ["dist/**", ".next/**", "!.next/cache/**"] },
    "typecheck": { "dependsOn": ["^build"], "outputs": [] },
    "lint":      { "outputs": [] },
    "test":      { "dependsOn": ["^build"], "outputs": ["coverage/**"] },
    "dev":       { "cache": false, "persistent": true }
  }
}
```

```jsonc
// packages/core/package.json — pure, no react/react-native
{
  "name": "@acme/core",
  "version": "0.0.0",
  "private": true,
  "type": "module",
  "exports": { ".": "./src/index.ts" },   // ship source; consuming app's bundler transpiles
  "dependencies": { "zod": "^3.24.0" },
  "peerDependencies": {}
}
```

> **Expo + monorepo reality:** Expo's Metro supports monorepos but you must enable it. In
> `apps/mobile/metro.config.js` set `config.watchFolders = [workspaceRoot]` and add
> `config.resolver.nodeModulesPaths = [appNodeModules, workspaceNodeModules]`. Use
> `withExpoMetroConfig`/`getDefaultConfig` and **do not** symlink-hoist native deps blindly — RN
> native modules must resolve to a single copy or you get duplicate-symbol crashes. pnpm's
> `node-linker=hoisted` (in `.npmrc`) is the pragmatic setting for Expo monorepos in 2026.

---

## Shared packages: what goes where

| Package | Contains | May import | Must NOT import |
|---------|----------|------------|-----------------|
| `@acme/core` | domain logic, zod schemas, pure functions, XState machines, formatting | `zod`, date libs | `react`, `react-native`, `next`, anything with `window`/`fs` |
| `@acme/api` | typed API client, query keys/options, DTO mappers | `@acme/core`, `@tanstack/react-query` | UI libs, platform globals |
| `@acme/ui` | RN + RN Web components, tokens, hooks | `react`, `react-native`, `@acme/core` | `next`, Node APIs, `electron` |
| `@acme/config` | eslint/tsconfig/tailwind presets | — | runtime code |

Enforce the boundaries with lint, not vibes:

```jsonc
// .eslintrc — ban platform leakage into core via import boundaries
{
  "rules": {
    "import/no-restricted-paths": ["error", {
      "zones": [
        { "target": "./packages/core", "from": "./packages/ui",  "message": "core must not depend on UI" },
        { "target": "./packages/core", "from": "./apps",          "message": "core must not depend on apps" }
      ]
    }]
  }
}
```

For server↔client type safety, prefer a **contract**: tRPC (TS-only backend) or OpenAPI →
`openapi-typescript` codegen. Either way the client lives in `@acme/api` and every surface imports
the *same* client. (Backend/contract details → `fullstack-stacks-master`, `backend-api-master`.)

---

## Platform-specific file resolution (the escape hatch)

Metro (RN/Expo) and bundlers resolve platform extensions automatically. Keep the *public API*
identical; vary the *implementation*:

```
Analytics.ts          # types + default (throws if used directly)
Analytics.native.ts   # iOS + Android (expo-firebase-analytics / native SDK)
Analytics.web.ts      # web (PostHog / GA)
Analytics.ios.ts      # iOS-only override (wins over .native on iOS)
Analytics.android.ts  # Android-only override
```

Resolution order: `.ios.ts` / `.android.ts` → `.native.ts` → `.web.ts` (web) → `.ts`. So `.ios`
beats `.native`, and web never sees `.native`.

```ts
// storage.ts — single import site, platform picks the impl
export interface KVStore { get(k: string): string | null; set(k: string, v: string): void }
export const storage: KVStore = (() => { throw new Error("import platform file"); })();
```
```ts
// storage.native.ts  — MMKV (synchronous, fast)
import { MMKV } from "react-native-mmkv";
const mmkv = new MMKV();
export const storage = {
  get: (k) => mmkv.getString(k) ?? null,
  set: (k, v) => mmkv.set(k, v),
};
```
```ts
// storage.web.ts — localStorage
export const storage = {
  get: (k: string) => globalThis.localStorage.getItem(k),
  set: (k: string, v: string) => globalThis.localStorage.setItem(k, v),
};
```

Use platform files for the *capability* boundary; use a runtime `Platform.select()` only for tiny
style/value tweaks. Don't `if (Platform.OS === 'web')` your way through a 300-line component — split
the file.

---

## State & data layer choices

| Concern | Recommendation (2026) | Why |
|---------|----------------------|-----|
| **Server cache / data fetching** | **TanStack Query v5** | Caching, dedupe, offline persistence, optimistic updates — works identically on RN + web. Don't hand-roll this. |
| **Client/UI state** | **Zustand** (or Jotai for atomic) | Tiny, no provider hell, works in RN + web + Node tests. Redux Toolkit only if you need its devtools/middleware ecosystem at scale. |
| **Complex flows** | **XState** in `@acme/core` | Auth, checkout, onboarding as a machine = same logic every surface, testable headless. |
| **Local persistence** | **MMKV** (KV) · **op-sqlite / expo-sqlite + Drizzle** (relational) | MMKV for tokens/flags; SQLite+Drizzle for offline-first records. |
| **Offline sync** | **PowerSync / WatermelonDB / Legend-State** | Don't invent sync. Pick a CRDT/replication library and own the conflict policy. |

Keep all of this — query keys, store creators, machines — in `@acme/core`/`@acme/api` so a screen
on any surface is just *glue*. If your Zustand store imports `react-native`, you've already lost web.

---

## Edge cases & gotchas (war stories)

- **The duplicate-React crash.** Two copies of `react` or `react-native` in the tree → cryptic
  "Invalid hook call" or native duplicate-symbol failures. Cause: a package declared `react` as a
  *dependency* instead of `peerDependency`. Rule: shared UI packages put `react`/`react-native` in
  `peerDependencies` only. Verify with `pnpm why react`.
- **Web-only module imported in native bundle.** A util `import`s `localStorage` at module top →
  Metro bundles it → red screen on device. Fix: platform files, or lazy-import behind a capability
  check, never a bare top-level platform global.
- **Next.js + RN Web transpile.** If `apps/web` is Next.js consuming `@acme/ui` (RN Web), you must
  `transpilePackages: ["@acme/ui", "react-native-web", "react-native"]` in `next.config.js` and
  alias `react-native` → `react-native-web`. Forgetting this = "Unexpected token" on Flow syntax.
- **Hoisting + native autolinking.** pnpm's strict linker can hide native deps from Expo
  autolinking. Use `node-linker=hoisted` for Expo apps; isolated linker is fine for pure-TS packages.
- **"Shared everything" cargo cult.** Sharing a button across RN and Flutter is impossible; sharing
  copy/i18n strings, types, and analytics event names is trivial and high value. Share the boring
  stuff aggressively; stop pretending the UI layer crosses framework lines.
- **Versioning drift.** Apps on different Expo SDKs in one monorepo = dependency hell. Keep all
  Expo/RN apps on **one** SDK; bump them together.

---

## Performance (architecture-level)

- **Bundle:** ship `@acme/core` as **source** and let each app's bundler tree-shake, rather than
  pre-bundling to CJS (dead code from a sibling app's feature won't ride along). Mark packages
  `"sideEffects": false` where true.
- **Turborepo remote cache** turns a 6-minute CI typecheck/lint/test into seconds on cache hit —
  the single biggest DX/perf win in a monorepo. Wire it on day one.
- **Don't barrel-export huge index files** from `@acme/ui`; deep imports keep mobile bundles lean
  (RN has no automatic route-level code splitting like web).
- Measure share %, don't guess: `cloc packages/core packages/api` vs per-app `app/`. If "shared" is
  <40% you built a monorepo for nothing — reconsider the strategy.

## Security

- **Secrets never live in `@acme/core`.** Shared code is bundled into clients; anything in it is
  public. API keys → server; per-platform secure storage (`expo-secure-store` / Keychain / Keystore)
  for tokens. See `native-bridge-integration` and `mobile-apps-pro`.
- **Supply chain:** one lockfile, `pnpm audit` in CI, pin Expo SDK + RN. A monorepo multiplies blast
  radius — a compromised dep hits every surface. Use `pnpm.overrides` to force-patch transitive CVEs.
- **Different surfaces = different threat models.** Web has XSS; desktop has IPC/RCE; mobile has
  reverse-engineering. Don't assume one auth/storage approach is safe everywhere — the surface skills
  cover each.

## Scale & maintainability

- **One SDK/RN version across all apps**, bumped in lockstep. Use `expo install --check`.
- **Codeowners per package** so `@acme/core` changes get domain review, not a UI reviewer rubber-stamp.
- **Public API discipline:** every package exposes a curated `index.ts`; internal files are not
  importable cross-package. This is what lets you refactor internals without breaking 4 apps.
- Graduate to Nx only if you outgrow Turborepo's task graph (distributed task execution, project
  generators at very large scale). For ≤~20 packages, Turborepo is the right call.

## Testing

- **Core is unit-test heaven:** zod schemas, machines, formatters run in plain Vitest/Jest with no
  device, no DOM. Aim for high coverage *here* — it's cheap and protects every surface at once.
- **Contract tests** on `@acme/api` against a mock server (MSW) catch API drift before any surface does.
- Surface-specific E2E (Detox/Maestro for mobile, Playwright for web/desktop-web) lives in `apps/*`,
  not in shared packages. Covered in the surface skills.

## Observability

- Define analytics **event names + payload schemas once in `@acme/core`** (zod), emit through a
  platform `Analytics` file. This guarantees "checkout_completed" means the same thing on every
  surface and gives you typed events. (Funnels/flags → `analytics-master`.)
- Centralize a `logger` capability the same way; wire Sentry per surface but tag `release` +
  `surface` so dashboards split by platform.

## Accessibility & i18n / RTL

- Put translation **keys and ICU messages in a shared package**; load per surface. One source = no
  surface ships a stale string.
- **RTL (Arabic) is an architecture decision, not a CSS afterthought.** RN uses `I18nManager`
  (logical `start`/`end` instead of `left`/`right`); web uses `dir="rtl"` + CSS logical properties.
  Bake logical directions into `@acme/ui` from the first component so Arabic mirrors correctly
  everywhere. Test pseudo-localization in CI.

---

## Anti-patterns

- **Monorepo before a second surface exists.** Optionality tax with no payoff. Ship the app first.
- **`react-native` / `window` / `fs` imported in `@acme/core`.** Kills portability; enforce with
  `import/no-restricted-paths`.
- **Two UI frameworks for the same screens** (Flutter mobile + React web) while claiming "shared
  app." You share types at best — own that decision explicitly.
- **`Platform.OS` ladders everywhere** instead of `.native`/`.web` files. Unreadable, unbundleable.
- **Copy-pasting the API client into each app.** The #1 source of "works on web, broken on iOS."
- **One giant `@acme/ui` barrel** that defeats tree-shaking and bloats mobile bundles.
- **Different Expo SDKs across apps** in one repo — guaranteed dependency deadlock.

## Agent checklist
```
- [ ] Strategy chosen from the matrix and written down (with the realistic share %)
- [ ] Monorepo: pnpm workspaces + Turborepo; node-linker=hoisted for Expo apps
- [ ] @acme/core is pure TS (no react/react-native/window/fs); enforced by lint
- [ ] Shared api-client + query keys live in @acme/api, imported by every surface
- [ ] Platform splits via .native/.web/.ios/.android, not Platform.OS ladders
- [ ] react/react-native are peerDependencies in shared UI packages (pnpm why react == 1 copy)
- [ ] Next.js web transpiles RN packages + aliases react-native→react-native-web (if used)
- [ ] State: TanStack Query (server) + Zustand/XState (client) in shared packages
- [ ] i18n keys + analytics event schemas shared; RTL/logical directions baked into UI
- [ ] All RN/Expo apps on a single SDK version
```

## References
- Expo monorepos: https://docs.expo.dev/guides/monorepos/
- Turborepo: https://turbo.build/repo/docs · pnpm workspaces: https://pnpm.io/workspaces
- React Native Web: https://necolas.github.io/react-native-web/
- TanStack Query: https://tanstack.com/query/latest · Zustand: https://zustand.docs.pmnd.rs/
- Expo Router: https://docs.expo.dev/router/introduction/

## Related
`unified-one-codebase`, `desktop-apps-pro`, `mobile-apps-pro` (this master) · `mobile-master`
(RN/Expo/Flutter deep-dives) · `fullstack-stacks-master` (shared TS stack + API contract) ·
`ui-master` + `tailwind-master` (design system, RN Web) · `backend-api-master`
