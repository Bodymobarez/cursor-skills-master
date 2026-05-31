---
name: elite-multi-agent-composer
description: >-
  Orchestrate multiple elite agents in Cursor Composer for coding and design in
  parallel. Use when one agent isn't enough — split exploration, implementation,
  design, review, and QA across specialized agents (Task subagents, background
  agents, skill-specific passes). Maximum throughput on hard projects.
---

# Elite Multi-Agent Composer

Run **specialized agents in parallel** — coder, designer, reviewer, explorer — inside one Composer
session or via background agents.

## Agent roles (assign explicitly)

| Agent | Skill stack | Delivers |
|-------|-------------|----------|
| **Architect** | `fullstack-stack-architecture`, `claude-ultimate-in-cursor` | ADR, folder structure, API contract |
| **Builder** | `god-mode-autonomous-agent`, `typescript-unified-stack` | Working code + tests green |
| **Designer** | `ui-master`, `figma-grade-design-system`, `award-winning-ui-effects` | UI, tokens, motion |
| **Reviewer** | `code-quality-master`, `human-natural-code` | Security, perf, style |
| **Explorer** | `cursor-composer-max-power` @Codebase | Map codebase, find patterns |
| **Mobile** | `xcode-native-full-power`, `mobile-master` | Swift/RN native |
| **Payments** | `payments-master` | Checkout, webhooks, PCI-safe |

## Parallel patterns in Cursor

### 1. Task subagents (same session)
```
Parent Composer:
  Task(explore): "Map auth flow in @apps/web — return file list + diagram"
  Task(security): "Audit @apps/api for OWASP top 5 — return findings only"
  [wait for both] → synthesize → Task(builder): implement fixes
```
- Launch **independent** explorations in one message (parallel Task calls).
- Parent **merges** results; avoids one agent context stuffed with noise.

### 2. Skill-stacked passes (sequential, different hats)
```
Pass 1: use ui-master — build static UI from spec
Pass 2: use typescript-unified-stack — wire data + server actions
Pass 3: use code-quality-master — review diff
Pass 4: use god-mode-autonomous-agent — fix all findings + verify
```

### 3. Background agents (Multitask)
- Agent A: long test suite / migration on branch.
- You + Agent B: feature on main line.
- Merge when A reports green.

### 4. Best-of-N (hard problems)
- Same prompt, N branches/worktrees; pick best implementation by tests + review.

## Design + code parallel (the "جامد" combo)

```
Thread A (Designer agent):
  figma-grade-design-system + ultra-hd-visual-rendering
  → components in packages/ui, Storybook/preview, no API yet

Thread B (Builder agent):
  typescript-unified-stack + advanced-forms-architecture
  → API + DB schema + Zod types

Sync point: shared packages/types + design tokens imported into web app
```

## Handoff contract (between agents)

Every handoff document includes:
```
Goal · Files touched · Decisions made · Commands run · What's left · Risks
```
Parent agent writes this; child agent reads — no re-exploration from zero.

## Context budget rules

- **Small contexts win** — explorer returns 20-line summary, not 50 files raw.
- One role per agent; don't ask designer to also write SQL migrations.
- Re-invoke `claude-ultimate-in-cursor` Opus only for architecture pass.

## Composer prompt (multi-agent)

```
Phase 1: Launch parallel explore agents for [auth] and [payments].
Phase 2: Architect proposes plan (Opus thinking).
Phase 3: Builder implements with god-mode; Designer polishes UI in packages/ui.
Phase 4: Reviewer pass; fix until lint+test green.
use cursor-composer-max-power throughout.
```

## Checklist
```
- [ ] Roles split (explore vs build vs design vs review)
- [ ] Parallel Task calls for independent research
- [ ] Shared types/tokens package as sync boundary
- [ ] Handoff notes between phases
- [ ] Final verify: one agent runs full CI commands
```

## Anti-patterns
- One agent doing design + backend + security + docs in one pass (shallow everything).
- Parallel agents editing **same files** (merge hell).
- No sync on types/tokens between UI and API agents.
- Skipping reviewer pass before merge.
