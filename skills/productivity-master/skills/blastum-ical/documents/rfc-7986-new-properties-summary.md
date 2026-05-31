# Summary: RFC 7986 — New properties for iCalendar

Source: [rfc-7986-new-properties](./rfc-7986-new-properties.txt)

## Key Facts

- **Updates** RFC 5545 (October 2016). Standards Track.
- Adds **calendar-level** (`VCALENDAR`) use of metadata: `NAME`, `DESCRIPTION`, `UID`, `LAST-MODIFIED`, `URL`, `CATEGORIES` — so subscriptions can show titles and sync identity without opening a `VEVENT`.
- New properties: `REFRESH-INTERVAL` (suggested polling), `SOURCE` (upstream URI), `COLOR` (CSS3 color for UI), `IMAGE` (URI or inline with `FMTTYPE`/`DISPLAY`), `CONFERENCE` (conferencing feature URIs/labels).
- New **parameters:** `DISPLAY` (e.g. badge, graphic, fullsize), `EMAIL` (on `ATTENDEE`/`ORGANIZER`), `FEATURE` (audio, video, chat, etc. on `CONFERENCE`), `LABEL` (human-readable conference label).

## Section Digest

### §3–4 Backwards compatibility

Extensions use existing iCalendar extensibility rules; clients that do not know a property should preserve it when possible (RFC 5545 behavior).

### §5 Properties (conceptual)

- **`NAME`:** human-visible calendar title.
- **`COLOR`:** `#rrggbb` or CSS3 name for client tinting.
- **`IMAGE` / `CONFERENCE`:** structured hooks for icons, logos, and click-to-join UX; `FEATURE` parameter lists capabilities.

### §7–8 Security / privacy

`IMAGE` and `CONFERENCE` URIs can be trackers or malicious links; same caution as any fetched URL. Privacy-sensitive data can appear in new descriptive fields.

## Tables & Structured Data

See RFC §9 IANA registries for formal property and parameter registrations.
