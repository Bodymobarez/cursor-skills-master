# Components and properties

Digest from [rfc-5545-icalendar-summary.md](../documents/rfc-5545-icalendar-summary.md); verify cardinality in RFC §3.6.

## Calendar-level (`VCALENDAR`)

- **Required:** `PRODID`, `VERSION:2.0`.
- **Common:** `CALSCALE` (default GREGORIAN), `METHOD` (scheduling / iTIP-related semantics).

## Property groups (§3.8)

- **Descriptive:** `ATTACH`, `CATEGORIES`, `CLASS`, `COMMENT`, `DESCRIPTION`, `GEO`, `LOCATION`, `PERCENT-COMPLETE`, `PRIORITY`, `RESOURCES`, `STATUS`, `SUMMARY`.
- **Date/time:** `DTSTART`, `DTEND`, `DUE`, `DURATION`, `COMPLETED`, `TRANSP`, …
- **Time zone definition:** `TZID`, `TZNAME`, `TZOFFSETFROM`, `TZOFFSETTO`, `TZURL` (inside `VTIMEZONE` / definitions).
- **Relationships:** `ATTENDEE`, `CONTACT`, `ORGANIZER`, `RECURRENCE-ID`, `RELATED-TO`, `URL`, **`UID`**.
- **Recurrence:** `RRULE`, `RDATE`, `EXDATE`.
- **Alarm:** `ACTION`, `TRIGGER`, `REPEAT`, … (under `VALARM`).
- **Change management:** `CREATED`, **`DTSTAMP`**, `LAST-MODIFIED`, **`SEQUENCE`**.
- **Extension:** `X-` properties, IANA-registered names.

## Parameters (examples)

`ALTREP`, `CN`, `CUTYPE`, `DELEGATED-*`, `DIR`, `ENCODING`, `FMTTYPE`, `LANGUAGE`, `MEMBER`, `PARTSTAT`, `RANGE`, `RELATED`, `RELTYPE`, `ROLE`, `RSVP`, `SENT-BY`, **`TZID`**, **`VALUE`**, … (§3.2).

## UID and revisions

- **`UID`:** globally unique; **stable** for the same logical object across exports/updates (otherwise clients duplicate). Modern privacy: prefer **opaque UUID** form per **RFC 7986** (see [ical4j-blog-generating-uids-summary.md](../documents/ical4j-blog-generating-uids-summary.md)) while keeping stability — not a new random id per download.
- **`DTSTAMP`:** UTC with **`Z`** in generated files; update when the object meaningfully changes (scheduling contexts care).
- **`SEQUENCE`:** bump when publishing updates in many scheduling flows.

## Seconds

If a target system does not support non-zero seconds, use **`00`** for the seconds field (RFC §5 recommended practice).
