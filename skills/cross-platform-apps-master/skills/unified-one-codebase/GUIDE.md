---
name: unified-one-codebase
description: >-
  The reference architecture for ONE codebase that ships web + desktop + mobile at staff depth:
  Expo Router universal routes + React Native Web for web, a Tauri 2 (or Electron) shell wrapping
  the web build for desktop, and native iOS/Android from the same RN tree — plus the Flutter
  alternative. Covers a shared RN+RN-Web design system, responsive/adaptive layout, .native/.web
  platform splits, the all-targets build pipeline, and the real pitfalls (web-only/native-only
  modules, desktop = web APIs not native RN). Use when one team must cover every surface.
---

# Unified One-Codebase — Web + Desktop + Mobile from One System

**Mandate:** One routing tree, one design system, one core — emitting four artifacts (iOS, Android,
web, desktop). The magic isn't "write once run everywhere" (a lie); it's **one component tree with
disciplined platform seams** so 80%+ is shared and the 20% that must differ is *explicit and
contained*, not smeared across every file.

---

## When to use / NOT use

**Use** when a single team must deliver a consistent product across all surfaces and you're a
React/TypeScript shop. This is the highest-leverage setup for startups and product teams that can't
staff separate iOS, Android, web, and desktop squads.

**Do NOT use** when any one surface needs a *fundamentally different* product (e.g. a content-heavy
SEO marketing web app + a tool-like native app — those are two apps sharing a Core, not one universal
app), when desktop genuinely needs native OS depth a web shell can't give, or when the web surface
lives or dies on SEO/SSR and Expo Router web's tradeoffs don't fit. In those cases use
`cross-platform-architecture` to split deliberately and share only the Core ring.

---

## Mental model: one tree, two renderers, one desktop wrapper

```
                         ┌──────────────────────────────────────────┐
                         │   Expo Router (file-based universal routes)│
                         │   + @acme/ui  (RN primitives)              │
                         │   + @acme/core / @acme/api  (shared logic) │
                         └──────────────────────────────────────────┘
                                  │                         │
                 React Native (Fabric)             React Native Web (DOM)
                                  │                         │
                ┌─────────────────┴───────┐         ┌───────┴────────────────┐
                │  iOS app   │  Android app │         │  web build (static)    │
                │  (native modules work)    │         │  served on the web     │
                └───────────────────────────┘         └───────┬────────────────┘
                                                               │ wrap the web build
                                                       ┌───────┴────────────────┐
                                                       │  Tauri 2 / Electron     │  ← DESKTOP
                                                       │  (web APIs + IPC, NOT   │
                                                       │   RN native modules)    │
                                                       └─────────────────────────┘
```

The non-obvious truth that trips up every team: **desktop is the *web* build wrapped in a native
shell.** On desktop your code runs in a system WebView/Chromium with **web APIs**, not React Native
native modules. So `react-native-mmkv` (a native module) does *not* work on desktop; `localStorage`
or a Tauri command does. Design your capability seams (`.native` / `.web`) accordingly — desktop
follows the **`.web`** path. Treat "desktop" as a third member of the web family, gaining native
power only through the Tauri/Electron IPC bridge you expose.

---

## Decision matrix: how to get desktop

| Approach | Desktop from… | Native depth on desktop | Bundle | Pick when |
|----------|---------------|-------------------------|--------|-----------|
| **Tauri 2 wraps Expo-web build** ⭐ | the RN-Web bundle | via Rust commands you expose | tiny (~5–10 MB) | Default. Small, secure, one toolchain (also does mobile). |
| **Electron wraps Expo-web build** | the RN-Web bundle | via Node IPC | large (~100 MB+) | Need Chromium parity or heavy Node libs on desktop. |
| **react-native-windows / -macos** | the RN native tree | true RN native modules | medium | You need *RN native* on desktop (rarer; smaller ecosystem). |
| **Flutter (single codebase)** | Flutter engine | platform channels | medium | You chose Flutter for everything; multi-window desktop preview in 3.44. |

**Opinion:** Expo Router universal + RN Web + **Tauri 2** shell is the 2026 sweet spot for a React
team. Choose Electron only for Chromium-parity needs. Choose `react-native-windows/macos` only if
desktop truly must run RN *native* modules (it rarely does). Flutter is the coherent alternative if
you don't want the JS ecosystem at all.

