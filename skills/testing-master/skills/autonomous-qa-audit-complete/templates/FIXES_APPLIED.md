# Fixes Applied — QA Audit

**Project:** {{PROJECT_NAME}}  
**Started:** {{ISO_DATE}}  
**Last updated:** {{ISO_DATE}}

Chronological log of every fix during the autonomous audit loop. Each entry must include retest result.

---

## Summary

| Metric | Count |
|--------|------:|
| Issues fixed | |
| Files changed | |
| Retests passed | |
| Retests failed (follow-up) | |

---

## Fix log

### Fix {{NNN}} — {{SHORT_TITLE}}

| Field | Value |
|-------|-------|
| **Issue ID** | {{from QA_AUDIT_REPORT}} |
| **Type** | `DEAD_BUTTON` / `ROUTE_404` / … |
| **Severity** | P0 / P1 / P2 |
| **Route** | `/path` |

**Root cause:**  
{{1–2 sentences}}

**Files changed:**
- `path/to/file.tsx` — {{what changed}}

**Change summary:**
```diff
// optional snippet
```

**Retest:**
- [ ] `npx playwright test …` — **PASS / FAIL**
- [ ] Manual: {{steps}}
- [ ] Regression smoke: {{routes}}

**Commit:** {{hash or "pending"}}

---

<!-- Repeat Fix NNN blocks -->

## Deferred / not fixed

| Issue ID | Reason |
|----------|--------|
| | Requires product decision / external API / prod-only |
