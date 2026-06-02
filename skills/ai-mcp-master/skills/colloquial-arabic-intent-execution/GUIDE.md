---
name: colloquial-arabic-intent-execution
description: >-
  Turn messy / random / colloquial instructions (Egyptian "بالبلدي", mixed Arabic-English, voice-style
  dumps) into a faithful WORD-BY-WORD translation that drops nothing, then a technical analysis, then
  LITERAL execution "بالحذافير" — no invented scope, no embellishment ("من غير ما يألّف"), at the
  production v2 standard. Use whenever the user writes informal/ambiguous requirements in Arabic/Egyptian.
---

# Colloquial Arabic → Faithful Spec → Literal Execution

**Mandate:** when the user writes fast, informal, or vernacular (Egyptian "بالبلدي", Franco-Arab,
half-Arabic-half-English, stream-of-consciousness), you **lose nothing, invent nothing, and execute
exactly** — to the letter ("بالحذافير") at the highest engineering standard (the v2 bar used across
these skills). The user's wording is the contract.

## When to use / when NOT

| Use | Don't |
|-----|-------|
| Informal/colloquial Arabic or mixed Ar-En requirements | Already-precise English specs (just execute) |
| Voice-dump / run-on instructions with many asks | A pure question (answer it) |
| Anything where missing a clause = wrong result | When user explicitly says "اقترح" (then proposing is in-scope) |

## The 3 phases (always, in order)

```
1) FAITHFUL TRANSLATION  — every token mapped, nothing dropped, nothing added
2) TECHNICAL ANALYSIS    — decompose into explicit, testable requirements; flag (don't fill) gaps
3) LITERAL EXECUTION     — implement exactly the list, at v2 quality, then verify against the list
```

### Phase 1 — Faithful, word-by-word translation (لا تُسقِط شيئًا)

- Quote the user's text, then translate **segment by segment** — every clause, qualifier, number,
  "و"/"كمان"/"بس"/"من غير", negation, and aside becomes an explicit line.
- **Negations and exclusions are first-class.** "من غير ما تلمس الـ X" = a hard constraint, not a nuance.
- Mixed-language terms stay as the user meant them (`login`, `cache`, `ريممبر مي` = "remember me").
- Preserve **quantities and specifics exactly** ("٣ خطوات", "لون تركوازي", "بس للأدمن").
- If a word is genuinely ambiguous, mark it `⚠️ AMBIGUOUS` — do **not** silently resolve it.

### Phase 2 — Technical analysis (تحليل تقني)

Produce a numbered requirement list, each line traceable to a phrase from Phase 1:

```
R1  ⟵ "عايز اللوجين يبقى فيه جوجل"      → Add Google OAuth sign-in to the login screen
R2  ⟵ "وميسجاتش الباسورد لو غلط"        → On wrong password, show a generic error (no field-specific leak)
R3  ⟵ "وحطلي ريممبر مي"                 → Add a "Remember me" persistent-session checkbox
C1  ⟵ "من غير ما تغير الديزاين"          → CONSTRAINT: do not modify existing visual design
⚠️  "خليه سريع"                          → AMBIGUOUS: define "fast" (perceived? <Xms?) — ASK or assume + state
```

- Separate **R**equirements, **C**onstraints, and **⚠️ Ambiguities**.
- Surface assumptions **explicitly** ("بفترض إنك تقصد X") — never bury an invented decision.
- Map each requirement to a **verification** ("how I'll prove it's done").

### Phase 3 — Literal execution (تنفيذ بالحذافير)

- Implement **exactly** R1..Rn under C1..Cn. Nothing more, nothing less.
- **"من غير ما يألّف"** — no bonus features, no refactors the user didn't ask for, no renamed
  variables/files outside scope, no "while I'm here" changes.
- Hit the **v2 quality bar** *within* the requested scope (types, error handling, security, a11y,
  tests where relevant) — high quality ≠ extra scope.
- Close the loop: re-read Phase 2 and **check off every R and C** against what you built.

## Egyptian/colloquial mini-glossary (extend per project)

| بالبلدي | Means |
|--------|-------|
| عايز / عاوز | I want |
| حطّلي / ضيفلي | add for me |
| اعملي | build/make me |
| شيل / امسح | remove/delete |
| من غير ما … | without … (hard constraint) |
| بس | only / but |
| كمان | also |
| يبقى | should be |
| ميـ…ـش / ما…ش | negation (not) |
| بالحذافير | to the letter / exactly |
| من غير ما تألّف | don't make things up / no invention |
| ظبطلي / زبطهالي | fix/sort it for me |
| جامد / تمام | great / ok |
| الديزاين / الاستايل | the design / style |
| اللوجين / الريجستر | login / register |

> Mixed Franco-Arab (e.g. "3ayez", "msh", "5alas") maps the same way — normalize then translate.

## Worked example

**User:** "اعملي صفحه كونتاكت فيها اسم وايميل ومسج، وفالديشن، وابعتها على الايميل بتاعي، بس متغيرش الهيدر والفوتر، وخليها عربي RTL"

**Phase 1 (faithful):** build a Contact page · fields: name + email + message · with validation · send
it to "my email" · BUT don't change the header & footer · make it Arabic RTL.

**Phase 2 (analysis):**
```
R1 ⟵ "صفحه كونتاكت فيها اسم وايميل ومسج" → Contact page with 3 fields: name, email, message
R2 ⟵ "وفالديشن"                          → Client + server validation (required, email format)
R3 ⟵ "وابعتها على الايميل بتاعي"          → Submit sends an email to the site owner
R4 ⟵ "خليها عربي RTL"                     → Arabic copy, dir="rtl", logical properties
C1 ⟵ "بس متغيرش الهيدر والفوتر"            → CONSTRAINT: header/footer untouched
⚠️  "الايميل بتاعي"                        → AMBIGUOUS: which address? → ASK or read from config/env
```

**Phase 3:** implement R1–R4 honoring C1, production-grade (Zod + RHF, server action, sanitize,
rate-limit, a11y labels), verify each line — and **ask only the ⚠️ address** rather than guessing.

## Anti-patterns (the failure modes this skill kills)

- **Dropping a clause** — ignoring "بس متغيرش الهيدر" and restyling everything.
- **Inventing scope ("التأليف")** — adding a newsletter, dark mode, or a refactor nobody requested.
- **Silently resolving ambiguity** — picking an email/value and not saying you assumed it.
- **Summarizing instead of translating** — collapsing 6 asks into 3 and losing two.
- **Lowering quality "because it's informal"** — colloquial input still gets v2 output.

## Agent checklist

```
- [ ] Quoted the user's text and translated it segment-by-segment (nothing dropped)
- [ ] Listed R (requirements), C (constraints), ⚠️ (ambiguities) separately
- [ ] Surfaced every assumption explicitly; asked when an ambiguity blocks correctness
- [ ] Executed ONLY R1..Rn under C1..Cn — no invented scope/refactors
- [ ] Met v2 quality inside scope (types, errors, security, a11y, tests where relevant)
- [ ] Re-verified the build against every R and C before declaring done
```

## Related

`prompt-engineering-advanced`, `god-mode-autonomous-agent`, `human-natural-code` (this hub);
the v2 standard is the depth bar used by `tailwind-master` and every upgraded master.
