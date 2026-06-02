---
name: fleet-asset-tracking-platform
description: >-
  Build a telematics platform end-to-end at staff depth: the ingestion → normalize → enrich → trip/stop
  detection → events (speeding/idle/harsh) → live map + history → dashboards pipeline, a real Postgres/PostGIS
  data model, real-time fan-out to operators (WebSocket/SSE), retention + downsampling so storage doesn't
  explode, and the throughput/sharding/idempotency that make it survive 100k devices. Cross-links map rendering.
---

# Fleet & Asset Tracking Platform — End-to-End Telematics

**A fleet platform is a stream-processing system that happens to be about geography.** Dumb sensors emit
unreliable, out-of-order, bursty fixes; you turn that firehose into *trips, stops, events, live presence, and
reports* that someone runs a business on. The architecture is the product — accuracy, latency, and cost all
come from how you stage ingestion → normalization → derived state → serving.

The senior move is **separating raw fixes (write-optimized, high-volume, expiring) from derived facts (trips,
events, last-known — small, durable, queried)**. Conflate them and you get a slow, expensive, unqueryable blob.

---

## When to use this skill / when NOT

**Use it when** you're assembling the *whole system*: vehicle fleets, asset/equipment tracking, cold-chain,
logistics, field service, micromobility ops, container/trailer tracking — ingest → store → detect → show.

**Do NOT** treat this as the place for: the wire protocols (`device-integration-protocols`), how GNSS works
(`gps-gnss-fundamentals`), PostGIS query/index internals (`geospatial-data-postgis`), geofence event logic
(`geofencing-events`), or the live map UI + routing/ETA (`ride-hailing-maps-master`). This skill is the
**pipeline + data model + serving** that wires those together.

---

## 1. Mental model — the pipeline (stages, not a monolith)

```
 devices ─┐                         ┌────────── HOT PATH (real-time) ──────────┐
 (trackers,│  INGEST    NORMALIZE   │  last_position (Redis)  ──▶ fan-out       │ live map
  phones) ─┼─▶ gateway ─▶ + enrich ─┼─▶ event detectors (speed/idle/harsh/geo) │ alerts
          ─┘  (per      (UTC, units, │   trip/stop builder (stateful)            │
              protocol)  filter,     └───────────────────────────────────────────┘
                         reverse-geo)                │
                                          COLD PATH (durable)
                                          fixes (TimescaleDB/partitioned, downsampled, TTL)
                                          trips · stops · events (small, indexed, kept long)
                                                       │
                                                  reports / dashboards / API
```

- **Ingest** = `device-integration-protocols` (frame, checksum, ACK) → push normalized fixes to a **queue**
  (Kafka/NATS/Redis Streams). The bus decouples spiky ingestion from processing.
- **Normalize/enrich** = UTC timestamps, SI units, drop `(0,0)`/low-quality fixes, optional reverse-geocode &
  snap-to-road, attach `vehicle_id`.
- **Derive** = stateful consumers build trips/stops and emit events.
- **Serve** = hot last-known + fan-out for live; durable trips/events for history/reports.

---

## 2. Architecture decision matrix

| Decision | Options | Pick |
|----------|---------|------|
| Ingest→process coupling | direct DB writes / **message bus** | **Bus** (Kafka/NATS/Redis Streams) — absorbs bursts, replayable |
| Raw fix store | plain Postgres / **TimescaleDB or native partitioning** / columnar | **Timescale/partitioned by time** for time-series at scale |
| Derived store | same table / **separate trips/events tables** | **Separate** — small, durable, indexed for queries |
| Last-known position | DB row / **Redis/KV** | **Redis** — every live map hits it; don't query the fix table |
| Live fan-out | poll / **WebSocket/SSE** / MQTT | **WS/SSE** push (or MQTT) — see `ride-hailing-maps-master` |
| Trip detection | device-reported / **server-derived** | **Server-derived** (uniform across mixed hardware) |
| Reverse-geocode | per fix / **on stop/trip only** | **On stops/trip ends** — per-fix geocoding is a cost bomb |

---

## 3. Data model (Postgres + PostGIS + Timescale) — copy-paste

Separate **high-volume raw** from **low-volume derived**. Store points as `geography` (metre-true) or
`geometry(Point,4326)`; trips as a `LINESTRING` for cheap history rendering.

