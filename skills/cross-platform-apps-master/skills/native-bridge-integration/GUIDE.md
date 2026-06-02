---
name: native-bridge-integration
description: >-
  Bridge to native at staff depth on the New Architecture: Expo Modules API (Swift/Kotlin),
  RN TurboModules + Fabric via Codegen, Nitro Modules for hot paths, and Tauri commands/plugins
  (Rust) — to reach camera, BLE, biometrics, Secure Enclave/StrongBox, background tasks, and
  payments/IAP. Covers the permissions model, when to write native vs use a library, JSI/bridge
  performance, threading, and security of the boundary. Use when no library exists or you must
  touch a platform SDK directly.
---

# Native Bridge Integration — Expo Modules · TurboModules · Tauri

**Mandate:** Reach native capability through the *thinnest, type-safe, correctly-threaded* seam
possible — and write native code only when no maintained library exists. Every line of native code is
a line you must build, sign, and maintain on two (or three) platforms forever. Use a library first;
bridge deliberately.

---

## When to use / NOT use

**Use** when you need a device capability with no good maintained library, must call a vendor's native
SDK (payments, maps, ML, hardware), need performance the JS layer can't give (per-frame processing),
or must run platform background tasks.

**Do NOT use** when a well-maintained, New-Arch-compatible library already exists — `expo-camera`,
`expo-local-authentication`, `expo-secure-store`, `expo-notifications`, `react-native-ble-plx`,
`react-native-iap`, etc. Reinventing these is how teams acquire a permanent maintenance tax and
subtle platform bugs. The senior move is usually *not* writing native code.

---

## Mental model: it's all the same JSI boundary now

Post-bridge (RN 0.85 removed the Bridge; SDK 55 is New-Arch-only), every RN native call is **JSI** —
direct, synchronous-capable C++ refs, no JSON serialization. Three ways to author it, plus Tauri for
desktop:

```
          JavaScript / TypeScript
                   │  (JSI — direct C++ refs, Codegen-typed)
   ┌───────────────┼─────────────────────────────┬───────────────── desktop ─────────┐
   ▼               ▼                              ▼                                     ▼
Expo Modules   TurboModules + Fabric        Nitro Modules                       Tauri commands
(Swift/Kotlin, (Codegen specs, lower-level  (mrousavy; codegen C++,             (#[tauri::command],
 ergonomic)     RN primitive)                fastest, hot paths)                 Rust, allowlisted)
```

| Author with | Best for | Trade-off |
|-------------|----------|-----------|
| **Expo Modules API** | 95% of RN native work — clean Swift/Kotlin DSL, lifecycle, views, events | Expo toolchain (which you want anyway) |
| **TurboModules + Fabric** | Library authors, fine-grained control, custom native views | More boilerplate (Codegen specs, C++) |
| **Nitro Modules** | Performance-critical paths (audio/video/per-frame), huge call volumes | Newer; only where you need the speed |
| **Tauri commands/plugins** | Desktop native (filesystem, OS APIs, hardware via Rust) | Rust; desktop only (web build path) |

**Default to the Expo Modules API** for RN. Drop to TurboModules/Nitro only when you're authoring a
shared library or chasing a measured hot path. Use Tauri for the *desktop* side of a unified app.

---

## Expo Modules API — a real module (Swift + Kotlin + TS)

This is the 2026 default. The DSL handles threading, type marshaling, events, and New-Arch support
for you.

```swift
// ios/MyDeviceModule.swift
import ExpoModulesCore

public class MyDeviceModule: Module {
  public func definition() -> ModuleDefinition {
    Name("MyDevice")

    // Sync function (runs on the JS thread via JSI — keep it fast)
    Function("getModel") { () -> String in
      UIDevice.current.model
    }

    // Async function (Expo runs it off the JS thread; return a value or throw)
    AsyncFunction("getBatteryLevel") { () -> Double in
      UIDevice.current.isBatteryMonitoringEnabled = true
      let level = UIDevice.current.batteryLevel
      if level < 0 { throw Exception(name: "Unavailable", description: "battery level unknown") }
      return Double(level)
    }

    // Emit events to JS
    Events("onBatteryChange")
    OnStartObserving {
      NotificationCenter.default.addObserver(forName: UIDevice.batteryLevelDidChangeNotification,
        object: nil, queue: .main) { [weak self] _ in
        self?.sendEvent("onBatteryChange", ["level": UIDevice.current.batteryLevel])
      }
    }
  }
}
```

