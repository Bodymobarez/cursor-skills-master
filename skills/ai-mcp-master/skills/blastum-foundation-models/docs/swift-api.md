# Swift API

## Availability check

```swift
let model = SystemLanguageModel.default
switch model.availability {
case .available:
    // Show AI features
case .unavailable(.appleIntelligenceNotEnabled):
    MessageView(message: "Turn on Apple Intelligence to use this feature.")
case .unavailable(.modelNotReady):
    MessageView(message: "Try again later.")
}
```

## Core types

- `SystemLanguageModel` — on-device LLM; `.default` or `SystemLanguageModel(useCase: .contentTagging)` for tagging
- `LanguageModelSession` — stateful session; `LanguageModelSession(tools: [...], instructions: Instructions { ... })`
- `Instructions` — system instructions (role, constraints); never include untrusted content
- `Prompt` — user prompt
- `Transcript` — session history: `.instructions`, `.prompt`, `.toolCall`, `.toolOutput`, `.response`
- `GenerationOptions` — e.g. `GenerationOptions(sampling: .greedy)`

## Minimal request → response

```swift
let session = LanguageModelSession()
let response = try await session.respond(to: "Summarize this in 3 bullets: \(inputText)")
// response is String
```

## Streaming

```swift
for try await partial in session.streamResponse(to: prompt) {
    // partial is streamed text
    ui.update(partial)
}
```

## Content tagging (hashtags)

```swift
let model = SystemLanguageModel(useCase: .contentTagging)
let session = LanguageModelSession(model: model)
// streamResponse(to: text, generating: TaggingResponse.self)
```

## Use cases

- **Writing & content**: Draft replies, refine copy, suggest headlines, rewrite tone/length
- **Understanding & organizing**: Summarize, extract entities, tag content, classify feedback
- **Structured output**: `@Generable` for itineraries, forms, quiz questions
- **Conversation**: Chat grounded in app data; tools for lookups
- **Creative**: Game dialogue, story beats, name suggestions

## Sample app pattern (trip planner)

- Configure: `LanguageModelSession(tools: [FindPointsOfInterestTool], instructions: Instructions { ... })`
- Custom tool: conform to `Tool`; model calls to find hotels, restaurants, activities
- Stream: `streamResponse(generating: Itinerary.self, includeSchemaInPrompt: false, options: GenerationOptions(sampling: .greedy))`
- UI: show tool lookup history ("Searching hotel in Yosemite…") and incremental itinerary
- Integrate: MapKit `MKLocalSearch`, WeatherKit; model output + location data

## Performance (iPhone 15 Pro)

- ~0.6 ms per prompt token (time-to-first-token)
- ~30 tokens/sec
- Low-bit palletization, LoRA, mixed 2-bit/4-bit