```sql
CREATE EXTENSION IF NOT EXISTS postgis;
-- TimescaleDB optional but ideal for the fixes hypertable.

-- Devices / vehicles (small, durable)
CREATE TABLE vehicle (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  org_id      bigint NOT NULL,
  imei        text UNIQUE NOT NULL,
  label       text,                         -- human name / plate, never show raw IMEI in UI
  speed_limit_kmh int
);

-- RAW FIXES — the firehose. Write-optimized, partitioned by time, EXPIRES.
CREATE TABLE fix (
  vehicle_id  bigint NOT NULL,
  ts          timestamptz NOT NULL,         -- FIX time (device), UTC
  geom        geometry(Point,4326) NOT NULL,
  speed_kmh   real,
  heading     smallint,
  hdop        real,
  ignition    boolean,
  PRIMARY KEY (vehicle_id, ts)              -- idempotent: re-ingest of same fix is a no-op upsert
);
-- SELECT create_hypertable('fix','ts', chunk_time_interval => INTERVAL '1 day');  -- Timescale
CREATE INDEX ON fix USING gist (geom);
CREATE INDEX ON fix (vehicle_id, ts DESC);  -- "last N fixes for vehicle" / history window

-- DERIVED: trips (small, durable, kept for years)
CREATE TABLE trip (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  vehicle_id  bigint NOT NULL,
  started_at  timestamptz NOT NULL,
  ended_at    timestamptz,
  path        geometry(LineString,4326),    -- the trip polyline for history rendering
  distance_m  double precision,
  max_speed_kmh real,
  start_addr  text, end_addr text           -- reverse-geocoded at trip boundaries only
);
CREATE INDEX ON trip (vehicle_id, started_at DESC);

-- DERIVED: stops & events (speeding/idle/harsh/geofence)
CREATE TABLE stop (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  vehicle_id bigint NOT NULL, arrived_at timestamptz, departed_at timestamptz,
  geom geometry(Point,4326), address text
);
CREATE TABLE event (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  vehicle_id bigint NOT NULL,
  kind text NOT NULL CHECK (kind IN ('SPEEDING','IDLE','HARSH_BRAKE','HARSH_ACCEL','TOW','GEOFENCE','POWER_CUT')),
  occurred_at timestamptz NOT NULL,
  geom geometry(Point,4326), value jsonb,   -- e.g. {"speed":118,"limit":90}
  UNIQUE (vehicle_id, kind, occurred_at)    -- idempotency
);
```

---

## 4. Trip & stop detection (stateful, server-side)

A "trip" is motion bracketed by stops. Detect with **ignition** if available (cleanest), else a **speed +
displacement + dwell** heuristic with hysteresis (same anti-flap discipline as `geofencing-events`).

```ts
// trip-detector.ts — per-vehicle state. Fed normalized fixes IN ORDER (shard by vehicle_id).
interface Cfg { moveSpeedKmh: number; stopSpeedKmh: number; stopDwellMs: number; minTripM: number }
const CFG: Cfg = { moveSpeedKmh: 5, stopSpeedKmh: 3, stopDwellMs: 180_000, minTripM: 100 };

type S = { driving: boolean; tripStart?: number; lastMove: number; pts: [number, number][]; dist: number };

export function onFix(s: S | undefined, f: { ts: number; lat: number; lon: number; speedKmh: number }, prev?: { lat: number; lon: number }): { s: S; emit?: "TRIP_START" | "TRIP_END" } {
  s ??= { driving: false, lastMove: f.ts, pts: [], dist: 0 };
  const moving = f.speedKmh > CFG.moveSpeedKmh;

  if (!s.driving && moving) {                       // start
    return { s: { driving: true, tripStart: f.ts, lastMove: f.ts, pts: [[f.lon, f.lat]], dist: 0 }, emit: "TRIP_START" };
  }
  if (s.driving) {
    s.pts.push([f.lon, f.lat]);
    if (prev) s.dist += haversineM(prev.lat, prev.lon, f.lat, f.lon);
    if (f.speedKmh > CFG.stopSpeedKmh) s.lastMove = f.ts;
    // Ended when stationary for the dwell window (hysteresis: low speed for a sustained time, not one fix)
    if (f.ts - s.lastMove >= CFG.stopDwellMs) {
      const valid = s.dist >= CFG.minTripM;          // discard GPS-jitter "trips" while parked
      return { s: { driving: false, lastMove: f.ts, pts: [], dist: 0 }, emit: valid ? "TRIP_END" : undefined };
    }
  }
  return { s };
}
function haversineM(la1: number, lo1: number, la2: number, lo2: number) {
  const R = 6371000, d = Math.PI / 180;
  const a = Math.sin(((la2 - la1) * d) / 2) ** 2 +
    Math.cos(la1 * d) * Math.cos(la2 * d) * Math.sin(((lo2 - lo1) * d) / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}
```

