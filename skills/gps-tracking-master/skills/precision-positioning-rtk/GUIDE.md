---
name: precision-positioning-rtk
description: >-
  Centimeter GNSS at staff depth: RTK vs DGPS vs PPP vs PPP-RTK decision matrix, base/rover carrier-phase
  ambiguity resolution (fix vs float), RTCM3 message sets, the NTRIP stack (caster/server/client, sourcetable,
  mountpoints, VRS GGA upload, NTRIP v1 vs v2) with a real Node NTRIP client, public + commercial correction
  networks, and u-blox ZED-F9P rover integration (CFG-VALSET, RTCM on UART2, NAV-PVT carrSoln). For survey,
  drone, agriculture, and machine control.
---

# Precision Positioning & RTK — Centimeters, Honestly

**RTK works by resolving the integer number of carrier wavelengths between you and a known base — when that
"ambiguity" is fixed, you get 1–2 cm; until then you're "float" at decimeters.** Everything here is about
getting and keeping that integer fix: a nearby base, a clean correction stream (RTCM3 over NTRIP), and a
dual-frequency rover. Lose the corrections for a few seconds and you drop to float; that's the whole drama.

If you only need 1–5 m, **you do not need this skill** and you should not pay its cost. RTK is for the jobs
where centimeters are the product: survey stakeout, drone mapping (PPK/RTK), precision agriculture (auto-steer),
construction machine control, and lane-level automotive.

---

## When to use this skill / when NOT

**Use it when** the requirement is **sub-decimeter** and you control (or can subscribe to) a correction source.

