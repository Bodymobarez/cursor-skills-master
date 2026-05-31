---
name: blastum-hummingbird
description: Swift Hummingbird 2 web framework — routing, Application lifecycle, streaming responses, middleware, extensions, and SPM. Use when building or debugging Hummingbird servers, TaxWeb/taxcalc, SwiftNIO HTTP apps, or integrating HB ecosystem packages (WebSocket, Fluent, Lambda, OpenAPI).
---
# Hummingbird (Swift)

Lightweight **SwiftNIO**-based HTTP framework; **v2** is structured-concurrency-native (not EventLoopFuture-centric like v1).

## When this applies

- Swift `Package.swift` depends on `hummingbird-project/hummingbird` (2.x).
- Routers, `Application`, middleware, `ResponseBody`, HB testing, or ecosystem packages (auth, Fluent, WebSocket, Lambda).

## Before writing code

1. **Confirm APIs** against the **pinned** package revision (DocC or Xcode jump-to-def). Public samples differ (`run()` vs `runService()`, router builder styles).
2. **DocC** (`docs.hummingbird.codes`) is a **JS DocC app**: a plain HTTP GET (`curl`, naive fetch) returns an empty HTML shell, not the article. Read docs in a **browser**, via **IDE jump-to-definition / DocC**, or snapshot with **headless Chrome** (e.g. notebook skill `fetch-page-puppeteer.mjs`) if you need extracted text.

## Instructions

Read **[docs/guide.md](docs/guide.md)** for patterns, ecosystem table, pitfalls, and links.

## Quick links

| Resource | URL |
|----------|-----|
| DocC (2.x) | https://docs.hummingbird.codes/2.0/documentation/hummingbird/ |
| Repo | https://github.com/hummingbird-project/hummingbird |
| Examples | https://github.com/hummingbird-project/hummingbird-examples |
| Ecosystem page | https://hummingbird.codes/ecosystem |

## Optional project notebook

If the workspace is **taxcalc**, see `notebook/hummingbird/` for acquired sources and `repo-taxweb-hummingbird-usage` (TaxWeb wiring).
