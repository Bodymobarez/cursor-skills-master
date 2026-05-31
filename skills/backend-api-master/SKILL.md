---
name: backend-api-master
description: Master hub for Backend, APIs & data. Use for backend, REST/GraphQL APIs, auth, databases, payments, and integrations. Bundles 12 specialized skills (in skills/<name>/GUIDE.md). Use this for any backend api task.
---

# Backend, APIs & data — Master Hub

Use for backend, REST/GraphQL APIs, auth, databases, payments, and integrations.

## How to use this hub

This single skill bundles **all 12 backend api skills**. Each bundled skill's full instructions live in `skills/<name>/GUIDE.md` (plus any `scripts/`, `data/`, `references/` next to it).

**Workflow:**
1. Match the user's request to one or more skills in the list below.
2. Read that skill's `skills/<name>/GUIDE.md` for full instructions before acting.
3. Combine multiple bundled skills when a task spans several areas.

## Bundled skills

- **adding-api-docs** — Generate OpenAPI/Swagger documentation for an API, including endpoint schemas, request/response types, and interactive docs UI.  
  → `skills/adding-api-docs/GUIDE.md`
- **adding-auth** — Add authentication to a web application using NextAuth.js (Auth.js), including OAuth providers, session management, and protected routes.  
  → `skills/adding-auth/GUIDE.md`
- **adding-stripe** — Integrate Stripe payments into a web application, including checkout sessions, webhooks, and customer portal.  
  → `skills/adding-stripe/GUIDE.md`
- **cursor-skills-api** — API development rules for Cursor — REST, GraphQL, gRPC, authentication, versioning, and API design. Use when building or documenting APIs.  
  → `skills/cursor-skills-api/GUIDE.md`
- **cursor-skills-integrations** — Integration development rules for Cursor — webhooks, message queues, databases, microservices, and service mesh patterns.  
  → `skills/cursor-skills-integrations/GUIDE.md`
- **cursor-skills-node** — Node.js development rules for Cursor — Express, NestJS, Next.js, npm, TypeScript, and async patterns. Use for Node.js or JavaScript backend work.  
  → `skills/cursor-skills-node/GUIDE.md`
- **cursor-skills-php** — PHP development rules for Cursor — Laravel, Symfony, WordPress, Composer, and PHP project structure. Use when working with PHP, Laravel, Symfony, or WordPress.  
  → `skills/cursor-skills-php/GUIDE.md`
- **cursor-skills-python** — Python development rules for Cursor — Django, Flask, FastAPI, data science, virtual environments, and testing. Use when working with Python projects.  
  → `skills/cursor-skills-python/GUIDE.md`
- **database-design** — Design database schemas — tables, relationships, indexes, constraints, and ORM setup. Covers relational design, normalization, and common patterns.  
  → `skills/database-design/GUIDE.md`
- **stripe-stripe-best-practices** — >-  
  → `skills/stripe-stripe-best-practices/GUIDE.md`
- **stripe-stripe-projects** — >-  
  → `skills/stripe-stripe-projects/GUIDE.md`
- **stripe-upgrade-stripe** — Guide for upgrading Stripe API versions and SDKs  
  → `skills/stripe-upgrade-stripe/GUIDE.md`

## Note

These bundled skills are intentionally not registered as separate Cursor skills (their files are `GUIDE.md`, not `SKILL.md`) so only this master appears in the skills list. Read the relevant `GUIDE.md` on demand.
