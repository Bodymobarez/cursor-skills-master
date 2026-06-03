# Prompt Engineering Core — The Smart Prompter Framework

Author or upgrade any prompt to elite, professional quality. This is the brain
behind every role in `prompt-master`.

## The 7-block anatomy of a powerful prompt

Every strong prompt assembles these blocks (omit a block only when irrelevant):

1. **Role** — Who the model is. Be senior and specific.
   `Act as a [senior/PhD/principal] [exact role] with [N years / domain] expertise.`
2. **Context** — What it's working with. Inputs, audience, goal, constraints,
   prior decisions. Paste real data, don't describe it.
3. **Task** — The single clear objective, as a verb. One mission per prompt.
4. **Constraints** — Boundaries: scope, length, tone, what to avoid, what's
   out of scope, quality bar, must-cite rules.
5. **Output format** — Exact structure: sections, table columns, JSON schema,
   word counts. Models follow templates far better than prose.
6. **Reasoning directive** — How to think: "reason step by step", "weigh
   trade-offs", "state assumptions", "consider 3 alternatives before deciding".
7. **Self-critique / quality gate** — "Before finishing, review against [criteria]
   and fix weaknesses." Forces a second pass.

## Quality bar (a strong prompt is...)

- **Specific** — no vague verbs ("help", "improve"); use measurable targets.
- **Bounded** — defines scope, length, and what NOT to do.
- **Structured** — dictates the output shape.
- **Grounded** — supplies real context/data and demands evidence.
- **Role-anchored** — sets seniority so the answer isn't generic.
- **Testable** — you can tell if the output succeeded.

## Upgrade workflow (turning a weak prompt strong)

Copy this checklist when improving a user's prompt:

```
- [ ] Identify the true intent and success criteria
- [ ] Assign a senior, specific role
- [ ] Inject missing context (audience, goal, inputs, constraints)
- [ ] Sharpen the task to one clear verb-driven objective
- [ ] Add explicit constraints + out-of-scope list
- [ ] Define the exact output format (sections / table / schema)
- [ ] Add a reasoning directive
- [ ] Add a self-critique / quality gate
- [ ] Remove ambiguity, filler, and contradictions
```

### Before → after example

**Weak:** "Summarize these papers."

**Strong:**
```
Act as a PhD Researcher and Academic Analyst.

Context: 5 attached studies on X (audience: a research review board).
Task: Synthesize them into a critical literature review — not a summary.

Analyze and identify: core findings, research gaps, contradictions across
studies, emerging trends, and actionable insights.

Output in this structure:
1. Executive Summary (≤150 words)
2. Key Findings (bulleted, each tied to its source)
3. Research Gaps
4. Contradictions (study A vs study B, with the conflicting claim)
5. Recommendations
6. Future Research Directions

Reason like a university researcher: weigh evidence quality, flag inferences
vs established facts. Before finishing, re-check that every claim cites a source.
```

## Advanced techniques

- **Few-shot** — give 1–3 input→output examples for format-sensitive tasks.
- **Chain-of-thought** — request explicit reasoning for analysis/strategy.
- **Decomposition** — split big asks into ordered sub-tasks.
- **Persona stacking** — combine roles ("strategist + data analyst") for
  multi-angle output.
- **Self-consistency** — "generate 3 options, then pick the best and justify."
- **Negative constraints** — say what to avoid (jargon, fluff, hallucinated stats).
- **Format locking** — provide a JSON schema or markdown skeleton to fill.
- **Anti-hallucination** — "If a fact isn't in the provided material, say so;
  never invent statistics or sources."

## Reusable prompt template

```
Act as a [senior role] with deep expertise in [domain].

CONTEXT:
[goal, audience, inputs/data, constraints, prior decisions]

TASK:
[one clear objective]

REQUIREMENTS:
- [constraint 1]
- [scope / length / tone]
- Out of scope: [list]

OUTPUT FORMAT:
[sections / table columns / JSON schema]

THINKING:
Reason step by step, weigh trade-offs, and state any assumptions.

QUALITY GATE:
Before finishing, review the output against [success criteria] and fix gaps.
Do not invent facts; cite the provided material.
```

## Anti-patterns to avoid

- Multiple unrelated tasks in one prompt → split them.
- Asking for "everything" → forces shallow output. Scope it.
- No output format → inconsistent results.
- No role → generic, chatbot-grade answers.
- Asking for facts without supplying or allowing sources → hallucination risk.
