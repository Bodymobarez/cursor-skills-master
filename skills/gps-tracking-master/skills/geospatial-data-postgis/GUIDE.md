---
name: geospatial-data-postgis
description: >-
  PostGIS for location data at staff depth: geometry vs geography (and when to cast), GiST indexing that
  actually gets used, index-assisted KNN with the <-> operator, ST_DWithin radius search (never ST_Distance
  in WHERE), trajectory storage (points vs LINESTRING), time-series partitioning/Timescale, ST_ClusterDBSCAN,
  and reading EXPLAIN ANALYZE to prove the index is hit. The query patterns the rest of GPS tracking depends on.
---

# Geospatial Data & PostGIS — Store, Index, Query at Scale

**90% of PostGIS performance is one rule: filter with an index-assisted spatial operator on a type-matched,
GiST-indexed column — and prove it with `EXPLAIN`.** The other 10% is choosing geometry vs geography and
storing trajectories sanely. Almost every "PostGIS is slow" ticket is a `ST_Distance(...) < r` in a `WHERE`
clause doing a sequential scan over millions of rows, or a `geography`/`geometry` type mismatch quietly
bypassing the index.

This is the storage/query foundation that `geofencing-events`, `fleet-asset-tracking-platform`, and any
"nearby/within/along" feature stand on.

---

## When to use this skill / when NOT

**Use it when** you design schemas or write queries for spatial data: nearest-N, radius search, point-in-
polygon, trajectory storage, spatial joins, map-viewport (bbox) queries, clustering, spatial analytics.

**Do NOT** use it for: map *rendering* / tiles (`ride-hailing-maps-master` / `backend-api-master` gis-maps),
geofence event *logic* (`geofencing-events` — it uses these queries but adds state), or pipeline architecture
(`fleet-asset-tracking-platform`). This skill is the **SQL + indexing + EXPLAIN** craft.

---

## 1. Mental model — bbox prune, then exact

```
Spatial query = (1) cheap bounding-box filter via GiST index  →  (2) exact geometry test on survivors
   ST_DWithin / ST_Intersects / && do (1)+(2) for you and USE the index.
   ST_Distance / ST_Contains alone in WHERE skip (1) → seq scan → slow.
```

PostGIS stores a **bounding box** with every geometry; the **GiST** index is an R-tree over those boxes. The
`&&` "bbox overlaps" operator and the functions built on it (`ST_DWithin`, `ST_Intersects`) let the planner
eliminate almost everything by box before running expensive exact math on the handful that survive. Your job
is to write queries that let it do that — and to confirm with `EXPLAIN ANALYZE` that a `Seq Scan` didn't sneak in.

---

## 2. geometry vs geography (DECISION MATRIX)

| | `geometry` | `geography` |
|---|-----------|-------------|
| Model | planar (flat) | spheroidal (WGS84, Earth-aware) |
| Distance/area units | **SRS units** (degrees for 4326! metres for 3857) | **always metres** |
| Speed | **fast** | slower (real spheroid math) |
| Function coverage | huge | subset (the common ones) |
| Long distances / global | wrong unless projected | correct everywhere |
| Best for | local data, KNN/cluster math, projected (3857) work | "within X metres" on lat/lon, global datasets, areas |

The trap: a `geometry(Point,4326)` distance is in **degrees**, not metres — `ST_DWithin(geom, pt, 1000)` on
4326 means "1000 **degrees**", i.e. the whole planet. Three valid strategies:
- **Store `geography(Point,4326)`** → `ST_DWithin(..., 500)` is "500 m". Simplest for tracking; slightly slower.
- **Store `geometry(Point,4326)`** and **cast to geography** for metre tests: `ST_DWithin(geom::geography, pt::geography, 500)`.
- **Store/transform to a metric projection** (e.g. local UTM or 3857) and use `geometry` directly — fastest
  for heavy KNN/clustering in a local area.

> Senior pattern for big global tables: keep a `geometry(Point,4326)` **plus** a generated `geography` column,
> index both, and query the type that matches the operation. Don't cast inside `WHERE` on a column that's only
> indexed as the *other* type — the cast happens before the lookup and the index won't be used.

---

## 3. Schema + indexes that get used

```sql
CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TABLE place (
  id    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name  text,
  geom  geometry(Point,4326) NOT NULL,                  -- store lng/lat (SRID 4326)
  geog  geography(Point,4326) GENERATED ALWAYS AS (geom::geography) STORED
);
-- Index BOTH; query the one matching your operation.
CREATE INDEX place_geom_gix ON place USING gist (geom);
CREATE INDEX place_geog_gix ON place USING gist (geog);

-- Composite for "this org's places near a point": equality col(s) + spatial works well.
CREATE INDEX place_org_geog_gix ON place USING gist (org_id, geog);
```

