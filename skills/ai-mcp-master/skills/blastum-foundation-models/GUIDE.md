---
name: blastum-foundation-models
description: Add Apple Foundation Models (on-device LLM) to iOS/macOS/visionOS apps. Use when integrating generative AI, guided generation (@Generable), tool calling, content tagging, or custom adapters. Covers Swift API, Python SDK, prompts, safety, and adapter training.
---
# Foundation Models

Expert in adding Apple's on-device foundation model to apps. Same ~3B model that powers Apple Intelligence; no API keys, no per-request cost, runs on device.

## When to Use

- Adding summarization, entity extraction, drafting, tagging, or chat to an app
- Generating structured Swift data with `@Generable`
- Letting the model call your code (tools: DB lookup, API, app actions)
- Evaluating or prototyping with Python
- Training custom adapters for domain-specific behavior

## Quick Reference

| Topic | Doc |
|-------|-----|
| Integration checklist | [docs/checklist.md](docs/checklist.md) |
| Swift API | [docs/swift-api.md](docs/swift-api.md) |
| Guided generation (@Generable) | [docs/guided-generation.md](docs/guided-generation.md) |
| Tool calling | [docs/tool-calling.md](docs/tool-calling.md) |
| Prompts & safety | [docs/prompts-safety.md](docs/prompts-safety.md) |
| Python SDK | [docs/python-sdk.md](docs/python-sdk.md) |
| Adapter training | [docs/adapter-training.md](docs/adapter-training.md) |

## Essentials

- **Platforms**: iOS 26+, iPadOS 26+, macOS 26+, visionOS 26+
- **Requirement**: User must enable Apple Intelligence on supported device
- **Framework**: `FoundationModels` (Swift); `apple-fm-sdk` (Python)
- **Core types**: `SystemLanguageModel`, `LanguageModelSession`, `@Generable`, `Tool`, `Instructions`, `Prompt`, `Transcript`, `GenerationOptions`

## Resources

- [Apple docs](https://developer.apple.com/documentation/foundationmodels)
- [SystemLanguageModel](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel)
- [Acceptable use](https://developer.apple.com/apple-intelligence/acceptable-use-requirements-for-the-foundation-models-framework)
- [Supporting languages/locales](https://developer.apple.com/documentation/FoundationModels/supporting-languages-and-locales-with-foundation-models) — `supportsLocale(_:)`, `GenerationError.unsupportedLanguageOrLocale`
- WWDC25: 286 (overview), 259 (code-along), 301 (deep dive), 248 (prompt design & safety)
