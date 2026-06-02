---
name: geocoding-places-addressing
description: >-
  Staff-level geocoding, Places autocomplete & addressing for ride-hailing: forward/reverse
  geocoding (Google Geocoding, Mapbox Geocoding v6), Autocomplete with SESSION TOKENS for
  billing (Google Places New, Mapbox Search Box suggest/retrieve), debounced search, saved
  places, Arabic transliteration, and the MENA addressing reality (no street addresses →
  pin-drop + landmark, Dubai Makani, KSA National Address, what3words). Cost & accuracy.
---

# Geocoding, Places & Addressing — In MENA, the Pin Is the Address

**Outside the West, a street address is a hint, not a destination — the lat/lng pin and a landmark are the real address.** A ride-hailing geocoding stack that assumes "house number, street, postcode" fails the moment it lands in Dubai, Riyadh, Cairo, or Karachi. The principal design: **pin-drop is primary**, structured/landmark text is secondary metadata, and you integrate the local systems (Dubai **Makani**, KSA **National Address**, **what3words**) that actually pinpoint a door. On the billing side, **session tokens** are the difference between a sane bill and a 10× one.

---

## 1. Mandate

- **Pin-drop is the address; text is a hint.** Persist lat/lng as truth; landmark/structured text helps the driver, never replaces the coordinate.
- **Always use session tokens for autocomplete.** Group keystrokes + the final select into one billable session (Google Places New, Mapbox Search Box) or pay per keystroke.
- **Debounce + bias to the user.** ~250–350 ms debounce, bias by current location/city, restrict country — fewer, better, cheaper calls.
- **Integrate MENA systems.** Makani (Dubai/UAE), KSA National Address, what3words — first-class, not afterthoughts.

## 2. When to use / when NOT

**Use when:** building address entry / "set pickup & dropoff", autocomplete search, reverse-geocoding a dropped pin, saved places (Home/Work), or handling MENA addressing. Feeds the trip's pickup/dropoff (`ride-hailing-architecture`) and the search UI on the map (`maps-rendering-design`).

**Skip / go elsewhere when:** routing between the resolved points → `routing-navigation-eta`. Map rendering of results → `maps-rendering-design`. The trip data model → `ride-hailing-architecture`.

## 3. Mental model — search → resolve → confirm-on-map

```
user types ──debounce──▶ AUTOCOMPLETE (session token)  ──select──▶ RETRIEVE/DETAILS (same token → bills the session)
                                                                       │ lat/lng + components
 drop a pin ──────────────────────────────────────▶ REVERSE GEOCODE ──┘  + landmark/Makani hint
                          ▼
                 CONFIRM ON MAP (drag pin to the exact door — the pin is the truth)
```

The "confirm on map" step is **mandatory in MENA**: autocomplete gets you to the building; the rider drags the pin to the actual gate/entrance. Store that final pin.

## 4. DECISION MATRIX — geocoding/places provider

| Provider | Autocomplete | Session billing | MENA data | Reverse | Verdict |
|----------|--------------|-----------------|-----------|---------|---------|
| **Google Places (New)** ⭐ | `places:autocomplete` | ⭐ session token (first 12 billed, then free) | strongest POI/landmark coverage in Gulf | Geocoding API | ⭐ Best MENA POI + landmark recall |
| **Mapbox Search Box** | `/suggest` + `/retrieve` | ⭐ per-session (suggest→retrieve) | good, improving; pairs with Mapbox map | `/reverse` | ⭐ Value + same vendor as map |
| **Mapbox Geocoding v6** | `autocomplete` param | per-request (no POI) | addresses/places (no POI) | `/reverse` | Address-only, cheap, cacheable (`permanent`) |
| **HERE** | yes | yes | strong + hosts what3words | yes | what3words-native, enterprise |
| **Makani / National Address** | gov lookup | n/a | authoritative door-level | n/a | ⭐ The actual MENA door (overlay on the above) |

**Verdict:** Google Places (New) for the richest Gulf landmark/POI autocomplete; Mapbox Search Box when you're already on Mapbox tiles and want session-priced search co-located with your map. Always overlay the **local door-level systems** (Makani/National Address/what3words) on top.

## 5. Google Places (New) — Autocomplete + Details with session tokens

