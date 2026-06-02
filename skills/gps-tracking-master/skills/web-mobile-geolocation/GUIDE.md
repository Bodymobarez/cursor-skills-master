---
name: web-mobile-geolocation
description: >-
  Capture location on the client at staff depth: browser Geolocation API (watchPosition options,
  the Permissions API, secure-context rules), Expo Location foreground + background (TaskManager,
  foreground service, config plugin), native Android FusedLocationProvider (LocationRequest.Builder
  priorities) and iOS CoreLocation (legacy significant-change/visits + iOS 17/18 CLLocationUpdate,
  CLMonitor, CLServiceSession, CLBackgroundActivitySession), battery strategy, and accuracy filtering.
---

# Web & Mobile Geolocation — Client-Side Capture

**Getting a coordinate is easy; getting trustworthy coordinates without murdering the battery or the
user's trust is the job.** Three platforms, three permission models, three background stories. The
mistakes that hurt are always the same: requesting `enableHighAccuracy` you don't need, asking for
"always/background" too early, never filtering garbage fixes, and treating a permission as permanent.

---

## When to use this skill / when NOT

**Use it when** the *phone or browser itself* is the tracker: rider/driver apps, field-service, fitness,
delivery, "share my location", check-ins. You control the OS APIs, permissions, and battery trade-off.

**Do NOT** use it for: dedicated hardware trackers on a wire protocol (`device-integration-protocols`),
how positioning physically works/accuracy tiers (`gps-gnss-fundamentals`), centimeter survey
(`precision-positioning-rtk`), or what happens to points after upload (`fleet-asset-tracking-platform`,
`geospatial-data-postgis`). Here we stop at "a clean fix left the device."

---

## 1. Mental model — capture is a state machine, not a getter

```
        ┌─ permission: prompt ──askInContext──▶ granted(whenInUse) ──upgrade──▶ granted(always/background)
state ──┤                              └─denied─▶ degrade gracefully (manual entry / IP-coarse)
        └─ accuracy profile chosen by USE CASE, not "max"
              foreground watch ──(app backgrounded)──▶ OS background mode (service / sig-change / region)
              every fix ──▶ FILTER (accuracy, speed-plausibility, age) ──▶ buffer ──▶ upload (batched)
```

Two hard rules across all platforms:
1. **Request the minimum permission, just-in-time, with context.** "Always/Background" granted cold = denial.
2. **Pick an accuracy/interval profile per use case.** Highest accuracy is a battery and UX cost, not a default.

---

## 2. Platform decision matrix

| Need | Web (browser) | React Native / Expo | Native Android | Native iOS |
|------|---------------|---------------------|----------------|------------|
| One-shot | `getCurrentPosition` | `getCurrentPositionAsync` | `getCurrentLocation` | `CLLocationUpdate.liveUpdates()` (1st) |
| Continuous (foreground) | `watchPosition` | `watchPositionAsync` | `requestLocationUpdates` | `CLLocationUpdate.liveUpdates()` |
| Background tracking | ❌ (tab must be alive) | `startLocationUpdatesAsync`+TaskManager | foreground service + FusedLocation | `allowsBackgroundLocationUpdates` / `CLBackgroundActivitySession` |
| Wake on enter/exit area | ❌ | geofencing task | `GeofencingClient` | `CLMonitor` (iOS 17+) |
| Low-power "where roughly" | coarse (UA decides) | `Accuracy.Balanced/Low` | `PRIORITY_BALANCED_POWER` | significant-change / `kCLLocationAccuracyKilometer` |

> Browser truth: **there is no real background**. A web tab cannot track when backgrounded/closed. If you
> need background, you need a native/Expo app or a hardware tracker. Don't promise web background tracking.

---

## 3. Browser Geolocation API + Permissions API

Secure-context only (**HTTPS**); also gated by `Permissions-Policy: geolocation`. `PositionOptions`:
`enableHighAccuracy` (default `false`), `timeout` (default `Infinity` — **always set it**, or a denied/slow
fix hangs forever), `maximumAge` (default `0` = no cache). Errors: `PERMISSION_DENIED=1`,
`POSITION_UNAVAILABLE=2`, `TIMEOUT=3`.

