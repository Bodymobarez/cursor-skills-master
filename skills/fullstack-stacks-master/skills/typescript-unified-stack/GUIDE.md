---
name: typescript-unified-stack
description: >-
  Build with the TypeScript unified full-stack — Node.js, Next.js, React,
  TypeScript end-to-end. Use for the default modern web SaaS stack where every
  layer shares types and tooling. Covers App Router, API (tRPC/Server Actions),
  Prisma/Drizzle, auth, testing, and deployment. The highest-compatibility JS
  stack in 2026.
---

# TypeScript Unified Stack (Node + Next.js + React + TS)

The **default gold stack** for web products: one language, shared types, one ecosystem, maximum
compatibility from database to browser.

## The stack (all compatible)

| Layer | Choice | Role |
|-------|--------|------|
| Runtime | **Node.js 20 LTS** (22 ok) | Server, tooling, SSR |
| Framework | **Next.js 15** (App Router) | SSR/SSG, API routes, Server Components, deploy |
| UI | **React 19** + **TypeScript 5.x** | Components, hooks, strict types |
| Styling | **Tailwind CSS v4** + shadcn/ui | Utility + accessible primitives |
| DB ORM | **Prisma** or **Drizzle** | Schema, migrations, typed queries |
| Validation | **Zod** | Forms, API, env — shared in `packages/types` |
| API | **tRPC v11** OR **Server Actions** + Route Handlers | Type-safe server↔client |
| Auth | **Auth.js (NextAuth v5)** or **Clerk** | Sessions, OAuth, middleware |
| Monorepo | **pnpm** + **Turborepo** | Shared packages |
| Test | **Vitest** + **Playwright** | Unit + E2E |
| Deploy | **Vercel** (native Next) or **Docker** on Fly/Railway/AWS |

## Project structure (monorepo)

```
apps/web/                 # Next.js App Router
  app/                    # routes, layouts, server components
  app/api/                # route handlers (REST webhooks)
  server/                 # tRPC router OR server-only modules
packages/
  db/                     # prisma/schema.prisma + client export
  validators/             # Zod schemas (login, createOrder, …)
  ui/                     # shared Button, Form, …
```

## Data flow (type-safe end-to-end)

```ts
// packages/validators/user.ts
export const createUserSchema = z.object({ email: z.string().email(), name: z.string().min(1) });
export type CreateUser = z.infer<typeof createUserSchema>;

// Server Action or tRPC procedure — same schema
const parsed = createUserSchema.safeParse(input);
await db.user.create({ data: parsed.data });

// Client form — zodResolver(createUserSchema)
```

## Next.js App Router conventions
- **Server Components** by default; `"use client"` only for interactivity.
- **Server Actions** for mutations (forms); revalidatePath/revalidateTag after.
- **Route Handlers** for webhooks (Stripe, WhatsApp) and third-party callbacks.
- **Middleware** for auth gate, locale, A/B.
- `fetch` with Next cache tags for data; don't duplicate client state for server data.

## Database (Prisma example)

```prisma
// packages/db/prisma/schema.prisma
model User { id String @id @default(cuid()) email String @unique ... }
```
- Migrations: `prisma migrate dev`; generate client in CI.
- Use **cuid()/uuid** for IDs; indexes on lookup fields; connection pooling (PgBouncer) in prod.

## Auth (Auth.js v5 pattern)

```
Middleware checks session → protect /dashboard/*
Server Components: auth() for user
Client: useSession() sparingly; prefer server data
OAuth: Google/GitHub providers; link to google-sign-in patterns
```

## When to split `apps/api` (NestJS/Fastify)

Stay **Next-only** until you need: heavy background workers, WebSocket scale separate from web,
multi-service team boundaries. Then extract NestJS sharing `@repo/db` + `@repo/validators`.

## Mobile extension (same stack family)

**Expo (React Native) + TypeScript** in `apps/mobile`, share `@repo/validators`, `@repo/api-client`
(tRPC React Query or openapi-fetch). Same auth tokens.

## Compatibility checklist
```
- [ ] Node 20+, TS strict, React 19, Next 15 App Router aligned
- [ ] pnpm workspace; shared Zod + DB package
- [ ] One API layer (tRPC OR Server Actions — not both for same domain)
- [ ] Prisma/Drizzle migrations in repo; env via @t3-oss/env-nextjs or zod env
- [ ] Auth middleware + server session check on protected routes
- [ ] Vitest + Playwright in CI; ESLint flat config shared
```

## Anti-patterns
- Pages Router legacy patterns in App Router project (`getServerSideProps` in `app/`).
- `any` everywhere; skipping strict null checks.
- Prisma client instantiated per request without singleton in dev (use global pattern).
- Client-side `fetch` to your own API for data RSC can load (waterfalls).
- Mixing JavaScript files in a TypeScript monorepo without reason.
