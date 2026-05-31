# Summary: iCalendar.org — RFC 5545 §5 recommended practices

Source: [icalendar-org-section-5-recommended-practices](./icalendar-org-section-5-recommended-practices.html)

## Key Facts

- Mirrors **RFC 5545 section 5** (SHOULD-level interoperability practices).
- **Folding:** Content lines longer than **75 octets** SHOULD be folded.
- **Recurrence:** Duplicate start `DATE-TIME` from combined `RRULE` + `RDATE` → single instance; `RDATE` as **PERIOD** controls duration for that instance.
- **Scheduling:** Multiple duplicate requests from mailing lists → respond once; use `MEMBER` on `ATTENDEE` where appropriate.
- **SUMMARY:** May truncate to **255 octets** but MUST NOT break **UTF-8** multibyte sequences.
- **Seconds:** If not supported, use `00` for seconds field.
- **`TZURL`:** SHOULD NOT use `file:` URIs on the Internet.
- **CATEGORIES / RESOURCES:** Informative English example tokens listed (ANNIVERSARY, MEETING, PROJECTOR, etc.).

## Section Digest

Internationalization note on same page chain: UTF-8 generation / UTF-8 or US-ASCII acceptance — aligns with RFC 5545 §6.

## Tables & Structured Data

Authoritative text: [RFC 5545](rfc-5545-icalendar.txt) §5.
