---
name: desktop-apps-pro
description: >-
  Ship production desktop apps the right way at staff depth: Electron 42 vs Tauri 2 decision
  (bundle size, memory, security, Rust vs Node), hardened IPC (contextIsolation + preload +
  sandbox, Tauri capabilities/commands), native menus/tray/notifications, auto-update
  (electron-updater / Tauri updater), packaging (electron-builder / tauri build), full code
  signing — Apple Developer ID + notarytool notarization/stapling, Windows Authenticode/EV —
  deep links/protocol handlers, performance and memory. Use for any macOS/Windows/Linux app.
---

# Desktop Apps Pro — Electron vs Tauri, Signing, Auto-Update

**Mandate:** A desktop app is judged on three things users never see until they fail: it must be
*signed and notarized* (or it won't open), it must *auto-update* (or it rots), and its *IPC must be
locked down* (or it's an RCE box on the user's machine). Get those right first; features second.

---

## When to use / NOT use

**Use** when you need a real installed desktop app: a menu bar/tray utility, an offline-capable
productivity tool, a dev tool, or a desktop companion to a mobile/web product. Also use it to wrap a
web build into a distributable, signed binary (see `unified-one-codebase`).

**Do NOT use** when a PWA covers the need — if you don't require the filesystem, native menus, tray,
deep OS integration, background processes, or offline-first beyond service workers, ship a PWA and
skip code signing, notarization, and update servers entirely. Desktop is a *distribution and trust*
problem as much as a code problem; don't take it on for a glorified bookmark.

---

## Mental model: two processes, one trust boundary

Both Electron and Tauri are **two-process** architectures:

```
┌───────────────────────────┐        IPC (the trust boundary)        ┌────────────────────────┐
│  Frontend / WebView        │  ◄───────────────────────────────────►  │  Backend / Main         │
│  (untrusted: renders HTML) │   Electron: ipcRenderer ↔ ipcMain       │  Electron: Node.js      │
│  React/Vue/Svelte          │   Tauri: invoke() ↔ #[tauri::command]   │  Tauri: Rust            │
└───────────────────────────┘                                          └────────────────────────┘
```

The renderer/webview can be hijacked by any XSS or malicious dependency. **Treat it as hostile.**
The backend (Node/Rust) has OS power. The *only* safe path between them is a narrow, explicit,
allowlisted IPC surface. Everything in this skill orbits that boundary.

---

## Decision matrix: Electron vs Tauri (2026)

| Dimension | **Electron 42** | **Tauri 2.11** |
|-----------|-----------------|----------------|
| Backend language | Node.js (JS/TS) | **Rust** |
| Web rendering | Bundled Chromium (consistent everywhere) | **System WebView** (WKWebView/WebView2/WebKitGTK) |
| Installer size | **~85–150 MB** (ships Chromium + Node) | **~3–10 MB** (uses OS webview) |
| Idle memory | Higher (full Chromium) | **Lower** (shared system webview) |
| Rendering consistency | **Identical** across OSes | Varies (Safari vs Edge vs WebKitGTK quirks) |
| Security model | Opt-in: you must harden (contextIsolation/sandbox) | **Secure by default**: explicit capability allowlist |
| Mobile (iOS/Android) | No | **Yes** (Tauri 2 targets mobile too) |
| Ecosystem / maturity | Huge (VS Code, Slack, Discord, Figma) | Younger but production-ready, fast-growing |
| Native code | N-API addons | Native Rust crates (huge ecosystem) |
| Best when… | Need Chromium parity, heavy Node ecosystem, max maturity | Need small/fast/secure, Rust-friendly, or also targeting mobile |

**Opinion (2026):** Default to **Tauri 2** for new apps — 10–20× smaller binaries, lower memory,
secure-by-default IPC, and one toolchain that can also do mobile. Choose **Electron** when you need
guaranteed Chromium rendering parity (complex CSS/Canvas/WebGL that *must* look identical on Linux),
lean on heavy Node-only libraries, or your team has zero Rust appetite. WebKitGTK quirks on Linux
are the real Tauri tax — if Linux fidelity is critical, weigh that honestly.

---

## Electron — hardened setup (copy/paste)

Three files: secure `BrowserWindow`, a minimal `preload`, and `ipcMain` handlers. Never deviate from
these three flags.

```ts
// main.ts — the security flags are NON-NEGOTIABLE
import { app, BrowserWindow, ipcMain, shell } from "electron";
import path from "node:path";

function createWindow() {
  const win = new BrowserWindow({
    width: 1200,
    height: 800,
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,   // default since Electron 12 — keep it
      nodeIntegration: false,   // renderer must NEVER touch Node directly
      sandbox: true,            // renderer runs in an OS sandbox
      webSecurity: true,
    },
  });

  // Block in-app navigation to untrusted origins (anti-RCE)
  win.webContents.on("will-navigate", (e, url) => {
    if (new URL(url).origin !== "http://localhost:5173") e.preventDefault();
  });
  // External links open in the real browser, never a new Electron window
  win.webContents.setWindowOpenHandler(({ url }) => {
    shell.openExternal(url);
    return { action: "deny" };
  });

  win.loadURL(app.isPackaged ? `file://${path.join(__dirname, "../dist/index.html")}` : "http://localhost:5173");
}