- **Always create a GiST index** on any column you filter/join spatially. No index = `Seq Scan` = death at scale.
- `ST_MakePoint(lng, lat)` — **longitude first** (GeoJSON/PostGIS order); the classic bug is swapping them and
  landing on the wrong continent. Wrap with `ST_SetSRID(ST_MakePoint(lng,lat), 4326)`.
- For polygons, the same GiST index serves `ST_Intersects`/`ST_Contains`. Run `ST_IsValid`/`ST_MakeValid` on
  user-drawn polygons.
- **SP-GiST** is an alternative for points (sometimes smaller/faster for uniform point clouds); benchmark, but
  GiST is the safe default. BRIN can help **append-only time-ordered** fix tables on the *time* column.

---

## 4. The four query patterns you'll write constantly

### Radius search — `ST_DWithin` (index-assisted; NEVER `ST_Distance` in WHERE)
```sql
-- "places within 500 m of me" — uses place_geog_gix
SELECT id, name, ST_Distance(geog, :pt) AS dist_m   -- ST_Distance only in SELECT, for display/sort
FROM place
WHERE ST_DWithin(geog, :pt, 500)                     -- :pt = ST_MakePoint(:lng,:lat)::geography
ORDER BY dist_m
LIMIT 50;
```
`ST_DWithin` includes the bbox `&&` prune, so the GiST index does the heavy lifting. `WHERE ST_Distance(geog,:pt) < 500`
computes distance to **every row** then filters — seq scan. This single swap is the most common 100×–1000× win.

### Nearest-N — the `<->` KNN operator (index-assisted ONLY in `ORDER BY`)
```sql
-- 5 nearest places — true KNN via GiST when <-> is in ORDER BY and compared to a CONSTANT
SELECT id, name, geom <-> :pt_geom AS d
FROM place
ORDER BY geom <-> :pt_geom        -- index walks the R-tree nearest-first; no full distance computation
LIMIT 5;
```
`<->` is the *only* operator that uses the spatial index from `ORDER BY` (true KNN since PostgreSQL 9.5 /
PostGIS 2.2). For `geography`, KNN is sphere-based. Keep the right-hand side a **constant/parameter** (not a
correlated subquery) or the index won't engage. Combine with `ST_DWithin` when you want "nearest **and** within X".

### Point-in-polygon / spatial join — `ST_Intersects` / `ST_Contains`
```sql
-- which zone is each recent fix in? (spatial join; GiST on zone.geom)
SELECT f.id, z.name
FROM fix f
JOIN zone z ON ST_Intersects(z.geom, f.geom)         -- index-assisted
WHERE f.ts > now() - interval '1 hour';
```

### Map viewport (bbox) — `&&` with `ST_MakeEnvelope`
```sql
-- features visible in the current map window — pure bbox, very fast
SELECT id, name FROM place
WHERE geom && ST_MakeEnvelope(:minlng,:minlat,:maxlng,:maxlat, 4326)
LIMIT 5000;                                          -- cap; thin by zoom (see clustering)
```

---

## 5. Trajectory storage — points vs LINESTRING (DECISION MATRIX)

| Approach | Store | Pros | Cons | Use when |
|----------|-------|------|------|----------|
| **Point rows** (one per fix) | `fix(vehicle,ts,geom)` partitioned | query any window, spatial-index points, recompute anything | huge row count | the **raw** firehose, analytics, "where at time T" |
| **LINESTRING per trip** | `trip(path geometry(LineString,4326))` | one row per trip, cheap to render/measure (`ST_Length`) | can't query a single mid-trip point easily | **derived** history rendering, trip length/extent |
| **M-coordinate LINESTRING(ZM)** | line with measure = timestamp | time-aware geometry (`ST_LocateAlong`) | more complex | interpolate position at time along a path |

Senior pattern (matches `fleet-asset-tracking-platform`): **raw fixes as partitioned point rows** (write-
optimized, expiring) **+ derived trip LINESTRINGs** (durable, render-cheap). Build the line at trip end with
`ST_MakeLine(geom ORDER BY ts)` and **simplify** it (`ST_SimplifyVW`/Douglas-Peucker) for storage/rendering —
a history replay doesn't need 1 Hz vertices.

