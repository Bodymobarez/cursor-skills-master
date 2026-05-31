---
name: mapping-system
description: >-
  Build a travel mapping/deduplication system. Use to match the same hotel,
  room type, board, and content across multiple suppliers (bed banks/GDS) into
  one canonical entity. Covers property mapping, room mapping, GIATA/master IDs,
  fuzzy matching, geocode/name/address matching, and confidence/QA workflow.
---

# Mapping System (hotel / room / content)

The hardest problem in hotel aggregation: **the same hotel and room come from many suppliers with
different IDs, names, and room descriptions.** Mapping unifies them into one canonical entity so
search can dedupe and pick the best price.

## Layers of mapping

```
1. PROPERTY mapping  — Supplier hotel ID  → canonical hotelId  (one real hotel = many supplier IDs)
2. ROOM mapping      — Supplier room name → canonical roomType (e.g. "DBL STD" ≈ "Standard Double")
3. BOARD mapping     — Supplier board code → enum (RO/BB/HB/FB/AI)
4. CONTENT mapping   — merge descriptions/photos/amenities/geo from best source
```

## Property mapping (match the same hotel)

Combine signals → confidence score:
- **GIATA ID** (industry hotel master) or supplier-provided master codes → strongest signal.
- **Geo distance** (haversine on lat/lng) within a tight radius.
- **Name similarity** (normalized: strip "hotel", accents, casing; token-set ratio / Jaro-Winkler).
- **Address / postal / city** similarity; phone; chain code.

```
score = w1*name_sim + w2*geo_proximity + w3*address_sim + w4*(giata_match?1:0)
auto-accept ≥ 0.92 · queue 0.75–0.92 for human review · reject < 0.75
```

## Room mapping (match room types)
- Normalize room names: extract **room category** (Standard/Deluxe/Suite), **bed type**
  (Double/Twin/King), **view**, **occupancy**, **smoking**.
- Build a synonym/abbreviation dictionary (DBL→Double, STD→Standard, SGL→Single).
- Match on (category + bed + occupancy); board comes from the rate, not the room name.

## Architecture

```
supplier feeds → normalize → candidate matching (blocking by geo/city) →
score → auto-map (high) / review queue (medium) / reject (low) →
canonical master + mapping table (canonicalId ↔ {supplier, supplierId})
```
- **Blocking**: only compare hotels in the same city/geocell (don't compare all-vs-all).
- Store every mapping with **source, confidence, mapped_by (auto/human), timestamp**.
- **Feedback loop**: human corrections retrain thresholds/dictionaries.

## QA & maintenance
- Review queue UI: side-by-side candidates with photos/geo/address.
- Detect & merge duplicates in your own master; split wrong merges.
- Re-run mapping when suppliers add/replace inventory; track unmapped %.
- Metrics: mapping coverage, auto-map rate, false-merge rate.

## Checklist
```
- [ ] Canonical master entities (hotel, roomType) + mapping tables to supplier IDs
- [ ] Normalization (name/address/room) + synonym dictionaries
- [ ] Blocking by geo/city; scored matching (name+geo+address+GIATA)
- [ ] Auto/review/reject thresholds + human review queue
- [ ] Board-code enum mapping; content merge (best source per field)
- [ ] Confidence + provenance stored per mapping; audit
- [ ] Coverage/quality metrics + re-mapping on feed updates
```

## Anti-patterns
- Matching only by name (typos/duplicates/chains break it) — combine geo + address + name.
- All-vs-all comparison without blocking (doesn't scale).
- Auto-merging low-confidence matches → wrong hotel shown/booked.
- Treating board as part of the room name instead of the rate.
- No human-review queue or provenance → impossible to debug bad maps.
