---
name: prompt-engineering-advanced
description: >-
  Advanced prompt & context engineering for production LLM systems (2026). Use
  when designing system prompts, agent instructions, RAG pipelines, multi-agent
  context, evals, or optimizing prompts for reasoning models (Claude, GPT-5,
  Gemini). Covers context engineering (Write/Select/Compress/Isolate), the
  ROLE/LIMITS/CONTEXT/OUTPUT format, few-shot, meta-prompting, ReAct,
  self-consistency, failure modes, and prompt evaluation.
---

# Advanced Prompt & Context Engineering

Production-grade playbook for instructing modern LLMs. In 2026 the senior skill is
**context engineering** — deciding *what goes in the model's token window, when, and how it
persists* — with prompt wording as one (important) subset.

## When to use

- Writing or refactoring a **system prompt** / agent instruction set.
- Building **RAG**, tool-use, or **multi-agent** context flows.
- Optimizing prompts for **reasoning models** (don't hand-roll chain-of-thought).
- Setting up **prompt evals** and regression tests.
- Diagnosing flaky/inconsistent model output.

---

## Core mental model: the token stack

At every step the model sees a *stack*: system prompt + tool defs + retrieved docs + memory +
prior turns + current input. Your job is to **curate that stack**. The biggest wins come from
**removal, not addition** — remove redundant tools, trim history, move volatile state to the end.

### The four operations (LangChain framing)

| Op | Meaning | Practical move |
|----|---------|----------------|
| **Write** | Externalize state out of the window | Scratchpads, memory files, notes the agent can re-read |
| **Select** | Retrieve only what's needed | RAG / keyword / knowledge-graph lookup; RAG over tool descriptions |
| **Compress** | Summarize/prune to fight "context rot" | Compress proactively at 80–90% capacity, in atomic turn groups |
| **Isolate** | Split concerns across calls/agents | Separate sub-agents with focused windows |

> Never compress **instructions and data together** — keep instruction blocks intact.

---

## System prompt format (battle-tested)

Use four clearly delimited sections. Uppercase headings or XML tags give the model unambiguous
structure.

```text
ROLE
  Who the agent is, its expertise, its single primary objective.

LIMITS
  Hard constraints & non-negotiables. Highest-impact section for consistency.
  e.g. "Use conventional commits. Never force-push to main. Match surrounding code style."

CONTEXT
  The ONLY dynamic section. Everything that changes per request/user/state goes here.
  If it changes between calls, it does NOT belong in ROLE or LIMITS.

OUTPUT FORMAT
  Exact shape of the response. The more specific, the less downstream parsing you need.
```

Rules that matter most:
- **Be specific & prescriptive.** "Be helpful" → ❌. "Return JSON matching this schema; on
  error return `{\"error\": <reason>}`" → ✅.
- **LIMITS and OUTPUT FORMAT** have the highest impact — never cut them.
- Keep fixed sections **stable across requests**; isolate variability into CONTEXT.
- If behavior varies by user type, model it as **explicit conditional sections** or **separate
  agents** — not free-text caveats.

---

## The six techniques (they compose)

1. **Zero-shot** — clear instruction only. Default for capable models on simple tasks.
2. **Few-shot** — 2–5 input→output examples. Best lever for *format/style* consistency. Make
   examples diverse and edge-case-covering; wrong examples actively harm.
3. **Chain-of-Thought** — for reasoning models (Claude extended thinking, GPT-5, Gemini), the
   model already reasons internally. **Don't add "think step by step"** — it's redundant or
   harmful. Use CoT manually only on non-reasoning/older models.
4. **Self-Consistency** — sample N times, take the majority/best. Use for high-stakes answers
   where one bad sample is costly.
5. **Meta-Prompting** — ask the model to *write/critique the prompt itself*, then use it. Great
   for bootstrapping and for prompt-optimizer loops.
6. **ReAct (Reason + Act)** — interleave reasoning with tool calls so the agent fetches
   info **just-in-time** instead of front-loading everything. The backbone of agentic systems.

---

## Model-specific notes (2026)

- **Claude**: responds strongly to XML-tagged sections and explicit role framing; use extended
  thinking for hard tasks and *don't* duplicate CoT in the prompt. Treat Projects/memory as
  always-present context.
- **GPT-5**: prescriptive system prompt + explicit output schema; good at following structured
  conditional logic. Reasoning effort is a setting, not a prompt trick.
- **Gemini**: strong long-context; still curate — long ≠ relevant. Use gems/memory as persistent
  context.

---

## Failure modes → fixes

| Failure | Symptom | Fix |
|---------|---------|-----|
| **Context poisoning** | Model cites its own earlier hallucination | Don't feed unverified model output back as fact; ground with retrieval |
| **Distraction** | Long history degrades answers | Compress/trim; start a fresh session when the task changes |
| **Confusion** | Treats noise as signal | Remove irrelevant tools/docs; RAG-select tools (selection accuracy jumps when you don't expose all tools at once) |
| **Clash** | Conflicting instructions | De-duplicate; single source of truth for each rule |

---

## Workflow: write a production prompt

```
- [ ] 1. Define the ONE primary objective (ROLE).
- [ ] 2. List hard constraints (LIMITS) — be prescriptive.
- [ ] 3. Decide what is dynamic → CONTEXT only.
- [ ] 4. Specify exact OUTPUT FORMAT (schema/example).
- [ ] 5. Add 2–5 diverse few-shot examples IF format consistency matters.
- [ ] 6. For agents: define tools + ReAct loop; RAG-select tools if many.
- [ ] 7. Decide memory/retrieval (Write/Select) and compression triggers.
- [ ] 8. Build an eval set (below) and iterate via meta-prompting.
```

## Prompt evaluation (don't ship blind)

1. Collect **10–30 representative inputs** with expected outputs/criteria.
2. Run the prompt; score on **task success, format adherence, and consistency** (run each input
   3× to measure variance).
3. Change **one thing at a time**; keep a changelog of prompt versions.
4. Regression-test on every prompt edit. Treat the prompt like code.

---

## Anti-patterns

- Dumping everything into the window "just in case" (context rot).
- Politeness/role-play filler instead of concrete constraints.
- Manual "think step by step" on reasoning models.
- Mixing volatile state into fixed ROLE/LIMITS sections.
- Few-shot examples that are too similar or contain mistakes.
- No eval set — tuning by vibes.

## Quick templates

**Minimal agent system prompt**
```text
ROLE: You are a <domain> agent. Your objective is <single goal>.
LIMITS: <hard rules>. Never <forbidden>. Always <required>.
CONTEXT: <dynamic, per-request data injected here>
OUTPUT FORMAT: <exact schema / example>
```

**Meta-prompt to improve an existing prompt**
```text
Here is a prompt and 5 failing examples. Identify why it fails (ambiguity, missing
constraints, format drift), then rewrite it using ROLE/LIMITS/CONTEXT/OUTPUT FORMAT.
Output only the improved prompt.
```

---
Sources: 2026 prompt/context-engineering production playbooks and Anthropic system-prompt guidance.
