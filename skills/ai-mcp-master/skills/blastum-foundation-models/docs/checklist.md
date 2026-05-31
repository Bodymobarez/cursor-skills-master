# Integration Checklist: Adding Foundation Models to an App

## 1. Clarify the use case

- Decide what the AI should do: summarize, classify, extract fields, generate drafts, tag content, etc.
- Specify inputs (what your app sends) and outputs (free text, JSON, structured object).
- Note constraints: latency, privacy, cost, offline/online, safety.

## 2. Choose where the model runs

- **On-device** (Foundation Models): privacy, low latency, personal context.
- **Server/cloud**: heavier workloads, shared data, central control.
- **Hybrid**: on-device for personal tasks, server for cross-user or heavier tasks.

## 3. Minimal integration path

1. Add the model SDK / API client.
2. Implement smallest request → response flow:
   - Build prompt from user input + minimal context.
   - Send to model, get response.
   - Surface result in UI or downstream logic.
3. Log requests/responses (with privacy in mind) for debugging.

## 4. Design prompts

- Clear instructions: what the model is, what it should output.
- Structured: role/goal, task, constraints, examples if needed.
- Version prompts (name + version) to compare behavior over time.

## 5. Move to structured outputs

- Define schema (fields, types, constraints).
- Use `@Generable` (Swift) or guided generation; instruct model to follow schema.
- Validate all model outputs before use.

## 6. Plan tool/function calling

- List actions the model can trigger: look up data, call APIs, write to DB, send messages.
- For each: name, description, input schema, output schema.
- Register tools with `LanguageModelSession(tools: [...])`.

## 7. Implement tool-calling loop

- On tool call: validate name and arguments, execute service, return result to model.
- Model uses result for final reply.
- Restrict which tools are available in which contexts.

## 8. Add safety and guardrails

- Content policies in prompts and checks (allowed topics, no PII in logs).
- Limits: context size, response length, tool calls per request.
- User controls: confirmation before state changes, undo where possible.

## 9. Observe and iterate

- Evaluation sets: realistic inputs + target behavior.
- Re-run when changing prompts, models, or tools.
- Use feedback (ratings, flags, logs) to tighten prompts and schemas.

## 10. Scale responsibly

- Separate feature logic (prompts, schemas, tools) from generic plumbing.
- Feature flags for gradual rollout.
- Revisit model choice and placement as usage grows.
