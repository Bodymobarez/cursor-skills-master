---
name: fullstack-stack-architecture
description: >-
  Choose and architect a cohesive full-stack technology stack where every layer
  is compatible. Use when picking languages/frameworks, structuring a monorepo,
  sharing types between frontend and backend, or ensuring Node/Next/React/TS (or
  Python/Go/Rust stacks) work together. Covers stack selection, monorepos, API
  contracts, and cross-layer conventions.
---

# Full-Stack Stack Architecture

Pick a **unified stack** where language, types, tooling, and runtime conventions align — so frontend,
backend, and infra feel like one product, not three glued projects.

## Golden rule: one primary language per product (when possible)

| Stack family | Shared language | Why |
|--------------|-----------------|-----|
| **TypeScript unified** ⭐ | TS everywhere | One type system: DB → API → UI; biggest ecosystem for web |
| **Python unified** | Python backend + TS/React frontend OR Python full (Django templates/HTMX) | Strong for ML/data/APIs; split FE is common |
| **Go / Rust / PHP / Java** | Backend language + **TypeScript frontend** (Next/React) | Mature backends; industry-standard FE pairing |

> Default recommendation for most SaaS/web apps in 2026: **TypeScript unified** (Node + Next.js +
> React + TypeScript). See `typescript-unified-stack`.

## Layer compatibility matrix

```
┌─────────────┬──────────────────────────────────────────────────────────┐
│ Layer       │ Must align on                                             │
├─────────────┼──────────────────────────────────────────────────────────┤
│ Language    │ Same major version policy (Node 20 LTS, TS 5.x)           │
│ Types       │ Shared package or OpenAPI/tRPC — no drift                 │
│ Package mgr │ One: pnpm (monorepo) or npm — lockfile committed          │
│ API style   │ REST (OpenAPI) OR tRPC OR GraphQL — pick one              │
│ Auth        │ Same session/JWT model on server components + API routes  │
│ DB          │ One ORM/schema tool; migrations in repo                    │
│ Lint/format │ ESLint + Prettier (TS) / Ruff (Python) — same in CI       │
│ Deploy      │ One platform family (Vercel/Fly/Railway) or K8s           │
└─────────────┴──────────────────────────────────────────────────────────┘
```

## Monorepo layout (TypeScript unified — Turborepo)

```
apps/
  web/          → Next.js (App Router) — UI + server components + API routes
  api/          → optional standalone NestJS/Fastify if not using Next API routes
  mobile/       → Expo/React Native (shared packages)
packages/
  ui/           → design system components
  db/           → Prisma/Drizzle schema + client
  types/        → shared Zod schemas + inferred types
  config/       → eslint, tsconfig bases
  api-client/   → typed fetch or tRPC router types
```

- **pnpm workspaces** + **Turborepo** for build cache and task orchestration.
- `tsconfig` extends from `packages/config`; strict mode everywhere (`strict: true`).
- Import via workspace protocol: `"@repo/db": "workspace:*"`.

## API contract between layers (no drift)

| Approach | Best when |
|----------|-----------|
| **tRPC** | TS monorepo; end-to-end types, no codegen |
| **OpenAPI + codegen** | Polyglot or public API; generate client from spec |
| **GraphQL** | Complex graphs, many clients, federation |
| **Server Actions + Zod** | Next.js-first; forms and mutations without REST boilerplate |

Pick **one** per product; don't mix tRPC and hand-written REST types for the same resources.

## Cross-stack patterns (when backend ≠ frontend language)

```
Backend (Go/Rust/Python/Java) ── OpenAPI 3.1 spec ──► generate TS client for Next.js
                              ── or GraphQL schema ──► codegen
```
- OpenAPI is the **contract**; backend and frontend stay compatible via CI codegen.
- Auth: JWT or session cookie with documented flows; same CORS/cookie rules.

## Environment & runtime alignment

```
Node 20 LTS (or 22) · TypeScript 5.x · React 19 · Next.js 15 (App Router)
Package manager: pnpm 9+ · Bundler: Turbopack (Next dev) / Vite (non-Next apps)
```

- Pin versions in root `package.json` `engines` + `.nvmrc`.
- One `.env.example`; secrets never in frontend bundle (`NEXT_PUBLIC_` only for public).

## Checklist
```
- [ ] Pick one primary stack family; document in README/ADR
- [ ] Monorepo (if TS): pnpm + Turborepo + shared packages (db, types, ui)
- [ ] Single API contract strategy (tRPC / OpenAPI / GraphQL / Server Actions)
- [ ] Shared auth model across web + API + mobile
- [ ] Aligned Node/TS/React/Next versions; strict TS; one lint/format pipeline
- [ ] CI builds all apps/packages; typecheck + test before merge
```

## Anti-patterns
- Next.js 14 patterns on Next 15; React 18 hooks on React 19 without checking breaking changes.
- Duplicate types manually in frontend and backend (always share or codegen).
- Mixing npm and pnpm, or multiple lockfiles in one monorepo.
- Three different auth libraries on web vs API vs mobile.
- Choosing Rust/Go for CRUD SaaS when the team only knows TypeScript (match team + product).
