# Tool Calling

Tools extend the model: fetch data, ground in sources of truth, perform side effects.

## Pattern (6 phases)

1. Present list of available tools and parameters to the model
2. Submit prompt
3. Model generates arguments for tool(s) to invoke
4. Tool runs with model's arguments
5. Tool passes output back to model
6. Model produces final response

## Create a tool

Conform to `Tool`:

- `name` — short identifier
- `description` — what it does (keep short for context/latency)
- `Arguments` — `@Generable` struct with `@Guide` for constraints
- `call(arguments:) async throws` — returns `String` or `GeneratedContent`

## Example: Bread database

```swift
struct BreadDatabaseTool: Tool {
    var name: String { "searchBreadDatabase" }
    var description: String { "Search bread recipes by term" }

    @Generable
    struct Arguments {
        var searchTerm: String
        @Guide(.range(1...6))
        var limit: Int
    }

    func call(arguments: Arguments) async throws -> String {
        let results = await breadDB.search(arguments.searchTerm, limit: arguments.limit)
        return results.joined(separator: "\n")
    }
}
```

## Example: Weather (multiple parallel calls)

```swift
struct WeatherTool: Tool {
    var name: String { "getWeather" }
    var description: String { "Get current weather for a city" }

    @Generable
    struct Arguments {
        var city: String
    }

    func call(arguments: Arguments) async throws -> String {
        let data = await weatherService.fetch(city: arguments.city)
        return "\(data.city): \(data.temp)°F, \(data.condition)"
    }
}
```

Model can call tools multiple times in parallel (e.g. weather for several cities).

## Provide session with tools

```swift
let session = LanguageModelSession(tools: [BreadDatabaseTool(), WeatherTool()])
let response = try await session.respond(to: "Find three sourdough bread recipes")
```

## Error handling

- `LanguageModelSession.ToolCallError`: tool name, underlyingError
- Throw from tool to escape (no access, timeout)
- Or return string describing failure

## Inspect call graph

```swift
session.transcript  // observable
// entries: .instructions, .prompt, .toolCall(call), .toolOutput(output), .response(response)
// Use with SwiftUI for session history/debugging
```

## What tools can do

- Integrate Contacts, HealthKit (existing privacy)
- Perform app actions or web requests
- Query app database and reference in answer
