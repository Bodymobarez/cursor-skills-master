# Syntax, structure, MIME

Aligned with [rfc-5545-icalendar-summary.md](../documents/rfc-5545-icalendar-summary.md) and [icalendar-org-section-5-recommended-practices-summary.md](../documents/icalendar-org-section-5-recommended-practices-summary.md).

## Transport and charset

- Registered type **`text/calendar`**; Content-Type may include `method` / `component` parameters (RFC §8).
- **MUST** generate **UTF-8**. **MUST** accept UTF-8 or US-ASCII when parsing (§6).

## Line folding

- Physical lines **SHOULD** be ≤ **75 octets** before `CRLF`; longer logical lines **SHOULD** be folded.
- Continuation = **`CRLF` + one space or tab** + rest of the line. Count octets in the **encoded** line (folding matters for UTF-8 multibyte characters).

## Property values vs parameters

- **Property values** use **backslash** escaping where defined for `TEXT` etc. (comma, semicolon, backslash, newline rules per §3.3).
- **Parameter values** follow separate rules; **RFC 6868** adds **caret (`^`) escapes** inside parameter values only (`^^`, `^'` → `"`, `^n` / `^r`, etc.). Do not confuse with `\` in values — see [extensions-validation.md](extensions-validation.md) and [rfc-6868-escaped-strings-summary.md](../documents/rfc-6868-escaped-strings-summary.md).

## Value types (selection)

`BINARY`, `BOOLEAN`, `CAL-ADDRESS`, `DATE`, `DATE-TIME`, `DURATION`, `PERIOD`, `RECUR`, `TEXT`, `URI`, `UTC-OFFSET`, … — `DATE-TIME` may be **floating** (no zone) or tied to **`TZID`** / **UTC `Z`**.

## Components (overview)

Under `VCALENDAR`: `VEVENT`, `VTODO`, `VJOURNAL`, `VFREEBUSY`, `VTIMEZONE` (with `STANDARD` / `DAYLIGHT`), nested **`VALARM`**. Cardinality per §3.6 tables is authoritative.

## Binary attachments

`ENCODING=BASE64` and `VALUE=BINARY` when attaching binary data.