app.whenReady().then(createWindow);
app.on("window-all-closed", () => { if (process.platform !== "darwin") app.quit(); });
```

```ts
// preload.ts — expose a TINY, explicit API. No ipcRenderer leak, no Node leak.
import { contextBridge, ipcRenderer } from "electron";

contextBridge.exposeInMainWorld("api", {
  getVersion: (): Promise<string> => ipcRenderer.invoke("app:getVersion"),
  saveFile: (data: string): Promise<{ ok: boolean; path?: string }> =>
    ipcRenderer.invoke("file:save", data),
  // Event subscription — return an unsubscribe; never expose the raw event object
  onUpdateAvailable: (cb: (v: string) => void) => {
    const handler = (_e: unknown, v: string) => cb(v);
    ipcRenderer.on("update:available", handler);
    return () => ipcRenderer.removeListener("update:available", handler);
  },
});
```

```ts
// main.ts (handlers) — VALIDATE every input crossing the boundary
import { z } from "zod";
ipcMain.handle("app:getVersion", () => app.getVersion());

const SavePayload = z.string().max(10_000_000); // never trust renderer-sent data
ipcMain.handle("file:save", async (_e, raw) => {
  const data = SavePayload.parse(raw);          // throws → rejects the renderer promise
  const { canceled, filePath } = await dialog.showSaveDialog({});
  if (canceled || !filePath) return { ok: false };
  await fs.writeFile(filePath, data, "utf8");
  return { ok: true, path: filePath };
});
```

```ts
// global.d.ts — type the bridge so the renderer gets autocomplete + safety
export {};
declare global {
  interface Window {
    api: {
      getVersion(): Promise<string>;
      saveFile(data: string): Promise<{ ok: boolean; path?: string }>;
      onUpdateAvailable(cb: (v: string) => void): () => void;
    };
  }
}
```

> **2026 IPC gotcha (CVE-2026-34780):** Do **not** pass `VideoFrame` (WebCodecs) objects across
> `contextBridge` — it bypasses context isolation. Serialize to `ArrayBuffer`/`ImageBitmap` first.
> Keep Electron on ≥ 42 (or a patched 39.8/40.7) and follow the "latest 3 stable" support window.

---

## Tauri 2 — commands + capabilities (copy/paste)

Tauri inverts the model: the webview can call **nothing** native unless a capability explicitly
permits it. You write Rust `#[tauri::command]`s and grant them via JSON capabilities.

```rust
// src-tauri/src/lib.rs — typed commands with real error handling
use serde::Serialize;

#[derive(Serialize)]
struct SaveResult { ok: bool, path: Option<String> }

#[tauri::command]
async fn save_file(app: tauri::AppHandle, data: String) -> Result<SaveResult, String> {
    if data.len() > 10_000_000 { return Err("payload too large".into()); }
    let path = app
        .dialog()
        .file()
        .blocking_save_file()
        .ok_or("user cancelled")?;            // -> rejects the JS promise with this string
    std::fs::write(path.as_path().unwrap(), data).map_err(|e| e.to_string())?;
    Ok(SaveResult { ok: true, path: Some(path.to_string()) })
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_updater::Builder::new().build())
        .plugin(tauri_plugin_dialog::init())
        .invoke_handler(tauri::generate_handler![save_file])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
```

```ts
// frontend — invoke is the only door to Rust
import { invoke } from "@tauri-apps/api/core";
const res = await invoke<{ ok: boolean; path?: string }>("save_file", { data: json });
```

```jsonc
// src-tauri/capabilities/default.json — least privilege, explicit allowlist
{
  "$schema": "../gen/schemas/desktop-schema.json",
  "identifier": "default",
  "windows": ["main"],
  "permissions": [
    "core:default",
    "dialog:allow-save",
    "updater:default"
    // NOTE: no broad "fs:allow-write" — the save goes through OUR command, which validates
  ]
}
```

