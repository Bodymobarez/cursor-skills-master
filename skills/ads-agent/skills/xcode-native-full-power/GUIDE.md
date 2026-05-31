---
name: xcode-native-full-power
description: >-
  Use Xcode and Apple native development at full power inside Cursor Composer.
  Use for Swift, SwiftUI, UIKit, Xcode projects, SPM, signing, simulators,
  Instruments, TestFlight, widgets, App Intents, and Apple platform APIs. Covers
  the complete native iOS/macOS workflow while coding in Cursor with Xcode build/
  test loops. Pairs with mobile-master (blastum-xcode-build, ios-speech).
---

# Xcode & Native Apple — Full Power in Composer

Build **real native** iOS/macOS/visionOS apps — Swift + Xcode — with Composer writing code and
**Xcode CLI** verifying builds. Pair with `mobile-master` skills (`blastum-xcode-build`, `vercel-react-native-skills` only for RN).

## When native vs cross-platform

| Choose **Xcode native** | Choose **React Native / Expo** |
|-------------------------|--------------------------------|
| Best Apple UX, widgets, Live Activities | Shared mobile+web team in TS |
| Heavy Apple APIs (HealthKit, ARKit) | Faster Android+iOS one codebase |
| App Store polish, SwiftUI animations | OTA updates via Expo |

## Stack (Apple 2026)

```
Language:    Swift 6 (strict concurrency)
UI:          SwiftUI first; UIKit where needed (representable)
Package:     Swift Package Manager (SPM) + optional CocoaPods legacy
IDE:         Xcode 16+ (build/sign/archive)
Min targets: iOS 17+ typical (adjust per product)
Async:       async/await, actors, @MainActor for UI
```

## Project layout

```
MyApp/
  MyApp.xcodeproj | .xcworkspace
  MyApp/                 # app target — App, Views, ViewModels
  MyAppKit/              # SPM module (shared logic)
  Packages/              # local SPM packages
  MyAppTests/ · MyAppUITests/
```

- Prefer **SPM** for dependencies; pin versions in `Package.resolved`.
- **MVVM** or **TCA** for larger apps; keep Views dumb.

## Composer + Xcode loop (critical)

Cursor writes Swift files → **build in Xcode CLI** (don't trust syntax-only):

```bash
# list schemes
xcodebuild -list -project MyApp.xcodeproj
# simulator build
xcodebuild -scheme MyApp -destination 'platform=iOS Simulator,name=iPhone 16' build
# tests
xcodebuild -scheme MyApp -destination 'platform=iOS Simulator,name=iPhone 16' test
```

Use `blastum-xcode-build` (mobile-master) for deeper CLI, XCUITest, signing.

## SwiftUI power patterns

```swift
@Observable class CartModel { ... }  // iOS 17+ observation
struct CheckoutView: View {
  @Environment(CartModel.self) private var cart
  var body: some View { ... }
}
```
- Previews with `#Preview` + sample data; use for Composer visual iteration.
- `NavigationStack` + typed `navigationDestination`; avoid deprecated NavigationView.

## Capabilities checklist (use what you need)

```
- [ ] Push notifications (APNs) + Background modes
- [ ] Sign in with Apple / Keychain
- [ ] Core Data or SwiftData for persistence
- [ ] WidgetKit / Live Activities
- [ ] App Intents / Shortcuts
- [ ] StoreKit 2 (subscriptions)
- [ ] HealthKit / Camera / CoreLocation (privacy strings in Info.plist)
- [ ] TestFlight → App Store Connect pipeline
```

## Signing & release

- Automatic signing (dev team) for simulator; **Distribution cert** + provisioning for TestFlight.
- Archive: `xcodebuild archive` or Xcode Organizer; upload via `xcrun altool` / Transporter.
- **Privacy Manifest** (`PrivacyInfo.xcprivacy`) required for third-party SDKs.

## Debugging elite

- **Instruments**: Leaks, Time Profiler, SwiftUI body updates.
- **LLDB** in Xcode for native crashes; symbolic breakpoints on `objc_exception_throw`.
- Simulator: location, photos, slow network simulation.

## Composer prompts (native)

```
use xcode-native-full-power + mobile-master/blastum-xcode-build.
Implement [feature] in SwiftUI. @MyApp/Views. Run xcodebuild test. Fix until green.
Match Apple HIG. use ultra-hd-visual-rendering for assets.
```

## Pair with design skills

`figma-grade-design-system` (tokens) → SwiftUI `Color`/`Font` extensions; `award-winning-ui-effects` →
SwiftUI animations (matchedGeometryEffect, spring).

## Anti-patterns
- Editing `.pbxproj` by hand without care — let Xcode add files or use consistent paths.
- UI updates off main thread (use `@MainActor`).
- Ignoring Swift 6 concurrency warnings (data races).
- React Native patterns in SwiftUI (no useEffect — use .task/onChange).
- Never running xcodebuild after Composer edits.
