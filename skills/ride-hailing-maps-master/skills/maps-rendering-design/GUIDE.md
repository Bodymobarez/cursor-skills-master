---
name: maps-rendering-design
description: >-
  The maps-design mastery skill — Mapbox GL JS v3 (+ react-map-gl) vs MapLibre GL JS v5 vs
  Google Maps JS decision, custom light/dark styles, GeoJSON sources + symbol/line layers,
  smooth driver-marker interpolation, animated route polylines, camera fitBounds/flyTo,
  supercluster clustering, 3D/terrain, RTL/Arabic labels, performance (layer/source budget)
  and accessibility. Real copy-paste Mapbox GL v3 + MapLibre code.
---

# Maps Rendering & Design — Data in Sources, Style in Layers, Animation on the GPU

**A great ride-hailing map is a styling and data-flow problem, not a "drop a pin" problem.** The amateur attaches hundreds of DOM markers and re-creates them every GPS tick; the map jank-stutters and the battery dies. The principal puts moving data in **GeoJSON sources**, paints it with **style layers** (rendered on the GPU), animates the driver marker by **interpolating between fixes**, and keeps the layer/source count tiny. Markers are DOM (expensive); layers are GPU (cheap) — know which you're using and why.

---

## 1. Mandate

- **GeoJSON source + layer, not 500 DOM markers.** Live cars, the route, clusters all live in sources updated with `setData`; the GPU draws them. Reserve DOM markers for 1–3 special pins (pickup/dropoff/driver) if you want HTML/CSS.
- **Interpolate the driver marker.** GPS arrives every ~4 s; animate position with `requestAnimationFrame` between fixes so it glides, never teleports.
- **One source, `setData` updates.** Never remove/re-add layers per tick. Mutate the source's data; the renderer diffs.
- **Pick the renderer deliberately.** Mapbox GL v3 (best-looking, paid tiles), MapLibre v5 (free/open, self-host), or Google Maps JS (ecosystem). It's a cost/control/aesthetic decision.

## 2. When to use / when NOT

**Use when:** building the *map UI* — rider/driver map screens, ops dashboards, custom styling, markers, route lines, clustering, camera choreography, dark mode, RTL labels. This is the visual layer over `live-location-tracking` (data) and `routing-navigation-eta` (the route geometry).

**Skip / go elsewhere when:** the location *pipeline* (smoothing/snap/presence) → `live-location-tracking`. Computing the *route* or ETA → `routing-navigation-eta`. Address search UI → `geocoding-places-addressing`. General design system / Tailwind → `ui-master`.

## 3. DECISION MATRIX — map renderer

| Renderer | Cost | Look (3D/lighting) | Data control | RTL/Arabic | Verdict |
|----------|------|--------------------|--------------| -----------|---------|
| **Mapbox GL JS v3** | paid (MAU/tile loads) | ⭐ Standard style: 3D lighting, landmarks, light presets | excellent (vector, expressions) | RTL plugin, Arabic labels | ⭐ Best-looking consumer apps with budget |
| **MapLibre GL JS v5** | free / self-host tiles | great (globe, 3D terrain; you pick a style) | excellent (same GL spec lineage) | RTL plugin works | ⭐ Cost control / open-source / own your tiles |
| **Google Maps JS** | paid (per load) | good (vector, photoreal 3D tiles) | best POI data, Places | strong Arabic data | Deep Google ecosystem / Places-heavy |
| **Apple/others** | platform | native-only | limited web | varies | Native iOS edge cases only |

