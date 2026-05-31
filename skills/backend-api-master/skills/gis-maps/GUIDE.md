---
name: gis-maps
description: >-
  Build GIS and interactive maps. Use for map UIs, geospatial data, markers/
  clustering, heatmaps, choropleths, polygons/drawing, routing/directions, geocoding,
  tiles/vector tiles, and spatial queries. Covers map libraries, PostGIS, GeoJSON,
  performance, and visualization.
---

# GIS & Interactive Maps

Render maps, visualize geospatial data, and run spatial queries.

## Map library — pick one

| Library | Strength |
|---------|----------|
| **MapLibre GL** | Open-source vector tiles, fast, no vendor lock (fork of Mapbox GL) |
| **Mapbox GL JS** | Polished, great styles/3D (paid tiles) |
| **Leaflet** | Lightweight, huge plugin ecosystem, raster-first |
| **deck.gl** | Big-data layers (millions of points), WebGL, pairs with MapLibre |
| **OpenLayers** | Heavy-duty GIS (projections, WMS/WFS) |

Default for modern apps: **MapLibre GL + free/own tiles**; add **deck.gl** for large datasets.

## Data format: GeoJSON

```json
{ "type":"FeatureCollection", "features":[
  { "type":"Feature", "properties":{"name":"Store"},
    "geometry":{"type":"Point","coordinates":[31.2357,30.0444]} } ] }
```
> GeoJSON is **[lng, lat]** order. Use SRID 4326. For large/static layers serve **vector tiles**
> (`.pbf` / `pmtiles`) instead of giant GeoJSON.

## Common visualizations
- **Markers + clustering** (Supercluster) for many points.
- **Heatmap** for density.
- **Choropleth** (color regions by value — join polygons to data).
- **Lines/routes** (trips, GPS trails from `gps-integration`).
- **Drawing/editing** polygons (mapbox-gl-draw) for geofences/territories.

## Backend: PostGIS spatial queries

```sql
-- points inside a polygon
SELECT * FROM stores s, regions r
WHERE r.name = :region AND ST_Contains(r.geom, s.geom);
-- features in current map viewport (bbox)
SELECT * FROM features
WHERE geom && ST_MakeEnvelope(:minlng,:minlat,:maxlng,:maxlat, 4326);
```
Always add a **GiST index** on geometry; query by **bounding box** for the visible viewport.

## Services
- **Geocoding / reverse**: Nominatim (OSM), Mapbox, Google.
- **Routing / directions / isochrones**: OSRM, Valhalla, Mapbox, Google Directions.
- **Tiles**: self-host (TileServer GL, PMTiles on object storage/CDN) or a provider.

## Performance checklist
```
- [ ] Vector tiles / PMTiles for large or static layers (not megabyte GeoJSON)
- [ ] Cluster points; simplify polygons (ST_Simplify) per zoom level
- [ ] Server returns only viewport bbox features; GiST index on geom
- [ ] deck.gl/WebGL for >50k features
- [ ] Debounce map `moveend` before refetching
- [ ] Lazy-load the map library (it's heavy)
```

## Anti-patterns
- Loading a huge GeoJSON into Leaflet and wondering why it's slow (use tiles/clustering).
- Mixing up lat/lng order (GeoJSON is lng,lat; many APIs are lat,lng).
- No spatial index; filtering in app code instead of PostGIS.
- Hard-coding a single tile/geocode provider with no fallback or attribution.
