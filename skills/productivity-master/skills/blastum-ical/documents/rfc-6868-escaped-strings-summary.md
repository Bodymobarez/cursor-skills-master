# Summary: RFC 6868 — Parameter value encoding

Source: [rfc-6868-escaped-strings](./rfc-6868-escaped-strings.txt)

## Key Facts

- **Updates** RFC 5545 (and vCard RFCs). February 2013.
- Problem: property *values* allow `\` escaping, but **parameter** values forbade quotes and control characters, blocking many real-world names and URIs.
- Solution: **caret escape** sequence inside parameter values only: `^` introduces escapes; `^^` is a literal caret.
- Encodings (normative set in §3): e.g. `^'` → `"`, `^n` → LF, `^r` → CR, `^N` → NUL (see RFC for full table).

## Section Digest

### §3 Encoding scheme

Backwards-compatible: legacy parsers that do not implement RFC 6868 may see caret-prefixed sequences as opaque text; authors should use only when necessary.

### §4 Security

Same as base format: escaped content can still carry malicious text; do not treat as safe HTML.

## Tables & Structured Data

| Sequence | Meaning (per RFC 6868) |
|----------|-------------------------|
| `^^` | Literal `^` |
| `^'` | `"` (double quote) |
| `^n` | LF |
| `^r` | CR |
| `^N` | NUL |

(Complete table in RFC §3.)
