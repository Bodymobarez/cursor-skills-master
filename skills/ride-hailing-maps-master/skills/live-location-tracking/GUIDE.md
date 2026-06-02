---
name: live-location-tracking
description: >-
  Staff-level live GPS pipeline for ride-hailing: throttled/batched on-device ingestion,
  EMA/Kalman smoothing, snap-to-road, driver presence (Redis GEO + TTL), privacy-scoped
  fan-out to the assigned rider only, WebSocket vs MQTT scaling math, battery & accuracy
  modes, and offline buffering. Real TypeScript + Redis. Feeds matching-dispatch and the
  rider's live map.
---

# Live Location Tracking — Throttle on the Device, Smooth on the Server, Fan Out by Trip

**Raw GPS is a firehose of noisy, battery-burning, privacy-sensitive data — tame it at the source, clean it in the middle, and show it to exactly one person.** The three principal mistakes: streaming 1–10 Hz fixes (battery + ingest meltdown), rendering raw jittery coordinates (drunk-looking marker), and broadcasting a driver's position to anyone but their matched rider (privacy breach). Throttle on-device, smooth + snap server-side, fan out scoped to the active trip.

---

## 1. Mandate

- **Throttle on the device.** Stream every 3–5 s (or movement-gated), adapt by trip phase. Never stream raw high-frequency fixes.
- **Smooth then snap.** EMA/Kalman to kill jitter, snap-to-road so the marker rides the street, not the sidewalk.
- **Presence in Redis with TTL.** A driver is "online" only while a key lives; no heartbeat → auto-offline. GPS in the OLTP DB is forbidden.
- **Fan out by trip, not by broadcast.** Only the *assigned* rider sees the driver, only during the active trip, with exact location masked after dropoff.

## 2. When to use / when NOT

**Use when:** building the location service — GPS ingest, smoothing, snap, presence, and the live "where's my driver" channel. It supplies the H3/GEO index that `realtime-matching-dispatch` queries and the live marker that `maps-rendering-design` animates.

**Skip / go elsewhere when:** the *matching* logic itself → `realtime-matching-dispatch`. Map *rendering*/marker interpolation visuals → `maps-rendering-design`. Routing/ETA math → `routing-navigation-eta`.

## 3. Mental model — the pipeline

```
 driver device                  ingest edge                  hot store            consumers
 ┌───────────┐  batch 3–5s   ┌───────────────┐   smooth+snap ┌──────────┐  fan-out ┌──────────┐
 │ GPS + EMA │ ─MQTT/WS────▶ │ validate, EMA │ ─────────────▶│ Redis GEO│ ───WS───▶│ assigned │
 │ on-device │  (offline buf)│ Kalman, snap  │   presence TTL│ + presence│  by trip │  rider   │
 └───────────┘               └───────────────┘               └──────────┘          └──────────┘
                                     │ archive (sampled)            │
                                     ▼                              ▼
                                cold storage (trail)        matching candidate set
```

## 4. On-device throttling & adaptive accuracy

```ts
// React Native (expo-location / react-native-geolocation). Adapt cadence to trip phase.
type Phase = "idle_online" | "enroute_pickup" | "on_trip";
const PROFILE: Record<Phase, { distanceFilterM: number; intervalMs: number; accuracy: "balanced" | "high" }> = {
  idle_online:   { distanceFilterM: 50, intervalMs: 8000, accuracy: "balanced" }, // save battery while waiting
  enroute_pickup:{ distanceFilterM: 15, intervalMs: 4000, accuracy: "high" },     // rider is watching
  on_trip:       { distanceFilterM: 20, intervalMs: 4000, accuracy: "high" },
};

// Batch fixes and flush periodically — one frame per few seconds, not per fix.
const buffer: Fix[] = [];
function onFix(f: Fix) {
  if (f.accuracy > 50) return;                 // drop garbage fixes (>50m) before they cost anything
  buffer.push(f);
}
setInterval(async () => {
  if (!buffer.length) return;
  const batch = buffer.splice(0);
  try {
    await transport.publish(`drivers/${cityId}/${driverId}/loc`, batch); // MQTT QoS1 or WS
  } catch {
    persistOffline(batch);                     // offline buffering — replay on reconnect (§9)
  }
}, PROFILE[phase].intervalMs);
```

**Battery is a feature.** A driver app that drains the phone gets uninstalled. Lower cadence + larger distance filter while idle; only go aggressive when a rider is actually watching (en-route/on-trip).

## 5. Server-side smoothing (EMA → Kalman)

