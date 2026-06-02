---
name: routing-navigation-eta
description: >-
  Staff-level routing, turn-by-turn navigation & traffic-aware ETA for ride-hailing:
  Google Routes API (computeRoutes/computeRouteMatrix with X-Goog-FieldMask), Mapbox
  Directions/Matrix (polyline6, annotations), self-hosted OSRM/Valhalla decision matrix,
  ETA accuracy & recompute, multi-stop optimization, snap-to-roads, and cost control.
  Real TypeScript with field masks, error handling, and fallbacks.
---

# Routing, Navigation & ETA — Traffic-Aware or Wrong

**A ride-hailing ETA is a promise with money attached, computed against live traffic on a road graph — straight-line distance is malpractice.** Routing shows up in three places with different cost profiles: a **matrix** call to rank dispatch candidates (M drivers × pickup), a **single route** for the rider's map + fare estimate, and **turn-by-turn** for the driver's navigation. Each has a right API and a wrong (expensive) one. The principal move: minimize paid calls (H3-cap candidates, cache briefly, self-host at volume) while keeping ETAs honest with traffic.

---

## 1. Mandate

- **Traffic-aware always for live ETA.** `TRAFFIC_AWARE`/`driving-traffic`; reserve traffic-unaware only for cheap pre-filtering.
- **Right API per job:** Matrix for dispatch ranking, single Route for the rider line + estimate, turn-by-turn for the driver.
- **Field masks are mandatory (Google).** Request only the fields you use — it's required *and* it controls latency/cost.
- **Recompute ETA on meaningful movement, not on a timer alone.** A static ETA is a broken promise; an over-recomputed one is a cost leak.
- **Self-host (OSRM/Valhalla) when API spend bites** — but keep a managed fallback for traffic quality.

## 2. When to use / when NOT

**Use when:** computing ETAs (pickup & trip), drawing the route line, powering driver navigation, ranking dispatch candidates by road-network time, or controlling routing spend. Feeds `realtime-matching-dispatch` (the ETA matrix), `maps-rendering-design` (the polyline), and `surge-dynamic-pricing` (distance/duration for fares).

**Skip / go elsewhere when:** the *matching* algorithm → `realtime-matching-dispatch`. Drawing/animating the line → `maps-rendering-design`. Address → coordinates → `geocoding-places-addressing`. Map-matching raw GPS trails → `live-location-tracking` (uses the same engines).

## 3. DECISION MATRIX — routing engine

| Engine | Traffic | Matrix | Turn-by-turn | Cost model | Self-host | Verdict |
|--------|---------|--------|--------------|------------|-----------|---------|
| **Google Routes API** ⭐ | best (real-time + predictive `trafficModel`) | `computeRouteMatrix` | yes (steps) | per element/route, tiered | no | ⭐ Best ETA quality; default for accuracy |
| **Mapbox Directions/Matrix** | good (`driving-traffic`) | Matrix API (≤25×25) | yes (banner/voice) | per request, tiered | no (managed) | ⭐ Great value + same-vendor as map |
| **OSRM** | none (free-flow) | `table` (fast, huge) | basic | free (your infra) | ⭐ yes | ⭐ Cheap matrices at volume (add traffic separately) |
| **Valhalla** | limited (can add traffic tiles) | `sources_to_targets` | yes (OSRM-format) | free (your infra) | ⭐ yes | Self-host with richer costing + nav |
| **ML ETA (e.g., DeepETA-style)** | learned from history | — | — | your model | yes | Mature scale: physics route + ML correction |

**Verdict:** start with **Google Routes** (best traffic ETA) or **Mapbox** (value + map synergy). As matrix volume explodes in dispatch, move the *candidate-ranking matrix* to **self-hosted OSRM/Valhalla** (free, microsecond tables) and keep a managed traffic-aware call only for the *final* chosen route/ETA. Layer an ML correction on top at scale.

## 4. Google Routes API — single route (computeRoutes)

