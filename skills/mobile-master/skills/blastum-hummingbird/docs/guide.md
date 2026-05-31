# Hummingbird 2 — agent guide

## Mental model

- **`Router`**: register methods + paths; handlers are `async throws` and receive `(Request, Context)` (or `_` if unused).
- **`Application`**: binds router + `ApplicationConfiguration` (address, optional TLS/HTTP2).
- **Concurrency**: assume `async`/`await` throughout; cancellation and task locals work as in Swift 6-era server code.

## SPM (typical)

```swift
.package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0")
// target:
.product(name: "Hummingbird", package: "hummingbird"),
```

CLI alternative: `swift package add-dependency …` / `add-target-dependency` (see upstream README).

## Minimal app shape (illustrative)

Two common public styles exist; **verify** parameter labels and lifecycle method names on your pin:

```swift
import Hummingbird

let router = Router()
router.get("hello") { _, _ -> String in "Hello" }

let app = Application(
    router: router,
    configuration: .init(address: .hostname("127.0.0.1", port: 8080))
)
try await app.runService()  // or run() — check symbol on Application for your version
```

Some docs use a fluent `Router().get { … }` without a path string; both reflect HB2-era APIs — **do not** copy without checking.

## Routing

- Path parameters: `:id` style; access via request parameters API (exact method names vary by minor version).
- Wildcards / groups: supported; see DocC and `hummingbird-examples` (`hello`, `todos-*`).

## Request body

- Collect with an **explicit byte limit** for JSON/form endpoints (avoid unbounded memory).
- Example pattern (taxcalc TaxWeb): `try await request.body.collect(upTo: 1_000_000)` then `JSONDecoder`.

## Responses

- Plain `String` / `Codable` return types often work when middleware/encoder is set up; otherwise build **`Response`** with status + headers.
- Large or binary payloads: **`ResponseBody`** with `contentLength` and a writer closure writing **`ByteBuffer`** chunks (streaming).

## Middleware

- Compose cross-cutting concerns (logging, CORS, auth) as middleware; order matters.
- HB distributes some behaviors as **separate products** (e.g. compression) — add the product to the target, not just `import`.

## Built-in extension products (separate modules)

Often pulled in as additional products from the main repo or sibling packages:

| Product / area | Role |
|----------------|------|
| HummingbirdRouter | Result-builder / alternate router DSL |
| HummingbirdTLS | TLS termination config |
| HummingbirdHTTP2 | HTTP/2 upgrade |
| HummingbirdTesting | In-process route/app tests |

## Ecosystem (separate repos)

| Package | Role |
|---------|------|
| hummingbird-websocket | WebSocket upgrade |
| hummingbird-lambda | AWS Lambda |
| hummingbird-auth | Auth framework |
| swift-openapi-hummingbird | OpenAPI → Swift server |
| hummingbird-fluent | Fluent ORM bridge |
| hummingbird-redis | RediStack integration |
| hummingbird-compression | Compress/decompress |
| swift-mustache | Mustache templates |
| swift-jobs | Job queues |

**DB / infra** commonly paired: postgres-nio, mysql-nio, sqlite-nio, MongoKitten, RediStack, swift-log, swift-metrics, swift-distributed-tracing. Full list: https://hummingbird.codes/ecosystem

## Testing

- Prefer **`HummingbirdTesting`** for route-level tests (see examples repo and DocC).
- Example projects cover auth, multipart, SSE, WebSocket, uploads, OpenTelemetry, etc.

## Reading DocC (docs.hummingbird.codes)

The site ships as a **client-rendered** DocC bundle: the initial HTML has no article body. **Unacceptable for article text:** `curl`, simple scripts that only read response HTML. **Fine:** browser, Xcode/sourcekit, or Puppeteer-style acquisition that executes JS (validated: notebook `fetch-page-puppeteer.mjs` on Getting Started). `robots.txt` disallows `/1.0/` only; `/2.0/` is allowed — still throttle politely if bulk-fetching.

## Pitfalls

1. **Snippet drift**: Cursor rules and blog posts may show HB1 or outdated HB2 APIs — trust **DocC + your Package.resolved pin**.
2. **Assuming static doc HTML**: same as above — not a “don’t scrape” rule, a “non-JS clients won’t see prose” rule.
3. **Product vs import**: Extra features need **Package.swift product** dependency, not only `import`.
4. **`run()` vs `runService()`**: both may exist across versions; pick one consistently per repo.

## History (one line)

HB2 = rewrite for **structured concurrency**; HB1 was EventLoopFuture-first. New work targets 2.x only.

## References

- Release narrative: https://hummingbird.codes/news/hummingbird-2  
- Todos tutorial (DocC mirror): https://hummingbird-project.github.io/hummingbird-docs/2.0/tutorials/todos  
- Template script (optional): `hummingbird-project/template` download script linked from upstream docs
