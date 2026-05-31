---
name: planning-master
description: Master hub for Planning, architecture & product. Use to plan features: PRDs, issues, architecture decisions, prototyping, and scoping. Bundles 11 specialized skills (in skills/<name>/GUIDE.md). Use this for any planning task.
---

# Planning, architecture & product — Master Hub

Use to plan features: PRDs, issues, architecture decisions, prototyping, and scoping.

## How to use this hub

This single skill bundles **all 11 planning skills**. Each bundled skill's full instructions live in `skills/<name>/GUIDE.md` (plus any `scripts/`, `data/`, `references/` next to it).

**Workflow:**
1. Match the user's request to one or more skills in the list below.
2. Read that skill's `skills/<name>/GUIDE.md` for full instructions before acting.
3. Combine multiple bundled skills when a task spans several areas.

## Bundled skills

- **architecture-decision-records** — Document technical decisions as Architecture Decision Records (ADRs) with context, options considered, and rationale.  
  → `skills/architecture-decision-records/GUIDE.md`
- **blastum-plan** — Create restartable, session-spanning project plans with dependency-ordered tasks and verification criteria. Cursor-adapted version of Getting Shit Done. Use when building a plan, creating a task br...  
  → `skills/blastum-plan/GUIDE.md`
- **mattpocock-grill-me** — Interview the user relentlessly about a plan or design until reaching shared understanding, resolving each branch of the decision tree. Use when user wants to stress-test a plan, get grilled on the...  
  → `skills/mattpocock-grill-me/GUIDE.md`
- **mattpocock-grill-with-docs** — Grilling session that challenges your plan against the existing domain model, sharpens terminology, and updates documentation (CONTEXT.md, ADRs) inline as decisions crystallise. Use when user wants...  
  → `skills/mattpocock-grill-with-docs/GUIDE.md`
- **mattpocock-improve-codebase-architecture** — Find deepening opportunities in a codebase, informed by the domain language in CONTEXT.md and the decisions in docs/adr/. Use when the user wants to improve architecture, find refactoring opportuni...  
  → `skills/mattpocock-improve-codebase-architecture/GUIDE.md`
- **mattpocock-prototype** — Build a throwaway prototype to flesh out a design before committing to it. Routes between two branches — a runnable terminal app for state/business-logic questions, or several radically different U...  
  → `skills/mattpocock-prototype/GUIDE.md`
- **mattpocock-to-issues** — Break a plan, spec, or PRD into independently-grabbable issues on the project issue tracker using tracer-bullet vertical slices. Use when user wants to convert a plan into issues, create implementa...  
  → `skills/mattpocock-to-issues/GUIDE.md`
- **mattpocock-to-prd** — Turn the current conversation context into a PRD and publish it to the project issue tracker. Use when user wants to create a PRD from the current context.  
  → `skills/mattpocock-to-prd/GUIDE.md`
- **mattpocock-triage** — Triage issues through a state machine driven by triage roles. Use when user wants to create an issue, triage issues, review incoming bugs or feature requests, prepare issues for an AFK agent, or ma...  
  → `skills/mattpocock-triage/GUIDE.md`
- **mattpocock-zoom-out** — Tell the agent to zoom out and give broader context or a higher-level perspective. Use when you're unfamiliar with a section of code or need to understand how it fits into the bigger picture.  
  → `skills/mattpocock-zoom-out/GUIDE.md`
- **sentry-sred-project-organizer** — Take a list of projects and their related documentation, and organize them into the SRED format for submission.  
  → `skills/sentry-sred-project-organizer/GUIDE.md`

## Note

These bundled skills are intentionally not registered as separate Cursor skills (their files are `GUIDE.md`, not `SKILL.md`) so only this master appears in the skills list. Read the relevant `GUIDE.md` on demand.