---

## The build pipeline (all four targets)

```jsonc
// package.json (apps/universal) scripts — one project, four outputs
{
  "scripts": {
    "dev": "expo start",                         // mobile + web dev
    "ios": "expo run:ios",
    "android": "expo run:android",
    "web": "expo start --web",
    "export:web": "expo export -p web",          // -> dist/  (static web build)
    "desktop:dev": "tauri dev",                  // points at expo web dev server
    "desktop:build": "expo export -p web && tauri build"
  }
}
```

```jsonc
// src-tauri/tauri.conf.json — wrap the exported web build
{
  "build": {
    "frontendDist": "../dist",                   // expo export -p web output
    "devUrl": "http://localhost:8081",           // expo web dev server (Metro)
    "beforeBuildCommand": "pnpm export:web"
  },
  "app": { "windows": [{ "title": "Acme", "width": 1100, "height": 720 }] }
}
```

So the pipeline is: **mobile** → EAS Build from the RN tree; **web** → `expo export -p web` →
static host; **desktop** → that same `dist/` wrapped by `tauri build` (signed + notarized). Four
artifacts, one source. CI runs them in parallel (see `app-store-deployment`).

---

## Shared design system across RN + RN Web

The whole model collapses if your UI library only works on one renderer. Build `@acme/ui` on RN
primitives (`View`, `Text`, `Pressable`) — RN Web maps these to DOM automatically. For styling in
2026, **NativeWind** (Tailwind for RN, compiles to RN styles on native and real CSS on web) gives you
one className API across all surfaces; or use a styled system like Tamagui (optimizing compiler,
strong web+native story). Don't hand-roll two style systems.

```tsx
// packages/ui/Button.tsx — ONE component, works on iOS/Android/web/desktop
import { Pressable, Text, type PressableProps } from "react-native";
import { cva, type VariantProps } from "class-variance-authority";

const button = cva("flex-row items-center justify-center rounded-lg px-4 h-11", {
  variants: {
    variant: {
      primary: "bg-primary active:opacity-90",
      outline: "border border-border bg-transparent",
    },
    size: { md: "h-11 px-4", lg: "h-13 px-6" },
  },
  defaultVariants: { variant: "primary", size: "md" },
});

export interface ButtonProps extends PressableProps, VariantProps<typeof button> {
  title: string;
}
export function Button({ title, variant, size, ...props }: ButtonProps) {
  // With NativeWind, className compiles to RN styles on native and CSS on web.
  return (
    <Pressable
      className={button({ variant, size })}
      accessibilityRole="button"            // becomes role="button" on web, trait on native
      {...props}
    >
      <Text className="text-primary-foreground font-medium">{title}</Text>
    </Pressable>
  );
}
```

Tokens live once (see `tailwind-design-tokens` / `ui-master`); a token change re-themes every
surface. The button above renders as a real `<button>`-like element on web/desktop and a native
pressable on mobile, with the same a11y semantics.

---

## Responsive / adaptive layout

Don't ship a 375px phone column stretched across a 1440px desktop window. Adapt by **available
width**, not by platform:

```tsx
import { useWindowDimensions } from "react-native";

export function useLayout() {
  const { width } = useWindowDimensions();
  return {
    isCompact: width < 640,           // phone
    isMedium: width >= 640 && width < 1024, // tablet / small window
    isExpanded: width >= 1024,        // desktop / large window
  };
}
```

```tsx
// A list/detail that becomes master-detail on wide surfaces
function Inbox() {
  const { isExpanded } = useLayout();
  return isExpanded
    ? <Row><MessageList style={{ width: 360 }} /><MessageDetail /></Row>   // desktop/tablet
    : <MessageList onSelect={(id) => router.push(`/message/${id}`)} />;     // phone: navigate
}
```

Use breakpoints driven by window size (so a *resized desktop window* and a tablet behave the same),
safe-area insets on mobile, and keyboard/pointer affordances (hover, right-click menus) only where a
pointer exists. Expo Router's typed routes power both the mobile stack and web/desktop URLs.

---

## Platform splits: the escape hatch, contained

