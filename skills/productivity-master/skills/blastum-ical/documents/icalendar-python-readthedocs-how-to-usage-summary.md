# Summary: icalendar (Python) — Usage guide (Read the Docs)

Source: [icalendar-python-readthedocs-how-to-usage](./icalendar-python-readthedocs-how-to-usage.html)

## Key Facts

- **Imports:** `from icalendar import Calendar, Event` (and other components as needed).
- **Create:** `Calendar()` / `Event()`, set properties via dict-like API (`event.add('dtstart', dt)`, etc.) or helper attributes where documented.
- **Serialize:** `calendar.to_ical()` returns bytes (typical write pattern: open file `wb`).
- **Parse:** `Calendar.from_ical(ics_string_or_bytes)` — walk `calendar.walk('VEVENT')` etc.
- **Examples in doc:** Building recurring meeting with location, organizer, attendees, alarms; using `Calendar.example("timezoned")` for timezone demonstrations.
- **Types:** Document references `icalendar.prop` value types; datetime integration with timezone-aware Python objects.

## Section Digest

Later sections (in full HTML) cover **todos**, **free-busy**, **timezone** components, **alarms**, and edge cases — grep snapshot for headings when researching.

## Tables & Structured Data

Live docs may update; snapshot dated 2026-03-19. Canonical URL: https://icalendar.readthedocs.io/en/latest/how-to/usage.html
