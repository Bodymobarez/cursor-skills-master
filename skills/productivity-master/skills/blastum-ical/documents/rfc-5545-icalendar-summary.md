# Summary: RFC 5545 — iCalendar core

Source: [rfc-5545-icalendar](./rfc-5545-icalendar.txt)

## Key Facts

- **Normative name:** Internet Calendaring and Scheduling Core Object Specification (iCalendar). **Obsoletes** RFC 2445. **Category:** Standards Track (September 2009).
- **Media type:** `text/calendar` — registered in RFC 5545 §8; MIME examples show `method` and `component` parameters on Content-Type.
- **Charset:** Implementations **MUST** generate UTF-8; **MUST** accept UTF-8 or US-ASCII (§6 Internationalization).
- **File / transport:** Often named `.ics` or `.ifb` (free/busy); format is independent of CalDAV/iTIP (those are separate protocols that carry iCalendar data).
- **Line model:** Logical lines = `name`/`param`*`:` `value` `CRLF`. Physical lines ≤ 75 octets should use **folding**: continuation lines start with a single space or tab (§3.1).
- **Binary vs text:** `ENCODING=BASE64` and `VALUE=BINARY` for binary attachments; default value type is context-dependent per property.

## Section Digest

### Object structure (§3.4–3.6)

- One **iCalendar object** is wrapped in `BEGIN:VCALENDAR` / `END:VCALENDAR`.
- Required calendar properties: `PRODID`, `VERSION` (value `2.0`).
- **Components** (each `BEGIN:x` … `END:x`): `VEVENT`, `VTODO`, `VJOURNAL`, `VFREEBUSY`, `VTIMEZONE`, `VALARM` (alarm is nested under others). Time zone uses nested `STANDARD` and `DAYLIGHT` subcomponents.
- **Calendar properties** (on `VCALENDAR`): `CALSCALE` (default GREGORIAN), `METHOD` (when used with iTIP-like semantics), `PRODID`, `VERSION`.

### Property parameters (§3.2 — “options” on properties)

Examples of registered parameters: `ALTREP`, `CN`, `CUTYPE`, `DELEGATED-FROM`, `DELEGATED-TO`, `DIR`, `ENCODING`, `FMTTYPE`, `FBTYPE`, `LANGUAGE`, `MEMBER`, `PARTSTAT`, `RANGE`, `RELATED`, `RELTYPE`, `ROLE`, `RSVP`, `SENT-BY`, `TZID`, `VALUE`, plus others in §3.2. Parameters qualify the property value (language, timezone, participation, etc.).

### Value data types (§3.3)

Registered types include: `BINARY`, `BOOLEAN`, `CAL-ADDRESS`, `DATE`, `DATE-TIME`, `DURATION`, `FLOAT`, `INTEGER`, `PERIOD`, `RECUR`, `TEXT`, `TIME`, `URI`, `UTC-OFFSET`. `DATE-TIME` may be floating (no TZ) or tied to `TZID` / UTC suffix `Z`.

### Component properties (§3.8 — major groups)

- **Descriptive:** `ATTACH`, `CATEGORIES`, `CLASS`, `COMMENT`, `DESCRIPTION`, `GEO`, `LOCATION`, `PERCENT-COMPLETE`, `PRIORITY`, `RESOURCES`, `STATUS`, `SUMMARY`.
- **Date/time:** `COMPLETED`, `DTEND`, `DUE`, `DTSTART`, `DURATION`, `FBTYPE` usage with `FREEBUSY`, `TRANSP`.
- **Time zone:** `TZID`, `TZNAME`, `TZOFFSETFROM`, `TZOFFSETTO`, `TZURL`.
- **Relationships:** `ATTENDEE`, `CONTACT`, `ORGANIZER`, `RECURRENCE-ID`, `RELATED-TO`, `URL`, `UID`.
- **Recurrence:** `EXDATE`, `RDATE`, `RRULE`.
- **Alarm:** `ACTION`, `REPEAT`, `TRIGGER` (with related duration/repeat rules in §3.8.6).
- **Change management:** `CREATED`, `DTSTAMP`, `LAST-MODIFIED`, `SEQUENCE`.
- **Misc:** `IANA` / `X-` non-standard properties, `REQUEST-STATUS`.

Full cardinality and defaults are per-component tables in RFC 5545 (§3.6.x).

### Recurrence (§3.3.10, §3.8.5)

- `RRULE` uses `FREQ`, `UNTIL`/`COUNT`, `INTERVAL`, `BY*` parts; week start `WKST`.
- `EXDATE` / `RDATE` interact with `RRULE`; **recommended practice:** duplicate start times from RRULE+RDATE collapse to one instance (RFC §5).

### Recommended practices (§5 — excerpt)

1. Fold lines > 75 octets.
2. Collapse duplicate instance start times from RRULE+RDATE; RDATE as PERIOD overrides instance duration.
3. Duplicate scheduling requests from multiple mailing lists: respond once; use `MEMBER` on `ATTENDEE` where appropriate.
4. `SUMMARY` may be truncated to 255 octets but **not** mid UTF-8 sequence.
5. If seconds unsupported, use `00` for seconds.
6. Avoid `file:` `TZURL` on the open Internet.
7. Suggested English `CATEGORIES` / `RESOURCES` tokens listed in §5 (informative examples).

### Security (§7)

Format alone does not protect privacy; transport/protocol must address confidentiality, integrity, and authenticity.

## Tables & Structured Data

| Item | Role |
|------|------|
| `VCALENDAR` | Root container |
| `VEVENT` | Scheduled occurrence or event |
| `VTODO` | Task |
| `VJOURNAL` | Journal entry |
| `VFREEBUSY` | Free/busy grid |
| `VTIMEZONE` | TZ definitions for `TZID` references |
| `VALARM` | Reminder or action |

For every property name, allowed parameters, value type, and component applicability, the RFC §3 tables are authoritative.
