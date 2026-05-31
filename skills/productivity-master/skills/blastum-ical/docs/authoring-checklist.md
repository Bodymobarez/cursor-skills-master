# Generator checklist and testing

Synthesizes [correctics-generate-ics-best-practices-summary.md](../documents/correctics-generate-ics-best-practices-summary.md), [icalendar-org-section-5-recommended-practices-summary.md](../documents/icalendar-org-section-5-recommended-practices-summary.md), and [learned-facts.md](../notes/learned-facts.md).

## Before shipping

1. **`BEGIN:VCALENDAR` / `END:VCALENDAR`**, **`VERSION:2.0`**, **`PRODID`** (identify your product).
2. Each **`VEVENT`:** **`UID`** (stable for life of logical event), **`DTSTAMP`** (UTC `Z`), **`DTSTART`**, and **`DTEND` *or* `DURATION`** — do not leave end/duration ambiguous.
3. **`SUMMARY`** for human-visible titles; **`LOCATION`**, **`DESCRIPTION`** as needed.
4. **Line endings:** **`CRLF`** throughout (RFC text format).
5. **Fold** logical lines **> 75 octets**.
6. **UTF-8** encoding for new files.
7. **RRULE:** clear `FREQ`; `UNTIL` or `COUNT`; mind §5 duplicate-instance collapse with `RDATE`.
8. **Time zones:** IANA `TZID` + **`VTIMEZONE`** when targeting Outlook desktop and broad interop.

## UID policy

- **Never** roll a **new random UUID on every download** for the same event (duplicates in Google/Apple/Outlook).
- **RFC 7986:** new UIDs **must not** embed host/domain/user-identifying data; **recommended:** opaque **UUID** — still **reuse** that string for updates to the same event.

## Client matrix (spot-check)

Import the same file into **Google Calendar**, **Outlook** (desktop and web if possible), **Apple Calendar**, **Microsoft Teams** where relevant — especially **`VTIMEZONE`** and **all-day** `DATE` vs `DATE-TIME` edge cases.

## Library hints (bundled README / usage digests)

- **Python `icalendar`:** build `Calendar` / `Event`, `to_ical()` bytes — see [icalendar-python-readthedocs-how-to-usage-summary.md](../documents/icalendar-python-readthedocs-how-to-usage-summary.md).
- **`ical.js`:** `ICAL.parse(text)`; use **`ical.timezones.js`** when zone data is missing from the ICS — see [ical-js-kewisch-readme-summary.md](../documents/ical-js-kewisch-readme-summary.md).
- **Swift:** `iCalendarParser` (dmail-me) incomplete RFC coverage; **`icalendar-kit`** (thoven87) broader RFC claims — compare [dmail](../documents/icalendar-parser-dmail-readme-summary.md) vs [thoven](../documents/icalendar-kit-thoven-readme-summary.md) summaries before depending on edge features.

## Common mistakes (from CorrectICS narrative)

Missing **`UID`**, wrong line endings, non-IANA TZ abbreviations, broken **`RRULE`**, forgetting folding, omitting **`DTSTAMP`**, conflicting **`DTEND`** and **`DURATION`**.