```sql
-- build a simplified trip line from ordered fixes
INSERT INTO trip (vehicle_id, started_at, ended_at, path, distance_m)
SELECT :veh, min(ts), max(ts),
       ST_SimplifyVW(ST_MakeLine(geom ORDER BY ts), 0.000005),   -- tolerance in degrees for 4326
       ST_Length(ST_MakeLine(geom ORDER BY ts)::geography)        -- metres
FROM fix WHERE vehicle_id = :veh AND ts BETWEEN :start AND :end;
```

---

## 6. Time-series partitioning (fixes are time-series + spatial)

Tracking fix tables are **both** — partition by time, index by space.
- **TimescaleDB hypertable** (`create_hypertable('fix','ts')`) or native **declarative partitioning** by day/
  week. Writes hit the newest chunk; time-bounded history queries prune to a few chunks; **drop old partitions**
  to expire raw data instantly (no `DELETE` bloat/vacuum storm).
- GiST on `geom` **per chunk/partition** (Timescale propagates indexes to chunks).
- Timescale **continuous aggregates** for downsampled tracks; **native compression** (often 90%+ on telematics).
- Composite/covering indexes for the dominant access path: `(vehicle_id, ts DESC)` for "last N fixes / window."

---

## 7. Clustering & analytics

```sql
-- DBSCAN spatial clustering (window function): group nearby stops/incidents.
-- eps in the geometry's units → use a metric projection (3857) or pre-cast; minpoints = density threshold.
SELECT id, ST_ClusterDBSCAN(ST_Transform(geom,3857), eps := 50, minpoints := 5) OVER () AS cluster_id
FROM incident;
```
- `ST_ClusterDBSCAN` (density), `ST_ClusterKMeans` (k groups) for hot-spot/zone discovery. Note `eps` is in the
  geometry's **units** — project to metres first (3857/UTM) so `eps := 50` means 50 m.
- For server-side **map clustering** by zoom, snap points to a grid (`ST_SnapToGrid`) or use H3/geohash buckets;
  for client-side, Supercluster (`ride-hailing-maps-master`).

---

