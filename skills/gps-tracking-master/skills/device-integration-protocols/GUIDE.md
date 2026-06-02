---
name: device-integration-protocols
description: >-
  Integrate hardware GPS trackers at staff depth: the real wire protocols (Teltonika Codec 8/8E,
  Concox/GT06, JT/T 808-2019, Queclink, u-blox UBX/NMEA), a production Node TCP ingestion server that
  frames + CRC-checks + ACKs GT06 login/location packets, the Teltonika IMEI handshake, JT808 0x7e
  framing/escaping, cellular bearer trade-offs (LTE-M vs NB-IoT vs 2G), MQTT ingestion, and the
  checksum/framing/auth gotchas that silently lose data. Binary, big-endian, and unforgiving.
---

# Device Integration & Tracker Protocols — Talking to Real Hardware

**A hardware tracker is a dumb, cheap modem that opens a raw TCP socket and pushes binary frames until you
ACK them — or it disconnects and retries forever.** There is no REST, no JSON, no TLS on most units. You
write a byte-exact server that frames a TCP *stream* (not packets), validates a checksum, decodes
big-endian fields, and **replies in the device's idle window** or it floods you with retransmits.

Get three things right and 90% of pain disappears: **framing** (TCP is a stream, frames split/coalesce),
**checksum** (wrong CRC = ignored device, or worse, accepted garbage), and **ACK** (no ACK = infinite retry).

---

## When to use this skill / when NOT

**Use it when** you ingest from dedicated trackers: vehicle OBD/hardwired units, asset/container trackers,
personal/pet trackers, e-bike/scooter IoT — anything speaking GT06/Teltonika/JT808/Queclink over TCP/UDP/MQTT.

**Do NOT** use it for: phone/browser capture (`web-mobile-geolocation`), how GNSS works
(`gps-gnss-fundamentals`), RTK corrections (`precision-positioning-rtk`), or what you do with decoded points
(`fleet-asset-tracking-platform`, `geospatial-data-postgis`). This skill ends at "a normalized fix object."

---

## 1. Mental model — the tracker ↔ server loop

```
Tracker boots → attaches to cellular (LTE-M/NB-IoT/2G) → opens TCP to your.host:PORT
   │
   ├─ LOGIN frame (IMEI)  ────────────────────────────▶  server: identify device, bind socket↔IMEI
   │  ◀──────────────────────  ACK (echo serial + CRC)     (device disconnects if no ACK in ~30–60 s)
   │
   ├─ LOCATION frames (every few s / on event) ────────▶  server: frame → checksum → decode → normalize
   │  ◀──────────────────────  ACK                          → publish to queue (Kafka/NATS/MQTT)
   │
   ├─ HEARTBEAT / STATUS / ALARM frames ───────────────▶  ACK; update presence; raise alarms
   └─ (server → device) COMMAND frames (cut fuel, locate, set interval)
```

