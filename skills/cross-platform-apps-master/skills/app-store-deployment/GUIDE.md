---
name: app-store-deployment
description: >-
  Ship to every store at staff depth: App Store Connect + TestFlight, Google Play Console
  (tracks + staged rollout), EAS Build/Submit/Update config (eas.json) and EAS Workflows,
  desktop distribution (DMG/MSI/NSIS/AppImage + auto-update feeds), full iOS/macOS signing &
  notarization and Android keystore/Play App Signing, CI/CD with GitHub Actions for all targets,
  versioning & release management, OTA-vs-binary rules, and the common rejection reasons that
  actually bounce builds in 2026. Use to take a built app to users.
---

# App Store Deployment — TestFlight, Play, Desktop, CI/CD

**Mandate:** Releasing is a *repeatable pipeline*, not a heroic afternoon. Every artifact must be
signed by the right identity, versioned correctly, rolled out gradually, and reproducible from CI.
If a human has to remember a manual step, that step will eventually be the outage.

---

## When to use / NOT use

**Use** when you have a buildable app and need it in front of testers or users — first submission,
ongoing releases, or wiring CI/CD. Use it to design `eas.json`, the GitHub Actions pipeline, the
rollout strategy, and the credential model.

**Do NOT use** for the *build/sign mechanics themselves* — macOS notarization internals live in
`desktop-apps-pro`; native module/permission setup lives in `mobile-apps-pro` /
`native-bridge-integration`. This skill is the **distribution and release-management** layer on top.

---

## Mental model: four channels, one version source of truth

```
                         ┌────────── version source of truth ──────────┐
                         │  app version (marketing) + build number       │
                         │  EAS: appVersionSource: "remote" (auto)       │
                         └───────────────────────────────────────────────┘
   iOS  ──► EAS Build ──► .ipa ──► EAS Submit ──► App Store Connect ──► TestFlight ──► phased release
 Android ─► EAS Build ──► .aab ──► EAS Submit ──► Play Console ──► internal→closed→open→prod (staged %)
   Web  ──► expo export ─► static ─► CDN/EAS Hosting (instant, no review)
 Desktop ► electron-builder/tauri ─► DMG/MSI/AppImage ─► signed + notarized ─► update feed
```

Two release *speeds* coexist: **binary releases** (store review, slow, for native changes) and **OTA
updates** (EAS Update for JS/asset-only changes, instant). Knowing which one a change qualifies for is
the core competency — and shipping native changes via OTA is both against the rules and technically
broken.

---

## Decision matrix: OTA (EAS Update) vs new binary

| Change | Ship via | Why |
|--------|----------|-----|
| JS logic, styles, copy, images, RN-level bugfix | **EAS Update (OTA)** | Same runtime version → instant, no review |
| New/updated **native** module, permission, SDK bump, app icon, `expo` SDK upgrade | **New binary** (Build + Submit) | Changes the native runtime → OTA can't and mustn't |
| App config affecting native (`Info.plist`, manifest, entitlements) | **New binary** | Baked into the binary |
| Emergency revert of a JS regression | **EAS Update** (roll back the update) | Faster than a store hotfix |

Rule: **OTA can only change what fits the installed `runtimeVersion`.** Bump native = bump
`runtimeVersion` = new binary. Apple/Google allow OTA for bugfixes/JS, **not** to materially change
the app's behavior or bypass review — stay inside that line.

---

## `eas.json` — build + submit profiles (copy/paste)

