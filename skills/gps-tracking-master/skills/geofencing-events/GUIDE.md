---
name: geofencing-events
description: >-
  Geofencing at staff depth: circular vs polygon, device-side (OS GeofencingClient/CLMonitor) vs server-side
  trade-offs, enter/exit/DWELL with hysteresis + debounce that actually kills flapping, PostGIS ST_Contains /
  ST_DWithin evaluation, an idempotent event pipeline (no duplicate alerts), and scaling to many fences ×
  many devices (spatial index + candidate pruning). The hard part isn't "point in polygon" — it's not crying wolf.
---

# Geofencing & Events — Triggers That Don't Cry Wolf

**Point-in-polygon is a one-liner; a geofence system that doesn't spam false alerts is the actual engineering.**
A vehicle idling on a fence boundary with 15 m GPS jitter will, naively, fire ENTER/EXIT/ENTER/EXIT every few
seconds — wake the driver's phone, page an operator, bill an SMS each time. This skill is about **state,
hysteresis, debounce, and idempotency** far more than geometry.

The core insight: a geofence event is a **transition in a per-(device,fence) state machine**, debounced
against GPS noise — not a per-fix boolean test you alert on directly.

---

## When to use this skill / when NOT

**Use it when** you need "tell me when X enters/leaves/stays-in area Y": delivery zone arrival, jobsite
attendance, asset-leaves-yard theft alerts, speed-zone enforcement, kid/pet safe-zones, congestion/curfew zones.

**Do NOT** put raw geometry math here — that's `geospatial-data-postgis` (indexes, KNN, query tuning). Map
*drawing* of fences is `ride-hailing-maps-master` (mapbox-gl-draw). On-device permission/background plumbing is
`web-mobile-geolocation`. This skill is the **event logic** that sits between fixes and alerts.

---

## 1. Mental model — fences are state, events are transitions

```
fix(device, lat, lon, t)
   │
   ├─ candidate fences ← spatial index prune (don't test all N fences; test the few near the point)
   │
   ├─ for each candidate: inside? = ST_Contains(polygon) | ST_DWithin(center, r)  (with a hysteresis band)
   │
   ├─ feed (device,fence,inside?) into the STATE MACHINE:
   │      OUTSIDE ──enter(stable)──▶ INSIDE ──dwell(Δt)──▶ DWELLING ──exit(stable)──▶ OUTSIDE
   │      (transitions require persistence: N consecutive fixes / T seconds, + hysteresis distance)
   │
   └─ on a real transition → emit ENTER / EXIT / DWELL event (idempotent) → alert pipeline
```

Three layers, each with a job:
1. **Prune** — spatial index turns "test 100k fences" into "test 3."
2. **Classify** — inside/outside with a **buffer band** so the boundary isn't a knife-edge.
3. **Debounce** — only a *persistent* change flips state and emits an event.

---

## 2. Circular vs polygon (DECISION MATRIX)

