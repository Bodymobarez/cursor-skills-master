---
name: gps-integration
description: >-
  Advanced GPS / geolocation integration. Use for live location, tracking, geofencing,
  routing/ETA, distance calculations, reverse geocoding, or fleet/delivery tracking.
  Covers browser Geolocation API, mobile background tracking, geospatial storage
  (PostGIS), geofences, real-time streaming, and accuracy/battery best practices.
---

# GPS / Geolocation Integration

Capture, store, query, and act on location data — live tracking, geofencing, routing, and ETAs.

## Capture

**Browser (web):**
```js
const id = navigator.geolocation.watchPosition(
  (pos) => send({ lat: pos.coords.latitude, lng: pos.coords.longitude,
                  acc: pos.coords.accuracy, t: pos.timestamp }),
  (err) => console.error(err),
  { enableHighAccuracy: true, maximumAge: 5000, timeout: 10000 }
);
// navigator.geolocation.clearWatch(id) when done
```
**Mobile:** React Native → `react-native-geolocation-service` / Expo `expo-location` (request
**background** permission for tracking; configure significant-change/distance filters to save
battery). Native: CoreLocation (iOS) / FusedLocationProvider (Android).

## Store & query (PostGIS recommended)

```sql
CREATE EXTENSION IF NOT EXISTS postgis;
ALTER TABLE pings ADD COLUMN geom geography(Point,4326);
UPDATE pings SET geom = ST_MakePoint(lng, lat)::geography;
CREATE INDEX ON pings USING GIST (geom);

-- nearest drivers within 5km
SELECT id, ST_Distance(geom, ST_MakePoint(:lng,:lat)::geography) AS m
FROM drivers
WHERE ST_DWithin(geom, ST_MakePoint(:lng,:lat)::geography, 5000)
ORDER BY m LIMIT 10;
```
> Use SRID **4326** (WGS84). `geography` type gives meters directly.

## Distance (no DB)

Haversine for great-circle distance; for road distance/ETA use a routing API
(Google Directions, Mapbox Directions, OSRM, Valhalla).

## Geofencing

- Define zones as circles (center+radius) or polygons.
- Detect **enter/exit** by comparing previous vs current containment
  (`ST_Contains` / `ST_DWithin`); debounce to avoid flapping at the boundary.
- Trigger events (notify, log, automate) on transition — pair with `integrations-pro` webhooks.

## Real-time tracking pipeline

```
device → throttled pings (distance/time filter) → ingest API → store (PostGIS)
       → publish (WebSocket/MQTT/Pub-Sub) → live map (see gis-maps)
```
- Throttle on device (e.g. every 10–30 m or 5–15 s) — don't stream raw high-frequency fixes.
- Smooth jitter (Kalman/snap-to-road) for clean trails.

## Checklist
```
- [ ] Permissions (foreground + background w/ clear rationale) & graceful denial
- [ ] enableHighAccuracy only when needed (battery); set distance/time filters
- [ ] Store with PostGIS (4326) + GiST index; never float-compare coords for "near"
- [ ] Geofence enter/exit with debounce
- [ ] Routing/ETA via a routing API; reverse-geocode for addresses
- [ ] Real-time channel (WebSocket) + live map (gis-maps)
- [ ] Privacy: consent, retention policy, encrypt location at rest
```

## Anti-patterns
- High-frequency `enableHighAccuracy` always-on → battery drain.
- Storing lat/lng as floats and doing manual distance math at scale (use PostGIS + index).
- No geofence debounce → enter/exit spam at the edge.
- Ignoring privacy/consent and indefinite retention of location history.
