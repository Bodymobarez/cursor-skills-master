---
name: python-fullstack-stack
description: >-
  Build with the modern Python full-stack. Use for APIs and backends with FastAPI
  or Django, paired with a compatible frontend (Next.js/React via OpenAPI, or
  Django+HTMX). Covers FastAPI + SQLAlchemy/Pydantic, Django 5, async, typing,
  and TypeScript frontend integration. A cohesive Python-centric stack.
---

# Python Full-Stack Stack

Python for backend (and optionally full-server-rendered UI). Pair with **TypeScript/Next.js** for
SPA frontends via **OpenAPI** — the standard compatible pairing.

## Stack A: FastAPI + modern async (API-first) ⭐

| Layer | Choice |
|-------|--------|
| Framework | **FastAPI** |
| Server | **Uvicorn** / **Gunicorn** + Uvicorn workers |
| ORM | **SQLAlchemy 2.0** (async) or **SQLModel** |
| Validation | **Pydantic v2** (mirrors Zod role) |
| Migrations | **Alembic** |
| DB | **PostgreSQL** |
| Task queue | **Celery** + Redis or **ARQ** / Dramatiq |
| Frontend | **Next.js** (separate app) — generate TS client from OpenAPI |
| Package | **uv** or **poetry**; **Ruff** lint + format; **mypy** or pyright |

```
project/
  backend/          # FastAPI app
    app/main.py
    app/api/v1/
    app/models/
    app/schemas/     # Pydantic request/response
  frontend/         # Next.js (pnpm) — optional monorepo root
  openapi.json      # exported; codegen → frontend/src/api/
```

- FastAPI auto-generates **OpenAPI** → `openapi-typescript` or `orval` for the Next app.
- Share **no** runtime types — contract is OpenAPI; CI fails if spec drifts.

```python
# schemas mirror what frontend Zod should enforce
class UserCreate(BaseModel):
    email: EmailStr
    name: str = Field(min_length=1)
```

## Stack B: Django 5 (batteries-included)

| Layer | Choice |
|-------|--------|
| Framework | **Django 5** + **Django REST Framework** (API) |
| Admin | Django Admin (internal ops) |
| ORM | Django ORM |
| Templates | Django templates + **HTMX** + **Alpine** (no separate FE) |
| API for SPA | DRF + **drf-spectacular** (OpenAPI) → Next.js client |
| Auth | django-allauth; session or JWT (simplejwt) |

Use when: admin-heavy, CMS, rapid CRUD, team knows Django. HTMX stack avoids a separate Node app.

## Stack C: Python + data/ML

**FastAPI** + **pandas/polars** + **MLflow**; Next.js dashboard reads API. Same OpenAPI contract.

## Compatible frontend pairing

```
Python API ── OpenAPI 3.1 ──► Next.js + TypeScript (openapi-fetch / orval)
           ── GraphQL (Strawberry/Ariadne) ──► codegen (less common)
           ── HTMX (no Node frontend) ──► Django templates only
```

Never hand-write TS interfaces for Python models — **codegen from OpenAPI**.

## Tooling alignment

```
Python 3.12+ · Ruff (lint+format) · pytest · pre-commit
Docker Compose: api + postgres + redis
.env shared pattern; pydantic-settings for config
```

## Auth across Python + Next

- **JWT**: FastAPI issues access/refresh; Next stores refresh in httpOnly cookie; BFF route refreshes.
- **Session**: harder cross-origin; prefer same-site subdomain (`api.app.com`, `app.com`).
- OAuth: Auth.js on Next **or** Authlib on FastAPI — pick one owner, document flow.

## Checklist
```
- [ ] FastAPI or Django chosen for product fit (API-first vs admin/CMS)
- [ ] Pydantic/DRF schemas = source of truth; OpenAPI exported in CI
- [ ] TS frontend client generated from OpenAPI; breaking change = CI fail
- [ ] Async SQLAlchemy 2.0 if high concurrency (FastAPI)
- [ ] Ruff + pytest + typed Python 3.12+
- [ ] Dockerized deploy; migrations (Alembic/Django) automated
```

## Anti-patterns
- Duplicating validation rules only in frontend (must exist in Pydantic too).
- Sync SQLAlchemy in async FastAPI routes (blocks event loop).
- Django templates + separate Next app for same pages (pick one UI strategy).
- No OpenAPI export → TS types hand-maintained (guaranteed drift).
