---
name: blastum-plan
description: Create restartable, session-spanning project plans with dependency-ordered tasks and verification criteria. Cursor-adapted version of Getting Shit Done. Use when building a plan, creating a task breakdown, planning a feature, or resuming an existing plan.
---
# Plan

This skill is a **Cursor-adapted version of Getting Shit Done** (structured, dependency-ordered execution with explicit verification).

Create structured, persistent plans for complex multi-step work that spans sessions.

## When to Use

- Task requires 5+ steps with dependencies between them
- Work will span multiple sessions
- Requirements need formal tracking
- User explicitly asks for a plan

## Core Workflow

1. **Extract requirements** from the conversation
2. **Decompose** into dependency-ordered tasks
3. **Add verification** criteria to each task
4. **Write** the plan file
5. **Track** progress across sessions via checkboxes

## Plan File Location

Save plans to `tmp/plans/` in the workspace. Use a descriptive filename: `tmp/plans/<slug>.md`.

If `tmp/plans/` does not exist, create it.

## Creating a Plan

### Step 1: Requirements

Extract requirements from the conversation. If ambiguous, ask the user to clarify before proceeding. List each requirement with an ID for traceability.

### Step 2: Task Decomposition

Break requirements into atomic tasks. Each task should be completable in a single focused session or less.

Order tasks by dependencies:
- **Wave 1**: No dependencies (can be done first/in parallel)
- **Wave 2**: Depends on Wave 1 outputs
- **Wave N**: Depends on prior waves

### Step 3: Verification Criteria

Every task gets a verification line: how to confirm the task is actually done. This should be concrete and checkable — run a command, inspect a file, test a behavior. Avoid vague criteria like "works correctly."

### Step 4: Write the Plan

Use the format in [plan template](docs/template.md). The plan must include:
- Title and date
- Requirements list with IDs
- Tasks grouped by wave, each with checkbox, description, and verification
- A notes section for decisions and blockers discovered during execution

### Step 5: Present to User

After writing the plan file, show the user the full plan and confirm before execution begins.

## Resuming a Plan

When the user asks to resume or continue a plan:

1. Read the plan file from `tmp/plans/`
2. Find the first unchecked task
3. Summarize: what's done, what's next, any noted blockers
4. Continue execution from the next unchecked task

## Updating a Plan

When completing a task:
- Mark its checkbox `[x]`
- Add any decisions or discoveries to the Notes section
- If a task reveals new work, add it to the appropriate wave with a sub-ID (e.g., `2.1a`)

## Detailed Reference

- [Plan template and format](docs/template.md)
