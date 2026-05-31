# Advanced Patterns

## Orchestration Patterns

### Planner/Executor Separation

Prevents cognitive overload:
- **Planner**: Gathers context, creates plan
- **Executor**: Implements plan in parallel

**Why**: Context drift is the failure mode when combined.

### Document-Based Communication

Agents communicate through files, not conversation history:
- Critical instructions survive context truncation
- State persists across invocations
- Enables resumption and long-running tasks

**Pattern**: Use state files (`features.json`, `progress.md`) for handoffs.

### Orchestrator Pattern

For complex workflows:

```
orchestrator (background)
├── implementer (task 1) → verifier
├── implementer (task 2) → verifier
└── explorer (task 3)
```

**Example** (SDD pattern):
- `sdd-orchestrator`: Coordinates parallel execution
- `sdd-implementer`: Code generation (background)
- `sdd-verifier`: Validation after implementation
- `sdd-explorer`: Codebase discovery (readonly)

### Named Agent Roles (oh-my-cursor pattern)

Specialized workers:
- **Sisyphus/Atlas**: Orchestrators (not invokable as CLI subagents)
- **Explore**: Codebase search
- **Librarian**: Documentation management
- **Oracle**: Analysis and insights
- **Hephaestus**: Implementation
- **Metis**: Planning
- **Momus**: Review/critique
- **Prometheus**: Research

## Cost & Performance

### Token Economics

**Parallel penalty**: Running multiple subagents in parallel uses 25-35% more tokens than sequential execution.

**Mitigation**: Use `fast` model for appropriate tasks, minimal response formats, selective file inclusion, semantic search for relevant skills.

### Performance Characteristics

**Startup overhead**: Subagents start with clean context. They must gather their own context, so they're not faster than parent for simple tasks.

**When subagents shine**: Complex long-running tasks, parallel workstreams, context-heavy operations (searches, analysis).

**When to avoid**: Quick simple tasks (parent is faster), single-purpose one-shot operations (use skills instead).

### Cost Optimization Strategies

1. **Progressive Enhancement**: Start with cheaper models, enhance only when necessary
2. **Intelligent Caching**: Cache API responses (24-48 hour TTL), memoize computations
3. **Batch Processing**: Consolidate similar tasks for batch processing
4. **Model Selection**: Use `fast` for verification/testing, `inherit` for implementation

## Long-Running Agents

For tasks spanning multiple invocations:
- Use state files (`progress.md`, `features.json`)
- Subagent reads state at start to resume
- Document-based communication survives context truncation

## Subagent Trees (Cursor 2.5+)

Enable true parallel DAG execution:

```
orchestrator (background)
├── implementer (task 1) → spawns verifier
├── implementer (task 2) → spawns verifier
└── explorer (task 3)
```

**Pattern**: Each implementer spawns its own verifier to validate work independently.

## Background Execution

Set `is_background: true` for long-running tasks:
- Parent continues working immediately
- Subagent writes state to `~/.cursor/subagents/`
- Can resume after completion

## Hooks Integration

Use hooks for structured file output from subagents:

**`.cursor/hooks.json`**:
```json
{
  "subagentStop": {
    "command": "node scripts/process-subagent-output.js"
  },
  "stop": {
    "command": "node scripts/generate-summary.js"
  }
}
```

**Pattern**: Use hooks (afterFileEdit, stop) to process/save subagent output consistently rather than relying on subagent to save its own output.