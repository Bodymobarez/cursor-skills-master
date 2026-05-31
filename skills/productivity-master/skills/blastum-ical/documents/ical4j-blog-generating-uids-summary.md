# Summary: iCal4j — Generating UIDs

Source: [ical4j-blog-generating-uids](./ical4j-blog-generating-uids.html)

## Key Facts

- **RFC 5545** (quoted): UID MUST be globally unique; suggests `unique-part@domain-or-ip` with date/time + sequential id on left, domain on right.
- **RFC 7986** (quoted): Updates practice — UID MUST NOT include data identifying user, host, domain, or privacy-sensitive info; **RECOMMENDED:** hex-encoded random **UUID** per RFC 4122, e.g. `UID:5FC53010-1267-4F8E-BC28-1D7AE55A7C99`.
- **Implication:** New clients often choose **opaque UUID**; **stability** for the same event still required for updates (same UID string until logically new event).
- **iCal4j:** Blog mentions `FixedUidGenerator` vs `RandomUidGenerator` alignment with the two styles.

## Section Digest

Resolves common confusion: “domain-based UID from RFC 5545 prose” vs “privacy-preserving UUID from RFC 7986” — **both are spec-backed**; 7986 narrows what is acceptable for new UIDs.

## Tables & Structured Data

Example UUID line preserved in snapshot HTML.
