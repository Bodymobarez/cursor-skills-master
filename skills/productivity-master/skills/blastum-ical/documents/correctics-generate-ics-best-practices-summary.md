# Summary: CorrectICS — Generate correct ICS files

Source: [correctics-generate-ics-best-practices](./correctics-generate-ics-best-practices.html)

## Key Facts

- **Minimal file:** `BEGIN:VCALENDAR` / `VERSION:2.0` / `PRODID` / `END:VCALENDAR`; inner `VEVENT` needs `UID`, `DTSTAMP`, `DTSTART`, and **`DTEND` or `DURATION`** (not both ambiguously omitted).
- **UID:** Must be **stable** across revisions of the same logical event for CalDAV/sync; pattern like `UID:${eventId}-yourapp` or `evt1234-myapp`. **Avoid** issuing a **new random UUID on every export** of the same event (creates duplicate events).
- **DTSTAMP:** Document as **UTC** with `Z`; update when object changes (iTIP semantics matter in scheduling contexts).
- **Time:** Prefer **IANA** ids (`America/New_York`) not `EST`; article notes **Outlook desktop** often expects **`VTIMEZONE`** when using `TZID`, while some web clients tolerate floating/local rules differently — test targets.
- **RRULE:** Use clear `FREQ`/`UNTIL` or `COUNT`; validate expanded instances; cross-check with RFC §5 duplicate-instance guidance.
- **Folding:** Call out **75-octet** folding as commonly missed.
- **Testing:** Validate with tools; test import in Google Calendar, Outlook, Apple Calendar, Teams before shipping generators.
- **TL;DR section:** Always include `UID`, `DTSTAMP`, `VERSION`, `PRODID`; prefer UTC for single events when appropriate; test across clients.

## Section Digest

### §7 Templates

Provides **single event (UTC)**, **local + TZID** (with `VTIMEZONE` block), and **recurring** templates — suitable starting points for copy-paste then customize.

### §9 Common mistakes

Includes missing `UID`, wrong line endings, bad TZ abbreviations, broken RRULE, overlong unfolded lines, etc. (per page structure).

## Tables & Structured Data

Normative rules: RFC 5545. This article is **practical synthesis** + vendor notes.