```ts
import { randomUUID } from "node:crypto";

// 1) Start a session: ONE UUIDv4 token reused for every keystroke + the final details call.
function newSession() { return randomUUID(); }   // URL-safe; Google recommends v4 UUID

// 2) Autocomplete per keystroke (debounced) — same sessionToken throughout.
async function autocomplete(input: string, sessionToken: string, near: LatLng) {
  const res = await fetch("https://places.googleapis.com/v1/places:autocomplete", {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-Goog-Api-Key": process.env.GOOGLE_SERVER_KEY! },
    body: JSON.stringify({
      input,
      sessionToken,                                  // ← the billing-saver
      languageCode: "ar",                            // Arabic suggestions
      regionCode: "AE",
      includedRegionCodes: ["AE"],                   // restrict to country
      locationBias: { circle: { center: { latitude: near.lat, longitude: near.lng }, radius: 30000 } },
    }),
  });
  if (!res.ok) throw new Error(`Autocomplete ${res.status}`);
  const json = await res.json();
  return json.suggestions ?? [];                     // each has placePrediction.placeId, text, etc.
}

// 3) User selects → Place Details with the SAME token TERMINATES the session (bills once).
async function placeDetails(placeId: string, sessionToken: string) {
  const res = await fetch(
    `https://places.googleapis.com/v1/places/${placeId}?sessionToken=${sessionToken}`,
    { headers: {
        "X-Goog-Api-Key": process.env.GOOGLE_SERVER_KEY!,
        "X-Goog-FieldMask": "id,displayName,formattedAddress,location",  // minimal = cheap
    } });
  const p = await res.json();
  return { lat: p.location.latitude, lng: p.location.longitude, name: p.displayName?.text, addr: p.formattedAddress };
}
// Then DISCARD the token and mint a fresh one for the next search. Reusing a token = billed per request.
```

**Billing reality (verified 2026):** within a session the first 12 autocomplete requests bill at the Autocomplete-Requests SKU, requests 13+ are free, and the terminating Place Details bills at the Essentials SKU. **No token, or a reused/abandoned token → every keystroke bills separately.** This is the single biggest geocoding cost lever.

## 6. Mapbox Search Box — suggest/retrieve session

```ts
// /suggest (per keystroke) + /retrieve (on select) share a session_token (UUIDv4) → billed per session.
async function mbSuggest(q: string, sessionToken: string, near: LatLng) {
  const url = `https://api.mapbox.com/search/searchbox/v1/suggest`
    + `?q=${encodeURIComponent(q)}&session_token=${sessionToken}`
    + `&language=ar&country=ae&proximity=${near.lng},${near.lat}&limit=6`
    + `&access_token=${process.env.MAPBOX_TOKEN}`;
  return (await fetch(url)).json();                  // { suggestions: [{ mapbox_id, name, ... }] }
}
async function mbRetrieve(mapboxId: string, sessionToken: string) {
  const url = `https://api.mapbox.com/search/searchbox/v1/retrieve/${mapboxId}`
    + `?session_token=${sessionToken}&access_token=${process.env.MAPBOX_TOKEN}`;
  const json = await (await fetch(url)).json();      // GeoJSON FeatureCollection with coordinates
  const [lng, lat] = json.features[0].geometry.coordinates;
  return { lat, lng, name: json.features[0].properties.name };
}
// Session auto-expires after 2 min idle or 50 /suggest without /retrieve — mint fresh per search.
```

## 7. Reverse geocoding a dropped pin

```ts
// Pin dropped/dragged → resolve a human label + components. Mapbox Geocoding v6 reverse.
async function reverse(lat: number, lng: number) {
  const url = `https://api.mapbox.com/search/geocode/v6/reverse?longitude=${lng}&latitude=${lat}`
    + `&language=ar&access_token=${process.env.MAPBOX_TOKEN}`;
  // permanent=true ONLY if you will STORE the result (separate billing + terms); default is temporary.
  const json = await (await fetch(url)).json();
  return json.features?.[0]?.properties?.full_address ?? `${lat.toFixed(5)}, ${lng.toFixed(5)}`;
}
```

## 8. The MENA addressing reality (the part that actually matters)

| System | Where | What it is | Use in a ride app |
|--------|-------|------------|--------------------|
| **Pin-drop + landmark** ⭐ | everywhere in MENA | lat/lng + "near X mosque/mall" | Primary pickup/dropoff truth; the default flow |
| **Makani** | Dubai, Ajman, UAQ, Fujairah, RAK | 10-digit number per building **entrance**, 1 m² precision, QR plates | Accept/parse a Makani number → resolve to its exact entrance lat/lng |
| **KSA National Address** | Saudi Arabia | short code (4 letters + 4 digits, e.g. `RRRD2929`) + building/zip | Accept the short address; resolve via SPL |
| **what3words** | global (used in MENA) | 3-word label for a 3×3 m square (`///filled.count.soap`) | Optional input/convert; good for villas/desert sites |

