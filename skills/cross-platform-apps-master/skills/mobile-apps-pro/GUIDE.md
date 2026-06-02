---
name: mobile-apps-pro
description: >-
  Build high-end iOS + Android apps at staff depth with React Native 0.83+/Expo SDK 55 on the
  New Architecture (Fabric, TurboModules, Hermes, bridgeless) — and know when Flutter or fully
  native wins. Covers navigation/state/data architecture, performance (FlashList v2, startup,
  expo-image caching), offline-first + sync, push (APNs/FCM via expo-notifications), deep/
  universal links, secure storage (Keychain/Keystore), biometrics, a11y, and iOS/Android
  platform specifics + store guidelines. Use for any production phone/tablet app.
---

# Mobile Apps Pro — Production iOS + Android (RN/Expo, New Architecture)

**Mandate:** A great mobile app is *fast to first interaction, silky on lists, correct offline, and
respectful of the platform*. In 2026 that means the **New Architecture by default**, Expo for the
build/release pipeline, and ruthless attention to startup time, list perf, and secure storage —
because that's what users and reviewers actually feel.

---

## When to use / NOT use

**Use** for a polished consumer or B2B app on phones/tablets where you want one TypeScript codebase
across iOS + Android, OTA updates, and a fast release loop. React Native + Expo is the default.

**Reach for Flutter instead** when you want a single team to own pixel-identical custom UI across
iOS/Android/desktop with no DOM, or you're heavily animation/canvas-driven and want Impeller's
consistency. **Reach for fully native (SwiftUI/Compose)** when the app *is* the platform integration
— deep widgets/live activities, App Clips/instant apps, cutting-edge OS APIs on day one, or a perf
ceiling RN can't reach. **Don't** force RN onto a game (use a game engine) or onto a team with zero
JS skills and deep native expertise.

---

## Mental model: the New Architecture is the baseline now

As of **RN 0.82 you cannot disable** the New Architecture; **0.83 removed legacy code**; **0.85
(April 2026) removed the Bridge entirely**. Expo **SDK 55 (RN 0.83, React 19.2)** is New-Arch-only
and dropped `newArchEnabled`. So:

```
JavaScript (Hermes)  ⇄  JSI (direct C++ refs, synchronous)  ⇄  Native (Swift/Kotlin/C++)
                              │                     │
                          TurboModules         Fabric renderer
                       (lazy native modules)  (C++ shadow tree, concurrent React)
                              │
                          Codegen (build-time type-safe bindings)
```

No JSON bridge, no async serialization tax. Practically: native modules must be **TurboModules**;
custom views must be **Fabric** components; anything still on `RCTBridgeModule` won't run. Libraries
like `react-native-reanimated` v4 and `@shopify/flash-list` v2 are **New-Arch-only** — that's the
ecosystem signal that the migration is over.

**Use Expo, even for "bare" apps.** Continuous Native Generation (`expo prebuild`) + config plugins
means you describe native config in `app.config.ts` and regenerate `ios/`/`android/` instead of
hand-editing them. EAS builds/signs/submits. This is the 2026 default; "vanilla RN without Expo" is a
choice you should be able to justify.

---

## Decision matrix: RN/Expo vs Flutter vs Native

| Need | RN + Expo (0.83/SDK 55) | Flutter 3.44 | Native (SwiftUI/Compose) |
|------|-------------------------|--------------|--------------------------|
| One TS codebase incl. web/desktop reuse | ✅ best (shares with React web) | ⚠️ Dart only | ❌ |
| Pixel-identical custom UI everywhere | ⚠️ uses native widgets | ✅ own renderer (Impeller) | platform-specific |
| OTA JS updates | ✅ EAS Update / expo-updates | ⚠️ limited | ❌ |
| Day-one new OS API | ⚠️ wait for lib / write module | ⚠️ wait for plugin | ✅ |
| Animation/perf ceiling | ✅ good (Reanimated/JSI) | ✅ excellent | ✅ best |
| Team skill = JS/React | ✅ | ❌ Dart | ❌ Swift+Kotlin |
| Heavy native integration (widgets, live activities) | ⚠️ via modules | ⚠️ via channels | ✅ |

