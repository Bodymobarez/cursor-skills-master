---
name: documentation-pro
description: >-
  Create professional technical documentation. Use for API docs, READMEs, developer
  guides, docs sites, tutorials, reference docs, changelogs, ADRs, or runbooks.
  Covers the Diátaxis framework, docs-as-code, tooling (Docusaurus/Mintlify/MkDocs),
  OpenAPI reference, structure, and writing style.
---

# Documentation Pro

Write clear, maintainable technical docs. Structure first, then write, then automate.

## 1. Diátaxis — the 4 documentation types (don't mix them)

| Type | Answers | Form |
|------|---------|------|
| **Tutorial** | "Teach me, I'm new" | Step-by-step, guaranteed success, learning-oriented |
| **How-to guide** | "Help me do X" | Recipe for a specific task, goal-oriented |
| **Reference** | "Tell me the details" | API/config tables, accurate & complete, information-oriented |
| **Explanation** | "Help me understand why" | Concepts, trade-offs, background, understanding-oriented |

Most bad docs fail by blending these. Keep each page one type.

## 2. Docs-as-code

- Docs live in the repo (Markdown/MDX), reviewed in PRs, built in CI, versioned with the code.
- Tooling:
  - **Docusaurus** — React-based docs site, versioning, i18n, MDX.
  - **Mintlify** — beautiful, fast, great for API docs + AI search.
  - **MkDocs (Material)** — Python, simple, excellent default theme.
  - **Starlight (Astro)** — fast, modern.
  - **Nextra** — Next.js based.
- Auto-publish on merge (Vercel/Netlify/GitHub Pages). Pair with `devops-master` for CI.

## 3. API reference from OpenAPI

- Maintain an **OpenAPI 3.1** spec as the source of truth; render with Scalar / Redoc / Mintlify /
  Swagger UI. Generate it from code annotations where possible so it never drifts.
- Every endpoint: purpose, auth, params, request + **response examples**, error codes, rate limits.

## 4. Page structures

**README (project front door):**
```
1. One-line what + why    2. Badges    3. Quick start (copy-paste, <5 min)
4. Features    5. Install    6. Usage example    7. Config
8. Links (full docs, contributing, license)
```
**Tutorial:** prerequisites → numbered steps (each verifiable) → result → next steps.
**ADR (architecture decision record):** Context → Decision → Consequences (+ status/date).
**Runbook:** symptom → diagnosis steps → remediation → escalation.

## 5. Writing style

- Lead with the **outcome**; second person, active voice, present tense ("Run `x`", not "you would run").
- Short sentences; one idea per paragraph; scannable headings + lists.
- **Runnable, complete code samples** (copy-paste works); show expected output.
- Define terms once; link don't repeat; keep a glossary.
- Add **diagrams** for architecture/flows (Mermaid — see `diagrams` skill).

## Checklist
```
- [ ] Classify each page (tutorial/how-to/reference/explanation) — don't mix
- [ ] Quick start that works in <5 min, copy-paste tested
- [ ] API reference generated from OpenAPI (no drift)
- [ ] Examples runnable with expected output
- [ ] Search + versioning + navigation set up
- [ ] CI builds docs; broken-link check; docs reviewed in PRs
- [ ] Changelog + migration guides for breaking changes
```

## Anti-patterns
- Mixing tutorial + reference on one page.
- Out-of-date examples (untested, drift from code) — generate/test them.
- Walls of prose with no headings, lists, or code.
- Documenting *what* the code is instead of *how to use it* and *why*.
- A README that explains everything but never shows a working example.
