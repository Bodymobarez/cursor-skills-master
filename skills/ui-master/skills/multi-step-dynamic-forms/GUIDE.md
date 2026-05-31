---
name: multi-step-dynamic-forms
description: >-
  Build multi-step wizards, dynamic/conditional forms, and complex field logic. Use for
  stepped registration/onboarding, surveys, applications, and forms where fields show/
  hide based on answers. Covers step state, progress, field arrays, dependencies,
  async options, file uploads, and save/resume drafts.
---

# Multi-Step & Dynamic Forms

Wizards, conditional fields, repeating groups, and complex logic — the patterns behind "advanced"
registration and onboarding flows.

## Multi-step wizard architecture

```
Steps[]: { id, title, schema (Zod partial), optional? }
State:   currentStep, formData (accumulated), completedSteps, draftId?
UI:      progress bar (%, steps clickable only if completed), Back/Next/Submit
```
- **One form instance** (RHF) holding all steps; validate **only current step** on Next:
  `trigger(stepFields)` or step-specific `z.object().pick()`.
- **Final submit**: validate full merged schema; single API call (or per-step save — see drafts).
- Persist `formData` in memory; optional **localStorage/sessionStorage** draft on unload.
- Mobile: one step per screen; sticky footer with Next.

```ts
const step1Schema = z.object({ email: z.string().email(), password: z.string().min(8) });
const step2Schema = z.object({ company: z.string().min(1), size: z.enum(["1-10","11-50",...]) });
const fullSchema = step1Schema.merge(step2Schema).merge(step3Schema);
```

## Progress UX
- Show step names + current; completed steps with checkmark; optional click-back to edit.
- Don't show step 3 of 3 until user passes step 2 (no skip ahead unless allowed).
- Summary/review step before submit (common on checkout, applications).

## Conditional fields (show/hide)

```
if role === "business" → show companyName, taxId
if country === "EG" → show nationalId
if hasVat === true → show vatNumber
```
- Implement with `watch()` (RHF) or `form.watch` + render; **clear hidden field values** on hide
  (or they still submit stale data).
- Re-validate when visibility changes (hidden required fields must not block submit).
- Animate enter/exit sparingly (`prefers-reduced-motion`).

## Field arrays (repeating groups)

```
Team members: [{ name, email, role }, ...]  — useFieldArray (RHF)
Line items, addresses, phone numbers, education history
```
- Add/remove rows; min/max count in schema: `z.array(item).min(1).max(10)`.
- Each row validates independently; show errors per row.
- Drag-to-reorder optional (`@dnd-kit`).

## Dependent / cascading selects

```
Country → Region → City (options loaded async)
Category → Subcategory → Product
```
- Load options on parent change; reset child when parent changes.
- Loading skeleton on child; handle empty states.
- Cache option lists; debounce search selects (Combobox/Command palette pattern).

## Async validation & lookups
- Email/username availability (debounced `onChange`).
- VAT/tax ID verification API.
- Address validation (Places API).
- Show spinner on field; don't block entire form.

## File uploads in forms
- Drag-drop zone + list of files with progress, preview (image/PDF), remove.
- Client: size/type check; Server: re-check, scan, store (S3 presigned).
- Multi-file with max count; integrate into Zod as `FileList` or custom.

## Save draft / resume later
```
draftId → auto-save partial data every N seconds or on step change
Resume link: /onboarding?draft=uuid (auth required)
```
- Store server-side with user id + expiry; merge on resume.
- Show "Continue where you left off" on return.

## Survey-specific
- Branching: answer A → jump to step 5; answer B → step 3 (step graph, not linear).
- Randomize question order (A/B tests); required vs skippable per question.

## Checklist
```
- [ ] Per-step partial Zod validation on Next; full schema on Submit
- [ ] Progress UI + back navigation without losing data
- [ ] Conditional fields: watch + clear hidden values + re-validate
- [ ] field arrays with min/max; per-row errors
- [ ] Cascading selects reset children; async loading states
- [ ] File upload client+server validation
- [ ] Optional draft save/resume for long forms
- [ ] a11y: announce step changes (aria-live); focus first field on step enter
```

## Anti-patterns
- Separate unconnected forms per step (loses data on back).
- Hidden fields still in submit payload with stale required values.
- Validating entire form on every Next (slow, confusing errors on future steps).
- No loading state on dependent dropdowns.
- Linear-only wizard when product needs branching.
