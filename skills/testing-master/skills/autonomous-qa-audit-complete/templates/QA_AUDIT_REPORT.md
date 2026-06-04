# QA Audit Report

**Project:** {{PROJECT_NAME}}  
**Date:** {{ISO_DATE}}  
**Target:** {{QA_BASE_URL}}  
**Auditor:** Autonomous QA Audit (Cursor Agent)  
**Status:** {{PASS | FAIL | IN_PROGRESS}}

---

## Executive summary

{{2–4 sentences: overall health, ship/no-ship recommendation}}

---

## Discovery totals

| Metric | Count |
|--------|------:|
| Pages / routes discovered | |
| Layouts | |
| Components (unique files) | |
| Buttons (approximate) | |
| Forms | |
| API endpoints | |
| User flows mapped | |
| Modals / dialogs | |

---

## Test execution summary

| Category | Run | Pass | Fail | Skip |
|----------|----:|-----:|-----:|-----:|
| Route render | | | | |
| Link navigation | | | | |
| Button / interaction | | | | |
| Forms (empty / invalid / valid) | | | | |
| CRUD flows | | | | |
| Authentication | | | | |
| API integration | | | | |
| DB persistence | | | | |
| Responsive (3 viewports) | | | | |
| Accessibility (axe) | | | | |

---

## Issues summary

| Severity | Found | Fixed auto | Manual |
|----------|------:|-----------:|-------:|
| Critical (P0) | | | |
| High (P1) | | | |
| Medium (P2) | | | |
| Low (P3) | | | |
| **Total** | | | |

---

## Issues detail

### {{ISSUE_ID}} — {{TITLE}}

- **Severity:** {{P0–P3}}
- **Type:** `DEAD_BUTTON` | `ROUTE_404` | `FORM_VALIDATION` | `API_ERROR` | `CONSOLE_ERROR` | …
- **Route / flow:** {{path}}
- **Steps to reproduce:**
  1. …
- **Expected:** …
- **Actual:** …
- **Screenshot:** `qa-audit/screenshots/{{file}}.png`
- **Trace:** `qa-audit/traces/{{file}}.zip` (if any)
- **Status:** `OPEN` | `FIXED` | `MANUAL` | `WONT_FIX`
- **Fix notes:** {{file:line or PR}}

---

## Console & server

### Browser console

| Route | Error message | Status |
|-------|---------------|--------|
| | | |

### Server log

| Timestamp | Error | Status |
|-----------|-------|--------|
| | | |

---

## Performance recommendations

| Route | LCP (approx) | Issue | Recommendation |
|-------|-------------|-------|----------------|
| | | | |

---

## Accessibility findings

| Route | Rule | Impact | Status |
|-------|------|--------|--------|
| | | | |

---

## Remaining warnings (non-blocking)

- …

---

## Manual intervention required

| ID | Reason blocked | Owner suggestion |
|----|----------------|------------------|
| | | |

---

## Success criteria checklist

- [ ] Zero console errors (app-owned)
- [ ] Zero broken routes
- [ ] Zero dead buttons
- [ ] Zero failing forms
- [ ] Zero failing API calls (happy path)
- [ ] Zero unhandled exceptions
- [ ] All pages render
- [ ] All P0 user flows complete

---

## Artifacts

- HTML report: `qa-audit/reports/html/index.html`
- JSON results: `qa-audit/reports/results.json`
- Screenshots: `qa-audit/screenshots/`
- Coverage matrix: `TEST_COVERAGE.md`
- Fix log: `FIXES_APPLIED.md`