Tauri's allowlist is the security win: even a fully XSS'd frontend can only reach the commands +
permissions you granted. There is no "accidentally gave the renderer Node" failure mode.

---

## Native menus, tray, notifications

```ts
// Electron — app menu + tray
import { Menu, Tray, Notification, nativeImage } from "electron";
const tray = new Tray(nativeImage.createFromPath("assets/trayTemplate.png")); // *Template.png → auto dark/light on macOS
tray.setContextMenu(Menu.buildFromTemplate([
  { label: "Open", click: () => win.show() },
  { type: "separator" },
  { label: "Quit", role: "quit" },
]));
new Notification({ title: "Synced", body: "All changes saved" }).show();
```

```jsonc
// Tauri — tray + notifications via plugins (tauri-plugin-tray is built-in; add notification plugin)
// permissions: "notification:default", and configure trayIcon in tauri.conf.json
```

macOS specifics that bite: use a **Template image** (`fooTemplate.png`) for the tray so it adapts to
menu-bar dark/light; set `app.dock.hide()` for a pure menu-bar app; respect the system
`role`-based menu items (`about`, `services`, `hide`, `quit`) or your app feels foreign.

---

## Auto-update

| | Electron | Tauri |
|--|----------|-------|
| Library | `electron-updater` (electron-builder) | `@tauri-apps/plugin-updater` |
| Feed | `latest.yml` + artifacts (S3/GitHub Releases/generic) | `latest.json` (static) or dynamic server |
| Signing of update | Cert + (mac) notarization | Ed25519 signature (`pubkey` in config) |
| Delta updates | Blockmap (partial download) | Full artifact (use bytecode/diff externally) |

```ts
// Electron — electron-updater with explicit user control (don't silently restart mid-work)
import { autoUpdater } from "electron-updater";
autoUpdater.autoDownload = false;
autoUpdater.on("update-available", (info) => win.webContents.send("update:available", info.version));
autoUpdater.on("update-downloaded", () => { /* prompt user, then */ autoUpdater.quitAndInstall(); });
ipcMain.handle("update:download", () => autoUpdater.downloadUpdate());
app.whenReady().then(() => autoUpdater.checkForUpdates());
```

```ts
// Tauri — check / download / relaunch
import { check } from "@tauri-apps/plugin-updater";
import { relaunch } from "@tauri-apps/plugin-process";
const update = await check();                 // null if up to date
if (update) {
  await update.downloadAndInstall((e) => {/* progress events */});
  await relaunch();
}
```

```jsonc
// tauri.conf.json — updater artifacts + endpoints + pubkey (NOT a file path — the key itself)
{
  "bundle": { "createUpdaterArtifacts": true },
  "plugins": {
    "updater": {
      "pubkey": "dW50cnVzdGVkIGNvbW1lbnQ6...",   // from `tauri signer generate`
      "endpoints": ["https://releases.acme.app/{{target}}/{{arch}}/{{current_version}}"]
    }
  }
}
```

The static `latest.json` platform keys are `OS-ARCH` (`darwin-aarch64`, `darwin-x86_64`,
`windows-x86_64`, `linux-x86_64`) and each needs the `.sig` *contents* (not a path). TLS is enforced
in production. Tauri only falls through to the next endpoint on a non-2XX.

---

## Packaging & code signing — the part that actually blocks shipping

### macOS (both frameworks): Developer ID + notarytool + staple

You need a **"Developer ID Application"** certificate (NOT "Apple Distribution" — that's for the
App Store and will fail notarization with error 65). Then: sign with **hardened runtime**, submit to
Apple's **notarytool** (the legacy `altool` was disabled in Nov 2023), and **staple** the ticket so
the app verifies offline.

```jsonc
// electron-builder.json (mac portion)
{
  "appId": "app.acme.desktop",
  "afterSign": "scripts/notarize.cjs",
  "mac": {
    "category": "public.app-category.productivity",
    "hardenedRuntime": true,
    "gatekeeperAssess": false,
    "entitlements": "build/entitlements.mac.plist",
    "entitlementsInherit": "build/entitlements.mac.plist",
    "notarize": false,                 // we notarize in afterSign for full control
    "target": [{ "target": "dmg", "arch": ["arm64", "x64"] }, { "target": "zip" }]
  }
}
```

```xml
<!-- build/entitlements.mac.plist — JIT for V8; do NOT add allow-unsigned-executable-memory on Electron 12+ -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.cs.allow-jit</key><true/>
</dict></plist>
```