**Default:** RN + Expo. Pick Flutter for design-controlled multi-surface UI; pick native for
platform-defining apps. (Framework deep-dives → `mobile-master`.)

---

## Reference architecture (the stack that ships)

| Layer | Pick | Notes |
|-------|------|-------|
| Routing | **Expo Router v7** (file-based, on React Navigation 7) | Universal (also web). Typed routes. |
| Server state | **TanStack Query v5** | Caching, offline persistence, optimistic updates. |
| Client state | **Zustand** (+ **XState** for flows) | Lives in `@acme/core`, framework-free. |
| Lists | **FlashList v2** | New-Arch-only, no estimates, recycling. |
| Images | **expo-image** | Disk+memory cache, blurhash, `recyclingKey` for lists. |
| Animation | **react-native-reanimated v4** + **gesture-handler** | UI-thread animations. |
| Storage (KV) | **react-native-mmkv** | Synchronous, fast; great for flags/tokens (encrypt for secrets). |
| Storage (DB) | **op-sqlite / expo-sqlite + Drizzle** | Offline-first records. |
| Secure storage | **expo-secure-store** | Keychain (iOS) / Keystore (Android). |
| Push | **expo-notifications** | APNs + FCM via Expo push service or direct. |
| Auth biometrics | **expo-local-authentication** | Face ID / Touch ID / fingerprint. |

```tsx
// app/_layout.tsx — Expo Router root: providers + query client + gesture root
import { Stack } from "expo-router";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { GestureHandlerRootView } from "react-native-gesture-handler";

const queryClient = new QueryClient({
  defaultOptions: { queries: { staleTime: 30_000, retry: 2, gcTime: 1000 * 60 * 60 * 24 } },
});

export default function RootLayout() {
  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <QueryClientProvider client={queryClient}>
        <Stack screenOptions={{ headerLargeTitle: true }}>
          <Stack.Screen name="(tabs)" options={{ headerShown: false }} />
          <Stack.Screen name="post/[id]" options={{ title: "Post" }} />
        </Stack>
      </QueryClientProvider>
    </GestureHandlerRootView>
  );
}
```

```tsx
// A data-driven screen: query + FlashList v2 (note: NO estimatedItemSize in v2)
import { FlashList } from "@shopify/flash-list";
import { Image } from "expo-image";
import { useQuery } from "@tanstack/react-query";
import { postsQuery } from "@acme/api";   // shared query options

export default function Feed() {
  const { data, isPending, refetch, isRefetching } = useQuery(postsQuery());
  if (isPending) return <FeedSkeleton />;
  return (
    <FlashList
      data={data}
      keyExtractor={(p) => p.id}
      renderItem={({ item }) => (
        <Row>
          <Image
            source={item.avatar}
            recyclingKey={item.id}          // critical: prevents wrong image flashing on recycle
            cachePolicy="memory-disk"
            style={{ width: 48, height: 48, borderRadius: 24 }}
          />
          <Text>{item.title}</Text>
        </Row>
      )}
      onRefresh={refetch}
      refreshing={isRefetching}
      getItemType={(item) => item.kind}     // multiple recycle pools for mixed item types
    />
  );
}
```

---

## Performance — the four things users feel

1. **Startup (TTI).** Enable **Hermes** (default; v1 in SDK 55). Keep the JS executed before first
   paint tiny — lazy-load routes (Expo Router does route-level splitting), defer analytics/SDK init to
   after interactive, avoid top-level heavy `require`s. Measure cold start with the systrace/RN
   DevTools, not vibes. Use a real splash (`expo-splash-screen`) and hide it only when the first
   screen is ready.
2. **Lists.** **FlashList v2** for anything scrollable and unbounded — it recycles views and needs
   **no** `estimatedItemSize` (removed in v2). Always set a stable `keyExtractor`, use `getItemType`
   for heterogeneous rows, and pass `recyclingKey` to `expo-image`. Never put a `ScrollView` of 500
   mapped items in production.