**Verdict:** Mapbox GL v3 for the flagship consumer aesthetic; **MapLibre v5 when tile cost or vendor lock matters** (it's a near drop-in of the GL spec, runs your own/free tiles). `react-map-gl` wraps *both* — `react-map-gl/mapbox` and `react-map-gl/maplibre` — so you can switch the renderer behind one component API.

## 4. Mapbox GL JS v3 — Standard style, light presets, config

```ts
import mapboxgl from "mapbox-gl";
import "mapbox-gl/dist/mapbox-gl.css";
mapboxgl.accessToken = import.meta.env.VITE_MAPBOX_TOKEN!;

const map = new mapboxgl.Map({
  container: "map",
  style: "mapbox://styles/mapbox/standard",   // v3 default: 3D lighting, landmarks, dynamic light
  center: [55.2708, 25.2048],                  // Dubai [lng, lat]
  zoom: 12, pitch: 45, bearing: -17,           // a little tilt reads as "premium" on ride apps
  antialias: true,
});

// Standard style is configured via setConfigProperty('basemap', ...), NOT by swapping styles.
map.on("style.load", () => {
  map.setConfigProperty("basemap", "lightPreset", "night");        // 'dawn' | 'day' | 'dusk' | 'night'
  map.setConfigProperty("basemap", "showPointOfInterestLabels", false); // declutter for a ride map
  map.setConfigProperty("basemap", "show3dObjects", true);         // landmark 3D buildings
});
```

```tsx
// react-map-gl v8 — same renderer, React props. Switch renderer by changing the import.
import Map from "react-map-gl/mapbox";   // or: import Map from "react-map-gl/maplibre"
import "mapbox-gl/dist/mapbox-gl.css";

export function RideMap() {
  return (
    <Map
      mapboxAccessToken={import.meta.env.VITE_MAPBOX_TOKEN}
      initialViewState={{ longitude: 55.2708, latitude: 25.2048, zoom: 12, pitch: 45 }}
      mapStyle="mapbox://styles/mapbox/standard"
      style={{ width: "100%", height: "100%" }}
      reuseMaps                              // keep the GL context across mounts (don't leak contexts)
    />
  );
}
```

## 5. MapLibre GL JS v5 — free/open, globe, self-host tiles

```ts
import maplibregl from "maplibre-gl";       // v5.24.x (Apr 2026)
import "maplibre-gl/dist/maplibre-gl.css";

const map = new maplibregl.Map({
  container: "map",
  style: "https://tiles.example.com/style.json",  // your own/free vector tiles (e.g., OpenFreeMap, Protomaps)
  center: [55.2708, 25.2048], zoom: 12, pitch: 45,
});
map.addControl(new maplibregl.NavigationControl());

map.on("style.load", () => {
  map.setProjection({ type: "globe" });     // v5 globe projection (GlobeControl also available)
});

// v5 addProtocol is PROMISE-based (no callbacks) — e.g. Protomaps single-file tiles (pmtiles).
// import { Protocol } from "pmtiles"; const p = new Protocol(); maplibregl.addProtocol("pmtiles", p.tile);
```

MapLibre is the GL-spec lineage Mapbox forked from — **layers, sources, expressions, and the style JSON are the same mental model**, so the source/layer code below works on both. The difference is tiles + style hosting (you own them) and licensing (BSD, free).

## 6. Live cars as a GeoJSON source (NOT DOM markers)

```ts
// ONE source for all nearby cars; update with setData every batch. GPU-drawn = thousands cheap.
map.on("load", () => {
  map.addSource("cars", { type: "geojson", data: emptyFC() });
  map.addImage("car", carPngBitmap, { pixelRatio: 2 });
  map.addLayer({
    id: "cars",
    type: "symbol",
    source: "cars",
    layout: {
      "icon-image": "car",
      "icon-size": ["interpolate", ["linear"], ["zoom"], 10, 0.4, 16, 0.9], // scale with zoom
      "icon-rotate": ["get", "bearing"],          // rotate to heading
      "icon-rotation-alignment": "map",
      "icon-allow-overlap": true,                  // don't drop cars under collision detection
    },
  });
});

// Per batch: mutate the source data — never addLayer/removeLayer per tick.
function updateCars(cars: { id: string; lng: number; lat: number; bearing: number }[]) {
  const fc = {
    type: "FeatureCollection",
    features: cars.map((c) => ({
      type: "Feature", id: c.id,
      geometry: { type: "Point", coordinates: [c.lng, c.lat] },
      properties: { bearing: c.bearing },
    })),
  };
  (map.getSource("cars") as maplibregl.GeoJSONSource).setData(fc as any);
}
```

## 7. Smooth driver-marker interpolation (the detail that reads as "premium")

```ts
// GPS lands every ~4s. Glide between the last and next position with rAF — no teleport.
class DriverMarker {
  private from: [number, number]; private to: [number, number];
  private startT = 0; private durMs = 4000; private raf = 0;
  constructor(private map: maplibregl.Map, start: [number, number]) { this.from = this.to = start; }

  moveTo(next: [number, number], bearing: number, durMs = 4000) {
    cancelAnimationFrame(this.raf);
    this.from = this.current(); this.to = next; this.durMs = durMs; this.startT = performance.now();
    const tick = (now: number) => {
      const t = Math.min(1, (now - this.startT) / this.durMs);
      const e = t * (2 - t);                                   // easeOutQuad — natural deceleration
      const lng = this.from[0] + (this.to[0] - this.from[0]) * e;
      const lat = this.from[1] + (this.to[1] - this.from[1]) * e;
      this.render([lng, lat], bearing);
      if (t < 1) this.raf = requestAnimationFrame(tick);
    };
    this.raf = requestAnimationFrame(tick);
  }
  private current(): [number, number] { /* read last rendered point */ return this.to; }
  private render(p: [number, number], bearing: number) {
    (this.map.getSource("driver") as maplibregl.GeoJSONSource).setData({
      type: "Feature", geometry: { type: "Point", coordinates: p }, properties: { bearing },
    } as any);
  }
}
// Interpolate over slightly LONGER than the GPS interval so it never "catches up and stalls".
```

## 8. Animated route polyline (decode + draw + grow)

```ts
import polyline from "@mapbox/polyline";   // decode encoded polylines from Directions/Routes APIs

// Draw the route as a line layer (with a wide "casing" under a colored line — the pro look).
function drawRoute(encoded: string) {
  const coords = polyline.decode(encoded, 6).map(([lat, lng]) => [lng, lat]); // polyline6 → [lng,lat]
  const data = { type: "Feature", geometry: { type: "LineString", coordinates: coords } } as const;
  if (map.getSource("route")) (map.getSource("route") as any).setData(data);
  else {
    map.addSource("route", { type: "geojson", data, lineMetrics: true }); // lineMetrics enables gradient
    map.addLayer({ id: "route-casing", type: "line", source: "route",
      paint: { "line-color": "#0b1f3a", "line-width": 10, "line-opacity": 0.9 },
      layout: { "line-cap": "round", "line-join": "round" } });
    map.addLayer({ id: "route", type: "line", source: "route",
      paint: { "line-color": "#1d9bf0", "line-width": 6 },
      layout: { "line-cap": "round", "line-join": "round" } });
  }
}

// "Traveled vs remaining" with a line-gradient driven by progress (0..1) along the line.
function setProgress(p: number) {
  map.setPaintProperty("route", "line-gradient", [
    "interpolate", ["linear"], ["line-progress"],
    0, "#9aa4b2", Math.max(0.0001, p), "#9aa4b2", p, "#1d9bf0", 1, "#1d9bf0",
  ]);
}
```

## 9. Camera choreography — fitBounds & flyTo

```ts
// Frame pickup + dropoff with padding for the bottom sheet (don't hide the route under the UI).
function frameTrip(pickup: [number, number], dropoff: [number, number]) {
  const b = new maplibregl.LngLatBounds(pickup, pickup).extend(dropoff);
  map.fitBounds(b, { padding: { top: 80, bottom: 320, left: 40, right: 40 }, duration: 800, maxZoom: 16 });
}
// Follow the driver smoothly during the trip.
function followDriver(p: [number, number], bearing: number) {
  map.easeTo({ center: p, bearing, pitch: 55, zoom: 16, duration: 1000, essential: true });
}
// flyTo for big context jumps (e.g., switching cities); easeTo for in-trip follow.
```

## 10. Clustering at scale (supercluster)

```ts
// Native GL clustering for moderate counts; supercluster for big/ops datasets.
map.addSource("demand", {
  type: "geojson", data: heatmapFC, cluster: true, clusterRadius: 50, clusterMaxZoom: 14,
});
map.addLayer({ id: "clusters", type: "circle", source: "demand", filter: ["has", "point_count"],
  paint: {
    "circle-color": ["step", ["get", "point_count"], "#51bbd6", 50, "#f1f075", 200, "#f28cb1"],
    "circle-radius": ["step", ["get", "point_count"], 16, 50, 22, 200, 30],
  } });
map.addLayer({ id: "cluster-count", type: "symbol", source: "demand", filter: ["has", "point_count"],
  layout: { "text-field": ["get", "point_count_abbreviated"], "text-size": 12 } });
// For 100k+ moving points (ops console), run `supercluster` off-thread and feed setData per viewport.
```

## 11. RTL / Arabic labels (MENA — mandatory, easy to forget)

```ts
// WITHOUT this plugin, Arabic/Hebrew labels render reversed/disconnected. Load it ONCE, before the map.
import { setRTLTextPlugin } from "maplibre-gl"; // mapbox-gl exposes the same API
setRTLTextPlugin(
  "https://unpkg.com/@mapbox/mapbox-gl-rtl-text@0.3.0/mapbox-gl-rtl-text.min.js",
  true, // lazy load
);
// Prefer Arabic name fields where the style/tiles provide them:
map.setLayoutProperty("place-labels", "text-field",
  ["coalesce", ["get", "name_ar"], ["get", "name"]]);
```

The RTL text plugin is **the** thing teams forget — Arabic place labels look broken without it. Load it before map init. Pick tiles that carry `name_ar` (Mapbox Standard does for many places; for MapLibre choose Arabic-capable tiles).

## 12. Edge cases & gotchas

- **`setData` is async-ish** — don't read features back synchronously after setting; rely on render events.
- **Marker drift on zoom/rotate** — DOM markers must use the map's projection; if you hand-position HTML, you'll fight the camera. Prefer symbol layers for moving things.
- **Icon collision dropping cars** — set `icon-allow-overlap: true` for vehicles (you *want* overlap), but allow collision for labels.
- **Memory leaks** — always `map.remove()` on unmount; with react-map-gl use `reuseMaps`; don't accumulate WebGL contexts (browsers cap them ~16 → blank map).
- **Bottom-sheet covers the route** — always pad `fitBounds` for the UI chrome (§9).
- **Token in the bundle** — Mapbox tokens are public by design; **restrict by URL/domain** and scope; never ship a secret-scoped token (§14).
- **`flyTo` spam** — calling it every GPS tick fights the user and burns CPU; use `easeTo` follow and only on meaningful movement.
- **Style swap nukes your layers** — `setStyle` clears custom sources/layers; re-add them on `style.load`, or (Mapbox Standard) use `setConfigProperty` instead of swapping styles for light/dark.

## 13. Performance — the budget that keeps it 60fps

- **Layer/source budget:** keep custom layers in the low dozens; every layer is a draw pass. Combine features into shared sources + data-driven styling (expressions) instead of one-layer-per-thing.
- **`setData`, never re-add:** mutate sources for live data; adding/removing layers per tick stalls.
- **Symbol layers > DOM markers** beyond ~50 markers; DOM markers repaint on every camera move.
- **Interpolate on rAF**, throttle camera follow, and decouple render cadence from GPS ingest (`live-location-tracking §11`).
- **Simplify geometry:** decimate long trails before drawing (Douglas–Peucker / turf.simplify); don't draw 10k-vertex polylines.
- **Cluster** dense point sets; never draw 100k individual points.

## 14. Security & key/billing abuse

- **Restrict the public token:** lock Mapbox/Google web keys to your domains/bundle IDs and the minimum scopes; set **billing alerts + quotas** — an unrestricted key scraped from your JS can run up thousands in tile loads.
- **Separate keys** for web/iOS/Android with platform restrictions; rotate on leak.
- **Proxy server-side calls** (Directions/Geocoding) through your backend with a server key so the powerful key never ships to clients (`routing-navigation-eta`, `geocoding-places-addressing`).
- **Self-host tiles (MapLibre)** to remove per-load vendor billing entirely when volume justifies it.

## 15. Testing

- **Visual regression:** Playwright `toHaveScreenshot()` on map states (route drawn, dark preset, clustered, RTL labels) so a style change can't silently break the look.
- **Interpolation tests:** feed scripted fixes, assert the marker position is monotonic and never jumps > expected per frame.
- **Renderer parity:** run the same source/layer code on Mapbox and MapLibre in CI to keep the abstraction honest.
- **Perf budget test:** assert layer count and frame time under a simulated city of cars.

## 16. Observability

- **Client RUM:** map load time, time-to-first-render, fps during trip follow, WebGL context losses.
- **Tile/SDK usage:** loads per session vs billing (catch a key-abuse spike early).
- **Marker latency:** GPS fix → on-screen update (works with `live-location-tracking` metrics).

## 17. Accessibility & i18n / RTL

- **The map can't be the only source of truth.** Provide the ETA, address, and driver info as text (screen-reader accessible), not just pixels — a blind rider needs "Driver 3 min away, Toyota Camry" in the DOM.
- **Sufficient contrast** for route line vs basemap in both light/dark presets (`color-design-master`); don't rely on color alone for traveled/remaining (use a marker too).
- **RTL layout** for all map-overlay UI (bottom sheet, ETA chip), Arabic numerals option, and `name_ar` labels (§11).
- **Respect reduced-motion:** cut camera fly animations when `prefers-reduced-motion` is set.

## 18. Anti-patterns

- **Hundreds of DOM markers** re-created per GPS tick → jank + battery death. Use a GeoJSON symbol layer + `setData`.
- **Teleporting driver marker** (snap to each fix) → cheap-looking. Interpolate on rAF.
- **`addLayer`/`removeLayer` per update** → render stalls. Mutate sources.
- **Forgetting the RTL text plugin** → broken Arabic labels in MENA. Load it once, up front.
- **Unrestricted public map token** → billing abuse. Domain-restrict + quotas + alerts.
- **`fitBounds` without UI padding** → route hidden behind the bottom sheet.
- **Style swap for dark mode on Standard** → loses layers. Use `setConfigProperty('basemap','lightPreset',...)`.
- **Drawing raw 10k-vertex trails** → GPU choke. Simplify first.

## 19. Agent checklist

```
- [ ] Renderer chosen deliberately (Mapbox GL v3 look | MapLibre v5 cost/control | Google Places-heavy)
- [ ] Live cars/route/clusters in GeoJSON SOURCES, painted by layers; setData updates (no per-tick addLayer)
- [ ] Driver marker INTERPOLATED on requestAnimationFrame (glide, slightly > GPS interval)
- [ ] Route polyline decoded (polyline6) with casing + line; traveled/remaining gradient
- [ ] Camera: fitBounds with bottom-sheet padding; easeTo follow (not flyTo spam)
- [ ] Clustering (native or supercluster) for dense point sets
- [ ] RTL text plugin loaded ONCE; name_ar labels for MENA
- [ ] Layer/source budget kept low; geometry simplified; map.remove() on unmount (no context leak)
- [ ] Public token domain-restricted + quotas + billing alerts; server-key calls proxied
- [ ] Text alternatives for map info (a11y); reduced-motion respected; contrast in light & dark
- [ ] Visual-regression + interpolation + renderer-parity tests
```

## 20. References (verify current — 2026)

- Mapbox GL JS v3 (Standard style, setConfigProperty, migrate-to-v3): https://docs.mapbox.com/mapbox-gl-js/guides/migrate-to-v3/ · https://docs.mapbox.com/map-styles/standard/guides/
- react-map-gl (Mapbox & MapLibre entrypoints): https://visgl.github.io/react-map-gl/docs/api-reference/mapbox/map
- MapLibre GL JS v5 (globe, addProtocol): https://maplibre.org/maplibre-gl-js/docs/ · https://www.npmjs.com/package/maplibre-gl
- Mapbox RTL text plugin: https://github.com/mapbox/mapbox-gl-rtl-text · supercluster: https://github.com/mapbox/supercluster
- Google Maps JS API: https://developers.google.com/maps/documentation/javascript · Protomaps/pmtiles (self-host): https://docs.protomaps.com

## 21. Related

`live-location-tracking` (the data this renders), `routing-navigation-eta` (route geometry + polyline), `geocoding-places-addressing` (search box UI on the map) · cross-master: `ui-master` (design system, RTL, contrast), `color-design-master` (light/dark map palettes, contrast), `cross-platform-apps-master` (native map SDKs for iOS/Android)
