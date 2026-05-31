---
name: cursor-composer-max-power
description: >-
  Use Cursor Composer and Agent mode at maximum power. Use when building in
  Composer — multi-file edits, long autonomous tasks, @ context, Rules, Skills,
  MCP tools, parallel tool calls, checkpoints, background agents, and Multitask
  Mode. The complete guide to squeezing everything out of Cursor's agent.
---

# Cursor Composer — Maximum Power

Operate in **Composer (Agent)** as a full autonomous engineer — not a single-file autocomplete.

## Composer vs Chat vs Tab

| Mode | Use |
|------|-----|
| **Composer / Agent** | Multi-file features, refactors, new modules, debugging, "build X" |
| **Chat** | Questions, small edits, explanations |
| **Tab** | Inline completion while you type |

> For "خطير جداً" work: **always Composer (Agent)** with the right **Skills + Rules + @ context**.

## Load maximum context (every serious task)

```
@folder src/          — scope the agent to relevant code
@file package.json    — deps & scripts
@Docs Next.js         — framework docs (indexed)
@Web                  — latest API changes
@Git                  — diff, blame, history
@Codebase             — semantic search whole project
@Agent transcript     — continue prior work
```
- Start narrow (`@apps/web`) then widen if needed — avoids noise.
- Paste **errors verbatim** + **screenshots** (Composer reads images).
- Attach **Figma/spec** screenshots for design tasks.

## Skills + Rules (your superpowers)

```
Skills  → invoke domain masters: ui-master, payments-master, god-mode-autonomous-agent, …
Rules   → always-on constraints in .cursor/rules (stack, style, security)
```
- Say explicitly: `use ui-master and figma-grade-design-system` or `use god-mode-autonomous-agent`.
- Rules enforce: TypeScript strict, no any, test before done, human-natural-code, etc.
- **Stack** the right masters: `fullstack-stacks-master` + `typescript-unified-stack` for web.

## Agent behavior settings (max output)

- **Long-running tasks**: let the agent run; use TODO plan; don't interrupt mid-verify.
- **Parallel tool calls**: agent should batch reads/searches/edits — you enable this by giving broad clear goals.
- **Checkpoints**: revert bad agent turns; compare diffs before accept all.
- **Multitask Mode**: run background agents for exploration while you steer main Composer.

## MCP tools (extend Composer's hands)

Enable MCP servers in Cursor Settings → MCP:
- **Browser** (cursor-ide-browser): visual QA, test flows, scrape docs.
- **GitHub** (`gh`): PRs, issues, CI logs.
- **Postgres/DB**, **Linear**, **Sentry**, **Slack** — wire what the project uses.

Pattern: `CallMcpTool` only after reading tool schema in `mcps/<server>/tools/`.

## Composer workflow (elite loop)

```
1. Brief   — goal, stack, constraints, definition of done
2. Context — @folder + rules + 1–3 master skills
3. Plan    — agent writes TODOs (god-mode skill)
4. Execute — multi-file implementation, parallel reads
5. Verify  — run build/test/lint; browser MCP if UI
6. Review  — diff all files; reject sloppy changes
7. Ship    — commit message; gh pr create if asked
```

## Multi-file edit discipline

- One Composer thread per **feature** (not whole product rewrite).
- Ask for **surgical diffs** — match `human-natural-code` + project style.
- After large edits: `npm run typecheck && test && lint` in terminal (agent must run).

## Background / Cloud agents (when local isn't enough)

- **Cloud Agents**: long jobs on remote VM; good for big migrations, test sweeps.
- **Best-of-N**: parallel attempts on same task; pick best diff.
- Hand off with a written spec + link to repo branch.

## Power prompts (templates)

```
Build [X] using typescript-unified-stack. use god-mode-autonomous-agent.
Read @apps/web. Match existing patterns. use ui-master + advanced-forms-architecture.
Run tests before done. No placeholders.
```

```
Debug [error]. use debugging-master. Read stack trace. Root cause only. Minimal fix.
```

```
Redesign [screen] to Figma-grade. use figma-grade-design-system + award-winning-ui-effects.
Browser-test @http://localhost:3000/path
```

## Checklist
```
- [ ] Composer (Agent) mode, not Chat-only
- [ ] @context: relevant folders + errors/screenshots
- [ ] Right master skills invoked by name
- [ ] .cursor/rules aligned with stack
- [ ] MCP enabled for browser/gh/db if needed
- [ ] Agent ran verify commands; you reviewed full diff
```

## Anti-patterns
- Vague "fix it" with no @context or skill → generic wrong code.
- Accepting all files without reading diff.
- Chat for 20-file refactors (use Composer).
- Ignoring Rules/Skills you already installed.
- Stopping agent before it runs tests.
