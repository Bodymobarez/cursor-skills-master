# Summary: ical.js README

Source: [ical-js-kewisch-readme](./ical-js-kewisch-readme.md)

## Key Facts

- **Scope:** Parses **RFC 5545** iCalendar, **RFC 7265** jCal, vCard/jCard family.
- **Install:** `npm install ical.js` → `import ICAL from "ical.js"`.
- **Browser:** ES module from `unpkg` (`ical.min.js`); or ES5 `ical.es5.min.cjs` for classic script tag.
- **API entry:** `ICAL.parse(text)` returns component tree; further manipulation via documented classes (see API docs).
- **Tools:** Online **validator**, **recurrence tester** (URLs in README).
- **Timezones:** Core build **excludes** IANA zone database; use **`ical.timezones.js`** (or CI-built artifact) when converting zones not embedded in the `.ics`.
- **License:** MPL 2.0.

## Section Digest

Wiki has additional recipes; `npm run test` / coverage for quality bar when evaluating library.

## Tables & Structured Data

| Artifact | Use |
|----------|-----|
| `dist/ical.min.js` | Browser / bundler ES module |
| `dist/ical.es5.min.cjs` | Legacy script |
| `ical.timezones.js` | TZ data when not in file |
