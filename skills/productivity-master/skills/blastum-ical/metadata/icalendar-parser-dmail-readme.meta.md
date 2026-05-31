---
title: "iCalendarParser (dmail-me) — README"
type: markdown
source: documents/icalendar-parser-dmail-readme.md
url: https://github.com/dmail-me/iCalendarParser/blob/main/README.md
acquired: 2026-03-19
snapshot: true
topics:
  - Swift
  - parsing
keywords:
  - ICParser
  - Swift Package Manager
  - RFC 5545
sections:
  - ref: "Usage"
    topic: "ICParser.calendar(from:)"
  - ref: "Is it production ready?"
    topic: "Incomplete RFC coverage; production use in Dmail.me"
---

## Why saved

Swift **SPM** library for **RFC 5545** ICS parsing: install lines, **`ICParser` / `ICalendar`** usage, stated gaps (TODO list), and production note.

## Summary

MIT-licensed parser; SPM from `0.1.0`; not claimed feature-complete; extends toward full component/property coverage per README TODO.

## Key facts

- Entry point `ICParser().calendar(from:)` returns optional model.
- Missing: VTODO, VJOURNAL, VFREEBUSY, VALARM per README TODO.