## 8. Reading EXPLAIN — prove the index is used

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT id FROM place WHERE ST_DWithin(geog, :pt, 500);
```
- ✅ Want: `Index Scan using place_geog_gix` (or `Bitmap Index Scan`). 
- ❌ Red flag: `Seq Scan on place` with a big `rows removed by filter` → your predicate isn't index-assisted
  (you used `ST_Distance` in `WHERE`, mismatched the indexed type, cast in `WHERE`, or the index is missing).
- `<->` KNN should show the GiST index feeding an ordered scan with a small `LIMIT`. If KNN seq-scans, the RHS
  isn't a constant.
- Run **`ANALYZE`** after big loads so the planner has stats; `VACUUM` to keep visibility maps fresh.
- **`CLUSTER`** the table on the GiST index to physically co-locate spatially-near rows — a real win for
  range/KNN on large static tables (one user cut a query from 4 s → 20 ms this way). Re-CLUSTER periodically.

---

## 9. Edge cases & gotchas

- **Degrees-as-metres** (geometry 4326 distance) — the cardinal PostGIS bug; cast to geography or project.
- **lng/lat vs lat/lng** swap — wrong hemisphere; standardize on `ST_MakePoint(lng,lat)`.
- **SRID mismatch** — operating on mixed SRIDs errors or gives nonsense; enforce a typmod (`geometry(Point,4326)`).
- **`(0,0)` Null Island** fixes pollute every bbox/extent — reject at ingest (`gps-gnss-fundamentals`).
- **Invalid polygons** (self-intersection) — `ST_IsValid`/`ST_MakeValid` before storing user-drawn fences.
- **Antimeridian (±180°) & poles** — bbox/line math breaks; use geography and split geometries crossing 180°.
- **Cast in `WHERE` bypassing index** — `WHERE ST_DWithin(geom::geography, …)` won't use a `geometry` GiST; index
  the `geography` (generated column) and query that.
- **Huge `IN`/no `LIMIT` viewport queries** — always cap rows and thin by zoom.

---

## 10. Performance & scale

- **Index everything you filter/join spatially** (GiST); add **composite** indexes (`org_id`+geog, `vehicle_id`+ts)
  for the real access paths, not just the geometry alone.
- **Bulk load** with `COPY`; `ANALYZE` after; consider building indexes after a big initial load.
- **Materialized views** for expensive recurring spatial joins (e.g. "fixes→zone" rollups); refresh on schedule.
- Partition/compress time-series fixes (§6); keep derived tables small and hot.
- Connection pool (PgBouncer) for high-concurrency tracking ingest; keep transactions short.

---

## 11. Security & privacy

- Coordinates are **PII**; enforce tenant isolation with **Row-Level Security** (`org_id` policies) so a tenant
  physically cannot read another's geometry, even via a query bug.
- **Parameterize** spatial predicates (`:pt`) — building WKT/SQL by string concat invites injection.
- **Retention by partition drop** (privacy + cost); least-privilege DB roles (analytics = read-only on derived,
  no raw-fix access). Encrypt at rest; restrict `pg_dump` of location tables.

---

## 12. Testing

- Seed known geometries with **known distances** and assert `ST_DWithin`/`<->`/`ST_Distance` return expected
  metres (catches geometry-vs-geography unit bugs).
- **`EXPLAIN` assertions** in CI for hot queries: fail the build if a plan shows `Seq Scan` on the big table
  (cheap guard against a refactor that drops index usage).
- Test antimeridian, pole, invalid-polygon, SRID-mismatch, and `(0,0)` cases explicitly.
- Load-test KNN/radius at production row counts (millions+), not on a 1k-row dev table where everything is fast.

---

## 13. Observability

- `pg_stat_statements` for slowest spatial queries; watch for plans regressing to `Seq Scan` after data growth
  or a missing `ANALYZE`.
- Index bloat & size (`pg_stat_user_indexes`, `pgstattuple`), chunk sizes & compression ratios (Timescale),
  partition pruning effectiveness.
- Cache hit ratio on spatial indexes; KNN/radius p95 latency; rows-scanned vs rows-returned ratio.

---

## 14. Accessibility & i18n

- Geometry is locale-neutral, but **outputs** aren't: format distances/areas per locale & unit system, render
  coordinates as DMS or decimal per user, support RTL in any tabular geo output.
- Place names / addresses returned from geocoding are i18n-sensitive — store original + localized, encode UTF-8.

---

## 15. Opinionated anti-patterns

- ❌ `ST_Distance(geom, :pt) < r` in `WHERE` → seq scan. Use `ST_DWithin`.
- ❌ `geometry(Point,4326)` distances treated as metres (they're **degrees**) → cast to geography or project.
- ❌ No GiST index on a spatially-filtered column.
- ❌ Casting to the non-indexed type inside `WHERE` (index bypassed).
- ❌ `lat,lng` instead of `lng,lat` in `ST_MakePoint`.
- ❌ KNN with `<->` against a subquery instead of a constant (no index).
- ❌ Storing every raw fix forever in one un-partitioned table; never simplifying trip lines.
- ❌ Shipping a query without checking `EXPLAIN` at production scale.
- ❌ Storing `(0,0)` / invalid polygons / mixed SRIDs.

## 16. Agent checklist

```
- [ ] geometry vs geography chosen deliberately; metre tests use geography or a metric projection
- [ ] GiST index on every spatially-filtered/joined column; composite indexes for real access paths
- [ ] Radius via ST_DWithin (never ST_Distance in WHERE); ST_Distance only in SELECT/ORDER BY
- [ ] Nearest-N via <-> in ORDER BY against a constant; viewport via && ST_MakeEnvelope with a LIMIT
- [ ] lng,lat order (ST_MakePoint); SRID 4326 enforced via typmod; polygons validated
- [ ] Raw fixes partitioned/hypertable by time + space-indexed; trips stored as simplified LINESTRINGs
- [ ] Old partitions dropped/compressed for retention + cost
- [ ] EXPLAIN (ANALYZE) confirms Index/Bitmap scan, not Seq Scan, at production row counts
- [ ] RLS tenant isolation; parameterized predicates; least-privilege roles; coordinates = PII
- [ ] CI EXPLAIN guard + known-distance unit tests + edge cases (antimeridian/poles/invalid/SRID/(0,0))
```

## References (2026-current)
- PostGIS manual: https://postgis.net/docs/ · ST_DWithin: https://postgis.net/docs/ST_DWithin.html
- KNN `<->`: https://postgis.net/docs/geometry_distance_knn.html · ST_ClusterDBSCAN: https://postgis.net/docs/ST_ClusterDBSCAN.html
- TimescaleDB: https://docs.tigerdata.com/ · PostgreSQL EXPLAIN: https://www.postgresql.org/docs/current/using-explain.html

## Related
`device-integration-protocols` (what gets stored), `fleet-asset-tracking-platform` (pipeline using these queries),
`geofencing-events` (ST_Contains/ST_DWithin in anger), `ride-hailing-maps-master` (rendering the results), `backend-api-master` (gis-maps)
