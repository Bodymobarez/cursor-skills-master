---
name: mapping-system
description: >-
  Build a hotel/room mapping & deduplication system at staff/principal depth — match the same
  property, room, and board across many suppliers (bed banks/GDS) into one canonical entity so search
  can dedupe and pick the best price. Ships GIATA Multicodes/Room-Mapping integration, a real blocking+
  weighted-scoring matcher (normalize → haversine geo → Jaro-Winkler/token-set name → address), auto/
  review/reject thresholds, room-attribute parsing that ignores rate modifiers, a human-review queue
  with provenance, false-merge defense, and coverage/quality metrics. The book always uses the supplier code.
---

# Mapping System (hotel / room / content)

**Mandate: a wrong merge is worse than no merge — book the supplier's original code, never your canonical
id.** The hardest problem in hotel aggregation is that the same hotel and room arrive from dozens of
suppliers with different ids, names, languages, and descriptions. Mapping unifies them so you can dedupe and
price-compare. But a false merge shows or books the *wrong hotel* — so high-confidence auto-maps, a
human-review band for the rest, and full provenance are not optional.

## When to use this skill
- Aggregating multiple hotel suppliers and seeing the same property/room duplicated in results.
- Building property dedupe, room-type normalization, or a mapping review/QA workflow.
- **Not** the place to call supplier search/book (that's `supplier-api-integration`) — mapping runs *between*
  fan-out and ranking, on the normalized offers.

## Layers of mapping

```
1. PROPERTY  Supplier hotel id  → canonical hotelId   (one real hotel = many supplier ids)
2. ROOM      Supplier room name → canonical roomType  ("DBL STD" ≈ "Standard Double")
3. BOARD     Supplier board code→ enum (RO/BB/HB/FB/AI)   — comes from the RATE, not the room name
4. CONTENT   merge descriptions/photos/amenities/geo, best-source per field
```

## DECISION MATRIX — build vs buy

| Option | What | When | Trade-off |
|--------|------|------|-----------|
| **GIATA Multicodes** | Industry hotel master: unique **GIATA ID** mapped to 600+ suppliers' codes (~1.2M properties, 124M booking codes) | You integrate mainstream bed banks; want instant coverage | Subscription; still review the long tail it can't auto-map |
| **GIATA Room Mapping (GRTM)** | Algorithmic room-name standardization (dictionary + NLP, ignores rate modifiers) | You need room-level dedupe fast | Apply at availability time; book with the **original** supplier room code |
| **Commercial (Gimmonix/Cupid/Vervotech/Nuitee)** | Mapping-as-a-service APIs | Want a managed pipeline | Vendor lock-in; validate their merges |
| **Build in-house** | Your own blocking+scoring+review | Niche suppliers, full control, cost at scale | You own precision/recall and the review ops |

> Pragmatic default: **GIATA Multicodes as the spine** (it resolves the bulk), your own scorer + review queue
> for the unmapped tail and for non-GIATA/niche suppliers. Never rely on a single signal.

## Property matching — blocking + weighted scoring (real code)

**Block first** (only compare candidates in the same city/geocell — never all-vs-all), then score with
multiple signals. GIATA match, when present, dominates.

```ts
// Normalize names: lowercase, strip accents, drop noise tokens, collapse whitespace.
const NOISE = /\b(hotel|hostel|resort|the|by|inn|suites?|apartments?|spa)\b/g;
const normalize = (s: string) =>
  s.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase()
   .replace(NOISE, " ").replace(/[^a-z0-9 ]/g, " ").replace(/\s+/g, " ").trim();

// Haversine → 0..1 proximity (1 = same point; ~0 beyond ~2km).
function geoProximity(a: GeoPoint, b: GeoPoint): number {
  const R = 6371e3, toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(b.lat - a.lat), dLng = toRad(b.lng - a.lng);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * Math.sin(dLng / 2) ** 2;
  const meters = 2 * R * Math.asin(Math.sqrt(h));
  return Math.max(0, 1 - meters / 2000);
}

interface Candidate { name: string; geo: GeoPoint; address: string; giataId?: string; }

function scoreMatch(a: Candidate, b: Candidate): number {
  if (a.giataId && b.giataId) return a.giataId === b.giataId ? 1 : 0; // master id is decisive both ways
  const name = jaroWinkler(normalize(a.name), normalize(b.name));     // robust to word order/typos
  const geo  = geoProximity(a.geo, b.geo);
  const addr = tokenSetRatio(normalize(a.address), normalize(b.address));
  // Geo-weighted: a great name match 5km apart is NOT the same hotel.
  return 0.45 * name + 0.35 * geo + 0.20 * addr;
}

function classify(score: number): "auto" | "review" | "reject" {
  if (score >= 0.92) return "auto";          // tune per supplier mix; measure false-merge rate
  if (score >= 0.75) return "review";
  return "reject";
}
```

```ts
// GIATA Multicodes lookup — resolve a supplier code to the canonical GIATA id (the spine).
async function resolveGiata(supplier: string, supplierHotelId: string): Promise<string | null> {
  const res = await fetch(
    `https://multicodes.giatamedia.com/webservice/rest/1.0/properties/${supplier}/${supplierHotelId}`,
    { headers: { Authorization: giataAuth() } });
  if (!res.ok) return null;
  return (await res.json()).giataId ?? null;
}
```

## Room mapping (match room types, ignore rate noise)

Parse room *attributes* — category, bed type, view, occupancy, smoking — and **ignore rate modifiers**
(board, refundable, promo). Two suppliers' "Deluxe King" and "King Deluxe Room" are one canonical room; their
breakfast/cancellation differences belong to the rate.

```ts
const SYN: Record<string, string> = { dbl: "double", sgl: "single", std: "standard", dlx: "deluxe", twn: "twin" };
function parseRoom(name: string) {
  const t = normalize(name).split(" ").map(w => SYN[w] ?? w);
  return {
    category: pick(t, ["standard", "superior", "deluxe", "suite", "executive"]),
    bed:      pick(t, ["single", "double", "twin", "king", "queen"]),
    view:     pick(t, ["sea", "ocean", "city", "garden", "pool", "mountain"]),
    occupancy: parseOccupancy(t),
  };
}
// Canonical room = (category + bed + occupancy [+ view]). Board comes from the RATE, never the room name.
```

> **GIATA Room Mapping insight (carry into your own builds):** standardize room names for *display/compare*
> only. **Always confirm the booking with the supplier's original room/rate code** — the canonical id is for
> grouping, not for transacting.

## Architecture

```
supplier feeds → normalize → BLOCK (by city/geocell) → score candidates →
  auto-map (≥0.92) │ review queue (0.75–0.92) │ reject (<0.75) →
  canonical master + mapping table { canonicalId ↔ {supplier, supplierId, confidence, mappedBy, ts} }
  feedback loop: human corrections retrain thresholds + grow synonym dictionary
