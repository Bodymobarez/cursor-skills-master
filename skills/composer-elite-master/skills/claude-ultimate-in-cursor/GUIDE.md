---
name: claude-ultimate-in-cursor
description: >-
  Use Claude models in Cursor at full capability — extended thinking, large
  context, tool use, vision, and production-grade reasoning. Use when you want
  maximum intelligence from Claude (Opus/Sonnet) inside Composer for hard coding,
  architecture, and design decisions. Covers model choice, prompting, context
  engineering, and Claude-specific strengths.
---

# Claude Ultimate in Cursor

Get **maximum intelligence** from Claude inside Composer — model selection, context, thinking depth,
and tool use.

## Model selection (Cursor)

| Model | Use |
|-------|-----|
| **Claude Opus** (thinking/high) | Architecture, hard bugs, security review, complex refactors, multi-system design |
| **Claude Sonnet** (fast/balanced) | Daily implementation, most Composer tasks, good speed/quality |
| **GPT/Codex** (if enabled) | Alternate for specific stacks user prefers |

> **Rule**: Opus for *decide & design*; Sonnet for *ship loops*; switch up when stuck 2+ times.

## Extended thinking (use on hard problems)

Enable **thinking / reasoning** models for:
- Race conditions, distributed systems, payment flows, auth bugs.
- "Why does X fail intermittently?" — not for renaming variables.

Prompt pattern:
```
Think through root cause before coding. List hypotheses, eliminate, then minimal fix.
use debugging-master. Show reasoning briefly, then implement.
```

## Context engineering (Claude's real limit)

Claude performs best when context is **curated**, not dumped.

Apply `prompt-engineering-advanced` (ai-mcp-master):
- **Write**: put spec, types, examples in the prompt or @files.
- **Select**: @folder not whole monorepo; attach only failing test + impl.
- **Compress**: summarize prior decisions in 5 bullets at thread start.
- **Isolate**: separate threads for backend vs UI vs Xcode.

```
ROLE: senior [stack] engineer on [product]
LIMITS: no new deps without ask; match repo style; run tests
CONTEXT: @relevant files + error log
OUTPUT: plan → code → commands run → result
```

## Vision (screenshots & designs)

- Paste UI bugs, Figma exports, Xcode simulator screenshots — Claude reads images in Composer.
- "Match this screenshot pixel layout" + `ultra-hd-visual-rendering` + `figma-grade-design-system`.

## Tool use mastery (let Claude act)

In Agent mode Claude can: read/write files, terminal, grep, MCP browser, Task subagents.

Maximize tools:
```
Don't explain how to run tests — run them and paste output.
Don't guess file paths — search codebase first.
Use parallel reads when exploring.
```

## Claude strengths to exploit

| Strength | How |
|----------|-----|
| Long reasoning | Architecture ADRs, migration plans, trade-off tables |
| Nuanced code | Subtle state bugs, protocol design, API design |
| Instruction following | Stacked skills + rules (composer max power) |
| Refactoring | Cross-file renames with typecheck loop |
| Docs | technical writing, OpenAPI, runbooks |

## Claude API patterns (if building AI features)

Pair with `anthropic-claude-api` (ai-mcp-master): prompt caching, tool calling, batch, structured outputs.

## Pair with other masters

```
Coding:   god-mode-autonomous-agent + human-natural-code + fullstack-stacks-master
Design:   ui-master + award-winning-ui-effects
Mobile:   xcode-native-full-power + mobile-master
Payments: payments-master (never hand-wave PCI)
```

## Checklist
```
- [ ] Right model tier (Opus vs Sonnet) for task difficulty
- [ ] Thinking mode on for hard/debug tasks
- [ ] Context curated (@files, ROLE/LIMITS/OUTPUT)
- [ ] Skills invoked explicitly
- [ ] Agent runs tools (tests, search) not prose-only instructions
- [ ] Vision used when UI/visual task
```

## Anti-patterns
- Opus for trivial CSS tweak (waste + slow).
- 500k tokens of irrelevant @Codebase.
- Asking Claude to "try" without running terminal commands.
- Ignoring extended thinking on intermittent production bugs.
- One prompt with 12 unrelated tasks.
