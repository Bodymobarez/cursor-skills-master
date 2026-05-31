# Summary: iCalendarParser (dmail-me) — README

Source: [icalendar-parser-dmail-readme](./icalendar-parser-dmail-readme.md)

## Key Facts

- **Swift SPM:** `https://github.com/dmail-me/iCalendarParser` from `0.1.0`; product/module `iCalendarParser`.
- **API:** `ICParser().calendar(from: rawICS)` → optional `ICalendar`.
- **Scope:** RFC 5545–oriented; authors state **not yet feature-complete** for full RFC compliance.
- **Production:** Used in **Dmail.me** iOS app per README.
- **TODO (README):** VTODO, VJOURNAL, VFREEBUSY, VALARM; more `ICEvent` properties.
- **License:** MIT.

## Section Digest

### Installation

Xcode **File → Add Packages** with repo URL, or `Package.swift` `.package(name:url:from:)`.

### Usage

Import `iCalendarParser`, instantiate `ICParser`, pass ICS string to `calendar(from:)`.

### Production readiness

Explicitly **incomplete** vs full RFC 5545; community contributions welcome; shipped in Dmail.me.

### Credits

Inspired by **chan614/iCalSwift**.
