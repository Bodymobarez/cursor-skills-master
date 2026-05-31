# Plan Template

Use this format when creating plans. Adapt section depth to the complexity of the work.

## Template

```markdown
# Plan: [Title]

**Created**: [date]
**Status**: In Progress | Complete | Paused
**Plan file**: `tmp/plans/[slug].md`

## Requirements

| ID | Requirement | Source |
|----|-------------|--------|
| R1 | [What must be true when done] | [conversation/ticket/spec] |
| R2 | ... | ... |

## Tasks

### Wave 1 — [description, e.g., "Foundation"]

- [ ] **1.1** [Task description]
  - Verify: [concrete check — command to run, file to inspect, behavior to test]
  - Reqs: R1

- [ ] **1.2** [Task description]
  - Verify: [concrete check]
  - Reqs: R1, R2

### Wave 2 — [description, e.g., "Core Logic"]
> Depends on: Wave 1

- [ ] **2.1** [Task description]
  - Verify: [concrete check]
  - Reqs: R2

- [ ] **2.2** [Task description]
  - Verify: [concrete check]
  - Reqs: R3

### Wave N — [description, e.g., "Polish & Verification"]
> Depends on: Wave N-1

- [ ] **N.1** Final verification against all requirements
  - Verify: Walk through each R* and confirm it holds

## Notes

> Decisions, blockers, and discoveries made during execution.
> Update this section as work progresses.

- [date]: [note]
```

## Format Rules

1. **Task IDs**: `[wave].[sequence]` — e.g., `1.1`, `2.3`. Sub-tasks use letter suffix: `2.1a`.
2. **Checkboxes**: `- [ ]` unchecked, `- [x]` done. This is what makes the plan restartable.
3. **Verify line**: Every task must have one. Must be concrete — a command, a file check, a testable behavior. Not "works correctly."
4. **Reqs line**: Trace back to requirement IDs so nothing gets lost.
5. **Wave ordering**: Tasks within a wave have no dependencies on each other. Cross-wave dependencies flow downward only.
6. **Final wave**: Always include a verification task that checks all requirements are satisfied.
7. **Notes section**: Living document. Record decisions, blockers, scope changes, and anything discovered during execution that future sessions need to know.

## Examples

### Good Verification Criteria

- `Run: pytest tests/auth/ — all pass`
- `File exists: src/services/UserAuth.ts with login/logout/refresh exports`
- `Manual: navigate to /settings, toggle dark mode, confirm styles apply`
- `Run: curl localhost:3000/api/health — returns 200 with {"status": "ok"}`

### Bad Verification Criteria

- `Works correctly` — not concrete
- `Tests pass` — which tests?
- `Looks good` — subjective
- `Done` — meaningless