Keep the public API identical; vary the implementation by file. **Remember desktop = `.web`.**

```
notifications.ts            # interface + throwing default
notifications.native.ts     # expo-notifications (iOS/Android)
notifications.web.ts        # Web Push / Notification API  ← also runs on desktop (Tauri/Electron)
```

For desktop-only native power (tray, true filesystem), expose it through the shell's IPC and call it
*only* behind a runtime capability check, so the same `.web` file degrades gracefully in a browser:

```ts
// notifications.web.ts — feature-detect the desktop bridge; fall back to web on a plain browser
export const notifications = {
  async notify(title: string, body: string) {
    // Tauri injects __TAURI__; Electron injects our contextBridge `window.api`
    if ("__TAURI__" in globalThis) {
      const { sendNotification } = await import("@tauri-apps/plugin-notification");
      return sendNotification({ title, body });
    }
    if (Notification?.permission === "granted") return void new Notification(title, { body });
  },
};
```

This is the core discipline: **one import site, platform/file resolution picks the impl, and
desktop-specific power is feature-detected, never assumed.**

---

## Edge cases & gotchas (war stories)

- **"It works on mobile, white screen on desktop."** You imported a **native module**
  (`react-native-mmkv`, a native-only lib) into code that runs on the web/desktop path. Desktop is the
  web bundle — it has no native modules. Move it behind `.native`, or use a web/desktop equivalent.
- **Next.js for web instead of Expo web** — totally valid, but then you must
  `transpilePackages: ["@acme/ui","react-native-web","react-native"]`, alias `react-native` →
  `react-native-web`, and accept that `apps/web` and `apps/universal` are different web stacks. Pick
  one web story; don't run both by accident. (Solito exists to bridge Expo + Next, but Expo Router now
  does web natively — only add Solito if you specifically want Next.js.)
- **WebView quirks on desktop.** Tauri uses the OS WebView (WKWebView on macOS, WebView2 on Windows,
  WebKitGTK on Linux). CSS/JS that's fine in Chrome can break on WebKitGTK. If pixel parity across
  Linux desktop matters, that's the case for Electron.
- **Routing divergence.** Don't build a separate router for web. Expo Router's file routes *are* your
  URLs on web/desktop and your stack on mobile. Fighting this = two navigation systems to maintain.
- **Bundle bloat on web.** RN Web + your whole mobile dependency graph can balloon the web bundle.
  Audit it; `.web` out native-only deps; lazy-load routes.
- **Desktop deep links vs mobile deep links** are different mechanisms (protocol handler +
  single-instance on desktop; universal links on mobile). Share the *router target*, not the
  registration code.

## Performance

- **Web/desktop:** code-split by route (Expo Router does this), tree-shake `@acme/ui` (deep imports,
  not one barrel), and keep RN Web's runtime lean. Measure with Lighthouse on web.
- **Mobile:** all of `mobile-apps-pro` applies — Hermes, FlashList v2, expo-image, Reanimated.
- **Desktop:** Tauri's tiny footprint is a feature; don't reintroduce Electron-scale weight unless you
  need it. Defer heavy work to Rust/Node via IPC so the WebView stays responsive.
- One bundle visualizer per target in CI; budget bundle size and fail the build on regressions.

## Security

- **Three threat models, one codebase.** Web/desktop WebView → XSS/CSP; desktop shell → IPC/RCE
  (harden per `desktop-apps-pro`); mobile → reverse-engineering + secure storage (`mobile-apps-pro`).
  Don't assume one storage/auth approach is safe on all three.
- Secrets never in shared/bundled code (it ships to every surface). Per-surface secure storage behind
  the capability seam.
- Desktop IPC: least-privilege Tauri capabilities / hardened Electron contextBridge; validate all
  inputs. The web build you wrap is attacker-influenceable via any XSS.

## Scale & maintainability

- One Expo SDK across mobile + web; bump in lockstep with the desktop shell.
- Keep `@acme/core`/`@acme/api` pure and framework-free so all four surfaces stay thin glue
  (`cross-platform-architecture`).
- A **capability registry** (`storage`, `notifications`, `analytics`, `auth`, `secureStore`) with
  `.native`/`.web` impls is the backbone — every platform difference funnels through it, so adding a
  surface is "implement the registry," not "grep the app."