```ts
// Start with EMA (exponential moving average) — cheap, kills most jitter. alpha ~0.3–0.5.
class EmaSmoother {
  private lat?: number; private lng?: number;
  constructor(private alpha = 0.4) {}
  push(lat: number, lng: number) {
    this.lat = this.lat == null ? lat : this.alpha * lat + (1 - this.alpha) * this.lat;
    this.lng = this.lng == null ? lng : this.alpha * lng + (1 - this.alpha) * this.lng;
    return { lat: this.lat, lng: this.lng };
  }
}

// Graduate to a Kalman/constant-velocity filter when EMA lags on turns. Weights by fix accuracy:
// a 5m fix moves the estimate a lot; a 40m fix barely nudges it. (Use a vetted lib in prod.)
function kalmanStep(state: KState, fix: Fix, dtS: number): KState {
  const predicted = predictConstantVelocity(state, dtS);
  const r = fix.accuracy ** 2;                 // measurement variance from reported accuracy
  const k = predicted.p / (predicted.p + r);   // Kalman gain
  return {
    lat: predicted.lat + k * (fix.lat - predicted.lat),
    lng: predicted.lng + k * (fix.lng - predicted.lng),
    vLat: predicted.vLat, vLng: predicted.vLng,
    p: (1 - k) * predicted.p,
  };
}
```

EMA first (it's enough 90% of the time); add a Kalman/constant-velocity model when you see lag through turns or want dead-reckoning during gaps.

## 6. Snap-to-road

```ts
// Snap a cleaned point/short path to the road graph so the marker rides the street.
// Mapbox Map Matching (v5) — snaps a GPS trace to roads.
async function snapMapbox(trace: LatLng[]): Promise<LatLng[]> {
  const coords = trace.map((p) => `${p.lng},${p.lat}`).join(";");
  const radiuses = trace.map(() => 25).join(";");                // tighter = stricter snap
  const url = `https://api.mapbox.com/matching/v5/mapbox/driving/${coords}`
    + `?geometries=geojson&radiuses=${radiuses}&access_token=${MAPBOX_TOKEN}`;
  const res = await fetch(url);
  if (!res.ok) return trace;                                     // degrade gracefully — show smoothed point
  const json = await res.json();
  return json.matchings?.[0]?.geometry?.coordinates?.map(([lng, lat]: number[]) => ({ lat, lng })) ?? trace;
}
// Self-host alternative: OSRM /match or Valhalla /trace_route (cost control at volume — routing-navigation-eta).
// For a SINGLE live point, "nearest road" snap is cheaper than full map-matching a path.
```

Snap the *marker* for display and the *trail* for clean playback; you don't need to snap every single fix — snap on render cadence.

## 7. Presence & the GEO index (Redis)

```ts
// Driver online presence = a TTL key. Location = Redis GEO. Coordinates: lng BEFORE lat.
async function updatePresence(driverId: string, cityId: string, lat: number, lng: number) {
  const pipe = redis.multi();
  pipe.geoadd(`geo:drivers:${cityId}`, lng, lat, driverId);      // GEOADD key lng lat member
  pipe.set(`presence:${driverId}`, "1", "EX", 30);              // no update in 30s → considered offline
  pipe.hset(`driver:last`, driverId, JSON.stringify({ lat, lng, t: Date.now() }));
  await pipe.exec();
}

// Nearby available drivers (matching can use this OR H3 sets — GEOSEARCH is the simplest start).
async function nearby(cityId: string, lat: number, lng: number, km = 5): Promise<string[]> {
  // GEOSEARCH key FROMLONLAT lng lat BYRADIUS r unit [COUNT n] [WITHDIST] [ASC]
  return redis.geosearch(`geo:drivers:${cityId}`, "FROMLONLAT", lng, lat,
                         "BYRADIUS", km, "km", "ASC", "COUNT", 20);
}