```ts
// geo.ts — robust browser capture with permission awareness and a hard timeout.
export type GeoState = "granted" | "prompt" | "denied" | "unsupported";

export async function geoPermission(): Promise<GeoState> {
  if (!("geolocation" in navigator)) return "unsupported";
  if (!("permissions" in navigator)) return "prompt";            // Safari historically lacked it
  try {
    const s = await navigator.permissions.query({ name: "geolocation" as PermissionName });
    return s.state as GeoState;                                   // 'granted' | 'prompt' | 'denied'
  } catch {
    return "prompt";
  }
}

export function getPosition(opts: PositionOptions = {}): Promise<GeolocationPosition> {
  return new Promise((resolve, reject) => {
    navigator.geolocation.getCurrentPosition(resolve, reject, {
      enableHighAccuracy: true,
      timeout: 10_000,        // NEVER omit — default is Infinity
      maximumAge: 0,
      ...opts,
    });
  });
}

/** Continuous watch with accuracy filtering + a clean teardown handle. */
export function watch(
  onFix: (c: GeolocationCoordinates) => void,
  onErr?: (e: GeolocationPositionError) => void,
  { maxAccuracyM = 50 } = {},
): () => void {
  const id = navigator.geolocation.watchPosition(
    (pos) => {
      // Reject low-confidence fixes (a 1500 m "accuracy" Wi-Fi guess will jitter your UI).
      if (pos.coords.accuracy != null && pos.coords.accuracy > maxAccuracyM) return;
      onFix(pos.coords);     // {latitude, longitude, accuracy, altitude, altitudeAccuracy, heading, speed}
    },
    onErr,
    { enableHighAccuracy: true, timeout: 15_000, maximumAge: 1_000 },
  );
  return () => navigator.geolocation.clearWatch(id);  // ALWAYS clear on unmount / route change
}

// React: subscribe to permission changes so UI reacts when user flips it in site settings.
// const s = await navigator.permissions.query({name:'geolocation'}); s.addEventListener('change', ...);
```

Gotchas: iOS Safari only delivers fixes on **HTTPS**; `enableHighAccuracy` on desktop usually changes
nothing (no GPS); a forgotten `watchPosition` keeps the GPS chip hot and drains mobile battery — clearing it
is not optional.

---

## 4. Expo Location — the React Native default (foreground + background)

`expo-location` + `expo-task-manager`. **Foreground:** `watchPositionAsync`. **Background:**
`startLocationUpdatesAsync` driving a task defined with `TaskManager.defineTask` — and the task **must be
defined at module scope** (not inside a component), or the headless background runtime can't find it.

```tsx
// location-task.ts — import this from app/_layout.tsx so it registers before navigation.
import * as TaskManager from "expo-task-manager";
import * as Location from "expo-location";

export const LOCATION_TASK = "background-location";

TaskManager.defineTask(LOCATION_TASK, async ({ data, error }) => {
  if (error) { console.error("[loc] task error", error.message); return; }
  const { locations } = data as { locations: Location.LocationObject[] };
  // Buffer + flush to backend. Runs headless; keep it cheap & idempotent. No React here.
  await enqueueFixes(locations);
});

export async function startTracking() {
  const fg = await Location.requestForegroundPermissionsAsync();
  if (fg.status !== "granted") return "foreground-denied";

  // Background MUST be a second, separate request, after foreground is granted.
  const bg = await Location.requestBackgroundPermissionsAsync();
  if (bg.status !== "granted") return "background-denied";

  if (await Location.hasStartedLocationUpdatesAsync(LOCATION_TASK)) return "already-running";

  await Location.startLocationUpdatesAsync(LOCATION_TASK, {
    accuracy: Location.Accuracy.Balanced,        // Balanced ≈ city block; High/BestForNavigation = GPS + battery
    distanceInterval: 25,                         // metres — event-driven beats time-driven for battery
    deferredUpdatesInterval: 30_000,              // let OS batch when app is backgrounded
    pausesUpdatesAutomatically: true,             // iOS: pause when stationary
    activityType: Location.ActivityType.AutomotiveNavigation,
    showsBackgroundLocationIndicator: true,       // iOS: required honesty for "always"
    foregroundService: {                          // ANDROID: mandatory for background, or it's killed
      notificationTitle: "Tracking active",
      notificationBody: "Your location is used while on a trip.",
      notificationColor: "#0B6BCB",
    },
  });
  return "started";
}

export async function stopTracking() {
  if (await Location.hasStartedLocationUpdatesAsync(LOCATION_TASK)) {
    await Location.stopLocationUpdatesAsync(LOCATION_TASK);
  }
}
```

