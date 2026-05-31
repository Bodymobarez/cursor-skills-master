# Summary: iCalendar Kit (thoven87) — README

Source: [icalendar-kit-thoven-readme](./icalendar-kit-thoven-readme.md)

## Key Facts

- **Swift SPM:** `https://github.com/thoven87/icalendar-kit.git` from **`2.0.0`**; import **`ICalendar`**.
- **Parse:** `try ICalendarKit.parseCalendar(from: icalContent)`; access **`calendar.events`** (example).
- **Serialize:** Build `EventBuilder` → `buildEvent()`, add to `ICalendar(productId:)`, then **`ICalendarSerializer().serialize(calendar)`**.
- **RFCs claimed complete (README table):** 5545, 7986, 6868, 7808, **9073** (event publishing / venue-style extensions).
- **Extras:** **VCard** builders/serializer; **Linux** supported; Swift **6.0+**, Xcode **16+**, Apple platforms as listed in README.
- **Interop:** README mentions **legacy X-WR fallbacks** for older calendar systems.
- **License:** MIT.

## Section Digest

### Features

Swift 6 **Sendable** / concurrency, fluent **EventBuilder**, alarms, time zones, recurrence, todos, journals (listed at high level).

### Quick start — authoring

`EventBuilder(summary:)` chaining: scheduling, transparency, sequence, geo, **COLOR**, **CONFERENCE**, attachments, organizer, attendees, alarms; then `ICalendar` + serializer.

### Quick start — parsing

Multi-line `BEGIN:VCALENDAR` … `END:VCALENDAR` string passed to `parseCalendar`.

### EventBuilder surface

Large property table: scheduling, status, priority, classification, transparency, versioning, location/geo, visual (color/image), modern (conference/attachment), RFC 9073 venue/resource, people, recurrence, alarms.

### Documentation

Points to in-repo DocC: `Sources/ICalendar/Documentation.docc/ICalendar.md`.
