# Core Guide

## Architecture

Subagents: isolated context windows (~170K-200K tokens). Operate independently, return structured summaries, run foreground/background.

**Benefits**: Context isolation, parallel execution, specialized expertise, cost efficiency.

**Built-in**: `explore` (codebase search), `bash` (shell execution), `browser` (MCP automation).

## File Format

### Location Hierarchy

Discovered in order (project-level takes precedence):
1. `.cursor/agents/` (project)
2. `.claude/agents/` (project)
3. `.codex/agents/` (project)
4. `~/.cursor/agents/` (user-level)
5. `~/.claude/agents/` (user-level)
6. `~/.codex/agents/` (user-level)

### Structure

Markdown file with YAML frontmatter:

```markdown
---
name: verifier
description: Validates completed work. Use after tasks are marked done to confirm implementations are functional.
model: fast
readonly: false
is_background: false
---

You are a skeptical validator. Verify that work claimed as complete actually works.

When invoked:
1. Identify what was claimed to be completed
2. Check implementation exists and is functional
3. Run relevant tests or verification steps
4. Look for edge cases

Report: verified/passed, incomplete/broken, specific issues.
```

### Frontmatter Fields

| Field | Required | Values | Description |
|-------|----------|--------|-------------|
| `name` | No | lowercase-hyphenated | Unique identifier. Defaults to filename |
| `description` | **Critical** | string | Determines delegation. Invest heavily |
| `model` | No | `fast`, `inherit`, or model ID | Default: `inherit` |
| `readonly` | No | boolean | Restricts write permissions |
| `is_background` | No | boolean | Runs async if true |

### Model Selection

- **`fast`**: Cheaper, lower capability. Use for simple tasks (verification, testing)
- **`inherit`**: Uses parent's model (default). Use when capability parity needed
- **Specific model ID**: e.g., `claude-sonnet-4-5`. Use for specialized requirements

**Note**: Legacy request-based plans without Max Mode run Composer regardless of model config.

## Delegation Patterns

### Automatic Delegation

Agent reads `description` field to decide when to delegate. Make descriptions specific:

**Bad**: `Use for general tasks`

**Good**: `Security specialist. Use proactively when implementing auth, payments, or handling sensitive data. Always use for OAuth flows and API key management.`

**Trigger phrases**: "use proactively", "always use for", "use when [specific condition]"

### Explicit Invocation

**Slash syntax**: `/verifier confirm the auth flow is complete`

**Natural language**: `Use the verifier subagent to confirm the auth flow is complete`

### Parallel Execution

Launch multiple subagents concurrently. Agent sends multiple `Task` tool calls simultaneously.

### Resuming

Resume using agent ID: `Resume agent abc123 and analyze the remaining test failures`

Background subagents write state to `~/.cursor/subagents/` for resumption.

## Best Practices

### 1. Single Responsibility

One clear job per subagent. Avoid generic "helper" agents.

**Bad**: "General purpose assistant for coding tasks"  
**Good**: "Security auditor specializing in authentication vulnerabilities"

### 2. Invest in Descriptions

The `description` field determines delegation reliability. Include: specific use cases, trigger conditions, domain expertise, when to use proactively.

### 3. Keep Prompts Concise

Target: 200-800 words for most subagents. Long prompts (2000+ words) dilute focus.

### 4. Structured Output Format

Return structured summaries, not raw data:

```markdown
## Goal
[Clear statement of what was accomplished]

## Approach
[High-level strategy and reasoning]

## Current Status
[What has been completed, what remains]

## Next Steps
[Specific actionable items]

## Key Files
- path/to/file1.ext - [role in solution]
- path/to/file2.ext - [role in solution]
```

### 5. Context Utilization Targets

Deploy subagents when operations risk exceeding 40-60% context utilization:

| Context Usage | Action |
|---------------|--------|
| 0-40% | Underutilized. Direct operations OK |
| 40-60% | Optimal. Monitor closely |
| 60-80% | Danger zone. Deploy subagent |
| 80-100% | Overflow. Compaction required |

**Trigger thresholds**:
- Glob: >20 files matched
- Grep: Always use subagent (500-2000 lines typical)
- Multiple Reads: >5 files
- Code flow analysis: Always use subagent (2000-10000 lines)
- Test/build logs: >500 lines

### 6. Model Selection Strategy

**Tiered approach**:
- **Haiku 4**: Initial data gathering, simple tasks
- **Sonnet 4**: Analysis, synthesis, most implementation
- **Opus 4**: Complex reasoning, orchestration only

Reduces average token costs by 60% while maintaining quality.

### 7. Version Control

Check `.cursor/agents/` into repository. Subagents are project assets.

### 8. Start Small

Begin with 2-3 focused subagents. Add more only with clear, distinct use cases.

## Anti-Patterns

### ❌ Vague Descriptions

**Bad**: "Use for general tasks"  
**Good**: "Use when implementing authentication flows with OAuth providers"

### ❌ Overly Long Prompts

2000+ word prompts don't make subagents smarter. Target 200-800 words.

### ❌ Duplicating Slash Commands

If a task is single-purpose and doesn't need context isolation, use a slash command instead.

### ❌ Too Many Subagents

Having 50+ subagents with vague instructions is ineffective. Start with 2-3, add only with clear use cases.

### ❌ Role-Playing Over Technical Tasks

Subagents are for context isolation, not anthropomorphizing. Focus on technical isolation.

### ❌ Deep Nesting

Subagents CAN spawn their own subagents (Cursor 2.5+). Use judiciously:
- Orchestrator → Implementers → Verifiers (good pattern)
- Arbitrary deep nesting (anti-pattern)

### ❌ Context Leakage

Don't allow subagent context to pollute main workflow. Return summaries, not raw output.

### ❌ Synchronous Blocking When Parallel Possible

Use `is_background: true` for long-running tasks.

## Taxonomy: Rules vs Skills vs Commands vs Subagents

| Type | Purpose | Invocation | When to Use |
|------|---------|------------|-------------|
| **Rules** | Persistent context and guardrails | Automatic or @mention | Conventions, constraints, policies |
| **Commands** | User-triggered workflows | `/command` | Repeatable procedures, multi-step tasks |
| **Subagents** | Specialized AI personas | Spawned by main agent | Context isolation, parallel work, deep expertise |
| **Skills** | Portable knowledge modules | Agent decides | Cross-project knowledge, shared capabilities |

### Decision Framework

**Use subagents when**: Need context isolation for long research tasks, running multiple workstreams in parallel, task requires specialized expertise across many steps, want independent verification of work.

**Use skills when**: Task is single-purpose (generate changelog, format), quick repeatable action, task completes in one shot, don't need separate context window.

**Use commands when**: User-triggered workflow, repeatable procedure, multi-step task.

**Use rules when**: Always-applied guidance, conventions and constraints, project-specific policies.

## Limitations

1. **Cloud Agents**: Cannot invoke subagents; delegation tool not available in cloud execution context
2. **Context startup overhead**: Subagents start with clean context; must gather their own context
3. **Parallel token penalty**: 25-35% overhead vs sequential execution