Config plugin (`app.json`) — the part everyone forgets, which makes Android background silently no-op:

```jsonc
{ "expo": { "plugins": [[ "expo-location", {
  "locationAlwaysAndWhenInUsePermission": "Allow $(PRODUCT_NAME) to use your location while on a trip.",
  "isAndroidBackgroundLocationEnabled": true,
  "isAndroidForegroundServiceEnabled": true        // adds FOREGROUND_SERVICE_LOCATION — without it: crash/no-op
}]]}}
```

> Real bug seen in the wild: task registers (`getRegisteredTasksAsync` confirms) but the callback **never
> fires on Android** → you forgot `isAndroidForegroundServiceEnabled`, or didn't `requestBackgroundPermissions`,
> or started the task while already backgrounded (Android forbids starting a foreground service from the
> background — **start it while the app is foregrounded**). Also: keep `expo-task-manager` current; older
> versions had a no-callback bug fixed in 11.8.2+.

---

## 5. Native Android — FusedLocationProvider (current API)

`LocationRequest.create()` / `PRIORITY_*` constants are **deprecated**. Use `LocationRequest.Builder` +
the `Priority` class. For a single fix prefer `getCurrentLocation` over the last-known cache.

```kotlin
// Kotlin — Google Play services Fused Location (current builder API)
val request = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 5_000L)  // interval ms
    .setMinUpdateIntervalMillis(2_000L)          // fastest you'll accept
    .setMinUpdateDistanceMeters(10f)             // displacement filter — huge battery win
    .setGranularity(Granularity.GRANULARITY_PERMISSION_LEVEL)
    .setWaitForAccurateLocation(true)            // delay first low-accuracy fix briefly for a good one
    .build()

private val callback = object : LocationCallback() {
    override fun onLocationResult(result: LocationResult) {
        val loc = result.lastLocation ?: return
        if (loc.hasAccuracy() && loc.accuracy > 50f) return    // filter low-confidence
        handleFix(loc.latitude, loc.longitude, loc.accuracy, loc.time)
    }
}

@SuppressLint("MissingPermission")   // assumes ACCESS_FINE_LOCATION already granted
fun start(client: FusedLocationProviderClient) =
    client.requestLocationUpdates(request, callback, Looper.getMainLooper())

fun stop(client: FusedLocationProviderClient) = client.removeLocationUpdates(callback)
```

`Priority`: `PRIORITY_HIGH_ACCURACY` (GPS), `PRIORITY_BALANCED_POWER_ACCURACY` (~block, Wi-Fi/cell — default),
`PRIORITY_LOW_POWER` (~city), `PRIORITY_PASSIVE` (free-ride other apps). Android permissions ladder:
`ACCESS_COARSE` → `ACCESS_FINE` → (separate prompt) `ACCESS_BACKGROUND_LOCATION`, plus a foreground service
with type `location`. Android 12+ lets users grant **approximate-only** — handle a coarse grant gracefully.

---

## 6. Native iOS — CoreLocation (legacy + iOS 17/18 modern)

Two worlds coexist; know which to use:

**Modern (iOS 17+)** — Swift-concurrency `CLLocationUpdate.liveUpdates()` (auto pause/resume, implicit
when-in-use session), `CLMonitor` (geofencing/beacons), `CLServiceSession` (iOS 18 declarative auth),
`CLBackgroundActivitySession` (iOS 17 background).