> The **`minTripM` guard is non-negotiable**: without it, a vehicle parked overnight generates dozens of
> phantom 8 m "trips" from multipath wander, and your "trips today" report becomes nonsense. Distance comes
> from snapped points ideally (snap-to-road via `ride-hailing-maps-master`) — raw odometry over-counts jitter.

---

## 5. Event detection (speeding / idle / harsh)

| Event | Signal | Debounce (avoid spam) |
|-------|--------|------------------------|
| **Speeding** | `speed > limit` (zone or road limit) | sustained > T s and/or > margin; one event per episode |
| **Idle** | ignition ON + speed ≈ 0 > T min | single event at threshold, not per fix |
| **Harsh brake/accel** | Δspeed/Δt beyond g-threshold (or device accel I/O) | per maneuver; needs ≥ a few Hz to be real |
| **Tow / unauthorized move** | motion while ignition OFF | confirm with displacement to avoid GPS jitter |
| **Power cut / tamper** | device I/O flag | from tracker I/O element (Teltonika/GT06 status) |

Speeding/harsh need **road or zone speed limits** (from your geofences or a maps provider) and a **sustained**
condition — alerting on a single fix at 1 km/h over is noise. Harsh-driving from GPS-derived acceleration is
crude; prefer the **accelerometer I/O** the tracker reports (Teltonika AVL IO IDs) when present. Emit through
the same **idempotent event table** (§3) so replays don't double-alert (mirror `geofencing-events` discipline).

---

## 6. Real-time fan-out (live map / ops console)

```
fix → normalize → SET last_position:{vehicle} in Redis (TTL) + PUBLISH vehicle:{id} channel
                                                   │
   operator opens live map → subscribes (WebSocket/SSE) to their org's vehicles
                                                   │
   gateway bridges Redis pubsub → connected sockets (only push deltas the viewer is watching)
```

- Serve **last-known from Redis**, never `SELECT … ORDER BY ts DESC LIMIT 1` on the fix table per viewer.
- Push **only what the operator is viewing** (bbox/org filter); don't broadcast 100k vehicles to every socket.
- Throttle to **1 update/sec/vehicle** to the UI even if devices send faster — humans can't see more, and it
  saves bandwidth. Rendering, clustering, and smooth marker animation are `ride-hailing-maps-master` (the
  `maps-rendering-design` + `live-location-tracking` skills) — **this platform feeds it, that skill draws it**.

---

## 7. Retention & downsampling — the cost-control skill

Raw 1 Hz fixes for 100k vehicles = **billions of rows/week**. Keeping them hot forever bankrupts you. Tier it:

| Tier | Resolution | Retention | Store |
|------|-----------|-----------|-------|
| **Hot raw** | full (1 Hz) | 7–30 days | partitioned/hypertable, fast disk |
| **Warm downsampled** | 1 point / 15–60 s, or Douglas-Peucker simplified trip lines | 6–24 months | cheaper disk / compressed chunks |
| **Cold / derived only** | trips + events + daily aggregates (no raw points) | years | object storage / archive |

- Keep **derived facts (trips/events) long** (they're tiny and answer business questions); **expire raw fixes**
  fast (drop whole time partitions — instant, no `DELETE` churn).
- Downsample with **Timescale continuous aggregates** or a job that simplifies trip `LINESTRING`s
  (`ST_SimplifyVW`/Douglas-Peucker) — a history replay doesn't need 1 Hz.
- Compress old chunks (Timescale native compression often 90%+ on telematics).

---

## 8. Performance & throughput

- **Bulk-insert fixes** (`COPY`/multi-row upsert), never row-at-a-time; batch by time window from the queue.
- **Idempotent upsert** on `(vehicle_id, ts)` so at-least-once delivery and reconnect-replays are harmless.
- Keep heavy work (reverse-geocode, snap-to-road, route-matching) **off the hot path** — do it on stop/trip
  completion, async.
- Partition/hypertable by time so writes hit the latest chunk and history queries prune to a few chunks.
- Last-known and counters in Redis; the fix table is for **history and analytics**, not live reads.

---

## 9. Scale & reliability (100k+ devices)

- **Shard processing by `vehicle_id`** so one vehicle's fixes are handled **in order** on one consumer (trip/
  event state machines need ordering). Kafka partition key = vehicle_id.
- The message bus gives **replay** (rebuild derived state by reprocessing) and **backpressure** (if DB is down,
  stop ACKing devices — their flash buffers absorb it; see `device-integration-protocols`).
- Expect **out-of-order & late** fixes (offline buffers dump on reconnect): order by `ts`, and make derived
  builders tolerant (or reprocess the affected window).
- Multi-tenant isolation by `org_id` everywhere (consider Postgres RLS) — one customer's query/scan must not
  starve another.

