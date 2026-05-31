---
title: "iCalendar (mluisbrown) — README"
type: markdown
source: documents/icalendar-mluisbrown-readme.md
url: https://github.com/mluisbrown/iCalendar/blob/master/README.md
acquired: 2026-03-19
snapshot: true
topics:
  - Swift
  - parsing
keywords:
  - VEVENT
  - minimal
  - booking
sections:
  - ref: "iCalendar"
    topic: "VEVENT-only property list"
---

## Why saved

**Minimal Swift** RFC 5545 parser README listing **exactly which VEVENT properties** are implemented—useful for **interop scoping** vs rental/booking `.ics` feeds.

## Summary

Six properties only (DTSTART, DTEND, UID, DESCRIPTION, LOCATION, SUMMARY); no broader component coverage stated.

## Key facts

- Positions use case as **Airbnb / Booking.com / Wimdu**-style calendar files.
