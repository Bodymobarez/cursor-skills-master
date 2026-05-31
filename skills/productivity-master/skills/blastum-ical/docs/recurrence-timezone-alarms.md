# Recurrence, time zones, alarms

From [rfc-5545-icalendar-summary.md](../documents/rfc-5545-icalendar-summary.md) and [icalendar-org-section-5-recommended-practices-summary.md](../documents/icalendar-org-section-5-recommended-practices-summary.md).

## Recurrence

- **`RRULE`:** `FREQ` required; `UNTIL` or `COUNT`; `INTERVAL`; `BY*` parts; `WKST` for weekly alignment.
- **`RDATE` / `EXDATE`:** interact with `RRULE`.
- **§5:** If **`RRULE` + `RDATE`** both yield the **same start instant**, treat as **one** instance (collapse duplicates).
- **`RDATE` as PERIOD:** sets **duration** for that occurrence (differs from default event length).

## Time zones

- Prefer **IANA** IDs in **`TZID`** (e.g. `America/New_York`) over ambiguous abbreviations like `EST`.
- When using `TZID` on `DATE-TIME`, include matching **`VTIMEZONE`** definitions for clients that require them — **Outlook desktop** commonly expects `VTIMEZONE`; web clients may be looser. **Interoperability test** (see checklist).
- **`TZURL`:** **SHOULD NOT** use `file:` on the public Internet (§5).

## Floating vs UTC

- **UTC** (`Z`) simplifies single-zone feeds and all-day clarity when appropriate.
- **Floating** times (no `TZID`, no `Z`) mean “local wall clock” in the importing calendar — useful only when that semantics is intentional.

## Alarms (`VALARM`)

Nested under event/todo/journal. Define `ACTION` and `TRIGGER` (and repeats per §3.8.6). Keep triggers reasonable; some clients ignore or sandbox alarms from untrusted feeds.