```ts
// POST https://routes.googleapis.com/directions/v2:computeRoutes
// Field mask is REQUIRED — request only what you render/charge on.
async function googleRoute(o: LatLng, d: LatLng) {
  const res = await fetch("https://routes.googleapis.com/directions/v2:computeRoutes", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Goog-Api-Key": process.env.GOOGLE_MAPS_SERVER_KEY!,        // SERVER key, never client
      "X-Goog-FieldMask": "routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline",
    },
    body: JSON.stringify({
      origin:      { location: { latLng: { latitude: o.lat, longitude: o.lng } } },
      destination: { location: { latLng: { latitude: d.lat, longitude: d.lng } } },
      travelMode: "DRIVE",
      routingPreference: "TRAFFIC_AWARE",          // or TRAFFIC_AWARE_OPTIMAL (slower, best)
      polylineEncoding: "ENCODED_POLYLINE",         // decode with polyline precision 5 for Routes
      languageCode: "ar",                           // localized instructions for MENA
      units: "METRIC",
    }),
  });
  if (!res.ok) throw new RoutingError(`Routes ${res.status}: ${await res.text()}`);
  const json = await res.json();
  const r = json.routes?.[0];
  if (!r) throw new RoutingError("No route");
  return {
    durationS: parseFloat(r.duration),              // "412s" → 412 (note the trailing 's')
    distanceM: r.distanceMeters,
    encoded: r.polyline.encodedPolyline,            // Google encoded polyline (precision 5)
  };
}
```

## 5. Google Routes — the dispatch matrix (computeRouteMatrix)

```ts
// POST https://routes.googleapis.com/distanceMatrix/v2:computeRouteMatrix
// M candidate drivers × 1 pickup, traffic-aware, ONE call. Cap M via H3 first (matching skill).
async function googleMatrix(drivers: LatLng[], pickup: LatLng) {
  const res = await fetch("https://routes.googleapis.com/distanceMatrix/v2:computeRouteMatrix", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Goog-Api-Key": process.env.GOOGLE_MAPS_SERVER_KEY!,
      "X-Goog-FieldMask": "originIndex,destinationIndex,duration,distanceMeters,condition",
    },
    body: JSON.stringify({
      origins: drivers.map((c) => ({
        waypoint: { location: { latLng: { latitude: c.lat, longitude: c.lng } } },
        routeModifiers: { avoidTolls: false },
      })),
      destinations: [{ waypoint: { location: { latLng: { latitude: pickup.lat, longitude: pickup.lng } } } }],
      travelMode: "DRIVE",
      routingPreference: "TRAFFIC_AWARE",
    }),
  });
  if (!res.ok) throw new RoutingError(`Matrix ${res.status}: ${await res.text()}`);
  // Elements stream back UNORDERED — key by originIndex. Each: {originIndex, destinationIndex, duration, ...}
  const elements: any[] = await res.json();
  const etaByDriver = new Map<number, number>();
  for (const el of elements) if (el.condition === "ROUTE_EXISTS")
    etaByDriver.set(el.originIndex, parseFloat(el.duration));
  return etaByDriver;     // driverIndex → seconds-to-pickup
}
```

**Gotcha:** matrix elements come back **out of order** — always key by `originIndex`/`destinationIndex`, never positionally. Check `condition === "ROUTE_EXISTS"` (some pairs have no route).

## 6. Mapbox Directions & Matrix

