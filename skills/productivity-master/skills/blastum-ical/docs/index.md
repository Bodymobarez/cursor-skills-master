# iCalendar — topic index

## Quick reference

- **MIME:** `text/calendar` (often `.ics` / `.ifb`). **Charset:** generate **UTF-8**; parsers must accept UTF-8 or US-ASCII (RFC 5545 §6).
- **Envelope:** `BEGIN:VCALENDAR` … `END:VCALENDAR` with **`VERSION:2.0`** and **`PRODID`** required.
- **Logical line:** `NAME[;param=value]*:value` then **`CRLF`**. Fold lines **> 75 octets** with a single leading space or tab on continuations (§3.1, §5).
- **VEVENT minimum for useful interop:** `UID`, `DTSTAMP`, `DTSTART`, and **`DTEND` or `DURATION`** (see checklist doc). `SUMMARY` strongly recommended.

## Topics

| Doc | Contents |
|-----|----------|
| [syntax-and-mime.md](syntax-and-mime.md) | Line model, folding, escaping, value types |
| [components-and-properties.md](components-and-properties.md) | VCALENDAR children, property groups, UID/SEQUENCE |
| [recurrence-timezone-alarms.md](recurrence-timezone-alarms.md) | RRULE, RDATE/EXDATE, VTIMEZONE, VALARM |
| [extensions-validation.md](extensions-validation.md) | RFC 7986, RFC 6868, security, validators |
| [authoring-checklist.md](authoring-checklist.md) | Stable UID, DTSTAMP, testing matrix |

**Related protocols (not iCalendar syntax itself):** CalDAV (RFC 4791), iTIP (RFC 5546 family), jCal (RFC 7265), xCal (RFC 6321) — see [document index](../notes/table-of-contents.md).