| Shape | Define by | Eval | Cost | Use when |
|-------|-----------|------|------|----------|
| **Circular** | center + radius | `distance ≤ r` (`ST_DWithin`) | cheapest | Point of interest, "near customer", safe-zone, most cases |
| **Polygon** | vertices | point-in-polygon (`ST_Contains`) | moderate | Real boundaries: neighborhoods, yards, fields, admin zones |
| **Multi-polygon** | many rings | `ST_Contains` | moderate+ | Disjoint areas as one logical fence (a city's depots) |
| **Corridor / route buffer** | line + width | `ST_DWithin(line, pt, w)` | moderate | "Stay on route", pipeline/road monitoring |

Default to **circular** unless the real-world thing is genuinely a shape — circles are cheaper, easier to
explain to users, and immune to "is the boundary too tight" arguments. Reach for polygons when a circle would
include the wrong side of a river/highway.

---

## 3. Device-side vs server-side (the architectural fork)

| | Device-side (OS geofencing) | Server-side (evaluate on ingest) |
|---|------------------------------|----------------------------------|
| **API** | Android `GeofencingClient`, iOS **`CLMonitor`** (iOS 17+) / `startMonitoring` | your pipeline + PostGIS |
| **Power** | **excellent** (OS wakes app on transition; GPS mostly off) | device streams fixes continuously (battery) |
| **Latency** | OS-dependent (can lag minutes; coarse) | as fast as your ingest |
| **Fence count** | **hard limits** (iOS ~**20/app**, Android ~100) | effectively unlimited |
| **Dynamic fences** | clumsy (must reprogram device) | trivial (rows in a table) |
| **Trust** | client-reported (spoofable) | server-authoritative |
| **Best for** | phone apps, battery-critical, few personal fences | fleet/asset platforms, many/dynamic fences, audit/billing |

**Hybrid is the senior answer for phone apps:** let the OS geofence the *few* fences near the user (cheap
wake-ups), then **confirm server-side** before alerting/billing (trust + audit). Hardware-tracker fleets are
almost always **server-side** (trackers stream anyway, and you have hundreds of dynamic fences).

> iOS's **20-region cap** is the constraint that forces hybrid design: you can't push 5,000 fences to a phone.
> Monitor the nearest 20 and swap them as the user moves.

---

## 4. The state machine — kill flapping with hysteresis + debounce

Two independent anti-flap mechanisms, use **both**:
- **Spatial hysteresis (buffer band):** you're "in" once you cross the radius **minus** a margin, and "out"
  only past the radius **plus** a margin. The boundary becomes a band the width of GPS noise, so jitter on the
  edge can't toggle you.
- **Temporal debounce (persistence):** a candidate transition must hold for **N consecutive fixes** or **T
  seconds** before it's real. One stray multipath fix across the line is ignored.

```ts
// geofence-fsm.ts — per (device,fence) state with hysteresis + persistence + dwell.
type Phase = "OUTSIDE" | "ENTERING" | "INSIDE" | "DWELLING" | "EXITING";
export type GeoEvent = { kind: "ENTER" | "EXIT" | "DWELL"; deviceId: string; fenceId: string; at: number };

interface FenceCfg {
  radiusM: number;           // for circular fences (polygon: pass a signed-distance fn instead)
  hysteresisM: number;       // buffer band (e.g. 25 m) — ~ GPS accuracy you expect
  enterFixes: number;        // persistence to confirm enter (e.g. 2)
  exitFixes: number;         // persistence to confirm exit (e.g. 3 — exit is costlier to get wrong)
  dwellMs: number;           // time inside before DWELL fires (e.g. 300_000 = 5 min)
}

interface St { phase: Phase; streak: number; insideSince: number; dwelled: boolean }

export function step(
  st: St | undefined, cfg: FenceCfg, distM: number, accuracyM: number, t: number,
): { st: St; event?: GeoEvent["kind"] } {
  st ??= { phase: "OUTSIDE", streak: 0, insideSince: 0, dwelled: false };

  // Reject fixes too noisy to decide a boundary crossing (don't let a 200 m fix flip a 25 m band).
  if (accuracyM > cfg.hysteresisM * 3) return { st };

  // Hysteresis: asymmetric thresholds. "in" earlier, "out" later → a dead band over the boundary.
  const inThreshold = cfg.radiusM - cfg.hysteresisM;
  const outThreshold = cfg.radiusM + cfg.hysteresisM;
  const insideNow = st.phase === "INSIDE" || st.phase === "DWELLING" || st.phase === "ENTERING"
    ? distM <= outThreshold        // already in: only "out" past the OUTER ring
    : distM <= inThreshold;        // currently out: only "in" past the INNER ring

  switch (st.phase) {
    case "OUTSIDE":
      if (insideNow) { st.streak++; if (st.streak >= cfg.enterFixes) {
        return { st: { phase: "INSIDE", streak: 0, insideSince: t, dwelled: false }, event: "ENTER" }; } }
      else st.streak = 0;
      return { st };

    case "INSIDE":
    case "DWELLING":
      if (!insideNow) { st.streak++; if (st.streak >= cfg.exitFixes) {
        return { st: { phase: "OUTSIDE", streak: 0, insideSince: 0, dwelled: false }, event: "EXIT" }; } }
      else {
        st.streak = 0;
        if (!st.dwelled && t - st.insideSince >= cfg.dwellMs) {
          return { st: { ...st, phase: "DWELLING", dwelled: true }, event: "DWELL" }; }
      }
      return { st };
    default:
      return { st };
  }
}
```

Tune `hysteresisM` to your expected GPS accuracy (urban ~25–50 m; open ~10 m). Make **exit harder than enter**
(`exitFixes > enterFixes`) — a spurious EXIT (then ENTER) is the noisiest, most expensive false pair.

---

## 5. PostGIS evaluation — prune then test

Store fences as `geometry`/`geography`, **GiST-indexed**, and let the index find candidates. Never scan all fences.

```sql
-- Fences: circular stored as center+radius; polygon stored as geography for metre-true tests.
CREATE TABLE geofence (
  id           bigint PRIMARY KEY,
  org_id       bigint NOT NULL,
  kind         text   NOT NULL CHECK (kind IN ('circle','polygon')),
  center       geography(Point,4326),       -- circle
  radius_m     double precision,            -- circle
  area         geography(Polygon,4326),     -- polygon
  active       boolean NOT NULL DEFAULT true
);
CREATE INDEX ON geofence USING gist (center);
CREATE INDEX ON geofence USING gist (area);

-- Which ACTIVE fences contain / surround this fix? Index prunes to nearby candidates first.
-- :pt is geography(Point,4326) = ST_MakePoint(:lon,:lat)::geography  (lng FIRST)
SELECT id, kind
FROM geofence
WHERE org_id = :org AND active
  AND (
    (kind = 'circle'  AND ST_DWithin(center, :pt, radius_m))   -- metres, uses GiST on center
    OR
    (kind = 'polygon' AND ST_Intersects(area, :pt))            -- point in polygon, uses GiST on area
  );
```

Two rules that decide whether this is fast or a seq scan: **(1)** keep the column and the literal the **same
type** (`geography` vs `geometry`) so the GiST index is used; **(2)** use `ST_DWithin`/`ST_Intersects` (index-
assisted), **never** `ST_Distance(...) < r` in `WHERE` (computes distance to every row → seq scan). Full
index/perf treatment lives in `geospatial-data-postgis`.

> For very high throughput, do the **hysteresis band in SQL too**: test `ST_DWithin(center, :pt, radius_m +
> :hysteresis)` for the "still inside" check and `radius_m - :hysteresis` for the "now inside" check, mirroring
> the FSM thresholds so DB and app agree.

---

## 6. Idempotent event pipeline — alert once, exactly

The event *emission* must be idempotent so retries, replays, and at-least-once queues don't double-alert.

```sql
-- One row per real transition. Unique key prevents duplicates from reprocessing the same crossing.
CREATE TABLE geofence_event (
  id           bigint GENERATED ALWAYS AS IDENTITY,
  device_id    bigint NOT NULL,
  fence_id     bigint NOT NULL,
  kind         text   NOT NULL CHECK (kind IN ('ENTER','EXIT','DWELL')),
  occurred_at  timestamptz NOT NULL,         -- the FIX time, not now()
  transition_seq bigint NOT NULL,            -- monotonic per (device,fence); the crossing # 
  PRIMARY KEY (id),
  UNIQUE (device_id, fence_id, kind, transition_seq)   -- idempotency anchor
);

-- Emit; ON CONFLICT DO NOTHING makes re-delivery / replay safe.
INSERT INTO geofence_event (device_id, fence_id, kind, occurred_at, transition_seq)
VALUES (:dev, :fence, :kind, :fixTime, :seq)
ON CONFLICT (device_id, fence_id, kind, transition_seq) DO NOTHING
RETURNING id;   -- NULL/no row → already emitted → DON'T alert again
```

Pipeline shape: `fix → FSM (state in Redis/row) → on transition, INSERT … ON CONFLICT → only if inserted,
enqueue notification`. Decouple **detection** from **notification** (a queue) so a slow SMS provider can't back
up ingestion, and so you can re-drive notifications without re-detecting. Use `occurred_at = fix time` (for
correct ordering when fixes arrive late/out of order), not wall-clock.

---

## 7. Edge cases & gotchas

- **Boundary flapping** — solved by §4 (hysteresis + persistence). The #1 reason geofencing "doesn't work."
- **Teleport/outlier fix** crossing a fence then snapping back — persistence (`enterFixes ≥ 2`) absorbs it.
- **Big sampling gaps** (tunnel, sleep) — device may jump *through* a fence between fixes: you'll see it
  already inside/outside with no crossing. Decide policy: infer a synthetic ENTER on first-seen-inside, or
  require a real crossing. For thin fences and slow sampling, you can **miss** a pass entirely — size sampling
  to fence size and speed.
- **Out-of-order/late fixes** — process by `fix time`; a naive "latest wins" reorders transitions. Buffer a
  short reorder window or carry `transition_seq`.
- **Overlapping fences** — a fix can be in many at once; evaluate **all** candidates, keep independent state per fence.
- **Polygon dateline / poles / self-intersection** — validate geometry (`ST_IsValid`); use `geography` for
  metre-true distance near edges.
- **DST/timezone** for time-windowed fences ("no entry 22:00–06:00") — evaluate in the fence's local tz.

---

## 8. Performance & scale (many fences × many devices)

- **Prune with the spatial index** (§5): O(candidates) not O(all fences). With a GiST index, "which of 1M
  fences contain this point" is milliseconds.
- **Hot per-(device,fence) state** lives in **Redis** (or in-memory keyed by `device:fence`), not a DB round-
  trip per fix. Persist transitions only.
- **Partition the work by org/region**; shard the FSM by `device_id` so a device's fixes are processed in
  order on one worker (ordering matters for transitions).
- **Bound candidate fan-out:** a fix near 10,000 overlapping fences is pathological — cap, or pre-aggregate
  zones. Most fixes hit 0–3 fences.
- **Coalesce DWELL timers** rather than scanning all inside-states every second; schedule a per-state timer.

---

## 9. Security & privacy

- Geofence membership reveals presence ("was at the clinic / competitor / home") — it's **sensitive PII +
  inference**. Restrict who can create fences over sensitive places and who sees events; log access.
- Server-side authority for anything that matters (attendance, billing, unlock) — **never trust a device's
  self-reported ENTER** without server confirmation; client position is spoofable (mock-location apps).
- Rate-limit/alert-fatigue protection isn't just UX: a flapping fence can be **weaponized** to drain SMS budget
  or DoS responders. Hysteresis + per-fence alert caps are a security control too.

---

## 10. Testing — synthetic crossings & replay

- **Unit-test the FSM** with crafted distance/accuracy/time sequences: clean enter, jitter on the boundary
  (must NOT flap), single outlier (must absorb), dwell timing, hard exit, big gap. This is the highest-ROI test set.
- **Replay GPX traces** through the whole pipeline; assert the exact event sequence (and *count* — flapping
  shows up as too many events).
- Property test: feeding the same trace twice produces the **same events, emitted once** (idempotency).

---

## 11. Observability

- **Events per fence per hour** and **enter/exit pairing ratio** — a fence emitting 100s of pairs/hour is
  flapping; auto-flag it.
- Alert-send count vs transition count (should match after idempotency), notification latency, FSM state-store
  hit rate, candidate fan-out p95.
- Per device: missed-crossing estimates (saw inside without an ENTER) to tune sampling rate.

---

## 12. Accessibility & i18n

- Localize event copy and place names; render times in the **recipient's** timezone with clear tz labels.
- Alert channels should respect accessibility (don't rely on color alone in maps; provide text "Truck 12
  entered Depot A at 14:03"). Support RTL. Let users set quiet hours / channel preferences to fight fatigue.

---

## 13. Opinionated anti-patterns

- ❌ Alerting on a **per-fix boolean** (`inside?`) instead of a debounced **transition** → flapping hell.
- ❌ No hysteresis band → the boundary is a knife-edge and GPS jitter toggles it.
- ❌ Symmetric enter/exit sensitivity → noisy EXIT/ENTER pairs (make exit harder).
- ❌ `ST_Distance(...) < r` in `WHERE` → full table scan; use `ST_DWithin`.
- ❌ Mixing `geometry`/`geography` types so the GiST index is silently bypassed.
- ❌ No idempotency key → retries/replays double-alert (and double-bill SMS).
- ❌ Trusting client-side ENTER for billing/attendance without server confirmation.
- ❌ Pushing thousands of fences to a phone (iOS caps at ~20) instead of hybrid nearest-N.
- ❌ Using wall-clock instead of fix time → out-of-order fixes scramble transition order.

## 14. Agent checklist

```
- [ ] Events are transitions from a per-(device,fence) state machine, not per-fix booleans
- [ ] Hysteresis band (~expected GPS accuracy) + persistence (N fixes / T s); exit harder than enter
- [ ] Noisy fixes (accuracy ≫ band) rejected from boundary decisions
- [ ] Candidate fences pruned via GiST index; ST_DWithin/ST_Intersects (never ST_Distance in WHERE)
- [ ] geometry/geography types consistent so the index is used
- [ ] Events idempotent (unique device,fence,kind,transition_seq; ON CONFLICT DO NOTHING)
- [ ] Detection decoupled from notification via a queue; occurred_at = fix time
- [ ] Device-side vs server-side chosen deliberately (hybrid nearest-N for phones; server for fleets)
- [ ] Hot state in Redis/memory sharded by device; transitions persisted
- [ ] FSM unit tests (jitter/outlier/gap/dwell) + GPX replay assert exact event count; idempotency property test
- [ ] Flapping fences auto-flagged; per-fence alert caps; events = sensitive PII, access controlled
```

## 15. References (2026-current)
- PostGIS ST_DWithin: https://postgis.net/docs/ST_DWithin.html · ST_Intersects: https://postgis.net/docs/ST_Intersects.html
- Android Geofencing: https://developer.android.com/develop/sensors-and-location/location/geofencing
- iOS CLMonitor (WWDC23 "Meet Core Location Monitor"): https://developer.apple.com/videos/play/wwdc2023/10147/

## Related
`geospatial-data-postgis` (indexes/queries), `web-mobile-geolocation` (device geofencing APIs),
`fleet-asset-tracking-platform` (events in the platform), `ride-hailing-maps-master` (drawing fences on a map)