```js
// scripts/notarize.cjs — runs after signing, before DMG/ZIP packaging
const { notarize } = require("@electron/notarize");
exports.default = async function (ctx) {
  if (ctx.electronPlatformName !== "darwin") return;
  const appName = ctx.packager.appInfo.productFilename;
  await notarize({
    tool: "notarytool",                                   // altool is dead
    appPath: `${ctx.appOutDir}/${appName}.app`,
    appleId: process.env.APPLE_ID,
    appleIdPassword: process.env.APPLE_APP_SPECIFIC_PASSWORD, // app-specific pw, not your login
    teamId: process.env.APPLE_TEAM_ID,
  });
};
```

Tauri does the same via `tauri.conf.json` `bundle.macOS` signing identity + the `APPLE_*` env vars;
`tauri build` signs, notarizes, and staples when configured. Verify either way:

```bash
xcrun stapler validate "out/Acme.app"     # must say "The validate action worked!"
spctl -a -vv "out/Acme.app"               # "accepted, source=Notarized Developer ID"
```

### Windows: Authenticode (EV/OV) — 2026 reality

As of mid-2023 Microsoft requires code-signing private keys on **FIPS-140 hardware** (HSM or token).
Don't expect a plain `.pfx` on disk anymore — use **Azure Trusted Signing** (cloud, cheapest path to
a trusted cert + good SmartScreen reputation) or a hardware EV token. New OV certs without reputation
still trigger SmartScreen warnings until they age; EV/Trusted Signing reduces that friction.

```jsonc
// electron-builder.json (win) — Azure Trusted Signing example
{
  "win": { "target": [{ "target": "nsis", "arch": ["x64", "arm64"] }],
           "azureSignOptions": { "publisherName": "Acme Inc.",
                                 "endpoint": "https://wus2.codesigning.azure.net",
                                 "certificateProfileName": "acme-profile",
                                 "codeSigningAccountName": "acme-signing" } }
}
```

### Linux: AppImage / deb / rpm, no central authority

Ship **AppImage** (portable, runs anywhere) plus `.deb`/`.rpm`. No notarization; optionally GPG-sign
repos. Provide a `.desktop` file + icons so it integrates with the launcher.

---

## Deep links / protocol handlers

```ts
// Electron — register acme:// and handle single-instance (deep links arrive via second-instance/open-url)
app.setAsDefaultProtocolClient("acme");
const gotLock = app.requestSingleInstanceLock();
if (!gotLock) app.quit();
app.on("second-instance", (_e, argv) => {            // Windows/Linux: URL is in argv
  const url = argv.find((a) => a.startsWith("acme://"));
  if (url) routeDeepLink(url);
  win?.show();
});
app.on("open-url", (_e, url) => routeDeepLink(url));   // macOS delivers it here
```

Tauri uses `tauri-plugin-deep-link` (register the scheme in config; listen with `onOpenUrl`). On
both, **single-instance is mandatory** or a second launch spawns a duplicate window and the deep link
goes to the wrong process. Validate the URL host/path before routing — a protocol handler is an
attacker-reachable entry point.

---

## Performance & memory

- **Startup:** lazy-create windows, defer non-critical IPC and update checks until after first paint.
  Electron: enable V8 snapshot for your app code if cold start matters. Tauri starts faster by virtue
  of the system webview.
- **Memory:** Electron's floor is ~1 Chromium per window — reuse windows, avoid spawning `BrowserView`
  per tab when a single renderer + virtualized UI suffices. Tauri's floor is far lower.
- **Don't ship a dev bundle:** enable `asar` (Electron) packaging, tree-shake the renderer, and
  exclude source maps/dev deps from the final artifact. A 300 MB installer is almost always
  unpacked node_modules.
- **Background work** belongs in the main/Rust process or a worker, never blocking the renderer's
  event loop (it freezes the UI exactly like a web page).
- **Native modules** (Electron N-API) must be rebuilt for Electron's ABI (`electron-rebuild`) and
  per-arch — a frequent CI failure on arm64/x64 universal builds.

## Security (beyond IPC)

- `contextIsolation: true`, `nodeIntegration: false`, `sandbox: true` — all three, always (Electron).
- A strict **CSP** on the renderer; block remote code, disallow `unsafe-eval` unless a framework
  truly needs it. Treat the webview like a public website.
- **Validate every IPC/command input** (zod / serde). The renderer is attacker-controllable via XSS
  or a poisoned npm dep.
- Tauri: keep capabilities **least-privilege**; don't grant `fs:*` or `shell:allow-execute` to dodge
  writing a command. The whole point is the allowlist.