```ts
// Directions: turn-by-turn + polyline6, traffic-aware. coords are lng,lat ; lng,lat (semicolons).
async function mapboxDirections(o: LatLng, d: LatLng) {
  const coords = `${o.lng},${o.lat};${d.lng},${d.lat}`;
  const url = `https://api.mapbox.com/directions/v5/mapbox/driving-traffic/${coords}`
    + `?geometries=polyline6&overview=full&steps=true&annotations=duration,distance,congestion`
    + `&banner_instructions=true&voice_instructions=true&language=ar`
    + `&access_token=${process.env.MAPBOX_SERVER_TOKEN}`;
  const res = await fetch(url);
  if (!res.ok) throw new RoutingError(`Mapbox dir ${res.status}`);
  const json = await res.json();
  const route = json.routes?.[0];
  return {
    durationS: route.duration, distanceM: route.distance,
    encoded: route.geometry,                       // polyline6 string → decode with precision 6
    steps: route.legs[0].steps,                    // turn-by-turn (maneuver, banner, voice)
  };
}
// Matrix: up to 25×25, returns durations[][]/distances[][] (NO geometry). Use 'driving-traffic' profile.
// https://api.mapbox.com/directions-matrix/v1/mapbox/driving-traffic/{coords}?annotations=duration&access_token=...
```

Mapbox requires `overview=full` to attach `annotations`, and `steps=true` to get `banner_instructions`/`voice_instructions` for the driver's nav UI. `geometries=polyline6` (precision 6) is the high-accuracy default — decode with the matching precision (don't decode a polyline6 as precision 5 → coordinates land in the ocean).

## 7. Self-host — OSRM table & Valhalla

```ts
// OSRM /table — free, microsecond matrices at scale (no traffic; pairs with an ML/traffic correction).
async function osrmTable(sources: LatLng[], dests: LatLng[]) {
  const all = [...sources, ...dests].map((p) => `${p.lng},${p.lat}`).join(";");
  const srcIdx = sources.map((_, i) => i).join(";");
  const dstIdx = dests.map((_, i) => sources.length + i).join(";");
  const url = `${OSRM_HOST}/table/v1/driving/${all}?sources=${srcIdx}&destinations=${dstIdx}&annotations=duration,distance`;
  const json = await (await fetch(url)).json();   // { durations:[[...]], distances:[[...]] }
  return json;
}