```swift
// iOS 17+ continuous updates via AsyncSequence — no delegate boilerplate.
func track() async throws {
    let updates = CLLocationUpdate.liveUpdates(.automotiveNavigation)
    for try await update in updates {
        if update.authorizationDenied { break }
        guard let loc = update.location, loc.horizontalAccuracy <= 50 else { continue } // filter
        await handleFix(loc.coordinate, loc.horizontalAccuracy, loc.timestamp)
    }
}

// iOS 17+ background: hold a session so updates continue when backgrounded.
let bgSession = CLBackgroundActivitySession()   // requires UIBackgroundModes: location + "Always"
// ... bgSession.invalidate() when done.
```

**Legacy (still the only way for some features):** significant-change & visit monitoring are **not** ported
to the new async APIs — keep a `CLLocationManager` and its delegate for those.

```swift
let mgr = CLLocationManager()
mgr.delegate = self
mgr.desiredAccuracy = kCLLocationAccuracyBest
mgr.allowsBackgroundLocationUpdates = true     // + UIBackgroundModes:location in Info.plist
mgr.pausesLocationUpdatesAutomatically = true
mgr.startMonitoringSignificantLocationChanges() // ultra-low-power; can relaunch a killed app
// delegate: func locationManager(_:didUpdateLocations:) / didVisit: / didChangeAuthorization:
```

iOS auth: `whenInUse` first; request `always` only with a clear reason — the system shows a delayed
"keep allowing?" prompt and surfaces the blue background bar. **Significant-change / region monitoring can
relaunch your terminated app in the background** — reinit the manager/monitor in `didFinishLaunching`.

---

## 7. Background battery strategy (the part that decides app-store reviews)

| Lever | Cheap | Expensive |
|-------|-------|-----------|
| Accuracy | Balanced/coarse, significant-change | `Best`/`PRIORITY_HIGH_ACCURACY` continuous |
| Trigger | **distance/displacement** + OS deferral/batching | fixed 1 Hz timer |
| Active window | only while "on a trip"/foreground task | 24/7 always-on |
| Geofences | wake on region enter/exit (OS-driven, ~free) | poll position to test fences |

Rules of thumb: prefer **`distanceInterval` over time interval**; let the OS **batch/defer** background
updates (`deferredUpdatesInterval` / `pausesUpdatesAutomatically`); use **significant-change or region
monitoring** for "where roughly" instead of a hot GPS; and **stop tracking the instant the use case ends**
(trip complete) — a forgotten watcher is the #1 battery complaint.

---

## 8. Accuracy filtering & smoothing (don't ship raw fixes)

- **Reject by `accuracy`** (`horizontalAccuracy`): drop fixes worse than your threshold (e.g., 50 m for
  navigation). A 1500 m Wi-Fi fix is not a position, it's a region.
- **Reject implausible speed:** distance/Δt between consecutive fixes implying 900 km/h is multipath/teleport.
- **Reject stale:** check `timestamp` — OS may hand you a cached fix first (esp. significant-change/`lastLocation`).
- **Snap when stationary:** below a small speed threshold, hold the last position to stop the parked-car
  "wander" (multipath jitter). Heavy smoothing (Kalman, map-matching) belongs server-side
  (`fleet-asset-tracking-platform` / `ride-hailing-maps-master`), not on-device.

---

## 9. Security & privacy

- Location is **PII**; continuous location is high-risk under GDPR/CCPA. Get **explicit, purpose-scoped
  consent**, show *why* in the OS permission string, and provide an obvious off switch. Both stores reject
  apps that request background location without a justified, demonstrated use.
- Don't exfiltrate more than the feature needs: precision (coarse vs fine), frequency, and retention should
  match purpose. Send over TLS; never log raw tracks to analytics tools.
- Client coordinates are **attacker-controlled** (rooted device, mock-location apps, devtools geolocation
  override). Anything security-relevant (geofenced unlock, attendance) must be **verified server-side** with
  plausibility checks — never trust the client's claimed location.

---

## 10. Scale & reliability

- **Batch uploads.** Buffer fixes on-device and flush every N seconds / M points (and on background-flush
  triggers). One request per fix at 1 Hz × 100k users = a self-inflicted DDoS.
