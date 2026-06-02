---
name: channel-manager-system
description: >-
  Build a hotel channel manager at staff/principal depth. Distribute a property's ARI (availability,
  rates, inventory, restrictions) to OTAs (Booking.com, Expedia, Agoda) and pull reservations back
  with reliable 2-way sync. Ships canonical ARI model + per-OTA channel adapters, a real Booking.com
  OTA_HotelRateAmountNotif push, the OTA_HotelResNotif GET→process→POST-ack reservation poll loop,
  atomic pooled-inventory decrement with overbooking protection, derived rates/restrictions, delta+
  full reconcile, and per-channel rate-limit handling. Covers OpenTravel connectivity standards.
---

# Channel Manager System

**Mandate: one source of truth (the property's CRS/PMS), pooled inventory, and a durable change queue
between you and every OTA.** A channel manager exists to prevent two things: **overbooking** (selling the
last room twice) and **drift** (an OTA showing a price/availability you no longer offer). If your CM can't
guarantee an atomic decrement on sale and a re-push within seconds, it is a liability, not a product.

## When to use this skill
- Building the *supply-distribution* side: you hold inventory and push it OUT to OTAs, pulling reservations IN.
- Connecting a property/chain to Booking.com / Expedia / Agoda connectivity.
- **Not** for consuming a bed bank's inventory (that's `supplier-api-integration`) or for the supplier UI to
  load rates (that's `extranet-system`). A CM sits *between* the extranet/CRS and the OTAs.

## What it syncs

```
OUT (push to channels):  Availability (rooms left) · Rates (price per rateplan/date) ·
                         Inventory (room types/rate plans) · Restrictions (MinLOS/MaxLOS, CTA/CTD, stop-sell)
IN  (pull from channels): new / modified / cancelled reservations  →  decrement pooled inventory, re-push
```

## Architecture

```
 CRS/PMS ──ARI change──► [ change queue ] ──per-OTA adapter──► OTA push API (rates/avail/restrictions)
    ▲                          │  (retry+backoff, dedupe, batch by date range)
    │                          ▼
 inventory ◄── atomic decrement ◄── reservation ingest ◄── poll/webhook ◄── OTA reservations API
 CM core: room/rate MAPPING table (your id ↔ OTA id) · pooled counters · rate derivation · reconcile job
```

## DECISION MATRIX — the choices that define the CM

| Decision | Option A | Option B | Pick |
|----------|----------|----------|------|
| **Inventory model** | **Pooled** (shared count, decrement on any sale) | Allocated (fixed per channel) | **Pooled** — only safe defense against oversell; allocate only for committed blocks |
| **Reservation delivery** | **Pull** (poll `OTA_HotelResNotif`, ack) | Push (OTA webhook to you) | Match the OTA — Booking.com is **pull+ack**; support webhooks where offered |
| **Rate derivation** | You compute child rates & push absolute | OTA derives from base + offset | Push absolute values you control — fewer "why is the price wrong" tickets |
| **Sync granularity** | Delta (changed dates only) | Full refresh | **Both**: deltas for speed, scheduled full reconcile to self-heal |
| **Connectivity per OTA** | Native API (BookingConnect/EQC/YCS) | Generic OpenTravel XML | Native where it exists (richer); OTA XML as the common shape |

## Canonical ARI model + channel adapter

```ts
export interface AriUpdate {
  propertyId: string; roomTypeId: string; ratePlanId: string;
  from: string; to: string;                 // ISO date range (inclusive)
  rate?: Money;                              // per night, per rate plan
  available?: number;                        // pooled count for the range
  restrictions?: { minLos?: number; maxLos?: number; cta?: boolean; ctd?: boolean; closed?: boolean };
}

export interface Reservation {
  channel: string; channelResId: string;     // dedupe key for idempotent ingest
  status: "NEW" | "MODIFIED" | "CANCELLED";
  propertyId: string; roomTypeId: string; ratePlanId: string;
  checkIn: string; checkOut: string; rooms: number;
  guest: { firstName: string; lastName: string }; total: Money;
}

export interface ChannelAdapter {
  readonly channel: string;                  // "booking" | "expedia" | "agoda"
  pushAri(u: AriUpdate, mapping: ChannelMapping): Promise<void>;
  pullReservations(since: string): Promise<{ reservations: Reservation[]; ack: () => Promise<void> }>;
}
```

The **mapping table** (`{ yourRoomTypeId, yourRatePlanId } ↔ { channel, channelRoomId, channelRateId }`) is
the #1 setup task and the #1 source of bugs. Treat it as first-class data with validation, not config.

## Reference: Booking.com push (OpenTravel `OTA_HotelRateAmountNotif`)

Booking.com connectivity is OpenTravel-XML over `https://supply-xml.booking.com/hotels/ota/...`, versioned
via the `Accept-Version` header, `Content-Type: application/xml`. Send **deltas** keyed by room type
(`InvTypeCode`) + rate plan (`RatePlanCode`) + date range.

```ts
function rateAmountNotifXML(u: AriUpdate, m: ChannelMapping): string {
  return `<?xml version="1.0" encoding="UTF-8"?>
<OTA_HotelRateAmountNotifRQ xmlns="http://www.opentravel.org/OTA/2003/05">
  <RateAmountMessages HotelCode="${m.channelHotelId}">
    <RateAmountMessage>
      <StatusApplicationControl Start="${u.from}" End="${u.to}"
        InvTypeCode="${m.channelRoomId}" RatePlanCode="${m.channelRateId}"/>
      <Rates><Rate><BaseByGuestAmts>
        <BaseByGuestAmt AmountAfterTax="${(u.rate!.amount / 100).toFixed(2)}" NumberOfGuests="2"/>
      </BaseByGuestAmts></Rate></Rates>
    </RateAmountMessage>
  </RateAmountMessages>
</OTA_HotelRateAmountNotifRQ>`;
}

async function pushToBooking(xml: string) {
  const res = await fetch("https://supply-xml.booking.com/hotels/ota/OTA_HotelRateAmountNotif", {
    method: "POST",
    headers: { "Content-Type": "application/xml", "Accept-Version": "1.1", Authorization: bookingAuth() },
    body: xml,
  });
  const body = await res.text();
  if (!res.ok || /Error/i.test(body)) throw new ChannelPushError("booking", res.status, body); // re-queue
}
```

> Availability/restrictions use `OTA_HotelAvailNotif`; room types/rate plans are set up via
> `OTA_HotelInvNotif` / `OTA_HotelRatePlanNotif` / `OTA_HotelProductNotif`. A property only goes **Open**
> once it has ≥1 room type, ≥1 rate plan, ≥1 room-rate, and ≥1 priced availability date.

## Reference: reservation pull loop (`OTA_HotelResNotif` GET → process → POST ack)

Booking.com delivers reservations via a **pull-and-acknowledge** cycle: GET new reservations since the last
call, integrate them, then POST an acknowledgement — leaving ~20s between cycles. Modifications/cancellations
come via `OTA_HotelResModifyNotif`.

```ts
async function reservationPollLoop(adapter: ChannelAdapter) {
  for (;;) {
    const { reservations, ack } = await adapter.pullReservations(lastCursor());
    for (const r of reservations) {
      // IDEMPOTENT ingest — dedupe by (channel, channelResId); a redelivery must NOT double-decrement.
      if (await alreadyIngested(r.channel, r.channelResId)) continue;
      await db.transaction(async (tx) => {
        await ingestReservation(tx, r);
        if (r.status === "NEW") await decrementPooled(tx, r);
        if (r.status === "CANCELLED") await releasePooled(tx, r);   // re-open inventory
      });
      await reSyncAvailability(r.propertyId, r.roomTypeId, r.checkIn, r.checkOut); // immediate re-push
    }
    await ack();                          // tell the OTA we processed; only then advance the cursor
    await sleep(20_000);                  // Booking.com recommends ~20s between GET calls
  }
}
```

## Pooled inventory & overbooking protection (the core invariant)

A sale on *any* channel must atomically decrement a single shared counter, and you must re-push the new
availability to *all* channels before the next sale can race it.

```sql
-- One row per (room type, date). Decrement is atomic and guarded — it CANNOT go negative.
UPDATE inventory
   SET available = available - :rooms
 WHERE room_type_id = :rt AND date = :d AND available >= :rooms
RETURNING available;          -- 0 rows affected ⇒ oversell attempt ⇒ reject + reconcile + alert
```

```ts
// Debounced re-push: many ARI changes in a burst → coalesce into one push per (room,dateRange) per channel.
const rePush = debouncePerKey(2000, async (key: string, u: AriUpdate) => {
  await Promise.allSettled(channels.map(c => enqueuePush({ channel: c.channel, update: u }))); // via queue, w/ retry
});
```

- **Pooled, not allocated:** allocation guarantees oversell or unsold rooms. Use allocation only for genuinely
  committed blocks (e.g. a tour-operator guarantee), and net it out of the pool.
- **Atomic decrement + guard** (`available >= :rooms`) prevents the last-room double-sell at the DB layer.
- **Debounce + immediate re-push** after every sale closes the race window across channels.

## Sync reliability (must-haves)
- **Durable change queue** for every ARI change; push with retry + exponential backoff; dead-letter on repeated
  failure with alerting. Never push straight from a request handler.
- **Delta + scheduled full reconcile:** deltas for latency, a nightly full ARI sync to self-heal silent drift.
- **Idempotent reservation ingest** by `(channel, channelResId)`; modifications via the modify endpoint, not a
  second NEW.
- **Per-channel rate-limit awareness:** batch updates by date range; respect each OTA's throttle; back off on 429.
- **Conflict resolution:** two near-simultaneous sales → atomic decrement wins, the loser is rejected and the
  true availability re-pushed immediately.

## Edge cases
- **Duplicate reservation delivery** (OTA resends before ack) → idempotent ingest is the only defense.
- **Cancellation re-opens inventory** — but only if it was previously decremented (check ingest provenance).
- **Currency:** push rates in the property's contracted currency per channel; don't silently FX-convert.
- **Date/timezone:** OTAs interpret stay dates in the property's locale — normalize and be explicit.
- **Connectivity version sunsets:** Booking.com is migrating `OTA_HotelProductNotif` to v1.3 (old versions
  sunsetting in 2026) — pin `Accept-Version` and track deprecation calendars, or pushes start 400-ing.

## Performance / scale / observability
- A chain pushes millions of ARI cells/day — coalesce, batch by date range, and shard the queue by property.
- Track **sync lag** (change→OTA-confirmed), push success/retry/dead-letter rates, **oversell-attempt count**
  (should be ~0), reservation-ingest lag, and per-channel 429 rate. Alert on rising sync lag — it precedes oversell.

## Security
- OTA credentials per property × channel in a vault; rotate; scope tokens narrowly.
- Reservation payloads contain guest PII — encrypt at rest, mask in logs, short retention per GDPR.

## Testing
- Use each OTA's test/staging connectivity; record real XML/JSON as fixtures; assert your mapping round-trips.
- Property-test the pooled decrement under concurrency (it must never go negative); chaos-test push failures
  → queue retry → reconcile convergence.

## i18n / RTL & currency
- Content (descriptions, room names) is multi-language — push per the OTA's locale fields; Arabic/Hebrew RTL.
- Rates per channel currency; never assume one currency across all channels.

## Anti-patterns
- Allocated inventory everywhere → oversell or unsold rooms (prefer pooled).
- Pushing ARI directly from request handlers without a durable queue/retry → drift.
- No full-reconcile job → silent drift accumulates until an oversell.
- Non-idempotent reservation ingest → duplicate bookings / double decrements.
- Ignoring OTA rate limits & version sunsets → throttling, suspension, or 400s.
- Letting OTA-derived rates and your computed rates both exist → inconsistent prices.

## Checklist
```
- [ ] Canonical ARI model + per-OTA channel adapters behind it
- [ ] Room-type & rate-plan mapping table (validated, first-class data)
- [ ] Pooled inventory with atomic guarded decrement; immediate debounced re-push on sale
- [ ] Derived rates + restrictions (MinLOS/MaxLOS/CTA/CTD/stop-sell)
- [ ] Durable ARI change queue + retry/backoff + dead-letter + scheduled full reconcile
- [ ] Reservation pull (GET→process→POST ack) idempotent by (channel, channelResId)
- [ ] Modify/cancel re-opens inventory; provenance tracked
- [ ] Per-channel rate-limit handling, version pinning, sync-lag + oversell-attempt alerts
```

## References (2026-current)
- Booking.com Connectivity (OTA_HotelRateAmountNotif, reservations, open/bookable, deprecations): https://developers.booking.com/connectivity/docs
- Expedia Partner Central / EQC connectivity: https://developers.expediagroup.com
- OpenTravel Alliance schemas: https://opentravel.org
- HTNG (Hospitality Technology Next Generation) specs: https://www.htng.org

## Related
`extranet-system`, `supplier-api-integration`, `mapping-system`, `travel-tech-architecture`;
pairs with `backend-api-master` (queues, webhooks), `devops-master` (queue infra, scaling).