```

- **Blocking** is what makes it scale: index by city/geocell + first normalized name token; compare within bucket.
- Store **every** mapping with `source, confidence, mappedBy (auto|human|giata), timestamp` — provenance is how
  you debug and reverse bad maps.

## Edge cases (where mapping breaks)
- **Chains & near-duplicates:** "Hilton Garden Inn" branches share names; geo+address must break the tie.
- **Bad supplier geo:** some feeds have lat/lng off by blocks or swapped — clamp geo's weight, require a 2nd signal.
- **Multi-language names:** Arabic/Cyrillic/CJK names — normalize per script or match on transliteration + geo.
- **Apartments/villas vs hotels:** different granularity (a building vs a unit) — don't force them into one model.
- **Split vs merge:** a wrong merge needs a clean **split** path that preserves bookings already made under the
  blended canonical id.
- **Stale mappings:** suppliers re-id properties; re-run mapping on feed updates and track unmapped %.

## Performance / scale
- Blocking turns O(n²) into O(n·k). Use a geohash/quadkey + name-token index; never cross-compare cities.
- Cache resolved supplier→canonical mappings (they're stable); only re-score on new/changed feed entries.
- Batch GIATA lookups; respect its API limits.

## Security / data
- Mapping data is operational, not PII — but supplier↔canonical tables are commercially sensitive (they reveal
  your supply graph). Scope access.

## Testing
- Maintain a **golden set** of known same/different pairs (incl. hard chains and bad-geo cases); track
  precision/recall and **false-merge rate** in CI — a regression here corrupts bookings.
- Replay supplier feed fixtures; assert auto/review/reject classification is stable.

## Observability (the metrics that matter)
- **Mapping coverage** (% supplier hotels mapped), **auto-map rate**, **false-merge rate** (caught in QA),
  review-queue depth/age, unmapped % per supplier, time-to-map. A rising false-merge rate is a stop-the-line alert.

## i18n / RTL
- Normalize and match across scripts; render review-queue candidates with localized names + photos; Arabic/RTL
  UI for reviewers where relevant (pair `ui-master`).

## Anti-patterns
- Matching on name alone (typos/duplicates/chains break it) — always combine geo + address + name.
- All-vs-all comparison without blocking — doesn't scale past a few thousand hotels.
- Auto-merging low-confidence matches — wrong hotel shown/booked; keep a review band.
- Booking on the canonical id instead of the supplier's original room/rate code.
- Treating board as part of the room name instead of the rate.
- No provenance / no split path → impossible to debug or reverse a bad merge.

## Checklist
```
- [ ] Canonical master (hotel, roomType) + mapping table to supplier ids (with provenance)
- [ ] GIATA Multicodes as the spine; in-house scorer for the unmapped tail
- [ ] Normalize (name/address/room) + synonym dictionary; block by city/geocell
- [ ] Weighted scoring (giata > geo+name+address) + auto/review/reject thresholds
- [ ] Room attribute parsing (category+bed+occupancy); board from rate, not room name
- [ ] Always book the supplier's original room/rate code; canonical id is for grouping only
- [ ] Human-review queue + split path; golden-set precision/recall + false-merge metric in CI
- [ ] Re-map on feed updates; coverage/auto-map/false-merge dashboards + alerts
```

## References (2026-current)
- GIATA Multicodes (hotel mapping master): https://www.giata.com/products/giata-multicodes/
- GIATA Room Mapping (algorithmic room dedupe): https://www.giata.com/products/giata-room-mapping/
- Jaro-Winkler / token-set string similarity background: https://en.wikipedia.org/wiki/Jaro%E2%80%93Winkler_distance

## Related
`supplier-api-integration`, `b2b-b2c-booking-platform`, `travel-tech-architecture`;
pairs with `ai-mcp-master` (embeddings/fuzzy matching at scale), `backend-api-master` (geo indexing).