- Tag each fix with a **client-generated id / monotonic seq** so the server dedupes after retries
  (offline → reconnect replays the buffer). Persist the buffer (SQLite/MMKV) so a crash doesn't lose a trip.
- Expect clock skew: send the **device fix timestamp**, and reconcile against server receive time.

---

## 11. Testing — simulators, not field trips

- **iOS Simulator:** Features ▸ Location ▸ custom GPX route (City Run/Freeway Drive, or your own GPX).
- **Android Emulator:** extended controls ▸ Location ▸ import GPX/KML and play a route.
- **Browser:** Chrome DevTools ▸ Sensors ▸ override geolocation / custom location / "location unavailable".
- Automate permission states (granted/denied/prompt, coarse-only, background-denied) and verify each
  degrades gracefully. Replay GPX through the *whole* pipeline, not just the parser.

---

## 12. Observability

- Funnel metrics: permission **prompt→granted→background-granted** conversion per platform (background grant
  is where you bleed users).
- Per-session: fixes received, % rejected by filter, mean `accuracy`, battery delta, background-kill events
  (Android foreground-service termination, iOS session invalidation).
- Alert on "tracking started but zero fixes in N s" — the silent Android foreground-service misconfig.

---

## 13. Accessibility & i18n

- Permission rationale strings are **user-facing UI**: localize them, keep them honest and specific.
- Show a confidence radius, not a fake-precise pin; localize units (km/h vs mph), number formats, RTL.
- Provide a non-GPS fallback (manual address / map pin-drop) for denied permission or no-fix — never dead-end.

---

## 14. Opinionated anti-patterns

- ❌ `getCurrentPosition` with **no `timeout`** (default `Infinity` → spinner forever on a denied/slow device).
- ❌ Requesting **Always/Background up front**. Ask when-in-use, justify, then upgrade in context.
- ❌ `enableHighAccuracy: true` / `PRIORITY_HIGH_ACCURACY` everywhere "to be safe" — battery killer.
- ❌ Never calling `clearWatch` / `removeLocationUpdates` / `stopLocationUpdatesAsync` (GPS stays hot).
- ❌ Defining the Expo `TaskManager` task inside a component instead of module scope.
- ❌ Forgetting `isAndroidForegroundServiceEnabled` → Android background silently does nothing.
- ❌ Shipping raw fixes with no accuracy/speed/staleness filter (jumpy dot, parked-car wander).
- ❌ Promising **web background tracking** (impossible) or **trusting client location** for security.
- ❌ One network request per fix instead of batching.

## 15. Agent checklist

```
- [ ] Permission requested just-in-time, when-in-use first, background as a separate justified step
- [ ] Every browser call has an explicit timeout; watchers are cleared on teardown
- [ ] Accuracy profile chosen by use case (Balanced default; High only when needed)
- [ ] Distance/displacement + OS deferral used instead of a fixed hot timer
- [ ] Expo task at module scope; Android foreground service + config plugin flags set
- [ ] iOS: chose modern CLLocationUpdate/CLMonitor vs legacy sig-change/visits deliberately
- [ ] Fixes filtered (accuracy / speed-plausibility / staleness) before upload
- [ ] Uploads batched + buffered offline with dedupe ids
- [ ] Location treated as PII (consent, retention, TLS); client location not trusted for security
- [ ] Tested via simulator GPX + all permission states; graceful degradation on deny/no-fix
```

## References (2026-current)
- W3C Geolocation API (REC 2025): https://www.w3.org/TR/geolocation/ · MDN: https://developer.mozilla.org/docs/Web/API/Geolocation_API
- Expo Location: https://docs.expo.dev/versions/latest/sdk/location/ · TaskManager: https://docs.expo.dev/versions/latest/sdk/task-manager/
- Android FusedLocation: https://developer.android.com/develop/sensors-and-location/location/request-updates
- Apple CoreLocation: https://developer.apple.com/documentation/corelocation · WWDC23 "Meet Core Location Monitor"

## Related
`gps-gnss-fundamentals` (accuracy/fix quality), `device-integration-protocols` (hardware path),
`geofencing-events`, `fleet-asset-tracking-platform`, `ride-hailing-maps-master` (live-location-tracking, maps)