```ts
// Detect & resolve a structured MENA token the rider pastes, BEFORE hitting generic autocomplete.
const MAKANI_RE = /^\d{10}$/;                                   // 10 digits, e.g. 3003295320
const W3W_RE    = /^\/{0,3}[\p{L}]+\.[\p{L}]+\.[\p{L}]+$/u;     // word.word.word (Arabic or Latin)
const KSA_RE    = /^[A-Z]{4}\d{4}$/;                            // RRRD2929

async function resolveStructured(input: string): Promise<LatLng | null> {
  const s = input.trim();
  if (MAKANI_RE.test(s)) return resolveMakani(s);              // Dubai GIS Makani lookup → entrance lat/lng
  if (W3W_RE.test(s))    return resolveW3W(s.replace(/^\/+/, "")); // what3words convert-to-coordinates
  if (KSA_RE.test(s.toUpperCase())) return resolveNationalAddress(s.toUpperCase());
  return null;                                                 // fall through to provider autocomplete
}
// what3words convert-to-coordinates (HERE-hosted or w3w API):
//   GET https://api.what3words.com/v3/convert-to-coordinates?words=filled.count.soap&key=KEY
//   → { coordinates: { lat, lng }, country, nearestPlace }
```

**This is the senior differentiator for MENA.** A rider in a new Dubai villa compound has no street address; they have a Makani plate by the door. A logistics-grade ride app *accepts the Makani number, the National Address short code, or a what3words label* and resolves each to a precise entrance — then still lets them confirm the pin on the map.

## 9. Debounced search + saved places (client)

```ts
// Debounce keystrokes; reuse the session token until a selection or reset. Cancel stale requests.
function makeSearch(near: LatLng) {
  let token = newSession(); let ctrl: AbortController | null = null; let timer: any;
  function onInput(q: string, cb: (r: Suggestion[]) => void) {
    clearTimeout(timer);
    timer = setTimeout(async () => {
      ctrl?.abort(); ctrl = new AbortController();
      if (q.length < 2) return cb(savedPlaces(near));          // show Home/Work/recents on empty
      const structured = await resolveStructured(q);
      if (structured) return cb([{ kind: "pin", ...structured }]);
      cb(await autocomplete(q, token, near));                   // same token across keystrokes
    }, 300);                                                    // 300ms debounce
  }
  function onSelect() { token = newSession(); }                 // mint fresh token AFTER details/retrieve
  return { onInput, onSelect };
}
// Saved places: Home/Work/recents resolve INSTANTLY from your DB — zero geocoding cost, best UX.
```

## 10. Edge cases & gotchas

- **No street address** → never block on a structured address; pin-drop + landmark always works.
- **Token reuse/abandonment** → silent per-request billing. Mint fresh per search; terminate with details/retrieve.
- **Ambiguous landmarks** ("Al Noor Mosque" — there are dozens) → bias by location, show distance, let the user disambiguate on the map.
- **Arabic vs transliteration** → users type "Burj Khalifa" or "برج خليفة" or "Borg Khalifa". Support both scripts + fuzzy transliteration; request `languageCode: ar` but accept Latin input.
- **Right-to-left mixed with digits** → addresses mix Arabic text + Latin digits; render with proper bidi handling (`ui-master`).
- **Pin precision vs accuracy** → don't show 6-decimal "precision" when the underlying result is a city centroid; surface confidence and force confirm-on-map.
- **Compound/gated communities** → the gate ≠ the villa; capture both entrance pin and unit note for the driver.
- **Makani for incomplete buildings** → not every structure has one yet; fall back to pin + landmark.

## 11. Performance & cost control

- **Session tokens** (the headline cost lever) + **debounce** (fewer calls) + **min query length** (≥2 chars).
- **Saved places & recents** answer most "where to?" with zero API cost — invest in this UX.
- **Cache reverse-geocode** of dropped pins briefly (rider drags around the same area).
- **Bias + country-restrict** to cut irrelevant calls and improve hit quality.
- **`permanent` only when storing** (Mapbox) — it bills differently and carries storage terms; default temporary for ephemeral search.
- **Field masks** (Google details) — request only `location`+`displayName`+`formattedAddress` you actually use.

## 12. Security & privacy

- **Server-proxy provider calls** with server keys; never ship a powerful geocoding key in the client (autocomplete keys are abuse magnets). If using client SDKs, **referer/bundle-restrict + quota + billing alerts**.
- **Saved places are sensitive PII** (Home/Work reveal where someone lives/works) → encrypt at rest, access-audit, support deletion.
- **Don't log full addresses/coords at info level**; they're location PII.
- **Rate-limit autocomplete per user** to blunt scraping/abuse of your proxy.