- CODEOWNERS on `@acme/ui` and `@acme/core`; visual-regression the design system so a token change
  can't silently break one renderer.

## Testing

- **Shared core:** Vitest/Jest (no device/DOM).
- **Component:** React Native Testing Library (runs the RN tree).
- **Web + desktop-web:** **Playwright** against the exported web build (and against the packaged Tauri
  app via `tauri-driver` / Electron via `_electron.launch()`).
- **Mobile:** **Maestro** for smoke/regression, **Detox** for high-risk flows.
- Run the **same critical-flow spec** against web and desktop where possible — the UI is shared, so the
  assertions should be too.

## Observability

- One typed analytics event schema (`@acme/core`) emitted via the `analytics` capability so funnels are
  comparable across surfaces; tag `surface: ios|android|web|desktop`.
- Sentry on every surface (`@sentry/react-native` for mobile, browser SDK for web,
  `@sentry/electron` / Tauri integration for desktop) with `release` + `surface` tags so a regression
  is attributable to the right target.

## Accessibility & i18n / RTL

- RN's `accessibilityRole`/`accessibilityLabel` map to ARIA on web/desktop and native traits on
  mobile — write them **once** in `@acme/ui` and all surfaces benefit. Keyboard nav matters on
  web/desktop; touch targets (44/48) on mobile.
- One i18n catalog (keys + ICU) loaded per surface. **RTL/Arabic:** logical `start`/`end` in styles
  (works on RN + RN Web), `I18nManager` on mobile, `dir="rtl"` on web/desktop. Build mirroring into
  `@acme/ui` from day one so Arabic is correct on all four targets at once. Pseudo-localize in CI.

---

## Anti-patterns
- Importing native-only modules into the web/desktop path (the #1 "white screen on desktop").
- Treating desktop as "another native app" — it's the **web** build; it has web APIs + your IPC only.
- Two routers (one for web, one for mobile) instead of Expo Router universal.
- Two design systems / style engines instead of one RN+RN-Web library (NativeWind/Tamagui).
- Phone UI stretched to desktop width with no adaptive layout.
- `Platform.OS` ladders everywhere instead of `.native`/`.web` capability files.
- One `@acme/ui` barrel export that bloats the web bundle and kills tree-shaking.
- Assuming one auth/secure-storage approach is safe across web, desktop, and mobile.

## Agent checklist
```
- [ ] Expo Router universal routes are the single navigation/URL system
- [ ] @acme/ui built on RN primitives + NativeWind/Tamagui — renders on RN and RN Web
- [ ] Desktop = Tauri 2 (default) or Electron wrapping `expo export -p web` output (dist/)
- [ ] Desktop code follows the .web path; native power exposed via IPC + feature-detected
- [ ] Capability registry (storage/notifications/analytics/auth) with .native/.web impls
- [ ] Adaptive layout by window width (master-detail on wide, stack on compact)
- [ ] No native-only modules imported on the web/desktop path
- [ ] Build pipeline emits 4 artifacts from one source; bundle budgets enforced per target
- [ ] Three threat models handled (web CSP, desktop IPC, mobile secure storage)
- [ ] Shared typed analytics + Sentry tagged by surface; one i18n catalog with RTL baked in
- [ ] Playwright (web/desktop) + Maestro/Detox (mobile); shared critical-flow specs
```

## References
- Expo Router (universal/web): https://docs.expo.dev/router/introduction/ · web rendering: https://docs.expo.dev/router/reference/static-rendering/
- React Native Web: https://necolas.github.io/react-native-web/ · NativeWind: https://www.nativewind.dev/ · Tamagui: https://tamagui.dev/
- Tauri 2: https://v2.tauri.app/ · Electron: https://www.electronjs.org/docs/latest/
- react-native-windows/macos: https://microsoft.github.io/react-native-windows/

## Related
`cross-platform-architecture` (monorepo + shared core), `desktop-apps-pro` (sign/notarize/IPC the
shell), `mobile-apps-pro` (the native side), `app-store-deployment` (ship all 4) · `ui-master` +
`tailwind-master` (design system, tokens) · `mobile-master` · `fullstack-stacks-master`