3. **Images.** `expo-image` with `cachePolicy="memory-disk"`, correct sizes (don't download a 4000px
   image into a 48px avatar), and `placeholder`/blurhash to avoid layout shift.
4. **Animations on the UI thread.** Reanimated v4 worklets + gesture-handler keep 60/120fps even when
   JS is busy. Don't animate via `setState` in a scroll handler — that's the classic jank source.

Also: enable **bytecode** Hermes for releases, watch the JS bundle size (`npx expo export` + a bundle
visualizer), and prefer `InteractionManager`/`startTransition` for non-urgent work.

---

## Offline-first & sync

Treat the network as optional. Architecture:

```
UI ──reads──► local DB (SQLite/Drizzle)  ──sync engine──►  server
   ──writes─► local first (optimistic)         ▲
                                          conflict policy (LWW / CRDT)
```

- **Read path:** UI reads local DB; TanStack Query hydrates from a persisted cache on launch so the
  app is useful at T=0 with no spinner.
- **Write path:** write locally + enqueue a mutation; reconcile on reconnect. Use TanStack Query's
  **mutation persistence** + optimistic updates, or a real sync engine (**PowerSync**,
  **WatermelonDB**, **Legend-State**) when you need true bidirectional sync and conflict resolution.
- **Own the conflict policy explicitly** (last-write-wins vs CRDT vs server-authoritative). "We'll
  figure out conflicts later" = data loss in the field.
- Detect connectivity with `@react-native-community/netinfo`; queue, don't drop.

## Push notifications (APNs + FCM)

```ts
// expo-notifications — request perms, get token, handle taps (deep link from notification)
import * as Notifications from "expo-notifications";
import * as Device from "expo-device";

export async function registerForPush(): Promise<string | null> {
  if (!Device.isDevice) return null;                       // simulators can't get tokens
  const { status } = await Notifications.requestPermissionsAsync();
  if (status !== "granted") return null;
  // Android requires a channel or notifications are silently dropped
  await Notifications.setNotificationChannelAsync("default", {
    name: "Default", importance: Notifications.AndroidImportance.HIGH,
  });
  const token = (await Notifications.getExpoPushTokenAsync({ projectId: "<eas-project-id>" })).data;
  return token;                                            // send to your backend
}

Notifications.addNotificationResponseReceivedListener((res) => {
  const url = res.notification.request.content.data?.url as string | undefined;
  if (url) router.push(url);                               // route the tap
});
```

Gotchas: iOS needs the **APNs key/cert + Push capability** (EAS handles credentials); Android needs
the **FCM v1 service account** wired into your push provider; **Android 13+ requires runtime
notification permission**; and you must create a **channel** or Android drops your notifications
silently.

## Deep links & universal/app links

- Custom scheme (`acme://`) for simple in-app routing; **Universal Links (iOS) / App Links
  (Android)** for `https://` links that open the app seamlessly and survive uninstall.
- iOS: host **`apple-app-site-association`** (no extension, `application/json`, on `https`, at
  `/.well-known/`) + add **Associated Domains** (`applinks:acme.app`).
- Android: host **`assetlinks.json`** at `/.well-known/` with your signing SHA-256, and set
  `autoVerify` intent filters.
- Expo Router maps URLs to routes automatically via `expo-linking` config — but the **server-side
  association files are the part teams forget**, and without them the OS opens the browser, not your app.

## Secure storage & biometrics

```ts
import * as SecureStore from "expo-secure-store";
import * as LocalAuthentication from "expo-local-authentication";

// Tokens go in the Keychain/Keystore — NEVER AsyncStorage/MMKV in plaintext
await SecureStore.setItemAsync("refresh_token", token, {
  keychainAccessible: SecureStore.WHEN_UNLOCKED_THIS_DEVICE_ONLY,  // not synced to iCloud
});

// Gate sensitive actions behind biometrics with a passcode fallback
const ok = await LocalAuthentication.authenticateAsync({
  promptMessage: "Confirm it's you",
  fallbackLabel: "Use passcode",
  disableDeviceFallback: false,
});
```