```jsonc
// eas.json — the command center for builds, OTA channels, and store submission
{
  "cli": { "version": ">= 16.0.0", "appVersionSource": "remote" },  // EAS owns version/build numbers
  "build": {
    "development": {
      "developmentClient": true,
      "distribution": "internal",
      "channel": "development",
      "ios": { "simulator": true }
    },
    "preview": {
      "distribution": "internal",          // ad-hoc / internal testers, not the store
      "channel": "preview",
      "ios": { "resourceClass": "m-medium" },
      "android": { "buildType": "apk" }    // installable APK for QA
    },
    "production": {
      "channel": "production",
      "autoIncrement": true,               // bump build number each build
      "android": { "buildType": "app-bundle" }   // .aab is required by Play
    }
  },
  "submit": {
    "production": {
      "ios": {
        "ascAppId": "1234567890",          // App Store Connect app ID
        "appleTeamId": "ABCDE12345"
      },
      "android": {
        "serviceAccountKeyPath": "./secrets/play-service-account.json",
        "track": "internal"                // internal | alpha | beta | production
      }
    }
  }
}
```

```bash
# Local / one-off release flow
eas build --platform all --profile production
eas submit --platform ios --profile production --latest
eas submit --platform android --profile production --latest
# OTA a JS-only fix to the production channel
eas update --branch production --message "fix: crash on empty cart"
```

`appVersionSource: "remote"` + `autoIncrement` stops the classic "duplicate build number" rejection
by letting EAS own the counter. iOS submit needs `ascAppId`; Android submit needs the **Play service
account JSON** with the *Release Manager* role and an app already created in Play Console.

---

## EAS Workflows — CI/CD without writing runners

EAS Workflows (`.eas/workflows/*.yml`) orchestrate build → submit → update → Maestro on Expo's cloud,
so you don't manage macOS runners or signing secrets yourself.

```yaml
# .eas/workflows/release.yml
name: Production release
on:
  push:
    branches: [main]
jobs:
  build_ios:
    type: build
    params: { platform: ios, profile: production }
  build_android:
    type: build
    params: { platform: android, profile: production }
  submit_ios:
    type: submit
    needs: [build_ios]
    params: { build_id: ${{ needs.build_ios.outputs.build_id }} }
  submit_android:
    type: submit
    needs: [build_android]
    params: { build_id: ${{ needs.build_android.outputs.build_id }} }
```

```bash
eas workflow:run release.yml      # or trigger on push/PR/cron
```

Job types you'll use: `build`, `submit`, `testflight` (distribute to TF groups with changelogs),
`update` (OTA), `maestro` (E2E on cloud devices), `deploy` (web → EAS Hosting). No matrix builds /
shared workflows yet — define each pipeline explicitly.

---

## GitHub Actions alternative (full control)

```yaml
# .github/workflows/mobile-release.yml — when you want your own runner + secrets
name: Mobile Release
on: { push: { tags: ["v*"] } }
jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
      - uses: actions/setup-node@v4
        with: { node-version: 22, cache: "pnpm" }
      - uses: expo/expo-github-action@v8
        with: { eas-version: latest, token: ${{ secrets.EXPO_TOKEN }} }
      - run: pnpm install --frozen-lockfile
      - run: eas build --platform all --profile production --non-interactive --no-wait
      # submit can run after build completes (separate job watching the build, or --wait)
```

For desktop in CI, run `electron-builder` / `tauri build` on a **macOS runner** (you can only
notarize on macOS) plus a Windows runner for Authenticode; pass `APPLE_ID`,
`APPLE_APP_SPECIFIC_PASSWORD`, `APPLE_TEAM_ID`, the signing cert (base64 secret → imported to a temp
keychain), and Windows signing creds as encrypted secrets. (Signing internals → `desktop-apps-pro`.)

---

## iOS / App Store Connect + TestFlight

- **Credentials:** let EAS manage signing (it creates/stores the distribution cert + provisioning
  profile) unless you have a corporate reason to manage them manually. For App Store Connect API
  access use an **API key (.p8)** — more CI-friendly than Apple ID + 2FA.
- **TestFlight:** internal testers (up to your team, no review) get builds immediately; external
  groups (up to 10,000) need a **Beta App Review** (lighter than full review). Provide a
  "what to test" changelog and demo credentials.