Per-protocol that loop is the same shape; only the byte layout, checksum, and ACK rules differ. **One TCP
port per protocol family** (you can't auto-detect reliably across vendors) — or a front proxy that sniffs
the first bytes (`0x7878`/`0x7979` = GT06, `0x00000000` preamble = Teltonika, `0x7e` = JT808).

---

## 2. Protocol decision matrix

| Protocol | Vendors | Transport | Framing | Checksum | ACK requirement | Notes |
|----------|---------|-----------|---------|----------|-----------------|-------|
| **Concox GT06** | Concox/Jimi, + dozens of clones | TCP | `0x7878`(1B len)/`0x7979`(2B len) … `0x0D0A` | CRC-16/X-25 (CRC-ITU) | login + most frames | Ubiquitous, cheap, many dialects |
| **Teltonika Codec 8 / 8E / 16** | Teltonika FMB/FMC/FMM | TCP/UDP | `0x00000000` preamble + length | CRC-16/IBM | IMEI accept (0x01) + record-count ACK | Well-documented, rich I/O, CAN |
| **JT/T 808-2019** | Chinese commercial vehicle units (mandated) | TCP/UDP | `0x7e` … `0x7e` + escaping | XOR (1 byte) | platform general response 0x8001 | National standard; GBK strings |
| **Queclink GV/GL** | Queclink | TCP/UDP | ASCII `+RESP:`/`+BUFF:` ... `$` or HEX | varies | per config | Often **human-readable ASCII** — easiest to start |
| **u-blox UBX / NMEA** | u-blox modules (not a tracker) | serial/I2C/UART | `0xB5 0x62` (UBX) / `$`…`*cc` (NMEA) | UBX 2-byte Fletcher / NMEA XOR | n/a (it's a receiver) | You build the tracker around it |

> **Start with Queclink or a Teltonika-on-Traccar** if you're learning; GT06 (binary, dialect drift) is the
> deep end. For production you typically support 2–3 families behind one normalizer.

---

## 3. Production GT06 TCP ingestion server (Node `net`, copy-paste)

The GT06 frame: `START(2) | LEN | PROTO(1) | CONTENT(N) | SERIAL(2) | CRC(2) | STOP(2)`. `LEN` counts
`PROTO … CRC` (i.e., everything after the length byte up to but not including STOP). Checksum is **CRC-16/X-25**
(a.k.a. CRC-ITU: poly 0x1021 reflected, init `0xFFFF`, xorout `0xFFFF`) over **`LEN … SERIAL`**. The login
**ACK is 10 bytes**, echoing the device serial. Coordinates are `value = totalMinutes × 30000`, so
`degrees = raw / 1_800_000`; hemisphere + validity live in the 2-byte course/status word.

```ts
// gt06-server.ts — frames the TCP stream, validates CRC, decodes, ACKs. Production-shaped.
import net from "node:net";

const START_STD = 0x7878;   // 1-byte length
const START_EXT = 0x7979;   // 2-byte length
const PROTO = { LOGIN: 0x01, LOCATION: 0x12, STATUS: 0x13, STRING: 0x15, ALARM: 0x16, GPS_LBS: 0x1a, COMMAND: 0x80 };

/** CRC-16/X-25 (CRC-ITU) — reflected poly 0x1021 (=0x8408), init 0xFFFF, xorout 0xFFFF. GT06's checksum. */
function crc16X25(buf: Buffer): number {
  let crc = 0xffff;
  for (const b of buf) {
    crc ^= b;
    for (let i = 0; i < 8; i++) crc = crc & 1 ? (crc >>> 1) ^ 0x8408 : crc >>> 1;
  }
  return (~crc) & 0xffff;     // xorout 0xFFFF == bitwise NOT on 16 bits
}

/** Pull complete frames out of a rolling buffer. TCP is a STREAM: frames split AND coalesce. */
function* frames(buf: Buffer): Generator<{ frame: Buffer; consumed: number }> {
  let off = 0;
  while (off + 5 <= buf.length) {
    const start = buf.readUInt16BE(off);
    let lenSize: number, len: number;
    if (start === START_STD) { lenSize = 1; len = buf[off + 2]; }
    else if (start === START_EXT) { lenSize = 2; len = buf.readUInt16BE(off + 2); }
    else { off++; continue; }                 // resync: garbage byte, skip one
    const total = 2 + lenSize + len + 2;       // start + lenfield + (proto..crc) + stop
    if (off + total > buf.length) break;        // partial frame — wait for more bytes
    if (buf[off + total - 2] !== 0x0d || buf[off + total - 1] !== 0x0a) { off++; continue; } // bad stop → resync
    yield { frame: buf.subarray(off, off + total), consumed: total };
    off += total;
  }
  return; // caller keeps the unconsumed tail
}

function buildAck(proto: number, serial: number, extended: boolean): Buffer {
  // body that CRC covers = LEN + PROTO + SERIAL ; LEN counts proto+serial+crc = 5
  const body = Buffer.from([0x05, proto, (serial >> 8) & 0xff, serial & 0xff]);
  const crc = crc16X25(body);
  const head = extended ? Buffer.from([0x79, 0x79]) : Buffer.from([0x78, 0x78]);
  return Buffer.concat([head, body, Buffer.from([(crc >> 8) & 0xff, crc & 0xff, 0x0d, 0x0a])]);
}

function decodeLocation(content: Buffer) {
  // content starts AT the byte after PROTO. Layout (GT06 0x12): datetime6, satByte, lat4, lon4, speed1, course2, ...
  const yy = content[0], mo = content[1], dd = content[2], hh = content[3], mi = content[4], ss = content[5];
  const sats = content[6] & 0x0f;
  const latRaw = content.readUInt32BE(7);
  const lonRaw = content.readUInt32BE(11);
  const speedKmh = content[15];
  const flags = content.readUInt16BE(16);

  let lat = latRaw / 1_800_000, lon = lonRaw / 1_800_000;
  const course = flags & 0x03ff;                  // bits 0–9
  const positioned = (flags >> 12) & 1;           // BYTE1 bit4: GPS positioned
  if (!((flags >> 10) & 1)) lat = -lat;           // BYTE1 bit2: 1=North,0=South → negate if south
  if ((flags >> 11) & 1) lon = -lon;              // BYTE1 bit3: 1=West → negate
  return {
    fixTime: new Date(Date.UTC(2000 + yy, mo - 1, dd, hh, mi, ss)).toISOString(),
    lat, lon, speedKmh, course, satellites: sats, valid: !!positioned,
  };
}

const server = net.createServer((sock) => {
  let buffer = Buffer.alloc(0);
  let imei: string | null = null;
  sock.setTimeout(180_000, () => sock.destroy());   // drop dead sockets; protect the FD pool

  sock.on("data", (chunk) => {
    buffer = Buffer.concat([buffer, chunk]);
    let lastConsumed = 0, total = 0;
    for (const { frame, consumed } of frames(buffer)) {
      total += consumed; lastConsumed = consumed;
      const extended = frame.readUInt16BE(0) === START_EXT;
      const lenSize = extended ? 2 : 1;
      const proto = frame[2 + lenSize];
      const body = frame.subarray(2, frame.length - 2);            // LEN..CRC region we re-check
      const givenCrc = frame.readUInt16BE(frame.length - 4);
      if (crc16X25(body.subarray(0, body.length - 2)) !== givenCrc) continue; // drop corrupt frame

      const serial = frame.readUInt16BE(frame.length - 6);          // SERIAL precedes CRC
      const content = frame.subarray(3 + lenSize - 1, frame.length - 6); // bytes after PROTO

      if (proto === PROTO.LOGIN) {
        imei = content.subarray(0, 8).toString("hex").replace(/^0/, ""); // 8-byte BCD IMEI
        sock.write(buildAck(proto, serial, extended));               // MUST ACK login or device drops
      } else if (proto === PROTO.LOCATION || proto === PROTO.GPS_LBS) {
        if (!imei) { sock.destroy(); return; }                       // refuse data before login (auth)
        const fix = decodeLocation(content);
        publish({ imei, ...fix });                                   // → queue; never block the socket on DB
        sock.write(buildAck(proto, serial, extended));
      } else if (proto === PROTO.STATUS || proto === PROTO.ALARM) {
        sock.write(buildAck(proto, serial, extended));               // ACK heartbeats/alarms too
      }
      // unknown protocols: leave un-ACKed or ACK per dialect; log for dialect discovery
    }
    buffer = buffer.subarray(total);                                 // keep only the unparsed tail
    void lastConsumed;
  });
  sock.on("error", () => {/* connection resets are normal on cellular; don't crash */});
});
function publish(_fix: unknown) {/* enqueue to Kafka/NATS/Redis Stream; see fleet-asset-tracking-platform */}
server.listen(5023, () => console.log("GT06 ingest on :5023"));
```

> **Why a buffer + framing generator and not `sock.on('data')` = one packet?** Because it isn't. Cellular
> stacks coalesce several frames into one `data` event and split one frame across two. Treating each `data`
> chunk as a frame is the single most common GT06 server bug — it works on your desk and corrupts in the field.

---

## 4. Teltonika Codec 8 / 8E — TCP handshake + AVL

Teltonika (FMB/FMC/FMM) is binary but **well-documented and consistent** — the pleasant one.

```
TCP open → device sends: [0x00 0x0F][15 ASCII IMEI bytes]
server replies:           0x01 (accept)  | 0x00 (reject)
device sends AVL packet:
  [Preamble 4: 0x00000000][Data Field Length 4][Codec ID 1][Num Data 1][AVL records...][Num Data 1][CRC-16 4]
  Codec ID: 0x08 = Codec 8, 0x8E = Codec 8 Extended, 0x10 = Codec 16
server ACKs:              4-byte big-endian = number of records accepted  (e.g. 0x00000007)
```

Each AVL record: `Timestamp(8, ms since UNIX epoch)` · `Priority(1)` · **GPS element**
`Longitude(4) Latitude(4) Altitude(2) Angle(2) Satellites(1) Speed(2)` · IO element. **Coordinates are
signed int32 = degrees × 1e7** (e.g. `547146368 → 54.7146368°`; negative for S/W via two's complement —
don't divide by 1.8M like GT06). CRC is **CRC-16/IBM** over Codec-ID…second-Num-Data. Codec **8E** widens
IO IDs and counts from 1→2 bytes and adds variable-length IO (CAN/BLE/1-Wire blobs) — default to 8E support.

```ts
// teltonika GPS element decode (offset = start of GPS element within a record)
function teltonikaGps(b: Buffer, o: number) {
  return {
    lon: b.readInt32BE(o) / 1e7,            // signed: degrees × 1e7
    lat: b.readInt32BE(o + 4) / 1e7,
    altitudeM: b.readInt16BE(o + 8),
    angleDeg: b.readUInt16BE(o + 10),       // heading from north
    satellites: b.readUInt8(o + 12),        // GPS invalid → speed reads 0x0000
    speedKmh: b.readUInt16BE(o + 13),
  };
}
```

---

## 5. JT/T 808-2019 — the Chinese national standard

Mandatory for commercial vehicles in China; you *will* meet it sourcing cheap units. Frame: `0x7e | header |
body | XOR-checksum | 0x7e`. **Escaping** (because `0x7e`/`0x7d` can't appear inside): encode `0x7d → 0x7d 0x01`,
`0x7e → 0x7d 0x02` (escape `0x7d` *first*); on receive, **un-escape before checking the checksum**. Checksum =
1-byte XOR from the first header byte through the last body byte. Header carries **Message ID** (`0x0100`
register, `0x0102` auth, `0x0200` **location report**, `0x8001` platform general response, `0x8400` etc.),
a body-attribute word (bits: length, encryption, sub-package, version flag), a **BCD terminal phone number**
(6 bytes in 2013, **10 bytes in 2019**), and a serial number. All multi-byte fields **big-endian**.

The `0x0200` location body: `alarm(4) status(4) lat(4) lon(4) altitude(2) speed(2) direction(2) time(BCD6
YYMMDDHHMMSS) + TLV extras`. **Lat/lon here are degrees × 1e6** (e.g. `116400000 → 116.400000°`) — a *third*
coordinate encoding, distinct from GT06 and Teltonika. Strings are **GBK**, not UTF-8 — transcode or you get 乱码.

```ts
// JT808 un-escape (run BEFORE checksum verification); inverse of the encoder.
function jt808Unescape(payload: Buffer): Buffer {
  const out: number[] = [];
  for (let i = 0; i < payload.length; i++) {
    if (payload[i] === 0x7d && payload[i + 1] === 0x01) { out.push(0x7d); i++; }
    else if (payload[i] === 0x7d && payload[i + 1] === 0x02) { out.push(0x7e); i++; }
    else out.push(payload[i]);
  }
  return Buffer.from(out);
}
```

---

## 6. u-blox UBX / NMEA — when YOU build the tracker

A receiver module, not a tracker. It emits **NMEA** (ASCII; parse per `gps-gnss-fundamentals`) and the
binary **UBX** protocol (`0xB5 0x62 | class | id | len(2 LE) | payload | ck_a ck_b`, 8-bit Fletcher checksum,
**little-endian** — opposite of tracker protocols). UBX gives what NMEA can't: `UBX-NAV-PVT` (one message:
position+velocity+time+fix-type+accuracy estimates), `UBX-NAV-RELPOSNED` (RTK baseline), `UBX-RXM-RTCM`
(correction status). Configure with the **CFG-VALSET** key-value interface (the old CFG-* messages are
legacy). `carrSoln` in NAV-PVT: 0=none, 1=float, 2=fixed — your RTK status field (see `precision-positioning-rtk`).

---

## 7. Cellular bearers — the trade-off that sets your power & coverage budget

| Bearer | Throughput | Latency | Power | Mobility | Use for |
|--------|-----------|---------|-------|----------|---------|
| **2G/GPRS** | low | high | high | yes | Legacy; **sunsetting** in many regions — don't design new on it |
| **LTE-M (Cat-M1)** | ~375 kbps–1 Mbps | low | low | **yes (handover, moving)** | **Vehicles & moving assets** — the default for fleet |
| **NB-IoT** | ~26–127 kbps | high | lowest | poor (mostly stationary) | Static/slow assets: meters, bins, containers, deep-indoor |
| **4G/5G** | high | low | high | yes | Dashcams, video telematics, high-rate units |

Rules: **moving = LTE-M** (NB-IoT doesn't do cell handover well, so a moving NB-IoT tracker drops). **Static
+ tiny payloads + years on a battery = NB-IoT.** Both like **UDP/CoAP/MQTT-SN** over chatty TCP to save power;
trackers often coalesce/buffer fixes and send bursts to keep the radio asleep (expect out-of-order, batched
arrivals). Always know your operator's 2G/3G sunset timeline before shipping hardware that'll live 7 years.

---

## 8. MQTT ingestion — the modern path

Newer/Wi-Fi/4G trackers and your own u-blox-based builds can publish **MQTT** instead of raw TCP — far nicer
to operate (broker handles connections, retained last-position, QoS, TLS, per-device auth).

```ts
// mqtt ingest with per-device auth + idempotent publish downstream
import mqtt from "mqtt";
const client = mqtt.connect("mqtts://broker.internal:8883", {
  username: "ingest", password: process.env.MQTT_PW, // or per-device client certs (mTLS)
});
client.on("connect", () => client.subscribe("trackers/+/location", { qos: 1 }));
client.on("message", (topic, payload) => {
  const imei = topic.split("/")[1];                  // trackers/<imei>/location
  const fix = JSON.parse(payload.toString());        // or decode binary per device
  // de-dupe on (imei, fixTime); QoS1 means AT-LEAST-once → you WILL get duplicates
  publishNormalized({ imei, ...fix });
});
```

Use **QoS 1** (at-least-once) and dedupe downstream; QoS 2 is rarely worth its overhead for telematics.
mTLS or per-device credentials, and **topic ACLs** so device A can't publish as device B.

---

## 9. Device auth — the protocols barely have any

Raw tracker protocols authenticate by **IMEI only**, sent in cleartext, no shared secret — trivially
spoofable. Harden at the platform:
- **Allow-list IMEIs** (a device must be provisioned before its socket is accepted; reject unknown IMEIs).
- **Bind socket↔IMEI** at login; reject location frames that arrive before a valid login (as the GT06 server
  above does).
- Prefer **mTLS/MQTT credentials** where the hardware supports it (newer units do).
- **Detect impossible motion / duplicate IMEIs** (same IMEI from two IPs = clone) server-side.
- Terminate raw TCP at a gateway in a **DMZ**; never expose your app/DB directly to the open tracker port.

---

## 10. Performance — high-frequency ingestion

- **Never block the socket on the database.** Decode → push to a queue (Kafka/NATS/Redis Streams) → ACK.
  Persisting synchronously means one slow write stalls thousands of sockets and triggers a retransmit storm.
- One Node process holds **tens of thousands of idle tracker sockets** fine (they're mostly silent); scale
  horizontally behind an L4 load balancer with **sticky** (a device's socket must stay on one instance for
  the login↔IMEI binding) — or externalize session state.
- Pre-allocate/limit per-socket buffers and **cap frame size**; a malformed length field claiming 64 KB must
  not let a buffer grow unbounded (DoS). Bound it and resync.

---

## 11. Scale & reliability

- Treat ingestion as **at-least-once**; idempotency key `(imei, fixTime)` downstream kills duplicates from
  retransmits, QoS1, and reconnect buffer replays.
- Trackers buffer offline and **dump history on reconnect** — expect bursts and **out-of-order/old**
  timestamps; sort by `fixTime`, don't assume arrival order.
- Backpressure: if the queue is down, **stop ACKing** (let the device buffer) rather than ACK-and-drop —
  the device's flash buffer is your free overflow.
- Heartbeat/idle timeouts: drop sockets with no traffic in N minutes to protect the FD pool; the device reconnects.

---

## 12. Testing — simulators & captured traces

- Build a **device simulator** that opens a socket and replays real captured frames (login + N locations +
  heartbeat + a malformed frame + a split frame). This is your regression suite — no hardware needed in CI.
- Keep **hex fixtures** of real frames per protocol/dialect; assert decoded lat/lon/speed/time exactly.
- Fuzz the framer: random byte streams, truncated frames, wrong CRC, wrong stop bytes, oversized length —
  the server must resync and never crash or hang.
- **Traccar** (open-source, 200+ protocols) is the reference oracle: point a real device at it and diff your
  decode against its output.

---

## 13. Observability

- Per **IMEI**: last-seen, frames/min, ACK latency, CRC-failure rate, unknown-protocol count, decode errors.
- Per **protocol/dialect**: % frames dropped on CRC, % resync events (framing health), reconnect rate.
- Alert on: a device gone silent (no frames in expected interval), a spike in CRC failures (firmware/dialect
  drift or a corrupt unit), duplicate-IMEI from two IPs (clone/spoof), and retransmit storms (you stopped ACKing).

---

## 14. Accessibility & i18n

- Surface device identity by **human label + plate/asset name**, not raw IMEI, in any UI.
- **Decode strings with the right charset** (JT808 = GBK; others often GBK/Latin-1) and store as UTF-8.
- Normalize all device times to **UTC at ingestion**; render in the operator's locale/timezone upstream.

---

## 15. Opinionated anti-patterns

- ❌ Treating each TCP `data` event as exactly one frame (split/coalesce will corrupt you).
- ❌ Not ACKing (or ACKing with a wrong/zeroed serial) → infinite retransmit, self-DDoS.
- ❌ Wrong CRC variant (GT06 = CRC-16/X-25; Teltonika = CRC-16/IBM; JT808 = XOR) — silently rejected device.
- ❌ Confusing coordinate encodings: GT06 `÷1.8M`, Teltonika `×1e7`, JT808 `×1e6`. Mixing = wrong continent.
- ❌ Endianness slips: trackers are **big-endian**; UBX is **little-endian**.
- ❌ Persisting synchronously inside the socket handler (stalls all sockets).
- ❌ Trusting IMEI as authentication with no allow-list / clone detection.
- ❌ Assuming frames arrive in time order (offline buffers replay old fixes out of order).
- ❌ Auto-detecting protocol on a shared port instead of one port per family (or a sniffing proxy).

## 16. Agent checklist

```
- [ ] TCP framed from a rolling BUFFER (handle split + coalesced frames + resync)
- [ ] Correct checksum per protocol (X-25 / IBM / XOR) verified before decode, recomputed for ACK
- [ ] ACK sent within the device idle window, echoing the device serial
- [ ] Coordinate decode matches the protocol (÷1,800,000 / ×1e7 / ×1e6) + hemisphere/sign handled
- [ ] Big-endian for trackers (little-endian for UBX); times normalized to UTC
- [ ] Decode → enqueue → ACK; never block the socket on the DB
- [ ] Device auth: IMEI allow-list, socket↔IMEI binding, reject data before login, clone detection
- [ ] Idempotent downstream on (imei, fixTime); out-of-order + burst replay tolerated
- [ ] Bearer chosen (LTE-M moving / NB-IoT static); 2G sunset checked
- [ ] Simulator + hex fixtures + framer fuzz in CI; diffed against Traccar
- [ ] Per-IMEI + per-protocol metrics; alerts on silence, CRC spikes, retransmit storms
```

## References (2026-current)
- Teltonika protocols: https://wiki.teltonika-gps.com/view/Teltonika_Data_Sending_Protocols
- GT06 protocol (v1.8.1) & Traccar: https://www.traccar.org/protocols/ · https://github.com/traccar/traccar
- JT/T 808-2019 overview: https://www.chinesestandard.net (JT/T 808) · MQTT v5: https://mqtt.org/
- u-blox interface description (UBX/NMEA, CFG-VALSET): https://www.u-blox.com/en/product-resources (per module)

## Related
`gps-gnss-fundamentals` (NMEA/coords), `web-mobile-geolocation` (phone path), `precision-positioning-rtk` (u-blox/RTK),
`fleet-asset-tracking-platform` (what happens after decode), `integrations-master` (MQTT/webhooks), `backend-api-master`