// Reaper: GEO members don't expire individually — sweep stale ones whose presence key is gone.
async function reapStale(cityId: string) {
  const members = await redis.zrange(`geo:drivers:${cityId}`, 0, -1);
  for (const id of members) if (!(await redis.exists(`presence:${id}`)))
    await redis.zrem(`geo:drivers:${cityId}`, id);              // GEO is a sorted set under the hood
}
```

**Gotcha that bites everyone:** `GEOADD` takes `longitude latitude` (x, y) — lng first. And GEO set members do **not** expire on their own; pair every member with a TTL presence key and reap (MQTT last-will makes this instant — disconnect fires a "go offline" message).

## 8. Privacy-scoped fan-out

```ts
// Only the ASSIGNED rider on the ACTIVE trip receives the driver's live location.
async function fanOut(driverId: string, point: LatLng) {
  const tripId = await redis.get(`trip:driver:${driverId}`);    // set on accept (matching skill)
  if (!tripId) return;                                          // idle driver → location is NOT broadcast
  const trip = await tripCache.get(tripId);
  if (!trip || !["accepted","arriving","arrived","in_progress"].includes(trip.status)) return;
  ws.toUser(trip.riderId, { type: "DRIVER_LOC", tripId, point, etaS: trip.pickupEtaS });
  // After 'completed'/'dropoff': stop sending; mask exact end location in history (privacy).
}
```

This is non-negotiable: an idle driver's exact position is **never** exposed to riders (riders may see anonymized "cars nearby" decorations, which should be jittered/sampled, not real driver IDs). After dropoff, stop the stream and blur the dropoff point in stored history.

## 9. Edge cases & gotchas

- **Tunnels / urban canyons / parking garages** → GPS drops or scatters. Hold last good position, dead-reckon with heading+speed (Kalman), show "GPS weak"; don't snap a wild fix to a random road.
- **GPS drift while stationary** → marker dances at a red light. EMA + a "stationary if speed < 1 m/s" clamp freezes it.
- **Reconnect storms** → city-wide cell drop → thousands reconnect at once. Jittered backoff on the client, sticky sessions / connection-id resume, and replay the offline buffer (idempotent by fix timestamp+seq).
- **Offline buffering** → driver loses signal for 2 min: buffer fixes locally (capped ring buffer), flush on reconnect with monotonic sequence numbers; server dedupes and reconstructs the trail.
- **Clock skew** → never trust device time for ordering/billing; carry device seq for ordering within a device, server-stamp on ingest.
- **Out-of-order batches** → use per-device sequence; drop fixes older than the latest applied.
- **Accuracy lies** → some phones report optimistic accuracy. Sanity-check against speed (teleport > physically possible → reject).

## 10. WebSocket vs MQTT scaling math

| Dimension | WebSocket | MQTT (EMQX/HiveMQ) |
|-----------|-----------|--------------------|
| Direction | bi-directional | pub/sub topics |
| Auto-offline | you build heartbeat | **last-will** = instant |
| Per-msg overhead | larger (HTTP upgrade, JSON) | tiny binary frames |
| Fan-out | you manage rooms | broker topic tree |
| Sweet spot | app↔backend state, <100k conns | **GPS firehose, 100k+ devices** |

**Back-of-envelope:** 50k online drivers × one batched frame / 4 s ≈ **12.5k msg/s ingest** (trivial). Fan-out is bounded by *active trips* (only assigned riders get frames), not by online drivers — that's the whole point of scoped fan-out. The cost explodes only if you broadcast all drivers to all clients (don't). At fleet scale, MQTT's tiny frames + last-will + topic fan-out win for ingest; keep WS/SSE for rider trip updates.

## 11. Performance & scale

- **Geo-shard by city** — one Redis GEO set / presence namespace per metro; hot cities scale independently and a city's load can't starve another.
- **Batch writes** — pipeline `GEOADD`+presence+last in one `MULTI`; don't round-trip per field.
- **Keep hot location in Redis, archive sampled** (every Nth fix, or simplified polyline) to columnar/cold storage for trip playback & analytics — never the OLTP DB.
- **Render cadence ≠ ingest cadence** — server may receive every 4 s but the client interpolates smoothly between frames (`maps-rendering-design`); don't push more than ~1 frame/2–4 s to the rider.
- **Backpressure** — if ingest lags, keep the *latest* fix per driver and drop intermediates; never block the device.

## 12. Security & privacy

- **Location is sensitive PII.** Minimize retention; share driver↔rider location only during the active trip; mask exact pickup/dropoff in stored history; honor data-deletion requests.
- **Don't leak idle-driver positions** to clients; "cars nearby" eye-candy must be jittered/decoyed, never real IDs/positions.
- **Authn on the stream** — short-lived tokens on WS/MQTT connect, scoped to the driver/rider and (for riders) the specific active trip topic; rotate; revoke on logout.
- **GPS spoofing** → device attestation (Play Integrity / DeviceCheck), speed/teleport plausibility, sensor cross-checks (`realtime-matching-dispatch §11`).
- **Encrypt in transit** (TLS/WSS/MQTTS) always; the trail at rest is encrypted and access-audited.

## 13. Testing — simulated drivers & replay

- **Synthetic GPS:** decode a real route polyline (`routing-navigation-eta`), step a virtual driver along it at realistic speed, inject noise + dropouts (tunnel) + accuracy variance; verify smoothing/snap output rides the road.
- **Replay traces:** capture real (consented/anonymized) traces, replay through the pipeline on every change, assert no marker teleports and trail length within tolerance.
- **Reconnect/offline tests:** kill the socket mid-trip, ensure buffered fixes flush and dedupe, presence flips offline within TTL, and recovers.
- **Load test:** simulate a city of drivers to validate ingest throughput, fan-out scoping (assert idle drivers never reach any rider), and Redis memory.

## 14. Observability

- **Ingest rate**, fixes dropped (garbage/old/teleport), batch size distribution.
- **Presence accuracy:** false-offline rate (good driver marked offline), stale-member reap lag.
- **Smoothing quality:** marker jitter metric, snap success rate, dead-reckoning duration during gaps.
- **Fan-out:** rider-facing location latency (fix → rider screen), frames/s per trip.
- **Battery/cadence:** reported device cadence vs profile, accuracy-mode distribution.

## 15. Accessibility & i18n / RTL (MENA)

- **Pickup is a pin + landmark, not an address** — the rider's map shows the driver approaching a landmark; surface bilingual landmark text and the Makani/National-Address hint to the driver (`geocoding-places-addressing`).
- **RTL live screens:** "driver arriving" / ETA strings and the bottom sheet render RTL; Arabic numerals option for ETA.
- **Cash trips** don't change tracking but do change completion; keep tracking until cash settlement step in the app.
- **Connectivity reality:** patchy coverage in some MENA areas → offline buffering + graceful "GPS weak" UX matter more than in dense-coverage Western markets.

## 16. Anti-patterns

- **Streaming raw 1–10 Hz GPS** → battery drain, ingest meltdown, cost. Throttle + batch on-device.
- **Rendering raw fixes** → jittery "drunk" marker. Smooth (EMA/Kalman) + snap + interpolate.
- **GPS in the primary OLTP DB** → write amplification. Redis hot, cold storage for trails.
- **Broadcasting all driver locations** to clients → privacy breach + fan-out explosion. Scope by active trip.
- **GEO members without presence TTL/reaper** → ghost drivers forever. Pair with TTL + last-will + reap.
- **Trusting reported accuracy / device time** → spoofable, skewed. Speed-plausibility + server stamps.
- **Same high cadence in all phases** → wasted battery while idle. Adaptive profiles.

## 17. Agent checklist

```
- [ ] On-device throttle (3–5s / movement-gated), adaptive accuracy by trip phase, batch + offline buffer
- [ ] Drop garbage fixes (>50m, teleports) before ingest
- [ ] Server smoothing: EMA (default) → Kalman/CV for turns & dead-reckoning
- [ ] Snap-to-road for marker + trail (Mapbox Map Matching / OSRM /match / Valhalla /trace_route), degrade gracefully
- [ ] Presence = Redis TTL key (+ MQTT last-will); location = Redis GEO (lng,lat!); reaper for stale members
- [ ] Fan-out scoped to ASSIGNED rider on ACTIVE trip only; mask exact location post-dropoff
- [ ] WS for app state; MQTT for GPS firehose at 100k+ devices; geo-shard by city
- [ ] Reconnect: jittered backoff, session resume, idempotent buffered replay (seq numbers)
- [ ] Render cadence decoupled from ingest; backpressure keeps latest, drops intermediates
- [ ] Stream authn (short-lived scoped tokens), TLS everywhere, spoof/attestation checks
- [ ] Simulator + replay-trace tests; assert idle drivers never reach riders
- [ ] Metrics: ingest rate, false-offline, fix→rider latency, snap success, battery cadence
- [ ] MENA: landmark pickup hints, RTL live screens, offline-tolerant UX
```

## 18. References (verify current — 2026)

- Redis GEO (GEOADD lng/lat order, GEOSEARCH): https://redis.io/docs/latest/commands/geosearch/ · https://redis.io/docs/latest/commands/geoadd/
- Mapbox Map Matching API: https://docs.mapbox.com/api/navigation/map-matching/
- OSRM match service: https://project-osrm.org/docs/v5.24.0/api/#match-service · Valhalla trace_route: https://valhalla.github.io/valhalla/api/map-matching/api-reference/
- MQTT last-will / EMQX: https://www.emqx.io/docs/en/latest/ · Kalman filter primer: https://www.kalmanfilter.net
- Expo Location (RN): https://docs.expo.dev/versions/latest/sdk/location/

## 19. Related

`realtime-matching-dispatch` (consumes presence/GEO index), `ride-hailing-architecture` (location service boundary, trip FSM), `maps-rendering-design` (marker interpolation on the rider map), `routing-navigation-eta` (route polyline for simulation/snap) · cross-master: `cross-platform-apps-master` (driver/rider GPS, background location), `backend-api-master` (Redis/GIS, GPS ingest), `communications-master` (WS/MQTT realtime infra)