- **Phased release:** App Store Connect can roll a production release out over 7 days automatically —
  use it; you can pause if crash rate spikes.
- **2026 requirement:** you must build with the **current Apple-required Xcode/SDK** (Apple mandates
  the latest SDK to upload to App Store Connect). EAS image selection handles this; pin it
  intentionally.

## Android / Play Console

- **Play App Signing is mandatory:** you upload an **.aab** signed with your *upload key*; Google
  re-signs with the *app signing key* it holds. **Back up your upload key/keystore** — lose it and you
  need a key reset. EAS can manage the keystore for you.
- **Tracks:** `internal` (instant, ~100 testers) → `closed` (alpha/beta) → `open` → `production`.
  Promote builds between tracks; don't rebuild.
- **Staged rollout:** start production at **5–10%**, watch Android vitals (ANR/crash rate), then ramp.
  Halt rollout if vitals regress.
- **2026 requirement:** new apps and updates must **target API level 35 (Android 15)**; Wear/TV/Auto
  may target 34. Below that, submission is blocked.
- **Data safety form + permissions declaration** are required and frequently cause review delays if
  inconsistent with your manifest.

## Desktop distribution

| OS | Format | Signing | Distribution |
|----|--------|---------|--------------|
| macOS | **DMG** (+ zip for updater) | Developer ID + **notarytool** + staple | Direct download / update feed; Mac App Store optional |
| Windows | **NSIS .exe** / MSI | Authenticode (Azure Trusted Signing / EV) | Direct download / winget / MS Store optional |
| Linux | **AppImage** + deb/rpm | optional GPG | Direct download / Flathub / apt repo |

Stores are optional for desktop — most apps self-distribute with an **auto-update feed**
(`latest.yml` for electron-updater, `latest.json` for Tauri). If you self-distribute, the update feed
*is* your release channel; treat a broken feed as a Sev-1. (Mechanics → `desktop-apps-pro`.)

## Versioning & release management

- **SemVer for the marketing version** (`1.4.0`); build number is monotonic and machine-owned
  (`autoIncrement`/remote).
- Keep a `runtimeVersion` policy (`appVersion` or a fingerprint) so EAS Update only serves compatible
  OTA bundles to a given binary.
- Tag releases in git (`v1.4.0`), keep a CHANGELOG, and map each store build ↔ git SHA (Sentry
  `release` should equal that). Reproducibility is the whole point.
- Release cadence: weekly OTA for JS fixes, binary releases as needed for native — but don't let the
  installed-binary fleet fall too many SDKs behind your OTA target.

## Security

- **Secrets live in the CI secret store / EAS secrets, never in the repo or `eas.json`.** The Play
  service-account JSON and Apple API key are submission credentials — leak = someone ships as you.
- Use **least-privilege** service accounts (Play "Release Manager", not Owner; ASC API key scoped to
  what CI needs).
- Sign everything with the correct identity; verify notarization/Play App Signing succeeded before
  announcing. Rotate compromised keys immediately (and remember the Android *app signing* key can't be
  rotated freely — guard it).
- Don't ship debug/dev builds to stores; strip source maps from the shipped bundle but **upload** them
  to Sentry.

## Observability for releases

- Wire **release health** (Sentry/Crashlytics) keyed to the exact `release`/build so a bad rollout is
  visible within minutes — this is what tells you to **pause the staged rollout**.
- Watch **Play Android vitals** and **App Store Connect crash/metrics** dashboards per release.
- For OTA: monitor adoption (how many sessions are on the new update) and keep the **previous update**
  available to roll back instantly.

## Accessibility & i18n for the *store listing*

- **Localize store metadata** (title, description, keywords, screenshots) for each market — Arabic
  listings need RTL-correct screenshots and translated copy, not just translated text on LTR images.
- Provide all required **screenshot sizes** (per device class) or submission is blocked; caption them
  accessibly.