```kotlin
// android/MyDeviceModule.kt
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition

class MyDeviceModule : Module() {
  override fun definition() = ModuleDefinition {
    Name("MyDevice")

    Function("getModel") { android.os.Build.MODEL }

    AsyncFunction("getBatteryLevel") {
      val bm = appContext.reactContext!!.getSystemService(Context.BATTERY_SERVICE) as BatteryManager
      val pct = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
      if (pct < 0) throw CodedException("Unavailable", "battery level unknown", null)
      pct / 100.0
    }
  }
}
```

```ts
// index.ts — typed JS surface
import { requireNativeModule } from "expo-modules-core";

interface MyDeviceModule {
  getModel(): string;
  getBatteryLevel(): Promise<number>;
  addListener(e: "onBatteryChange", cb: (p: { level: number }) => void): { remove(): void };
}
export default requireNativeModule<MyDeviceModule>("MyDevice");
```

Wire it as a **local module** (`npx create-expo-module --local`) inside the app, or a standalone
package for reuse. Config plugins let you add the native entries (permissions, capabilities) so
`expo prebuild` stays the source of truth — never hand-edit `ios/`/`android/`.

---

## TurboModule (Codegen spec) — the lower-level path

When authoring a library or you need precise control, define a Codegen **spec**; Codegen generates
type-safe native bindings at build time.

```ts
// src/NativeMyModule.ts — the Codegen contract (TurboModuleRegistry)
import type { TurboModule } from "react-native";
import { TurboModuleRegistry } from "react-native";

export interface Spec extends TurboModule {
  multiply(a: number, b: number): number;          // sync via JSI
  readTag(): Promise<string>;                       // async
}
export default TurboModuleRegistry.getEnforcing<Spec>("MyModule");
```

You then implement the generated protocol/abstract class in Obj-C++/Swift and Kotlin/C++ and register
it. Fabric (custom native *views*) follows the same Codegen-spec pattern with a `codegenNativeComponent`.
This is more boilerplate than Expo Modules — use it when you're publishing a general library or need
something the Expo DSL doesn't expose.

> **Nitro Modules** (mrousavy) push further: codegen'd C++ bindings with the lowest call overhead,
> ideal for very hot paths (e.g. `react-native-mmkv` v3, vision/audio). Reach for it only when a
> profiler says the boundary is your bottleneck — not by default.

---

## Tauri commands & plugins — the desktop native path

On a unified app, desktop runs the **web** build, so "native" there means **Rust via Tauri**, exposed
as allowlisted commands (see `desktop-apps-pro` for the security model).

```rust
// src-tauri/src/lib.rs — a command + a reusable plugin command
#[tauri::command]
async fn read_serial(port: String) -> Result<String, String> {
    // talk to hardware via a Rust crate; map errors to strings the JS promise rejects with
    serialport::new(&port, 115_200)
        .open()
        .map_err(|e| e.to_string())
        .and_then(|mut p| { /* read */ Ok("data".into()) })
}
```

```ts
import { invoke } from "@tauri-apps/api/core";
const data = await invoke<string>("read_serial", { port: "/dev/tty.usbmodem1" });
```

Tauri's plugin ecosystem (`fs`, `dialog`, `notification`, `deep-link`, `updater`, `biometric`,
`barcode-scanner`, `nfc`) covers most needs across desktop **and** Tauri mobile — prefer a plugin to a
bespoke command, and gate every capability in `capabilities/*.json`.

---

## Bridging the common capabilities (use the library, know the native)

| Capability | Use this first (library) | When you must go native |
|------------|--------------------------|--------------------------|
| Camera | `expo-camera` / `react-native-vision-camera` | custom frame processors (Nitro/VisionCamera plugins) |
| BLE | `react-native-ble-plx` | exotic GATT flows, background BLE |
| Biometrics | `expo-local-authentication` | custom LAContext / BiometricPrompt UX |
| Secure storage | `expo-secure-store` | Secure Enclave / StrongBox key ops |
| Push | `expo-notifications` | provider-specific payloads |
| Background tasks | `expo-task-manager` / `expo-background-task` | custom BGTaskScheduler / WorkManager jobs |
| Payments/IAP | `react-native-iap` / `expo-in-app-purchases`* | StoreKit 2 / Play Billing edge cases |

\*Confirm the current maintained IAP library for your SDK before adopting — the IAP space churns.

