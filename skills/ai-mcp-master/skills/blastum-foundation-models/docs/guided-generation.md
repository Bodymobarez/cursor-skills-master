# Guided Generation (@Generable)

Generate Swift data structures with strong type guarantees. No regex or fuzzy parsing.

## Basics

- `@Generable` macro on structs/enums
- `@Guide(description:)` — field description
- `@Guide(.anyOf(...))` — enum or constrained values
- `@Guide(.count(n))` — array length
- `@Guide(.range(...))` — numeric range

## Example: Itinerary

```swift
@Generable
struct Itinerary {
    @Guide(description: "Guide description")
    var title: String
    @Guide(.anyOf("Yosemite", "Sequoia", "Death Valley"))
    var destinationName: String
    var description: String
    var rationale: String
    @Guide(.count(3))
    var days: [DayPlan]
}

@Generable
struct DayPlan {
    var title: String
    var subtitle: String
    var destination: String
    @Guide(.count(3))
    var activities: [Activity]
}

@Generable
struct Activity {
    var type: Kind
    var title: String
    var description: String
}

@Generable
enum Kind {
    case sightseeing
    case foodAndDining
    case shopping
    case hotelAndLodging
}
```

## Streaming with PartiallyGenerated

When streaming, use `PartiallyGenerated<Itinerary>` — content fills in incrementally.

```swift
for try await partialResponse in session.streamResponse(
    generating: Itinerary.self,
    includeSchemaInPrompt: false,
    options: GenerationOptions(sampling: .greedy)
) { prompt in
    prompt  // build prompt
} {
    itinerary = partialResponse.content  // updates as streamed
}
```

## Example: Note summary

```swift
@Generable
struct NoteSummary {
    var title: String
    var summary: String
    var tags: [String]
}

// Prompt instructs: "Return JSON with keys title, summary, tags"
// Parse + validate before use
```

## Schema compatibility

Swift `@Generable` schemas are compatible with Python `@fm.generable` for evaluation and cross-platform use.