---

## 10. Security & privacy

- Tracks are **PII + behavioral data** (where employees/assets go, when). Enforce **org-scoped access** (RLS),
  audit who views live/history, and set **retention to the minimum the business needs** (and that law allows —
  some jurisdictions cap employee-tracking retention and mandate off-hours privacy).
- Driver privacy: support **private mode** / off-duty masking where required; don't track personal-use windows.
- Device auth & spoof detection upstream (`device-integration-protocols`); jump/teleport detection downstream.
- Encrypt at rest and in transit; secrets (provider keys) in a vault; never expose the raw ingest port to apps.

---

## 11. Testing

- **Replay GPX/recorded fleets** end-to-end; assert trips/stops/events match a golden output (and counts —
  phantom trips show up as count drift).
- Unit-test detectors against crafted sequences: parked-with-jitter (0 trips), tunnel gap (1 trip not 2),
  out-of-order fixes (correct ordering), idle vs slow-crawl.
- Load-test ingestion at target devices×rate with the bus; verify backpressure and idempotency under retries.
- Replayability test: wipe derived tables, reprocess the bus, get identical trips/events.

---

## 12. Observability

- **Pipeline lag** (queue depth, consumer lag per partition), fixes/sec, derived-events/sec.
- Data-quality: % fixes rejected (low HDOP / `(0,0)` / stale), % vehicles reporting, last-seen age distribution.
- Per stage latency (ingest→serve), Redis hit-rate, DB write batch sizes, partition sizes & compression ratio.
- Business dashboards downstream (utilization, idle %, speeding/100km) sit **on derived tables**, not raw fixes.

---

## 13. Accessibility & i18n

- Dashboards/reports: localized units (km vs mi, L/100km vs mpg), dates, currencies; RTL; colorblind-safe
  status palettes; screen-reader-friendly tables alongside maps (don't lock data inside a canvas map only).
- Render times in the **viewer's** timezone; store UTC. Translate event/status labels and exported reports.

---

## 14. Opinionated anti-patterns

- ❌ One table for raw fixes **and** derived facts → slow, huge, unqueryable; can't expire raw without losing trips.
- ❌ Writing fixes straight to the DB from the socket (no bus) → bursts stall ingestion, no replay/backpressure.
- ❌ `SELECT latest fix` from the fix table for every live-map tile instead of Redis last-known.
- ❌ **Reverse-geocoding every fix** (cost bomb) instead of at stops/trip ends.
- ❌ No `minTripM` guard → phantom parked-car "trips" wreck every report.
- ❌ Alerting on single-fix speeding/harsh (no sustained/debounce) → alert fatigue.
- ❌ Keeping 1 Hz raw forever (no downsampling/TTL) → storage cost explosion.
- ❌ Processing a vehicle's fixes across workers out of order → broken trips/events.
- ❌ Re-implementing map rendering/routing here instead of using `ride-hailing-maps-master`.

## 15. Agent checklist

```
- [ ] Ingestion decoupled from processing via a message bus (replay + backpressure)
- [ ] Raw fixes (partitioned/hypertable, idempotent on vehicle_id+ts, TTL) SEPARATE from derived trips/events
- [ ] Last-known in Redis; live fan-out via WS/SSE, viewer-scoped, throttled ~1 Hz
- [ ] Server-side trip/stop detection with hysteresis + minTripM guard (no phantom trips)
- [ ] Events debounced + idempotent (unique key); speed limits sourced; harsh prefers accel I/O
- [ ] Heavy enrich (reverse-geo, snap-to-road) off the hot path, at stop/trip boundaries
- [ ] Retention tiers: hot raw days → warm downsampled → derived kept years; old chunks compressed
- [ ] Processing sharded by vehicle_id (ordered); multi-tenant isolation by org (RLS)
- [ ] Tracks treated as PII: org-scoped access, audit, minimal retention, private-mode support
- [ ] End-to-end GPX replay + detector unit tests + load/idempotency tests; reprocess = identical output
- [ ] Map rendering/routing delegated to ride-hailing-maps-master; this feeds it
```

## 16. References (2026-current)
- TimescaleDB (time-series Postgres): https://docs.tigerdata.com/ · PostGIS: https://postgis.net/documentation/
- Kafka: https://kafka.apache.org/documentation/ · NATS JetStream: https://docs.nats.io/
- Open-source telematics reference (Traccar): https://www.traccar.org/

## Related
`device-integration-protocols` (ingest), `geospatial-data-postgis` (storage/queries), `geofencing-events`
(zone events), `ride-hailing-maps-master` (live map, routing, snap-to-road), `systems-platforms-master` (queues/DB)