- Privacy nutrition labels (Apple) / Data safety (Google) must match what the app actually does —
  mismatches are a top rejection/again-later cause.

## Common rejection reasons (the ones that actually bite)

- **iOS:** missing/incorrect **purpose strings** (`NS*UsageDescription`); broken **demo account** or
  login wall with no credentials for the reviewer; "**spam/minimal functionality**" (looks like a
  repackaged website — Guideline 4.2); using private APIs; **IAP**: selling digital goods without
  StoreKit (Guideline 3.1.1); crashes on the reviewer's device; placeholder/Lorem content; **3.2** /
  account-deletion requirements not met (apps must let users delete their account in-app).
- **Android:** target API below 35; **Data safety** mismatch; sensitive-permission (location/SMS)
  use without justification; broken obfuscation/missing mapping causing crashes; deceptive
  metadata.
- **Both:** privacy policy URL missing/dead; using a competitor/store name in metadata; pre-filled
  test data; not handling the "sign in with Apple" requirement when you offer 3rd-party social login.

---

## Anti-patterns
- Manual, click-through releases from a laptop ("works on my machine" credentials) — not reproducible.
- Hardcoding the build number → duplicate-build rejection. Use `appVersionSource: remote` + autoIncrement.
- Shipping native changes via OTA (against rules + technically broken across runtime versions).
- Submitting `.apk` to Play (it wants `.aab`) or skipping Play App Signing.
- Losing the Android upload keystore / not backing it up.
- 100% production rollout on day one with no health gate — staged rollout exists for a reason.
- Secrets (Play JSON, Apple .p8) committed to the repo or pasted into `eas.json`.
- Notarizing on a non-macOS runner (impossible) or forgetting to staple → Gatekeeper blocks users.
- Store privacy labels that don't match the app's real data use.

## Agent checklist
```
- [ ] eas.json: appVersionSource remote + autoIncrement; dev/preview/production profiles
- [ ] iOS submit: ascAppId + appleTeamId or ASC API key; Android submit: Play service-account JSON + track
- [ ] OTA-vs-binary decision matrix applied; runtimeVersion policy set
- [ ] CI pipeline (EAS Workflows or GitHub Actions) builds+submits all targets, no manual steps
- [ ] iOS: TestFlight (internal + external w/ changelog + demo creds); phased release on prod
- [ ] Android: .aab + Play App Signing (key backed up); track promotion; staged rollout 5–10%→ramp
- [ ] Targets current: Play API 35; current Apple Xcode/SDK
- [ ] Desktop: DMG/MSI/AppImage signed+notarized; auto-update feed published and smoke-tested
- [ ] Versioning: SemVer marketing version, machine build number, git tags = Sentry release
- [ ] Secrets in CI/EAS secret store (least-privilege); source maps/dSYM uploaded to Sentry
- [ ] Release health dashboards wired to gate/pause rollouts; OTA rollback ready
- [ ] Store metadata localized (incl. RTL screenshots); privacy labels match reality; account deletion in-app
```

## References
- EAS Build / eas.json: https://docs.expo.dev/build/eas-json/ · EAS Submit: https://docs.expo.dev/submit/introduction/
- EAS Update: https://docs.expo.dev/eas-update/introduction/ · EAS Workflows: https://docs.expo.dev/eas/workflows/introduction/
- App Store Connect: https://developer.apple.com/help/app-store-connect/ · App Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
- Play target API: https://developer.android.com/google/play/requirements/target-sdk · Play App Signing: https://support.google.com/googleplay/android-developer/answer/9842756
- electron-builder publish: https://www.electron.build/configuration/publish · Tauri distribute: https://v2.tauri.app/distribute/

## Related
`desktop-apps-pro` (signing/notarization mechanics), `mobile-apps-pro` (build prerequisites),
`unified-one-codebase` (ship all 4 from one source), `cross-platform-architecture` · `devops-master`
(CI/CD, runners, secrets) · `mobile-master`