// Valhalla sources_to_targets (matrix) + /route (turn-by-turn in OSRM format with banner/voice).
async function valhallaMatrix(sources: LatLng[], targets: LatLng[]) {
  const body = {
    sources: sources.map((p) => ({ lat: p.lat, lon: p.lng })),
    targets: targets.map((p) => ({ lat: p.lat, lon: p.lng })),
    costing: "auto",
  };
  const url = `${VALHALLA_HOST}/sources_to_targets?json=${encodeURIComponent(JSON.stringify(body))}`;
  return (await fetch(url)).json();                // sources_to_targets[][] with time + distance
}
// Valhalla /route with {"format":"osrm","banner_instructions":true,"voice_instructions":true,
//   "shape_format":"polyline6","language":"ar-SA"} → nav-SDK-compatible steps.
```

## 8. Polyline decode (the bug everyone hits)

```ts
import polyline from "@mapbox/polyline";
// Google Routes ENCODED_POLYLINE → precision 5. Mapbox polyline6 / Valhalla shape → precision 6.
const googleCoords = polyline.decode(encoded, 5);   // [[lat,lng], ...]
const mapboxCoords = polyline.decode(encoded, 6);   // MUST pass 6 or everything is 10x off
// Convert to [lng,lat] for GeoJSON / GL sources (maps-rendering-design §8).
const geojson = mapboxCoords.map(([lat, lng]) => [lng, lat]);
```

## 9. ETA accuracy & recompute strategy

```ts
// Recompute on MEANINGFUL change, not blindly every second. Hysteresis prevents flicker + cost.
class EtaTracker {
  private lastEtaS = Infinity; private lastAt = 0; private lastPoint?: LatLng;
  shouldRecompute(now: LatLng, t: number): boolean {
    const movedM = this.lastPoint ? haversineM(this.lastPoint, now) : Infinity;
    const aged = t - this.lastAt > 15_000;            // at most ~every 15s
    const movedEnough = movedM > 120;                 // or after ~120m of progress
    const offRoute = this.lastPoint && movedM > 400;  // big jump → likely re-route
    return aged || movedEnough || !!offRoute;
  }
  // Track error for observability: |predicted - actual| at arrival.
  recordArrival(actualS: number) { metrics.histogram("eta.error.s", Math.abs(this.lastEtaS - actualS)); }
}
```

ETA error is your routing quality KPI. Measure predicted-vs-actual at every arrival (pickup and dropoff), bucket by city/time, and use it to tune (or train an ML correction). Don't display second-precision ETAs — round to the minute; false precision erodes trust.

## 10. Multi-stop optimization

- **Pooled / multi-stop trips:** order the waypoints to minimize total time — Google Routes `optimizeWaypointOrder: true`, Mapbox **Optimization API** (`/optimized-trips/v1`, a TSP solver), or Valhalla `/optimized_route`.
- **Don't roll your own TSP** for live trips; use the provider solver or a heuristic (nearest-insertion) under a tight time budget.
- For driver multi-pickup (pool), cap stops so the first rider isn't punished (same principle as delivery stacking in `marketplace-master/delivery-logistics-dispatch`).

## 11. Edge cases & gotchas

- **Matrix order** — elements/return arrays are index-keyed; never assume positional order (§5).
- **Polyline precision mismatch** — decoding polyline6 as 5 (or vice-versa) → coordinates wildly off (§8).
- **No route / ferries / restricted zones** — check `condition`/status; fall back to haversine ETA with a "approx" flag rather than crash dispatch.
- **Tunnels / GPS gaps** during nav — keep last instruction, dead-reckon (`live-location-tracking`); re-route only on confirmed off-route.
- **Stale traffic at request time** vs reality at arrival — that's the irreducible ETA error; recompute en route.
- **One-way / U-turn asymmetry** — driver-to-pickup ETA ≠ pickup-to-driver; always route in the travel direction.
- **Rate limits / quotas** — providers throttle; implement retry-with-jitter + circuit breaker; cache identical short-lived requests.
- **Border/locale costing** — KSA vs UAE road rules, toll gates (Salik in Dubai) — include toll modifiers where fares depend on them.

## 12. Performance & cost control

- **H3-cap candidates before any matrix** (`realtime-matching-dispatch`): 20 candidates not 200 → 10× cost cut.
- **One matrix call per dispatch window**, not per request; batch.
- **Cache** identical OD pairs for a few seconds (traffic doesn't change in 3 s); memoize the rider's estimate route until they move.
- **Self-host OSRM/Valhalla** for the high-volume candidate matrix; reserve paid traffic-aware calls for the final route.
- **Field masks (Google)** trim payload + server compute — request the minimum.
- **ML ETA** at scale: a model over physics ETAs serves p95 in milliseconds and removes per-call cost on the hot path.

## 13. Security

- **Server keys only** for Directions/Routes/Matrix — proxy through your backend; never embed a routing key in the client (it's expensive to abuse).
- **Restrict & quota** keys per API and IP; billing alerts (a leaked Routes key is a costly leak).
- **Validate inputs** (coordinate ranges, waypoint counts) before calling providers to avoid abuse-amplification.
- **Don't log full polylines/PII routes** at info level; they're location PII.

## 14. Testing — replay & golden routes

- **Golden OD pairs** per city with known good routes; assert distance/duration within tolerance on provider/engine changes.
- **Simulated driver** steps along a decoded route polyline at realistic speed (shared with `live-location-tracking`/`realtime-matching-dispatch` simulators) to test nav + ETA recompute end-to-end.
- **Fallback tests:** force provider 5xx/timeout → assert haversine fallback + "approx ETA" flag, dispatch still proceeds.
- **Precision test:** decode every provider's polyline and assert coordinates land on the road (catches the 5-vs-6 bug).

## 15. Observability

- **ETA error** (|predicted − actual|) p50/p90 per city/product/time — the headline routing KPI.
- **Provider latency & error rate** per API; quota usage vs budget; cache hit rate.
- **Cost per trip** attributable to routing (matrix + route + nav); self-host vs managed split.
- **Re-route rate** and off-route detections during navigation.

## 16. Accessibility & i18n / RTL (MENA)

- **Localized turn-by-turn:** request `language=ar` (Mapbox) / `languageCode: "ar"` (Google) / `"language":"ar-SA"` (Valhalla) for Arabic banner + voice instructions; right-to-left instruction text in the UI.
- **Round ETAs to the minute** and present bilingually; Arabic numerals option.
- **Landmark-relative guidance** resonates in MENA ("after the mosque, turn right") — pair nav with landmark data (`geocoding-places-addressing`) where the provider supports it.
- **Tolls (Salik/Darb)** and gender-segregated/closed roads (some KSA areas) affect routing and fare — model them.

## 17. Anti-patterns

- **Straight-line / haversine as the real ETA** → wrong driver, broken promises. Traffic-aware road ETA.
- **Calling the matrix on uncapped candidates** → cost explosion. H3-cap first, one call per window.
- **Decoding polylines with the wrong precision** → coordinates in the sea. Match 5 vs 6.
- **Positional matrix parsing** → mismatched ETAs. Key by index.
- **Routing keys in the client** → billing abuse. Server-proxy only.
- **Recompute every second** (cost) or **never** (stale) → use hysteresis (move/age/off-route).
- **Second-precision ETAs** → false confidence. Round to the minute.

## 18. Agent checklist

```
- [ ] Engine chosen per job: Matrix (dispatch) / Route (rider+estimate) / turn-by-turn (driver)
- [ ] Google Routes with REQUIRED X-Goog-FieldMask (minimal fields); TRAFFIC_AWARE(_OPTIMAL)
- [ ] Matrix parsed by originIndex/destinationIndex (unordered) + condition check
- [ ] Mapbox: driving-traffic, geometries=polyline6, overview=full, steps for banner/voice
- [ ] Polyline decoded at correct precision (Google=5, Mapbox/Valhalla=6) → [lng,lat] for GL
- [ ] Self-host OSRM /table or Valhalla sources_to_targets for high-volume matrices; managed fallback
- [ ] ETA recompute via hysteresis (age/move/off-route); error measured at every arrival
- [ ] Multi-stop via provider optimizer (don't hand-roll TSP); cap pool stops
- [ ] Cost control: H3-cap, batch one call/window, cache short-lived OD, field masks
- [ ] Server keys only, proxied, quota+alert; inputs validated; routes not logged as info
- [ ] Localized (ar) banner/voice; ETAs rounded to minute; tolls (Salik) modeled
- [ ] Golden-route + fallback + precision tests; ETA-error/provider-latency/cost dashboards
```

## 19. References (verify current — 2026)

- Google Routes API — computeRoutes & field masks: https://developers.google.com/maps/documentation/routes/compute_route_directions · https://developers.google.com/maps/documentation/routes/choose_fields
- Google Routes — computeRouteMatrix: https://developers.google.com/maps/documentation/routes/compute_route_matrix
- Mapbox Directions: https://docs.mapbox.com/api/navigation/directions/ · Matrix: https://docs.mapbox.com/api/navigation/matrix/ · Optimization: https://docs.mapbox.com/api/navigation/optimization/
- OSRM API (table/route/match): https://project-osrm.org/docs/v5.24.0/api/ · Valhalla (matrix/turn-by-turn): https://valhalla.github.io/valhalla/api/
- Polyline algorithm: https://developers.google.com/maps/documentation/utilities/polylinealgorithm

## 20. Related

`realtime-matching-dispatch` (ETA matrix consumer), `maps-rendering-design` (draws the polyline), `surge-dynamic-pricing` (distance/duration → fare), `live-location-tracking` (snap-to-road, simulators) · cross-master: `backend-api-master` (GIS, API proxying), `ai-mcp-master` (ML ETA models), `marketplace-master/delivery-logistics-dispatch` (matrix-for-dispatch sibling)