### Secure Enclave / StrongBox (the one place to go native)

Hardware-backed keys never leave the chip. iOS: generate a `SecKey` with
`kSecAttrTokenIDSecureEnclave` + access control requiring biometrics. Android: `KeyStore` with
`setIsStrongBoxBacked(true)` + `setUserAuthenticationRequired(true)`. Expose only *sign/verify*
to JS — **never** the key material. This is worth a small native module because the security property
(key non-exportability) is the whole point and no JS library can provide it.

### Background tasks (the gotcha-heavy one)

iOS background execution is **budgeted and opportunistic** (`BGTaskScheduler`/`BGProcessingTask`) —
you don't get arbitrary background CPU; the OS decides. Android uses **WorkManager** with Doze/standby
constraints. Don't promise "runs every 15 min exactly" — neither platform guarantees it. Use
`expo-task-manager`/`expo-background-task` and design for *eventually*, with server-side fallbacks for
anything critical.

---

## Permissions model

- **Declare + request + handle-denial.** Declare in config (Expo config plugin → `Info.plist` usage
  strings / Android manifest), request **at the moment of use** with context, and handle the denied/
  "ask every time"/limited states gracefully.
- **iOS:** a missing `NS*UsageDescription` is an instant crash *and* an App Store rejection. iOS 14+
  has limited-photo access and approximate location — handle the partial grants.
- **Android:** runtime permissions for dangerous groups; Android 13+ needs `POST_NOTIFICATIONS`;
  scoped storage limits raw filesystem access; background location is a separate, heavily-scrutinized
  grant.
- Re-check permission state on every entry (users revoke in Settings); never assume a past grant holds.

## Performance of the bridge

- **JSI is fast, but crossings aren't free at volume.** Don't call a native function 10,000×/frame;
  batch (pass an array, return an array) or move the loop native.
- **Sync vs async:** synchronous JSI functions run on the JS thread — only for *cheap* work
  (a property read). Anything I/O or CPU-heavy must be `AsyncFunction`/off-thread or you block JS and
  jank the UI.
- **Per-frame work** (camera/audio) belongs in a native frame processor / Nitro, not in a JS callback
  per frame.
- **Threading:** Expo Modules marshals threads for you; with raw TurboModules you own dispatch — never
  touch UIKit/Views off the main thread (instant crash), never block the main thread with I/O.
- **Measure** with Hermes sampling profiler + native instruments before optimizing; "the bridge is
  slow" is usually an unbatched loop or main-thread I/O, not JSI.

## Security of the boundary

- **Validate everything crossing the seam.** Native code receiving JS input (and JS receiving native
  output) must validate — a native module is reachable by any compromised JS.
- **Expose the minimum.** Don't surface `eval`-like, raw-filesystem, or raw-key APIs to JS. For
  Secure Enclave, expose sign/verify, never the key.
- **Tauri:** least-privilege capabilities; a command is an attacker-reachable entry point (XSS in the
  web build can call it) — validate args, scope filesystem/shell access narrowly.
- **Supply chain:** native modules pull native deps (CocoaPods/Gradle/crates) — audit them; they run
  with full app privileges. Pin versions.
- **Don't log secrets** that pass through the bridge (tokens, key handles) to device logs.

## Testing

- **Native unit tests:** XCTest (Swift) / JUnit (Kotlin) / `cargo test` (Rust) for the native logic.
- **JS contract tests:** mock the native module (`jest.mock`) so app logic is testable without a
  device; assert the TS types match the spec.
- **E2E on real devices:** Detox (gray-box) for flows that exercise the native module (camera,
  biometrics, BLE) — these *cannot* be validated on JS mocks alone. Test permission **denied** paths
  explicitly.
- Test on **both** old and new OS versions and a low-end Android device — native behavior diverges
  most there.

## Observability

- Native crashes need symbolication: upload **dSYM** (iOS) and **ProGuard/R8 mapping** (Android) per
  release; `@sentry/react-native` captures native + JS crashes and ANRs. Tauri/desktop: capture Rust
  panics and report them.
- Add breadcrumbs around native calls (start/success/error with codes) so a field failure in a BLE or
  payment flow is debuggable from the dashboard.

## Accessibility & i18n / RTL

- **Custom native views (Fabric) must set accessibility** — `accessibilityLabel`/traits (iOS),
  `contentDescription` + `importantForAccessibility` (Android). A custom view with no a11y is invisible
  to VoiceOver/TalkBack.
