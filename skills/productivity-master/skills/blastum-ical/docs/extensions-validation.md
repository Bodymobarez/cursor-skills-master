# RFC 7986, RFC 6868, security, validation

Summaries: [rfc-7986-new-properties-summary.md](../documents/rfc-7986-new-properties-summary.md), [rfc-6868-escaped-strings-summary.md](../documents/rfc-6868-escaped-strings-summary.md), [icalendar-org-rfc-5545-overview-summary.md](../documents/icalendar-org-rfc-5545-overview-summary.md).

## RFC 7986 (updates 5545)

Adds **calendar-level** metadata so subscriptions can show titles without opening events:

- Properties such as **`NAME`**, **`DESCRIPTION`**, **`UID`**, **`LAST-MODIFIED`**, **`URL`**, **`CATEGORIES`** on `VCALENDAR`.
- **`REFRESH-INTERVAL`**, **`SOURCE`**, **`COLOR`**, **`IMAGE`**, **`CONFERENCE`** (with `FEATURE`, `LABEL`, etc.).
- New parameters include **`DISPLAY`**, **`EMAIL`** (on `ATTENDEE`/`ORGANIZER`).

Unknown properties/parameters should be **preserved** where possible (5545 extensibility).

## RFC 6868 — parameter escaping

- Use **caret** sequences **only inside parameter values** when you need quotes, controls, or carets: `^^` → `^`, `^'` → `"`, etc.
- Legacy parsers may treat carets literally; use when necessary for correct round-tripping.

## Security and privacy (format-level)

- iCalendar does **not** encrypt or authenticate content. Treat `DESCRIPTION`, `LOCATION`, `GEO`, URIs, **`IMAGE`**, **`CONFERENCE`**, and attachments as **untrusted** unless the transport and source are trusted.
- **`IMAGE` / `CONFERENCE` URIs** may be trackers or malicious links — same caution as any URL in email or web.

## Validation

- **iCalendar.org validator** applies RFC 5545 rules with a stated **512 KB** input limit (per [icalendar-org-rfc-5545-overview-summary.md](../documents/icalendar-org-rfc-5545-overview-summary.md)).
- Validate generated files; **cross-test imports** in major clients (checklist doc).

## SUMMARY length

May truncate to **255 octets** if needed but **MUST NOT** split a **UTF-8** multibyte sequence mid-sequence (§5).