**Do NOT** use it for: consumer 3–5 m navigation (`gps-gnss-fundamentals` + a normal receiver), phone apps
(phones are not RTK rovers — a handful have raw measurements but it's fragile), or tracker ingestion
(`device-integration-protocols`). RTK adds a dual-freq receiver, a correction subscription/base, and
convergence complexity — justify it.

---

## 1. Mental model — differential, not magic

```
        BASE (antenna on a SURVEYED point, knows its exact coords)
          │ observes the same satellites, computes "how wrong each pseudorange/phase is right now"
          │ encodes that as RTCM3 messages
          ▼
   ┌──── correction transport ────┐
   │  NTRIP caster (internet)  OR  │   radio link (UHF/LoRa, base→rover direct)
   └───────────────────────────────┘
          ▼
        ROVER (your moving receiver)
          applies corrections → cancels the errors COMMON to both (ionosphere, orbit, clock)
          resolves carrier-phase integer ambiguity → FIX (1–2 cm + 1 ppm × baseline)
```

The errors GNSS can't model (ionosphere, troposphere, orbit, clock) are **spatially correlated** — nearly
identical for two receivers a few km apart. Differencing cancels them. That's why RTK accuracy **degrades
with baseline** (the `+1 ppm` term: ~1 cm extra per 10 km) and why **≤ ~20–30 km to the base** is the
practical rule before you need network RTK.

---

## 2. RTK vs DGPS vs PPP vs PPP-RTK (DECISION MATRIX)

| Method | Measurement | Accuracy | Convergence | Base needed? | Coverage | Best for |
|--------|-------------|----------|-------------|--------------|----------|----------|
| **DGPS** | code differential | 0.3–1 m | seconds | nearby base/SBAS | local | Legacy marine, sub-metre GIS |
| **RTK** | carrier phase + base | **1–2 cm + 1 ppm** | seconds (with fix) | **yes, ≤~30 km** | local/NTRIP network | Survey, drone, auto-steer, machine control |
| **Network RTK (VRS)** | carrier phase + CORS net | 1–3 cm | seconds | network (no own base) | regional net | Survey without owning a base |
| **PPP** | precise orbit/clock, global | 5–30 cm | **5–30+ min** | no | global | Open ocean/field, no base reachable |
| **PPP-RTK (SSR)** | PPP + atmospheric (state-space) | 3–10 cm | seconds–min | no (uses correction service) | regional→global | Mass-market/auto precision |

How to choose:
- **Base within ~20 km (own or NTRIP network)?** → **RTK** — fastest fix, best accuracy.
- **No base, can wait minutes, need global?** → **PPP** (Galileo HAS is *free*; commercial like u-blox
  PointPerfect for faster/assured). Convergence is the tax.
- **Want RTK-like speed without owning a base, in a covered region?** → **Network RTK (VRS)** or **PPP-RTK**.
- **Only need sub-metre?** → **DGPS/SBAS**, don't pay for RTK.

---

## 3. Fix vs Float — the only status that matters

| Solution | Ambiguity | Accuracy | Trust it? |
|----------|-----------|----------|-----------|
| **None / autonomous** | — | 3–5 m | No (it's standalone) |
| **Float** | not resolved (real-valued) | 0.2–1 m, drifting | **No** — for survey/stakeout, never record float |
| **Fix** | resolved (integer) | **1–2 cm** | Yes |

Operational truth: **record only FIX**. A "float" looks precise but wanders decimetres; logging it as truth
is the classic survey blunder. Watch the transition fix→float (corrections dropped, sky blocked, baseline too
long) and **re-converge** before trusting again. On u-blox: `UBX-NAV-PVT.flags.carrSoln` = 0 none / 1 float /
2 fixed; in NMEA GGA: **quality 4 = RTK fixed, 5 = RTK float**.

---

## 4. RTCM3 — the correction wire format

RTCM **3.x** (binary, framed `0xD3 | len(10b) | payload | CRC-24Q`) is the universal correction format. You
don't hand-parse it (the rover firmware does) — but you must configure **which messages** the base sends,
matched to the rover's constellations:

| RTCM3 messages | Carry | Notes |
|----------------|-------|-------|
| **1005 / 1006** | Base station ARP coordinates (1006 adds height) | Required so rover knows the base position |
| **1074/1077, 1084/1087, 1094/1097, 1124/1127** | **MSM4/MSM7** observations: GPS / GLONASS / Galileo / BeiDou | Use **MSM7** (full) for modern multi-GNSS; one set per constellation you use |
| **1230** | GLONASS code-phase biases | Needed for GLONASS RTK across mixed receiver brands |
| **1033 / 1008** | Receiver & antenna descriptors | Helps mixed-vendor antenna phase-center handling |

Rule: the base must broadcast **1005/1006 + the MSM messages for every constellation the rover tracks**,
or that constellation can't contribute to the fix. Mismatched message sets = stuck on float.

---

## 5. NTRIP — how corrections travel over the internet

NTRIP (Networked Transport of RTCM via Internet Protocol) is HTTP-ish, port **2101** by convention. Three roles:

- **NTRIP Server** — software next to a base; *pushes* that base's RTCM to a caster (uploads a stream to a mountpoint).
- **NTRIP Caster** — the HTTP server; receives streams from servers, serves them to clients; publishes a
  **sourcetable** (the catalog of mountpoints: location, format, constellations, whether it needs GGA).
- **NTRIP Client** — your rover (or a relay); *pulls* RTCM from a chosen **mountpoint** and feeds it to the receiver.

**VRS (Virtual Reference Station)** mountpoints synthesize a base *at your location* from a CORS network — so
the rover must **upload its NMEA `GGA`** position upstream (every ~5–10 s) so the caster knows where to
generate corrections. **NTRIP v2** is cleaner HTTP/1.1 (chunked, standard headers); **v1** is a quirky
pre-HTTP handshake (`ICY 200 OK`). Support both — many casters are still v1.

```ts
// ntrip-client.ts — pull RTCM3 from a caster mountpoint, push to the receiver, upload GGA for VRS.
import net from "node:net";

interface NtripOpts {
  host: string; port?: number; mountpoint: string;
  user: string; pass: string;
  onRtcm: (chunk: Buffer) => void;        // pipe straight to the receiver's RTCM input port
  getGga?: () => string | null;           // return current $..GGA line for VRS casters (null until you have a fix)
}

export function connectNtrip(o: NtripOpts) {
  const port = o.port ?? 2101;
  const auth = Buffer.from(`${o.user}:${o.pass}`).toString("base64");
  const sock = net.connect(port, o.host);
  let headerDone = false, buf = Buffer.alloc(0);

  sock.on("connect", () => {
    sock.write(
      `GET /${o.mountpoint} HTTP/1.1\r\n` +
      `Host: ${o.host}\r\n` +
      `Ntrip-Version: Ntrip/2.0\r\n` +
      `User-Agent: NTRIP node-rover/1.0\r\n` +
      `Authorization: Basic ${auth}\r\n` +
      `Connection: close\r\n\r\n`,
    );
  });

  sock.on("data", (chunk) => {
    if (!headerDone) {
      buf = Buffer.concat([buf, chunk]);
      const sep = buf.indexOf("\r\n\r\n");
      if (sep < 0) return;
      const header = buf.subarray(0, sep).toString("latin1");
      // Accept BOTH: v2 "HTTP/1.1 200" and v1 "ICY 200 OK"
      if (!/200/.test(header.split("\r\n")[0])) { sock.destroy(); throw new Error(`NTRIP: ${header.split("\r\n")[0]}`); }
      headerDone = true;
      const rest = buf.subarray(sep + 4);
      if (rest.length) o.onRtcm(rest);                 // RTCM may trail the header in the same packet
      // VRS: start sending our position upstream so corrections are generated for HERE
      const tick = setInterval(() => { const g = o.getGga?.(); if (g) sock.write(g + "\r\n"); }, 10_000);
      sock.on("close", () => clearInterval(tick));
      return;
    }
    o.onRtcm(chunk);                                   // steady state: raw RTCM3 → receiver
  });

  sock.on("error", () => {/* reconnect with backoff — field links drop constantly */});
  return () => sock.destroy();
}
```

> Reconnect-with-backoff is mandatory, not optional: cellular/Wi-Fi in the field drops, and **every dropout
> risks a fix→float transition**. Keep a watchdog: "no RTCM for N seconds → reconnect."

---

## 6. Correction networks — what to actually subscribe to

| Type | Examples | Cost | When |
|------|----------|------|------|
| **Free/community casters** | **RTK2Go**, national CORS (e.g. NOAA CORS, EUREF) | free | Hobby, dev, sparse pro use; no SLA |
| **Government CORS** | many national geodetic agencies | free/low | Survey where a public net exists |
| **Commercial network RTK** | Trimble VRS Now, Hexagon/Leica SmartNet, regional providers | $$ | Pro survey/construction, SLA + coverage |
| **Global PPP / PPP-RTK** | u-blox PointPerfect, others; **Galileo HAS (free)** | free–$$$ | No base reachable / mass deployment |

Pick by **coverage at your job sites + SLA + receiver compatibility**. For one site far from any network,
**run your own base** (survey its position precisely first — a base on a wrong coordinate makes every rover
fix precisely wrong by the same offset).

---

## 7. u-blox ZED-F9P rover integration (concept)

The ZED-F9P (and newer ZED-X20P) is the workhorse low-cost dual-band RTK receiver. Wiring the rover:

1. **Feed RTCM3 in.** Route your NTRIP client's bytes to a receiver input port — commonly **UART2** (default
   **38400** baud) or USB/I2C/SPI. Configure input protocol to accept RTCM3 on that port.
2. **Output what you need.** Enable `UBX-NAV-PVT` (position + `carrSoln` fix/float) and high-precision NMEA
   (`CFG-NMEA-HIGHPREC=1`, plus `GGA` for VRS upload and `GST` for accuracy estimates).
3. **Use the modern config interface — `CFG-VALSET`** (key-value), not legacy `CFG-*` messages. Persist to
   flash/BBR so settings survive reboot.

```
# Representative CFG-VALSET keys (set via UBX or ubxtool/u-center; names are u-blox's):
CFG-UART2INPROT-RTCM3X = 1          # accept RTCM3 on UART2 (correction input)
CFG-MSGOUT-UBX_NAV_PVT_USB = 1      # position+velocity+time+carrSoln on USB
CFG-MSGOUT-NMEA_ID_GGA_UART1 = 1    # GGA out (feed back to NTRIP client for VRS)
CFG-NMEA-HIGHPREC = 1               # extra decimal places (default truncates cm away!)
CFG-NAVSPG-DYNMODEL = <portable|automotive|...>   # match the platform dynamics
```

Then watch `NAV-PVT.flags.carrSoln`: `0 → 1 (float) → 2 (fixed)`. Typical good-sky time-to-fix is seconds to a
minute. `NAV-RELPOSNED` gives the precise baseline vector for moving-baseline (heading from two antennas).

> Gotcha that bites everyone: **`CFG-NMEA-HIGHPREC` off** silently truncates NMEA lat/lon to ~mm-meaningless
> decimal places, so your cm fix arrives rounded to metres downstream. Turn it on, or read coordinates from UBX.

---

## 8. Use-case notes

- **Survey / stakeout:** record **fix only**, with the correct **datum/epoch** (WGS84 vs ETRS89/GDA2020 — see
  `gps-gnss-fundamentals` §8; plate motion is cm/yr, real at this accuracy). Keep RMS/σ from `GST`.
- **Drone mapping:** **RTK** (live) or **PPK** (post-process: log raw rover + base, fix later — survives link
  dropouts, ideal for BVLOS/poor-signal). Time-sync the camera trigger to GNSS (event marker) for cm geotags.
- **Precision agriculture:** auto-steer needs **pass-to-pass** repeatability; network RTK or a farm base.
  Continuity through headland turns matters more than absolute accuracy.
- **Machine control / automotive:** PPP-RTK/SSR for scalable lane-level; integrity (is the fix *trustworthy*)
  matters as much as accuracy — pair with IMU dead-reckoning through outages.

---

## 9. Edge cases & gotchas

- **Baseline too long** (>20–30 km) → can't fix, stuck on float; use network RTK/VRS.
- **Multipath/canopy/urban canyon** → fix drops to float or false-fixes; choke-ring/ground-plane antenna and
  good sky help more than anything in software.
- **Correction latency/age** → corrections older than a few seconds degrade the solution; monitor "RTCM age."
- **Constellation mismatch** base↔rover → that constellation silently doesn't help.
- **Base on a wrong coordinate** → every rover fix is precisely offset by the base error (garbage in).
- **Half-cycle/cycle slips** on signal interruption → brief float until re-fix.
- **Datum confusion** → cm accuracy in the wrong frame is still wrong by a metre+.

---

## 10. Security & privacy

- NTRIP credentials are often **Basic auth in cleartext** — prefer casters/relays over **TLS**; rotate
  credentials; don't embed shared creds in firmware you can't update.
- Centimeter tracks are extremely sensitive (exact field/asset/person location) — treat as high-grade PII;
  encrypt and restrict.
- A spoofed/forged correction stream can push a rover to a confidently wrong fix — source corrections only
  from trusted casters; validate base coordinates; cross-check with IMU/odometry for safety-critical control.

---

## 11. Scale & reliability

- One **NTRIP caster** fans the same base stream to many rovers cheaply (it's a stream multiplexer); VRS
  scales per-client because each gets a tailored stream (heavier — size the network service accordingly).
- **Watchdog + exponential backoff reconnect** on the client; buffer/relay corrections close to fleets to cut
  latency. For many rovers, run a **relay** that holds one caster connection and re-broadcasts (respect caster ToS).
- Log correction **age** and **fix-ratio** per rover to catch a degrading network before crews do.

---

## 12. Testing

- **Replay recorded RTCM3** + a static rover log to validate your client/relay deterministically (no field trip).
- **Zero-baseline / short-baseline test:** two receivers on one antenna (splitter) or a few metres apart — the
  computed baseline should be ~0 / the known distance; a great correctness check for the whole chain.
- **PPK as ground truth:** post-process the same data and diff against your live RTK fixes.
- Simulate dropouts: cut corrections mid-stream, assert fix→float→re-fix and that you **never log float as fix**.

---

## 13. Observability

- Per rover: **solution status** (none/float/fix) over time, **time-to-fix**, **fix uptime %**, **RTCM age**,
  **baseline length**, **HDOP/σ (GST)**, NTRIP reconnect count.
- Alert on: prolonged float, RTCM age climbing (correction starvation), repeated NTRIP 401/403 (creds), and
  baseline exceeding your network's design distance.

---

## 14. Accessibility & i18n

- Present status as **plain language + color** ("RTK FIXED ±1.5 cm" green / "FLOAT — do not record" amber),
  not a raw enum, to field crews.
- Localize units (cm/m, metric/imperial), datum/CRS labels, date/time; support RTL. Make "record point"
  physically hard to trigger while float.

---

## 15. Opinionated anti-patterns

- ❌ **Recording float as truth.** The cardinal RTK sin.
- ❌ Reporting "RTK accuracy" with no fix/float status and no baseline/RTCM-age context.
- ❌ Base set up on an unsurveyed/approximate coordinate (offsets every rover identically).
- ❌ Expecting **PPP to be instant** (it converges over minutes) or RTK to hold past ~30 km baseline.
- ❌ Mismatched base/rover constellation message sets; forgetting **1005/1006** so the rover has no base coords.
- ❌ `CFG-NMEA-HIGHPREC` left off → cm fix truncated to metres in NMEA output.
- ❌ No reconnect/backoff on the NTRIP client (one Wi-Fi blip = lost fix for the rest of the job).
- ❌ Treating a phone as an RTK rover for survey-grade work.
- ❌ Ignoring datum/epoch — cm accuracy in the wrong frame.

## 16. Agent checklist

```
- [ ] Right method chosen (RTK ≤30 km / Network-RTK VRS / PPP global-but-slow / DGPS sub-metre)
- [ ] Record FIX only; float never logged as truth; fix→float transitions monitored
- [ ] Base broadcasts 1005/1006 + MSM7 for EVERY rover constellation (+1230 for GLONASS)
- [ ] NTRIP client supports v1 (ICY) + v2; sends GGA upstream for VRS; reconnect w/ backoff + watchdog
- [ ] Rover (ZED-F9P): RTCM3 in on UART2/USB, NAV-PVT + HIGHPREC NMEA out, configured via CFG-VALSET, persisted
- [ ] carrSoln / GGA quality (4=fix,5=float) surfaced; RTCM age + baseline tracked
- [ ] Correct datum/epoch for the deliverable; antenna phase-center & height handled
- [ ] NTRIP creds over TLS where possible, rotated; corrections sourced from trusted casters only
- [ ] Zero/short-baseline + RTCM-replay + dropout tests pass; PPK cross-check for drone/survey
```

## References (2026-current)
- RTCM SC-104 standards: https://www.rtcm.org/ · NTRIP overview: https://igs.bkg.bund.de/ntrip/
- u-blox ZED-F9P + PointPerfect/PPP: https://www.u-blox.com/en/technologies/precise-point-positioning-ppp
- Galileo HAS (free PPP): https://www.gsc-europa.eu/galileo/services/galileo-high-accuracy-service-has
- RTK2Go community caster: https://rtk2go.com/ · SparkFun ZED-F9P NTRIP examples (GitHub)

## Related
`gps-gnss-fundamentals` (datums/accuracy/fix flags), `device-integration-protocols` (u-blox UBX, transports),
`geospatial-data-postgis` (storing high-precision points), `web-mobile-geolocation` (consumer accuracy contrast)