Rules: secrets → `expo-secure-store` (Keychain / EncryptedSharedPreferences-backed Keystore), never
plaintext KV. Biometrics gate *access*, they are not a transport secret. Use
`WHEN_UNLOCKED_THIS_DEVICE_ONLY` to keep tokens off iCloud Keychain sync.

## iOS / Android platform specifics & store guidelines

- **Permissions:** declare every iOS usage string (`NSCameraUsageDescription`, etc.) via Expo config
  — a missing string is an **automatic App Store rejection** (and a crash). Android: request
  dangerous permissions at runtime, in context, with a rationale.
- **Targets:** Play requires **target API 35 (Android 15)** for new apps & updates in 2026; build
  iOS with the **current required Xcode/SDK** (Apple mandates the latest SDK to upload). Keep these
  current or submissions bounce. (Full store rules → `app-store-deployment`.)
- **Tablets/foldables:** support large screens and rotation; Apple rejects iPad builds that are
  obviously unadapted phone UIs. Use responsive layout + `useWindowDimensions`.
- **Platform feel:** native back gesture on Android, swipe-back on iOS, large titles, safe-area
  insets (`react-native-safe-area-context`), haptics (`expo-haptics`) where the platform expects them.
- **Live activities / widgets** are increasingly expected for top-tier apps — Expo's widget tooling
  (SDK 55 `expo-widgets`/Live Activities) or a native module. (See `native-bridge-integration`.)

## Security

- TLS everywhere; consider certificate pinning for high-value apps (`react-native-ssl-pinning` /
  native). iOS ATS is on by default — don't disable it to talk to an http endpoint.
- Don't ship secrets in the JS bundle (it's trivially extractable). Keys live server-side.
- Obfuscate/limit logging in release; strip `console.*` (babel plugin) so you don't leak PII to
  device logs.