## 13. Testing

- **MENA fixtures:** Makani numbers, KSA short codes, what3words labels, Arabic + transliterated landmark queries → assert correct resolution and graceful fallthrough.
- **Session billing test:** assert one token spans keystrokes and is rotated on select (guards against the costliest regression).
- **Debounce/cancel test:** rapid typing cancels stale requests; only the latest resolves.
- **Bidi/RTL render test:** Arabic+digit addresses display correctly.

## 14. Observability

- **Cost:** autocomplete sessions vs raw requests (catch token regressions instantly), details calls, reverse calls; cost per completed search.
- **Quality:** select-rate (did a suggestion get chosen?), confirm-on-map drag distance (big drags = poor first result), zero-result rate per city.
- **Latency:** keystroke → suggestions p50/p95; structured-resolve success rate (Makani/W3W/National).

## 15. Accessibility & i18n / RTL (MENA — core, not a footnote)

- **Bilingual end to end:** Arabic + English suggestions, `languageCode/language=ar`, RTL result list, Arabic numerals option, prefer `name_ar`.
- **Transliteration tolerance:** accept Latin-typed Arabic place names and vice versa.
- **Landmark-first UI:** lead with landmarks/POIs (how MENA navigates), not house numbers.
- **Voice + paste:** let riders paste a Makani/what3words/National-Address token or speak it (`communications-master` for voice).
- **Screen-reader:** suggestion list and the resolved address must be readable; the pin's confirmed address announced in text.

## 16. Anti-patterns

- **Requiring a structured street address** → undeliverable in MENA. Pin-drop + landmark first.
- **No session token (or reusing one)** → 10× autocomplete bill. One token per search, rotate on select.
- **No confirm-on-map step** → wrong gate, driver calls, cancellations. Always let the rider drag the pin.
- **Ignoring Makani/National Address/what3words** → you're worse than the local incumbent. Integrate them.
- **Latin-only input / LTR-only UI** → excludes Arabic typists. Bilingual + bidi.
- **Client-side powerful keys, unrestricted** → scraping + billing abuse. Proxy + restrict + quota.
- **Storing temporary geocodes** (against terms) or **`permanent` for ephemeral search** (overpay) → match the flag to intent.

## 17. Agent checklist

```
- [ ] Pin-drop is the stored truth; landmark/structured text is a hint; confirm-on-map step present
- [ ] Autocomplete uses a session token reused across keystrokes, rotated after details/retrieve
- [ ] Debounce ~300ms, min length ≥2, location-bias + country-restrict, cancel stale requests
- [ ] Saved places/recents answer common searches with zero API cost
- [ ] MENA systems integrated: Makani (10-digit), KSA National Address (RRRD2929), what3words (w.w.w)
- [ ] Reverse geocode dropped pins; surface confidence; cache briefly
- [ ] Arabic + transliteration input; RTL/bidi result rendering; name_ar preferred
- [ ] Provider calls server-proxied with restricted+quota'd keys; saved places encrypted PII
- [ ] permanent flag only when storing (Mapbox); minimal field masks (Google)
- [ ] Cost dashboards: sessions vs requests; quality: select-rate, confirm-drag distance, zero-result
- [ ] Tests: MENA fixtures, session-billing regression, debounce/cancel, bidi render
```

## 18. References (verify current — 2026)

- Google Places (New) Autocomplete + session pricing: https://developers.google.com/maps/documentation/places/web-service/place-autocomplete · https://developers.google.com/maps/documentation/places/web-service/session-pricing
- Google Places session tokens: https://developers.google.com/maps/documentation/places/web-service/place-session-tokens
- Mapbox Search Box (suggest/retrieve): https://docs.mapbox.com/api/search/search-box/ · Geocoding v6: https://docs.mapbox.com/api/search/geocoding/
- Dubai Makani (official): https://www.makani.ae · KSA National Address (SPL): https://splonline.com.sa/en/national-address-1/
- what3words API (convert-to-coordinates): https://developer.what3words.com/public-api · HERE-hosted what3words: https://www.here.com/docs

## 19. Related

`ride-hailing-architecture` (pickup/dropoff in the trip model), `maps-rendering-design` (search UI + confirm-on-map), `routing-navigation-eta` (route between resolved points) · cross-master: `backend-api-master` (geocoding/GIS, key proxying), `ui-master` (RTL/bidi search UI), `communications-master` (voice address entry), `marketplace-master/delivery-logistics-dispatch` (shares MENA pin-drop+landmark addressing)