- Native-presented UI (system biometric prompt, native pickers) is localized by the OS, but **your**
  prompt strings (`promptMessage`, error copy) must be localized and **RTL-aware** for Arabic. Pass
  localized strings from JS; don't hardcode English in Swift/Kotlin.

---

## Edge cases & gotchas (war stories)

- **"It builds, then crashes on launch after SDK 55."** A native dep isn't a TurboModule / not
  New-Arch-compatible. On 0.85 there's no interop fallback — upgrade or replace the lib.
- **UIKit off the main thread → crash.** Any view/UI work in a native module must dispatch to main.
  Expo's `AsyncFunction` runs off-thread; hop back to main for UI.
- **Codegen didn't regenerate.** Changed the spec but forgot a clean rebuild/`pod install`/prebuild →
  stale bindings, cryptic "method not found." Clean build, not cached.
- **iOS background task "never runs."** It's opportunistic + budgeted; testing in the foreground or
  expecting exact intervals misleads you. Use the debugger's "simulate background fetch" and design for
  eventual execution.
- **pnpm hoisting hides the native module** from autolinking. Use `node-linker=hoisted` for Expo
  monorepos (see `cross-platform-architecture`).
- **Passing huge buffers across the seam every frame** tanks perf. Batch or process natively; don't
  ferry megabytes per call.
- **Tauri command works in dev, blocked in prod.** Capability/permission not granted in
  `capabilities/*.json` — dev is permissive, prod is the allowlist.

## Anti-patterns
- Writing a native module when a maintained library exists (permanent maintenance tax).
- Heavy/I/O work in a **synchronous** JSI function → blocks the JS thread, janks UI.
- Touching views off the main thread; blocking the main thread with I/O.
- Exposing raw filesystem/key material/`eval`-like power to JS "for convenience."
- Skipping Codegen clean rebuilds → stale bindings.
- Per-frame JS callbacks for camera/audio instead of a native frame processor/Nitro.
- Hardcoding English prompt strings in Swift/Kotlin (breaks i18n/RTL).
- Granting broad Tauri capabilities to avoid writing a scoped command.
- Shipping native code with no dSYM/mapping upload → unsymbolicated crash reports.

## Agent checklist
```
- [ ] Confirmed no maintained New-Arch library exists before writing native code
- [ ] RN: Expo Modules API by default; TurboModule/Codegen for libraries; Nitro only for measured hot paths
- [ ] Desktop: Tauri command/plugin with a least-privilege capability entry
- [ ] Typed JS surface (requireNativeModule / Codegen spec / invoke<T>) — no `any` at the boundary
- [ ] Sync functions are cheap-only; I/O & CPU use AsyncFunction/off-thread; UI work hops to main
- [ ] Permissions declared via config plugin (iOS usage strings, Android manifest), requested in-context, denial handled
- [ ] Secure Enclave/StrongBox: only sign/verify exposed, key material never crosses to JS
- [ ] Background work uses BGTaskScheduler/WorkManager via expo-task-manager; designed for "eventually"
- [ ] Inputs validated on both sides; minimal API surface; native deps audited + pinned
- [ ] Native unit tests + mocked JS contract tests + Detox on real devices incl. permission-denied
- [ ] dSYM / ProGuard mapping uploaded; breadcrumbs around native calls
- [ ] Custom Fabric views set a11y; native prompt strings localized + RTL-aware
```

## References
- Expo Modules API: https://docs.expo.dev/modules/overview/ · module config: https://docs.expo.dev/modules/module-api/
- RN TurboModules: https://reactnative.dev/docs/turbo-native-modules-introduction · Fabric: https://reactnative.dev/docs/fabric-native-components-introduction
- Codegen: https://reactnative.dev/docs/the-new-architecture/what-is-codegen · Nitro Modules: https://nitro.margelo.com/
- Tauri commands: https://v2.tauri.app/develop/calling-rust/ · plugins: https://v2.tauri.app/plugin/
- iOS background tasks: https://developer.apple.com/documentation/backgroundtasks · Android WorkManager: https://developer.android.com/topic/libraries/architecture/workmanager

## Related
`mobile-apps-pro` (consuming native capabilities), `desktop-apps-pro` (Tauri/Electron IPC security),
`cross-platform-architecture` (monorepo, platform splits), `app-store-deployment` (permission
declarations & review) · `mobile-master` (Swift/Kotlin deep-dives)
