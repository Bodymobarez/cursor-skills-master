---
topic: ical-format
title: "iCalendar (.ics) format, RFCs, properties, and interoperability practices"
created: 2026-03-19
document_count: 16
---

## Overview

Notebook on the **iCalendar** text format (commonly stored as `.ics`): grammar, components, properties, parameters, normative RFCs (5545, 7986, 6868), RFC §5 recommended practices, **practical authoring articles**, **copy-paste templates**, and **library README / usage docs** (Python `icalendar`, JS `ical.js`, Java iCal4j context, **Swift SPM packages**: iCalendarParser, iCalendar Kit, minimal mluisbrown/iCalendar, JiningLiu stub).

## Sources

| Slug | Title | Type | Key topics |
|------|-------|------|------------|
| rfc-5545-icalendar | RFC 5545 — iCalendar core | text | VCALENDAR, VEVENT, RRULE, TZ, MIME |
| rfc-7986-new-properties | RFC 7986 — New properties for iCalendar | text | NAME, COLOR, CONFERENCE, UID privacy |
| rfc-6868-escaped-strings | RFC 6868 — Parameter value encoding | text | Caret escaping in parameters |
| icalendar-org-rfc-5545-overview | iCalendar.org — RFC 5545 landing page | web | Validator, related specs index |
| correctics-generate-ics-best-practices | CorrectICS — Generate correct ICS files | web | Templates, UID, RRULE, testing |
| icalendar-org-section-5-recommended-practices | iCalendar.org — §5 Recommended practices (RFC text) | web | Folding, recurrence, SUMMARY |
| icalendar-org-section-4-examples | iCalendar.org — §4 Object examples | web | Example VCALENDAR snippets |
| icalendar-python-readthedocs-how-to-usage | icalendar (Python) — Read the Docs usage | web | Calendar/Event, from_ical, examples |
| kanzaki-ical-vevent-reference | Kanzaki — VEVENT component reference | web | Property tables, VEVENT |
| ical4j-blog-generating-uids | iCal4j — Generating UIDs (blog) | web | RFC 5545 vs RFC 7986 UID advice |
| ical-js-kewisch-readme | ical.js — README (kewisch) | markdown | parse, npm, browser, timezones |
| icalendar-python-collective-readme | icalendar (Python) — project README | text | PyPI, install, links to usage |
| icalendar-parser-dmail-readme | iCalendarParser (dmail-me) — README | markdown | Swift, ICParser, RFC 5545, SPM |
| icalendar-kit-thoven-readme | iCalendar Kit (thoven87) — README | markdown | Swift 6, parse, serialize, RFC 7986, VCard |
| icalendar-mluisbrown-readme | iCalendar (mluisbrown) — README | markdown | Swift, minimal VEVENT, booking ICS |
| icalparser-jiningliu-readme | iCalParser (JiningLiu) — README | markdown | Swift, placeholder README |