- Validate deep-link inputs before routing (they're attacker-reachable). Jailbreak/root detection for
  regulated apps if your threat model needs it.

## Testing

- **Unit/component:** Jest + **React Native Testing Library** (render, query by a11y role/label, fire
  events). Test the shared `@acme/core` logic with plain Vitest.
- **E2E:** **Maestro** (YAML, black-box, fast to write, auto-retries flakiness) for broad regression +
  smoke; **Detox** (gray-box, syncs to the JS thread, <2% flake) for the 5 high-risk flows — auth,
  payments, offline sync, biometrics, permissions. The 2026 pragmatic stack is **Jest + Maestro now,
  add Detox where you feel the pain.** EAS Workflows can run Maestro on cloud emulators.
- Always test on **real low-end Android hardware** — the emulator and your iPhone Pro lie about perf.

## Observability

- **Crash/error:** `@sentry/react-native` (captures JS + native crashes, ANRs); upload **source maps
  + dSYM/ProGuard mappings** per release or stacks are noise. Firebase Crashlytics is the common
  native-first alternative.
- Tag every event with `release`, `runtimeVersion` (OTA channel), `os`, `deviceClass`.
- **Analytics:** PostHog / Amplitude with a **shared, typed event schema** from `@acme/core` so
  "purchase_completed" is identical across platforms. (Funnels/flags → `analytics-master`.)

## Accessibility & i18n / RTL

- Every touchable needs an **accessible role + label**; min touch target **44×44pt (iOS) / 48×48dp
  (Android)**. Test with **VoiceOver** and **TalkBack**, not just by looking.
- Respect Dynamic Type / font scaling (`allowFontScaling`), reduced motion (gate Reanimated
  animations on `AccessibilityInfo.isReduceMotionEnabled`), and sufficient contrast.
- **RTL / Arabic:** use **`I18nManager`** and logical `start`/`end` (never hardcode `left`/`right`),
  mirror icons that imply direction, and remember `I18nManager.forceRTL` requires an **app reload** to
  take effect. Use `expo-localization` for locale/region and `i18next`/`expo-localization` + ICU
  messages for plurals. Pseudo-localize in CI to catch truncation and hard-coded strings.

---

## Edge cases & gotchas (war stories)

- **Migrated to SDK 55 and a native lib red-screens.** It's still on the old arch / not a TurboModule.
  Check the lib supports New Architecture; on RN 0.85 there is no interop fallback. Replace it.
- **Images flash the wrong content while scrolling FlashList.** You forgot `recyclingKey` on
  `expo-image`. The view recycled but the image didn't reset.
- **Android push works in dev, silent in prod.** No notification channel, or runtime permission not
  requested on Android 13+, or FCM v1 service account not configured.
- **Universal links open Safari, not the app.** AASA/assetlinks file missing, wrong content-type,
  behind a redirect, or signing SHA mismatch. Verify with Apple's CDN + Google's link tester.
- **`AsyncStorage` for tokens.** It's plaintext. Reviewers and pentesters will flag it. Use
  SecureStore.
- **App rejected for a missing usage description string** after a library quietly added a permission.
  Audit the merged `Info.plist`/manifest from `expo prebuild`, not just your config.
- **Reanimated worklet crashes on New Arch** because the Babel plugin isn't last in `babel.config.js`
  or versions mismatch RN. Pin matched versions via `expo install`.

## Anti-patterns
- Disabling the New Architecture "to make an old lib work" — impossible on 0.82+; fix the lib.
- `ScrollView` + `.map()` for long/unbounded lists → use FlashList.
- Tokens/PII in AsyncStorage or plaintext MMKV → SecureStore.
- `setState` in scroll/gesture handlers → use Reanimated shared values on the UI thread.
- Blocking startup on analytics/SDK init before first paint.
- Hardcoded `left`/`right` and unmirrored icons → broken Arabic layout.
- Shipping without dSYM/source maps → unreadable crash reports.
- Testing only on an iPhone Pro + emulator → ship jank to the 80% on mid-range Android.

## Agent checklist
```
- [ ] New Architecture (Expo SDK 55 / RN 0.83+) — all native deps are TurboModule/Fabric-compatible
- [ ] Hermes on; cold-start measured; splash hidden only when first screen is ready
- [ ] FlashList v2 for lists (no estimatedItemSize); expo-image with recyclingKey + cachePolicy
- [ ] Reanimated v4 + gesture-handler for UI-thread animation; reduced-motion respected
- [ ] Server state = TanStack Query (persisted); client state = Zustand/XState in @acme/core
- [ ] Offline: local-first reads/writes + explicit conflict policy (sync engine if needed)
- [ ] Push: perms + Android channel + APNs key + FCM v1; notification taps route via deep link
- [ ] Secure storage = expo-secure-store (Keychain/Keystore); biometrics via local-authentication
- [ ] Universal/App Links: AASA + assetlinks.json hosted and verified
- [ ] iOS usage strings + Android runtime perms declared; target API 35; current Xcode/SDK
- [ ] a11y roles/labels + 44/48 targets; VoiceOver/TalkBack tested; RTL via I18nManager
- [ ] Sentry/Crashlytics with source maps + dSYM; typed analytics events from @acme/core
- [ ] Jest + Maestro (smoke/regression) now; Detox for high-risk flows; tested on low-end Android
```

## References
- Expo SDK 55: https://expo.dev/changelog/sdk-55 · New Architecture: https://docs.expo.dev/guides/new-architecture/
- Expo Router: https://docs.expo.dev/router/introduction/ · FlashList v2: https://shopify.github.io/flash-list/
- expo-image: https://docs.expo.dev/versions/latest/sdk/image/ · expo-notifications: https://docs.expo.dev/versions/latest/sdk/notifications/
- expo-secure-store: https://docs.expo.dev/versions/latest/sdk/securestore/ · Reanimated: https://docs.swmansion.com/react-native-reanimated/
- TanStack Query: https://tanstack.com/query/latest · Maestro: https://maestro.dev/ · Detox: https://wix.github.io/Detox/

## Related
`native-bridge-integration` (TurboModules / Expo Modules / native SDKs), `app-store-deployment`
(EAS, TestFlight, Play), `unified-one-codebase` (add web/desktop), `cross-platform-architecture`
(monorepo + shared core) · `mobile-master` (RN/Flutter/Swift/Kotlin deep-dives) · `analytics-master`
