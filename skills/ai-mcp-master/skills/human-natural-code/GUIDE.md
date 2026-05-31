---
name: human-natural-code
description: >-
  Write code and reasoning that reads as authentic, natural, human-authored — not
  obviously AI-generated. Use when the user wants code that looks hand-written by
  an experienced developer, free of AI "tells", and that blends into a real
  codebase. Covers avoiding AI patterns, matching project style, natural naming/
  comments/commits, and idiomatic, pragmatic code.
---

# Human-Natural Code

Produce code (and explanations) that read like an experienced developer wrote them — idiomatic,
pragmatic, and consistent with the surrounding project — instead of the uniform, over-explained
style that screams "generated".

> Goal: **authentic, professional craftsmanship.** Natural human code isn't sloppy — it's
> idiomatic, context-aware, and free of the repetitive scaffolding that AI output tends to add.

## The "AI tells" to avoid

| AI tell | Human alternative |
|---------|-------------------|
| Comment narrating every line (`// increment counter`) | Comment only non-obvious **why**, sparingly |
| Redundant docstrings on trivial functions | Docstrings where they add real value |
| Generic names (`data`, `result`, `temp`, `handleData`) | Domain names (`invoice`, `pendingPayouts`) |
| Over-defensive boilerplate everywhere | Validate at boundaries; trust internal code |
| Perfectly uniform structure / symmetry | Natural variation; group by real concerns |
| Unnecessary abstraction / premature interfaces | Inline until duplication justifies extraction |
| Verbose hedging prose, "Here's the..." preambles | Direct, terse explanations |
| Emoji in code/commits/UI (unless asked) | None |
| Exhaustive try/except around everything | Handle errors that actually occur |
| Re-explaining language basics in comments | Assume a competent reader |

## Principles of natural code

- **Match the existing codebase**: conventions, naming, formatting, file layout, error handling,
  test style, import order. Read neighbors first; imitate them. Consistency > your defaults.
- **Idiomatic per language**: use the language's natural patterns (Pythonic comprehensions, Go
  error returns, Rust `?`, idiomatic JS/TS) — not a translated one-size template.
- **Pragmatic, not academic**: real devs take sensible shortcuts, leave a TODO, pick the obvious
  approach. Don't gold-plate every function.
- **Comments are intent, not narration**: explain trade-offs, gotchas, "why this not that",
  external constraints — the things code can't say. Delete comments that restate the code.
- **Natural naming**: short where scope is short (`i`, `e`, `db`), descriptive where it matters;
  domain vocabulary; no `myFunction`/`fooBar`/`exampleData`.
- **Asymmetry is human**: not every branch needs the same shape; helpers emerge from real reuse,
  not upfront symmetry.
- **Realistic commits/PRs**: concise, lowercase-ish, imperative, focused ("fix off-by-one in
  pagination", not "Implemented comprehensive pagination enhancement"). One logical change each.

## Reasoning that reads human
- Get to the point; state the approach and trade-off briefly; don't over-enumerate or pad.
- Show judgment ("X is simpler here; Y only if we need Z later") instead of listing every option.
- Avoid formulaic structure in every answer (not always "Here's a summary / Let me / In conclusion").

## Workflow
```
1. Read 3–5 nearby files → absorb the project's voice (naming, errors, tests, structure)
2. Write to fit THAT codebase, not a generic template
3. Strip narration comments; keep only intent/why
4. Use domain names; remove unused abstractions/boilerplate
5. Vary structure naturally; inline trivial helpers
6. Self-review: "would a senior dev on this team have written this?"
```

## Checklist
```
- [ ] Matches surrounding code's conventions & idioms
- [ ] No line-by-line narration comments; comments explain why, not what
- [ ] Domain-specific names (no data/result/temp/handleX)
- [ ] No premature abstraction or blanket try/except
- [ ] Natural structural variation; pragmatic choices
- [ ] Concise, imperative commit messages; focused diffs
- [ ] Reads like a teammate wrote it (peer-review test)
```

## Anti-patterns (the dead giveaways)
- Every function fully docstringed + every line commented.
- `data`/`result`/`response`/`output` naming and `processData()` helpers.
- Identical, symmetric scaffolding across unrelated functions.
- Verbose preambles, hedging, emoji, and "comprehensive" everything.
- Ignoring the existing codebase's style and dropping in a generic template.

> Note: use this to produce genuinely high-quality, idiomatic, maintainable code that fits its
> project — not to misrepresent authorship where honest disclosure is required.
