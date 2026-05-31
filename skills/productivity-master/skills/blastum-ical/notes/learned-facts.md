# Learned facts — iCalendar / .ics

## 2026-03-19

- The authoritative **core** format for `.ics` text streams is **RFC 5545** (obsoletes RFC 2445). Source: [RFC 5545](../documents/rfc-5545-icalendar.txt) — abstract, status.
- Registered MIME type is **`text/calendar`** (RFC 5545 §8). Source: [RFC 5545](../documents/rfc-5545-icalendar.txt) — §8 / examples.
- **UTF-8** generation is mandatory; parsers must accept UTF-8 or US-ASCII (§6). Source: [RFC 5545](../documents/rfc-5545-icalendar.txt) — §6.
- Root structure is **`BEGIN:VCALENDAR` … `END:VCALENDAR`** with **`VERSION:2.0`** and **`PRODID`** required. Source: [RFC 5545 summary](../documents/rfc-5545-icalendar-summary.md).
- Standard components include **`VEVENT`**, **`VTODO`**, **`VJOURNAL`**, **`VFREEBUSY`**, **`VTIMEZONE`**, **`VALARM`** (nested). Source: [RFC 5545 summary](../documents/rfc-5545-icalendar-summary.md).
- Lines longer than **75 octets SHOULD be folded** (space/tab continuation). Source: [RFC 5545](../documents/rfc-5545-icalendar.txt) — §5 recommended practice 1, §3.1.
- **`RRULE` + `RDATE`** duplicate start instants should **collapse to one** instance; **`RDATE` as PERIOD** sets instance duration for that occurrence. Source: [RFC 5545](../documents/rfc-5545-icalendar.txt) — §5 items 2.
- **`SUMMARY` truncation** to 255 octets is allowed but **must not split UTF-8** multibyte sequences. Source: [RFC 5545](../documents/rfc-5545-icalendar.txt) — §5 item 4.
- **`TZURL` SHOULD NOT** use `file:` URIs on the Internet. Source: [RFC 5545](../documents/rfc-5545-icalendar.txt) — §5 item 6.
- **RFC 7986** updates 5545 with calendar-level **`NAME`**, **`COLOR`**, **`IMAGE`**, **`CONFERENCE`**, **`REFRESH-INTERVAL`**, **`SOURCE`**, etc. Source: [RFC 7986](../documents/rfc-7986-new-properties.txt) — TOC §5.
- **RFC 6868** adds **caret (`^`) escapes** for characters inside **parameter** values (distinct from `\` in property values). Source: [RFC 6868](../documents/rfc-6868-escaped-strings.txt) — abstract, §3.
- **iCalendar.org validator** enforces RFC 5545 with a stated **512 KB** input limit. Source: [overview summary](../documents/icalendar-org-rfc-5545-overview-summary.md); [validator](https://icalendar.org/validator.html).

## 2026-03-19 (articles & libraries)

- **Generator UX:** For the same logical event, keep **`UID` stable** across exports; issuing a **new random UUID every download** makes many clients show duplicate events. Source: [CorrectICS summary](../documents/correctics-generate-ics-best-practices-summary.md).
- **Interop testing:** Practical guides recommend validating **.ics** output against **Google Calendar, Outlook (desktop vs web), Apple Calendar, Teams** — behavior differs especially for **`VTIMEZONE`**. Source: [CorrectICS summary](../documents/correctics-generate-ics-best-practices-summary.md).
- **UID privacy (RFC 7986):** New UIDs **MUST NOT** embed host/domain/user-identifying data; **RECOMMENDED:** opaque **UUID** form (hex). Contrasts with older RFC 5545 prose suggesting `local@domain`. Source: [iCal4j UID article summary](../documents/ical4j-blog-generating-uids-summary.md); [RFC 7986](../documents/rfc-7986-new-properties.txt).
- **Python `icalendar`:** Typical flow **`Calendar.from_ical` / build `Event` / `calendar.to_ical()`** (bytes). Source: [RTD usage summary](../documents/icalendar-python-readthedocs-how-to-usage-summary.md).
- **`ical.js`:** Entry **`ICAL.parse(text)`**; **IANA timezone file** not in default bundle — use **`ical.timezones.js`** when zones are missing from the ICS. Source: [ical.js README summary](../documents/ical-js-kewisch-readme-summary.md).
- **Kanzaki VEVENT page** is a common **unofficial** quick reference — cross-check mandatory/optional rules against **RFC 5545 §3.6.1**. Source: [Kanzaki summary](../documents/kanzaki-ical-vevent-reference-summary.md).

## 2026-03-19 (Swift libraries)

- **iCalendarParser (dmail-me):** SPM `https://github.com/dmail-me/iCalendarParser` from `0.1.0`; parse via **`ICParser().calendar(from:)`** → `ICalendar?`; README states **incomplete RFC 5545** coverage and TODO for VTODO / VJOURNAL / VFREEBUSY / VALARM. Source: [dmail README summary](../documents/icalendar-parser-dmail-readme-summary.md); [metadata](../metadata/icalendar-parser-dmail-readme.meta.md).
- **iCalendar Kit (thoven87):** SPM `https://github.com/thoven87/icalendar-kit.git` from **`2.0.0`**; **`ICalendarKit.parseCalendar(from:)`** and **`ICalendarSerializer().serialize`**; README claims **5545, 7986, 6868, 7808, 9073** support and includes **VCard** + **EventBuilder** (conference, color, geo, alarms, etc.). Source: [thoven README summary](../documents/icalendar-kit-thoven-readme-summary.md); [metadata](../metadata/icalendar-kit-thoven-readme.meta.md).
- **mluisbrown/iCalendar:** **VEVENT-only** minimal parser with properties **DTSTART, DTEND, UID, DESCRIPTION, LOCATION, SUMMARY** only (per README). Source: [mluisbrown README summary](../documents/icalendar-mluisbrown-readme-summary.md); [metadata](../metadata/icalendar-mluisbrown-readme.meta.md).
- **JiningLiu/iCalParser:** README captured as **placeholder only** (“actual README coming soon”) — not a documentation source yet. Source: [JiningLiu README summary](../documents/icalparser-jiningliu-readme-summary.md); [metadata](../metadata/icalparser-jiningliu-readme.meta.md).