- **Supply chain:** audit deps (`pnpm audit`, `cargo audit`), pin framework versions, stay inside the
  framework's supported/patched range (Electron's "latest 3 stable").

## Testing

- **Unit:** main-process logic and Rust commands as plain functions (Vitest / `cargo test`).
- **E2E:** drive the real app with **Playwright** — `_electron.launch()` for Electron;
  `tauri-driver` + WebDriver for Tauri. Test the *signed, packaged* build in CI on macOS + Windows
  runners, not just `dev` — signing/notarization breaks things `dev` never sees.
- Smoke-test auto-update against a staging feed before every release (a broken updater bricks your
  install base silently).

## Observability

- Crash reporting: **Sentry** (`@sentry/electron` captures main + renderer + native crashes) or
  Electron's `crashReporter` → your minidump endpoint. Tag `release`, `os`, `arch`.
- Upload **symbol/dSYM/PDB** files per release or stack traces are useless.
- Telemetry must be **opt-in/consented** on desktop (users notice and care more than on web). Respect
  it. (Dashboards/flags → `analytics-master`.)

## Accessibility & i18n / RTL

- The renderer is a web page: full ARIA/keyboard support applies — and desktop users are
  **keyboard-first**, so every action needs a shortcut and a focus path. Build the menu accelerators.
- Honor OS settings: dark/light (`nativeTheme`/`prefers-color-scheme`), reduced motion, system font
  scaling.
- **RTL (Arabic):** set `dir="rtl"` on the document and mirror native menus; macOS/Windows mirror the
  window chrome automatically when the app locale is RTL. Use CSS logical properties so the webview
  mirrors cleanly. Localize the installer strings and the app/menu names too.

---

## Anti-patterns
- `nodeIntegration: true` / `contextIsolation: false` "to make it work fast." That's shipping an RCE.
- Exposing `ipcRenderer` (or worse, `require`) directly on `window` instead of a tiny typed bridge.
- Passing `VideoFrame` across `contextBridge` (CVE-2026-34780) — serialize first.
- Shipping unsigned/un-notarized on macOS ("it works on my machine") → Gatekeeper blocks every user.
- Still calling `altool` for notarization — it's been disabled since Nov 2023; use `notarytool`.
- Using an **Apple Distribution** cert for a direct-download app — fails with notarization error 65.
- No single-instance lock → duplicate windows + misrouted deep links.
- Silent `quitAndInstall()` mid-edit → users lose work and uninstall. Prompt.
- Granting Tauri broad `fs:*`/`shell` perms instead of a validated command.

## Agent checklist
```
- [ ] Framework chosen from the matrix (default Tauri 2; Electron for Chromium parity/Node-heavy)
- [ ] Electron: contextIsolation + sandbox true, nodeIntegration false; tiny typed contextBridge
- [ ] Tauri: least-privilege capabilities; all native access via #[tauri::command]
- [ ] Every IPC/command input validated (zod / serde) — renderer treated as hostile
- [ ] Strict CSP; will-navigate + setWindowOpenHandler lock the renderer down
- [ ] macOS: Developer ID Application cert, hardenedRuntime, notarytool, stapled + verified (spctl)
- [ ] Windows: Authenticode via Azure Trusted Signing or EV token (HSM-backed key)
- [ ] Linux: AppImage + deb/rpm + .desktop entry
- [ ] Auto-update wired (electron-updater / Tauri updater) and smoke-tested on a staging feed
- [ ] Single-instance lock + validated deep-link routing
- [ ] Crash reporting with symbols uploaded; telemetry opt-in
- [ ] E2E (Playwright/tauri-driver) runs against the SIGNED packaged build in CI
```

## References
- Electron security: https://www.electronjs.org/docs/latest/tutorial/security · context isolation: https://www.electronjs.org/docs/latest/tutorial/context-isolation
- electron-builder: https://www.electron.build/ · electron-updater: https://www.electron.build/auto-update
- @electron/notarize: https://github.com/electron/notarize · notarytool: https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
- Tauri 2: https://v2.tauri.app/ · capabilities: https://v2.tauri.app/security/capabilities/ · updater: https://v2.tauri.app/plugin/updater/
- Azure Trusted Signing: https://learn.microsoft.com/azure/trusted-signing/

## Related
`unified-one-codebase` (wrap a web build into a signed desktop shell), `app-store-deployment`
(distribution + CI/CD), `native-bridge-integration` (Tauri plugins / Rust native), `cross-platform-architecture`
(monorepo + shared core) · `devops-master` (CI runners, signing secrets) · `mobile-master`
