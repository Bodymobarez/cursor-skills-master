---
name: gps-gnss-fundamentals
description: >-
  GNSS at staff depth: how positioning actually works (multilateration, pseudoranges, clock bias),
  the four global + two regional constellations, A-GPS/ephemeris/almanac, the real error budget
  (ionosphere, multipath, urban canyon), DOP/HDOP, honest accuracy tiers (standalone → SBAS → PPP →
  RTK), a correct NMEA 0183 parser (GGA/RMC/GSA + checksum), and WGS84/datums/ECEF/ENU. Read this first.
---

# GPS & GNSS Fundamentals — How Positioning Really Works

**A position is a least-squares solve, not a lookup.** A receiver measures the travel time of signals
from ≥4 satellites, multiplies by c to get *pseudoranges* (biased by the receiver's own cheap clock),
and solves 4 unknowns: `(x, y, z, clock_bias)`. Everything else in this skill — accuracy, DOP, error
budget, RTK — is about how clean those pseudoranges are and how favorably the satellites are arranged.

If you remember one thing: **"GPS accuracy" is meaningless without a fix-quality tier and an HDOP.**
A phone reporting `accuracy: 5` and a survey rover reporting `accuracy: 0.02` are not the same product.

---

## When to use this skill / when NOT

**Use it when** you need to: reason about real-world accuracy, parse raw receiver output (NMEA/UBX),
choose a constellation/frequency strategy, debug "the dot is jumping", spec hardware, or set a fix-quality
gate before ingestion. Everything downstream (geofencing, fleet, RTK) assumes you internalized this.

**Do NOT** reach here for: the browser/mobile permission flow (`web-mobile-geolocation`), tracker wire
protocols (`device-integration-protocols`), centimeter corrections (`precision-positioning-rtk`), or
map rendering/routing (`ride-hailing-maps-master`). This skill is the physics + the parser.

---

## 1. Mental model — the signal chain

```
Satellite (atomic clock, broadcasts ephemeris + ranging code on L1/L5...)
   │  signal travels ~67 ms, bent by ionosphere & troposphere, reflected by buildings
   ▼
Antenna → RF front-end → correlator (locks code + carrier phase)
   │  measures: pseudorange (code), carrier phase (RTK/PPP), Doppler (velocity), C/N0 (signal quality)
   ▼
PVT engine: solve (x,y,z,Δt) from ≥4 pseudoranges  →  WGS84 lat/lon/height
   │  + Kalman filter (fuses Doppler velocity, smooths, dead-reckons through gaps)
   ▼
NMEA 0183 / UBX / proprietary  →  your ingestion
```

Two measurements matter and people conflate them:
- **Code pseudorange** — meters-level, unambiguous, used by every phone. Basis of standalone/SBAS/DGPS.
- **Carrier phase** — millimeter-level *but* ambiguous by an integer number of wavelengths (~19 cm on
  L1). Resolving that integer ("fixing the ambiguity") is the entire game of **RTK/PPP**.

---

## 2. The constellations (2026 reality)

| System | Owner | Status 2026 | Signals | Notes you actually use |
|--------|-------|-------------|---------|------------------------|
| **GPS** | USA | ~31 operational | L1 C/A, L2C, **L5** | Baseline. L5 (newer SVs) enables dual-freq on consumer chips. |
| **GLONASS** | Russia | ~24 | L1/L2 (FDMA), L3 (CDMA) | FDMA per-satellite frequency complicates RTK; still helps fix count. |
| **Galileo** | EU | ~28, FOC | E1, E5a/E5b, **E6** | Best open signals; **HAS** free PPP on E6-B (see §6). |
| **BeiDou-3** | China | Complete (global since 2020) | B1I/B1C, B2a, B3, **B2b** | Global. **PPP-B2b** broadcasts free corrections over Asia-Pacific. |
| **QZSS** | Japan | Regional (Asia-Oceania) | L1/L5, **L6** | CLAS (L6D) cm-class + MADOCA-PPP over Japan; boosts urban-canyon fix in JP. |
| **NavIC** | India | Regional | L5, S-band | Indian subcontinent; L1 signal rolling out for mass-market chips. |

**Operational takeaway:** "multi-GNSS, dual-frequency (L1+L5/E5)" is the single biggest *consumer-grade*
accuracy lever. It roughly halves urban error vs L1-only by killing ionospheric delay and rejecting
multipath. Spec it on new hardware; verify your chip actually tracks L5, not just markets it.

---

## 3. A-GPS, ephemeris vs almanac, and TTFF

**Time-To-First-Fix** is dominated by how fresh your orbital data is:

| Data | What | Validity | Why TTFF cares |
|------|------|----------|----------------|
| **Almanac** | Coarse orbits for *all* SVs | weeks | Lets receiver know which SVs to look for |
| **Ephemeris** | Precise orbit + clock for *one* SV | ~2–4 h | Required per-SV to compute a fix |

- **Cold start** (no data): 30 s–several minutes — receiver must demodulate ephemeris at 50 bps from the
  signal itself (one frame = 18–30 s, and you need it for ≥4 SVs).
- **A-GPS / A-GNSS:** fetch ephemeris + rough position/time over the *network* (SUPL, or vendor like
  Google/Broadcom assisted data). Cold start → **seconds**. This is why phones fix instantly and a bare
  module in a basement does not. On IoT trackers, A-GPS over cellular is the standard TTFF fix.
- **Hot start:** valid ephemeris cached → ~1 s.

> Gotcha: a tracker that "takes 2 minutes to get GPS every wake" usually has no A-GPS and is doing a cold
> start each duty cycle. Add A-GPS (e.g., u-blox AssistNow) before you blame the antenna.

---

## 4. The error budget — name every meter

Standalone single-frequency UERE (User-Equivalent Range Error), roughly:

| Source | Typical | Mitigation |
|--------|---------|------------|
| **Ionospheric delay** | 2–5 m (up to 10+) | **Dual-frequency** (L1+L5) cancels it; SBAS/Klobuchar model otherwise |
| **Tropospheric delay** | 0.5–1 m | Models (Saastamoinen); estimated in PPP |
| **Multipath** (reflections) | 0.5–3 m, **worse in cities** | Antenna (choke-ring/ground plane), L5 (longer code), receiver rejection |
| **Ephemeris + SV clock** | 1–2 m | SBAS/DGPS/PPP corrections remove most |
| **Receiver noise** | 0.25–0.5 m | Better front-end, carrier smoothing |

`Position error ≈ UERE × DOP`. Note **Selective Availability is OFF** since May 2000 — don't cite the old
"100 m civilian" number. Standalone open-sky is ~3–5 m (often ~2–3 m on a modern dual-freq phone).

### Edge cases that wreck real deployments
- **Urban canyon:** tall buildings block half the sky → high HDOP, and reflected-only signals give
  *confidently wrong* positions (the dot lands across the street, on the wrong road). Worst failure mode
  in ride-hailing/fleet.
- **Multipath while stationary:** a parked car "wanders" 5–20 m. Don't log motion from it (see §7 drift).
- **Tunnels / parking garages / dense foliage:** no fix. Plan for dead-reckoning (IMU/odometer) or gaps.
- **Cold/indoor:** weak C/N0 → the receiver may output a *stale* or extrapolated position. Trust the fix
  flag, not the coordinates.
- **GPS week rollover & leap seconds:** old firmware reported dates 19.6 years off after a rollover.
  Sanity-check the year. GPS time ≠ UTC (currently +18 leap seconds); NMEA gives UTC.

---

## 5. DOP — geometry decides whether your meters are good

Dilution of Precision = how satellite *geometry* amplifies range error. Same receiver, same sky-blocking,
different DOP depending on where SVs sit. Lower is better.

| HDOP | Rating | Use |
|------|--------|-----|
| < 1 | Ideal | Survey-grade only |
| 1–2 | Excellent | Trust it |
| 2–5 | Good | Normal navigation |
| 5–10 | Moderate | Degrade UI confidence |
| 10–20 | Fair | Display only, don't log as truth |
| > 20 | Poor | Reject |

Flavors: **HDOP** (horizontal), **VDOP** (vertical — always worse, ~1.5–2× HDOP, why altitude is bad),
**PDOP** (3D), **TDOP** (time), **GDOP** (everything). For tracking you gate on **HDOP + fix flag +
satellites-used**. Multi-GNSS improves DOP because more SVs = better geometry.

---

## 6. Accuracy tiers — pick the right tool (DECISION MATRIX)

| Tier | Method | Horizontal accuracy | Converge | Cost | Use it for |
|------|--------|---------------------|----------|------|------------|
| **Standalone L1** | Single freq, code | 3–5 m open / 10–50 m urban | instant | $ | Phones, basic trackers |
| **Standalone dual-freq multi-GNSS** | L1+L5 / E1+E5 | 1–3 m | instant | $ | Modern phones, good trackers |
| **SBAS** | WAAS/EGNOS/MSAS/GAGAN/SouthPAN | 1–2 m | instant | free | Aviation, agriculture, free upgrade |
| **DGPS** | Local base, code differential | 0.3–1 m | seconds | $$ | Legacy marine/survey |
| **PPP** | Global precise orbit/clock corrections | 5–30 cm | **5–30+ min** | free–$$$ | Open-field, no base nearby |
| **PPP-RTK / SSR** | PPP + atmospheric, state-space | 3–10 cm | seconds–min | $$ | Auto, mass-market precision |
| **RTK** | Carrier phase + nearby base (≤~30 km) | **1–2 cm + 1 ppm** | seconds | $$–$$$ | Survey, drones, agri, machine control |

- **SBAS** (geostationary augmentation, free): **WAAS** (N. America), **EGNOS** (Europe), **MSAS** (Japan),
  **GAGAN** (India), **SDCM** (Russia), **SouthPAN** (Australia/NZ). Broadcasts corrections + *integrity*.
  Turn it on; it's a free 2–3× accuracy bump where covered.
- **Galileo HAS** (free PPP, declared Jan 2023, **Full Service targeted Q4 2026**): orbit/clock + code/phase
  bias corrections for Galileo **and** GPS, delivered on the **E6-B** signal *and* over the internet (IDD).
  Target **< 20 cm horizontal / < 40 cm vertical (95%)**, convergence **< 300 s** (SL1 global). Regional
  alternatives: **BeiDou PPP-B2b**, **QZSS MADOCA-PPP/CLAS**, **SouthPAN PPP** — these are regional, so a
  global OEM pays a "fragmentation tax." Commercial global PPP: u-blox **PointPerfect**, etc.

> **PPP's dirty secret is convergence.** Sub-decimeter PPP needs minutes of continuous tracking to settle;
> a re-converge after a tunnel can cost minutes. If you need *instant* cm, that's **RTK** (§ `precision-positioning-rtk`).

---

## 7. A correct NMEA 0183 parser (TypeScript, copy-paste)

NMEA 0183 is ASCII, comma-delimited: `$<talker><type>,<fields...>*<checksum>\r\n`. Checksum = 8-bit XOR
of every char **between** `$` and `*`. Talker IDs: `GP`=GPS, `GL`=GLONASS, `GA`=Galileo, `GB`/`BD`=BeiDou,
`GQ`=QZSS, **`GN`=combined** (most modern multi-GNSS receivers emit `GN`). Coordinates are the infamous
`ddmm.mmmm` (degrees+minutes glued together) — *not* decimal degrees.

```ts
// nmea.ts — production-grade GGA/RMC/GSA parser with checksum validation.
export type FixQuality =
  | "invalid" | "gps" | "dgps" | "pps" | "rtk-fixed" | "rtk-float"
  | "dead-reckoning" | "manual" | "simulation";

const GGA_QUALITY: Record<number, FixQuality> = {
  0: "invalid", 1: "gps", 2: "dgps", 3: "pps",
  4: "rtk-fixed", 5: "rtk-float", 6: "dead-reckoning", 7: "manual", 8: "simulation",
};

export interface GgaFix {
  type: "GGA";
  timeUtc: string | null;       // hhmmss.ss as sent
  lat: number | null;           // decimal degrees, +N / -S
  lon: number | null;           // decimal degrees, +E / -W
  quality: FixQuality;
  satellitesUsed: number | null;
  hdop: number | null;
  altitudeMslM: number | null;  // metres above geoid (mean sea level)
  geoidSepM: number | null;     // geoid - ellipsoid; add to MSL for ellipsoidal height
}

/** Validate the NMEA checksum. Reject silently-corrupt serial lines BEFORE trusting any field. */
export function checksumOk(sentence: string): boolean {
  const star = sentence.indexOf("*");
  if (!sentence.startsWith("$") || star < 0) return false;
  let xor = 0;
  for (let i = 1; i < star; i++) xor ^= sentence.charCodeAt(i);
  const given = parseInt(sentence.slice(star + 1, star + 3), 16);
  return xor === given;
}

/** ddmm.mmmm + hemisphere → signed decimal degrees. The classic bug is treating it as decimal. */
function dm2deg(dm: string, hemi: string, degDigits: 2 | 3): number | null {
  if (!dm) return null;
  const deg = parseInt(dm.slice(0, degDigits), 10);
  const min = parseFloat(dm.slice(degDigits));
  if (Number.isNaN(deg) || Number.isNaN(min)) return null;
  let v = deg + min / 60;
  if (hemi === "S" || hemi === "W") v = -v;
  return v;
}

const num = (s: string): number | null => (s === "" || s == null ? null : Number(s));

export function parseGGA(fields: string[]): GgaFix {
  return {
    type: "GGA",
    timeUtc: fields[1] || null,
    lat: dm2deg(fields[2], fields[3], 2),
    lon: dm2deg(fields[4], fields[5], 3),
    quality: GGA_QUALITY[Number(fields[6])] ?? "invalid",
    satellitesUsed: num(fields[7]),
    hdop: num(fields[8]),
    altitudeMslM: num(fields[9]),   // field 10 = "M"
    geoidSepM: num(fields[11]),     // field 12 = "M"
  };
}

export interface RmcFix {
  type: "RMC"; status: "A" | "V";          // A=valid, V=void — gate on this
  lat: number | null; lon: number | null;
  speedKmh: number | null; courseDeg: number | null;
  timestampUtc: string | null;             // ISO from date+time fields
}

export function parseRMC(fields: string[]): RmcFix {
  const knots = num(fields[7]);
  const t = fields[1], d = fields[9];      // hhmmss.ss , ddmmyy
  let iso: string | null = null;
  if (t && d && d.length === 6) {
    const yy = +d.slice(4, 6);
    iso = `20${String(yy).padStart(2, "0")}-${d.slice(2, 4)}-${d.slice(0, 2)}` +
          `T${t.slice(0, 2)}:${t.slice(2, 4)}:${t.slice(4, 6)}Z`;
  }
  return {
    type: "RMC",
    status: fields[2] === "A" ? "A" : "V",
    lat: dm2deg(fields[3], fields[4], 2),
    lon: dm2deg(fields[5], fields[6], 3),
    speedKmh: knots == null ? null : +(knots * 1.852).toFixed(2),  // knots → km/h
    courseDeg: num(fields[8]),
    timestampUtc: iso,
  };
}

export interface GsaDop {
  type: "GSA"; mode: "M" | "A"; fixType: 1 | 2 | 3; // 1=none 2=2D 3=3D
  pdop: number | null; hdop: number | null; vdop: number | null;
}

export function parseGSA(fields: string[]): GsaDop {
  return {
    type: "GSA",
    mode: fields[1] === "M" ? "M" : "A",
    fixType: (Number(fields[2]) as 1 | 2 | 3) || 1,
    pdop: num(fields[15]), hdop: num(fields[16]), vdop: num(fields[17]),
  };
}

/** Dispatch one line. Returns null for unknown/corrupt sentences (don't throw on a noisy serial port). */
export function parseNmea(line: string): GgaFix | RmcFix | GsaDop | null {
  line = line.trim();
  if (!checksumOk(line)) return null;
  const body = line.slice(1, line.indexOf("*"));
  const fields = body.split(",");
  const type = fields[0].slice(2);         // strip 2-char talker id (GP/GN/GA...)
  switch (type) {
    case "GGA": return parseGGA(fields);
    case "RMC": return parseRMC(fields);
    case "GSA": return parseGSA(fields);
    default: return null;
  }
}
```

Verified field layouts (NMEA 0183): **GGA** `time,lat,N/S,lon,E/W,quality,numSats,HDOP,alt,M,geoidSep,M,dgpsAge,dgpsId`;
**RMC** `time,status,lat,N/S,lon,E/W,speedKnots,course,date,magVar,E/W`; **GSA** `mode,fixType,sv1..sv12,PDOP,HDOP,VDOP`.

> **Production rule:** gate ingestion on `RMC.status === "A"` (or `GGA.quality !== "invalid"`) **and**
> `HDOP < 5` **and** `satellitesUsed >= 4`. Everything failing the gate is "no fix", not "position (0,0)".

---

## 8. WGS84, datums, ECEF/ENU — the coordinate truth

- **WGS84** (`EPSG:4326`) is the GNSS datum: lat/lon on the WGS84 ellipsoid. GeoJSON, Leaflet, Mapbox all
  speak WGS84 lng/lat. **Order trap:** GeoJSON/PostGIS = `[lng, lat]`; most GPS APIs/humans = `(lat, lng)`.
- **Ellipsoidal vs orthometric height:** GNSS natively gives *ellipsoidal* height. GGA reports *MSL*
  (orthometric) plus the **geoid separation**; `ellipsoidal = MSL + geoidSep`. Mixing them = tens of metres
  of vertical error. For elevation, use a geoid model, not raw GNSS height.
- **ECEF** (Earth-Centered Earth-Fixed `X,Y,Z`): the Cartesian frame the solver works in; convenient for
  3D math and baselines. **ENU** (East-North-Up): a *local tangent plane* at a reference point — use it for
  small-area metric work (relative offsets, IMU fusion) so you can do plain Euclidean math in metres.
- **Datum drift is real at RTK scale:** WGS84 is global; regional datums **NAD83**, **ETRS89**, **GDA2020**
  are pinned to tectonic plates that move **~2–7 cm/year**. At 2 cm RTK accuracy, "WGS84 vs ETRS89" is not
  pedantry — it's a metre over a couple decades. For survey, transform to the official local datum/epoch.

```ts
// Geodetic (WGS84) → ECEF. Use ECEF for baselines / 3D; convert to ENU for local metric work.
export function geodeticToEcef(latDeg: number, lonDeg: number, hM = 0) {
  const a = 6378137.0, f = 1 / 298.257223563;           // WGS84 ellipsoid
  const e2 = f * (2 - f);
  const lat = (latDeg * Math.PI) / 180, lon = (lonDeg * Math.PI) / 180;
  const N = a / Math.sqrt(1 - e2 * Math.sin(lat) ** 2);  // prime vertical radius
  return {
    x: (N + hM) * Math.cos(lat) * Math.cos(lon),
    y: (N + hM) * Math.cos(lat) * Math.sin(lon),
    z: (N * (1 - e2) + hM) * Math.sin(lat),
  };
}
```

---

## 9. Performance — high-frequency raw streams

- A receiver at 10 Hz emitting GGA+RMC+GSA+GSV per epoch is **dozens of sentences/sec**. Parse with a
  streaming line splitter (`readline`/byte buffer), **not** by re-splitting the whole buffer each chunk.
- **Down-rate at the edge, not the center.** A vehicle at 1 Hz is plenty for trips; 10 Hz is for RTK/IMU
  fusion. Don't ship 10 Hz to your backend "just in case" — it's 10× ingestion cost for noise.
- The parser above does zero allocation beyond the field array and is branch-light; checksum is one XOR
  pass. This sustains thousands of sentences/sec single-threaded — the bottleneck is your I/O, not parsing.

---

## 10. Security & privacy — location is PII

- **Raw position is sensitive personal data** (GDPR, CCPA, and most regimes treat continuous location as
  high-risk). Collect with **consent + purpose limitation**, encrypt in transit and at rest, and set
  **retention** (raw high-rate ≠ kept forever; downsample/expire — see `geospatial-data-postgis`).
- **GNSS is unauthenticated and spoofable.** Civilian signals have no signature; an SDR can forge a
  position, and "GPS spoofing" apps are trivial on rooted phones. Never trust a coordinate as proof of
  presence for anything that matters (payroll, fences, geofenced unlocks) without cross-checks: signal
  realism (C/N0, sat count), motion plausibility, multi-sensor (cell/Wi-Fi/IMU) agreement, server-side
  jump detection. **Galileo OSNMA** (navigation message authentication) exists for anti-spoofing on capable
  receivers — spec it if integrity is a real requirement.
- Minimize precision where the use case allows (city-level for analytics vs exact for dispatch).

---

## 11. Scale & reliability

- Treat the receiver as an **unreliable sensor**: gaps, dupes, out-of-order, and bursts after reconnect are
  normal. Your pipeline must be idempotent on `(device_id, fix_timestamp)` (see `fleet-asset-tracking-platform`).
- Cache A-GPS data server-side and push to fleets to keep TTFF low at scale.
- Don't store `(0,0)` ("Null Island") fixes — that's the universal "no fix" sentinel and it will pollute
  every heatmap and bounding-box query you ever run.

---

## 12. Testing — replay, don't drive

- **Replay real NMEA/GPX traces** as your fixtures. Capture once (a logging drive, or public datasets),
  then unit-test the parser and the whole pipeline against them deterministically.
- Keep a corpus of **adversarial fixtures**: bad checksum, truncated sentence, `status=V`, `(0,0)`,
  HDOP=99, week-rollover date, lat/lon swapped, empty fields, mixed `GN`/`GP` talkers.
- A simple GPX→NMEA generator lets you synthesize edge cases (teleport, stationary multipath jitter,
  tunnel gap) that are painful to reproduce in the field.

```ts
// minimal NMEA RMC line builder for tests (drops in real lat/lon/speed)
export function buildRMC(lat: number, lon: number, kmh: number, d = new Date()): string {
  const dm = (v: number, deg: 2 | 3) => {
    const a = Math.abs(v), D = Math.floor(a), m = (a - D) * 60;
    return String(D).padStart(deg, "0") + m.toFixed(4).padStart(7, "0");
  };
  const p2 = (n: number) => String(n).padStart(2, "0");
  const time = `${p2(d.getUTCHours())}${p2(d.getUTCMinutes())}${p2(d.getUTCSeconds())}.00`;
  const date = `${p2(d.getUTCDate())}${p2(d.getUTCMonth() + 1)}${p2(d.getUTCFullYear() % 100)}`;
  const body = `GPRMC,${time},A,${dm(lat, 2)},${lat >= 0 ? "N" : "S"},` +
    `${dm(lon, 3)},${lon >= 0 ? "E" : "W"},${(kmh / 1.852).toFixed(1)},0.0,${date},,`;
  let xor = 0; for (const c of body) xor ^= c.charCodeAt(0);
  return `$${body}*${xor.toString(16).toUpperCase().padStart(2, "0")}`;
}
```

---

## 13. Observability — watch fix *quality*, not just position

Log and dashboard these per device, because they predict bad data before users complain:
- **Fix quality distribution** (% invalid / gps / dgps / rtk-float / rtk-fixed).
- **HDOP** p50/p95, **satellites-used** histogram, **C/N0** if you have UBX.
- **Dropout rate** (gaps > N s) and **TTFF** per wake — rising TTFF = A-GPS broken or antenna failing.
- **`(0,0)` and stale-fix counts** — should be ~0 after gating.

---

## 14. Accessibility & i18n

- Show users a **confidence radius** (the `accuracy` circle), never a falsely precise pin. "Within ~30 m"
  is honest; a sharp dot 30 m off is a support ticket.
- Localize coordinate display: decimal degrees vs DMS, metric vs imperial speed/altitude, RTL layouts,
  and translate fix states ("No GPS signal", "Searching…"). Never read raw `ddmm.mmmm` to a human.

---

## 15. Opinionated anti-patterns

- ❌ Reporting "accuracy" with **no fix flag / no HDOP**. Meaningless.
- ❌ Treating `ddmm.mmmm` as decimal degrees (the #1 parser bug; puts you ~hundreds of km off).
- ❌ Logging `(0,0)` / Null Island as a real position.
- ❌ Using **GGA MSL altitude as ellipsoidal height** (or vice-versa) — tens of metres of error.
- ❌ Trusting coordinates while `RMC.status === "V"` or quality `invalid`.
- ❌ Citing "100 m" civilian accuracy or "you need 3 satellites" (you need **4** — clock bias is an unknown).
- ❌ Assuming "GPS" only = GPS. On modern chips you're using GPS+GLONASS+Galileo+BeiDou; design for `GN`.
- ❌ Believing a coordinate proves presence (spoofable). Cross-check.

---

## 16. Agent checklist

```
- [ ] Stated the accuracy TIER (standalone/SBAS/PPP/RTK), not a bare metre number
- [ ] Ingestion gates on fix-flag (RMC A / GGA quality) + HDOP + sats-used
- [ ] NMEA parser validates checksum and converts ddmm.mmmm correctly
- [ ] Coordinate order explicit (lng,lat for GeoJSON/PostGIS; lat,lng for GPS APIs)
- [ ] Altitude: MSL vs ellipsoidal handled with geoid separation
- [ ] Multi-GNSS + dual-frequency (L1/L5) considered for the hardware
- [ ] A-GPS in place if TTFF matters (IoT trackers)
- [ ] (0,0) / stale / spoofed fixes rejected; location treated as PII with retention
- [ ] Replay/GPX/NMEA fixtures incl. adversarial cases in tests
- [ ] Fix-quality + HDOP + dropout on a dashboard
```

## References (2026-current)
- NMEA 0183 reference: https://gpsd.io/NMEA.html · official: https://www.nmea.org/nmea-0183.html
- GPS / SPS Performance Standard: https://www.gps.gov/technical/ps/
- Galileo HAS (free PPP): https://www.gsc-europa.eu/galileo/services/galileo-high-accuracy-service-has
- GNSS constellation status: https://www.gps.gov/systems/gnss/ · WGS84: https://earth-info.nga.mil/?dir=wgs84
- SBAS / WAAS: https://www.faa.gov/about/office_org/headquarters_offices/ato/service_units/techops/navservices/gnss/waas

## Related
`web-mobile-geolocation`, `device-integration-protocols`, `precision-positioning-rtk`,
`geospatial-data-postgis`, `ride-hailing-maps-master` (rendering/routing), `backend-api-master` (gps-integration)
