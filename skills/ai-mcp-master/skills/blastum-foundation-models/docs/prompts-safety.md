# Prompts & Safety

## Prompt design

- **Structure**: role/goal, task, constraints, examples if needed
- **Clarity**: what the model is, what it should output
- **Versioning**: prompt name + version to compare behavior over time
- **WWDC25 248**: Explore prompt design & safety for on-device foundation models

## Instructions (system prompt)

- Use `Instructions { ... }` in `LanguageModelSession`
- **Never** include untrusted content in instructions
- Put safety guidelines in instructions
- Tell model to create itinerary, use tools, include descriptions, etc.

## Model limitations

- Can hallucinate
- Not optimized for math or code
- Limited world knowledge
- Use tools to ground in up-to-date data

## Guardrails

- `SystemLanguageModel.Guardrails` for content filtering
- Enforce content policies in prompts and your own checks
- Allowed topics, no PII in logs
- Limits: context size, response length, tool calls per request

## User-facing controls

- Confirmation before actions that change state
- "Undo" where possible
- Clear messaging when Apple Intelligence is unavailable

## Acceptable use

Required reading: [Acceptable use requirements](https://developer.apple.com/apple-intelligence/acceptable-use-requirements-for-the-foundation-models-framework)

Compliance required for app submission and distribution.
