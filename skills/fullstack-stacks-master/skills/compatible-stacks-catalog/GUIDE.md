---
name: compatible-stacks-catalog
description: >-
  Reference catalog of other production-grade full-stack combinations where backend
  and frontend layers are proven compatible. Use when the product needs Go, Rust,
  PHP/Laravel, Java/Kotlin, or .NET instead of Node/Python — always paired with
  the right frontend and contract (OpenAPI/GraphQL). Covers stack recipes and
  when to choose each.
---

# Compatible Stacks Catalog

When TypeScript-unified or Python isn't the right fit, use these **proven pairings**. Every backend
below pairs with **Next.js + TypeScript** via **OpenAPI** (or native SDK) unless noted.

## Go stack (performance, simplicity)

| Layer | Choice |
|-------|--------|
| Language | **Go 1.22+** |
| HTTP | **Chi**, **Echo**, **Fiber**, or **Gin** |
| API style | REST + **ogen** / **go-swagger** → OpenAPI → TS client |
| ORM | **sqlc** (typed SQL) or **GORM** |
| Config | **Viper** / env |
| Frontend | **Next.js** (separate repo or monorepo `apps/web`) |
| Deploy | Single static binary + Docker; **Fly.io**, **Railway**, K8s |

```
Best for: high-throughput APIs, microservices, infra tools, small teams wanting simple deploys.
Pairing: Go REST/OpenAPI ↔ Next.js — never share types at compile time; OpenAPI is the contract.
```

## Rust stack (safety, edge, systems)

| Layer | Choice |
|-------|--------|
| HTTP | **Axum** (Tokio) — default choice |
| ORM | **SQLx** (compile-time checked SQL) or **Diesel** |
| Frontend A | **Next.js** + OpenAPI (most common) |
| Frontend B | **Leptos** / **Yew** (full Rust WASM — niche, one language) |
| Desktop | **Tauri 2** (Rust + webview) |

```
Best for: security-critical, low-latency, WASM edge, Tauri desktop.
Compatible combo: Axum API + Next.js UI (industry standard).
```

## PHP / Laravel stack (rapid SaaS, agencies)

| Layer | Choice |
|-------|--------|
| Framework | **Laravel 11** |
| API | Laravel API + **Sanctum** / Passport |
| Full-stack UI | **Inertia.js** + **React** or **Vue** (no separate Next — one app) |
| OR alternative | Laravel **Livewire 3** (PHP-first, no Node build for UI logic) |
| SPA pair | Laravel API + **Next.js** via OpenAPI (headless) |

```
Best for: CRUD SaaS, agencies, hosting on Forge/Vapor.
Most compatible: Laravel + Inertia + React (single deploy, shared session).
```

## Java / Kotlin (enterprise)

| Layer | Choice |
|-------|--------|
| Framework | **Spring Boot 3** |
| API | REST + **springdoc-openapi** → TS codegen |
| Build | Gradle (Kotlin DSL) |
| Frontend | **Next.js** |
| Mobile | **Kotlin Multiplatform** or React Native |

```
Best for: enterprise, banks, large orgs, JVM ecosystem mandates.
```

## .NET stack (Microsoft ecosystem)

| Layer | Choice |
|-------|--------|
| Framework | **ASP.NET Core 8** |
| API | Minimal APIs / Controllers + OpenAPI (Swashbuckle) |
| Frontend | **Next.js** or **Blazor** (C# UI — single language option) |
| Deploy | Azure-native |

## Mobile + web unified (TypeScript family)

| Layer | Choice |
|-------|--------|
| Web | **Next.js** |
| Mobile | **Expo (React Native)** |
| Shared | `packages/validators`, `packages/api-client`, design tokens |
| Backend | Node (Next API) or any OpenAPI backend |

```
Highest cross-platform compatibility: TypeScript on web + mobile + Node API.
```

## Quick selection guide

| Need | Pick |
|------|------|
| Default SaaS / startup | **typescript-unified-stack** |
| ML / data / Python team | **python-fullstack-stack** |
| Max perf / simple ops | **Go** + Next |
| Memory safety / Tauri | **Rust** + Next or Leptos |
| Fastest CRUD / agency | **Laravel + Inertia** |
| Enterprise JVM | **Spring Boot** + Next |
| One language desktop+web | **Tauri** or **Laravel Livewire** |

## Contract discipline (all stacks)

```
Backend (any language) → OpenAPI 3.1 in CI artifact
                      → codegen TypeScript client for Next.js
                      → breaking change = semver + CI diff
Auth documented in OpenAPI securitySchemes; same cookie/JWT rules in Next middleware
```

## Anti-patterns
- Go/Rust backend with hand-written TS types (no OpenAPI codegen).
- Laravel Inertia + separate Next app duplicating the same routes.
- Mixing two backends (Node + Go) for one product without clear service boundaries.
- Choosing Rust/Go for team with zero experience when TS would ship faster.
