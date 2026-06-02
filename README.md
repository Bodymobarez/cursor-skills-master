# Cursor Skills Master

A curated, **organized** collection of **426 advanced agent skills** for [Cursor](https://cursor.com), bundled into **33 domain masters** — plus **`yasser`** the universal super-hub.

Instead of flooding your skills list with 426 entries, you get **34 hubs** (`yasser` + 33 domains). Use **`/yasser`** when you want everything; use a single `*-master` when you want focus.

> Sourced from the best public skill repos — Anthropic, Vercel, Sentry, PostHog, Cloudflare, Stripe, Matt Pocock, and curated community collections — then categorized and deduplicated.

---

## Why masters?

Cursor shows **every** `SKILL.md` in a flat list. With 426 skills that's noisy. This repo merges them so:

- ✅ **Yasser** (`/yasser`) routes to all domains — or pick one of **33 masters** alone.
- ✅ Each master bundles its domain's skills as `skills/<name>/GUIDE.md` (read on demand).
- ✅ Nothing is lost — all original scripts, data, and references are kept beside each skill.
- ✅ You invoke one master (e.g. `ui-master`) and the agent picks the right sub-skill.

---

## Install

### One-liner (global, recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/Bodymobarez/cursor-skills-master/main/install.sh | bash
```

This installs into `~/.cursor/skills/` (available in every project).

### Clone + install

```bash
git clone https://github.com/Bodymobarez/cursor-skills-master.git
cd cursor-skills-master
chmod +x install.sh
./install.sh                 # global → ~/.cursor/skills/
./install.sh --project .     # or into a specific project's .cursor/skills/
```

### Uninstall

```bash
./uninstall.sh               # global
./uninstall.sh --project .   # project
```

Your previous skills are **backed up** automatically to `~/.cursor/skills.backup.<timestamp>` before install.

After installing, **restart Cursor** (or open a new chat) and check **Settings → Skills**.

---

## Yasser — all-in-one

| Hub | Skills | What it covers |
|-----|:--:|----------------|
| **`yasser`** | routes all | **Super-hub:** all masters + 426 GUIDEs incl. **Remotion install** via `video-ai-master`. **`/yasser`** or `use yasser`. |

## The 33 domain masters

| Master | Skills | What it covers |
|--------|:--:|----------------|
| `integrations-master` | 16 | **World integrations**: GitHub/GitLab, OAuth, webhooks, CI/CD, AWS/GCP/Azure, Google/Microsoft 365, Slack/Teams, Jira/Linear/Notion, CRM, Shopify, analytics, Zapier/n8n, **80+ platform index** |
| `video-ai-master` | 12 | **AI video**: Veo/Kling/Runway, storyboard, fal.ai — **Remotion full install** (`npx create-video@latest`), render, avatars, ffmpeg, social export |
| `color-design-master` | 9 | **AI color harmony (Artist-Engineer)**: color theory, LLM palette prompts, OKLCH ramps, WCAG contrast, semantic UI roles, dark/light harmony, token export |
| `tailwind-master` | 13 | **Full Tailwind v4.3+ stack**: `@theme` tokens, CVA, shadcn/ui, Radix, RTL/Arabic, dark mode, **UAE AEGov DLS**, Next.js RSC, plugins, CSS/CSS Modules migration |
| `ui-master` | 27 | UI, frontend, **Tailwind v4** (see also `tailwind-master`), **advanced forms**, **brand identity**, **charts & dashboards**, **Figma-grade design systems**, **ultra-HD/8K rendering**, **award-winning effects**, CSS→Tailwind, responsive/a11y |
| `planning-master` | 11 | PRDs, issues, architecture (ADRs), prototyping, plan grilling |
| `testing-master` | 9 | Unit, integration, E2E (Playwright), TDD, smoke testing |
| `code-quality-master` | 16 | Code review, security audits, find-bugs, perf, simplification |
| `git-workflow-master` | 14 | Commits, branches, PRs, CI triage, `gh` CLI |
| `devops-master` | 20 | Docker, Kubernetes, Terraform, CI/CD, Cloudflare, Vercel deploy |
| `documents-master` | 21 | DOCX, PDF, PPTX, XLSX, Markdown, diagrams, images, **pro PDF + Excel + contracts**, docs sites (full AI video → `video-ai-master`) |
| `analytics-master` | 73 | PostHog, feature flags, error/LLM tracking, experiments, warehouse |
| `debugging-master` | 8 | Systematic debugging, port conflicts, profiling, build monitoring |
| `browser-automation-master` | 7 | Visual QA, network auditing, flow recording, Puppeteer |
| `ai-mcp-master` | 15 | MCP server building, **advanced prompt & context engineering**, **camera + AI vision**, **human-natural code**, **God-mode agent**, **colloquial-Arabic intent→literal execution**, model APIs |
| `content-seo-master` | 9 | Copywriting, blogs, brand/comms, SEO auditing |
| `mobile-master` | 6 | React Native, Expo, iOS/Swift, Flutter, Xcode |
| `backend-api-master` | 19 | REST/GraphQL, auth, **MFA**, databases, Stripe, integrations-pro (patterns), **QR/GS1**, Google Sign-In, GPS/GIS — **full platform integrations → `integrations-master`** |
| `business-master` | 8 | **CRM, ERP, double-entry accounting + full A→Z accounting system, affiliate, white-label, multi-tenant RLS, VAT/e-invoicing (ZATCA/Peppol)** |
| `travel-tech-master` | 7 | **Travel/tourism: GDS/NDC/bed-bank integration, channel manager, extranet, room mapping, B2B/B2C booking, booking-orchestration saga** |
| `marketplace-master` | 10 | **Multi-vendor (Amazon/Talabat-style): catalog, sellers, order-split, split payments/payouts, delivery dispatch, search/recs, reviews/trust, promotions, data platform** |
| `payments-master` | 8 | **Payment pages + every gateway/wallet worldwide & Africa: Stripe/Adyen/PayPal, Paystack/Flutterwave/Fawry/Paymob/M-Pesa, mobile money, orchestration, webhooks/idempotency, reconciliation/ledger, PCI/fraud** |
| `communications-master` | 7 | **Real-time chat, WhatsApp Business, helpdesk/SLA/CSAT, omnichannel + AI chatbot, advanced email (DKIM/DMARC), voice/SMS telephony, push notifications** |
| `systems-platforms-master` | 7 | **Backend platforms A→Z: MongoDB/Atlas, Supabase (Auth/RLS/Edge), Neon serverless Postgres, Cloudflare (Workers/R2/D1/KV/DO), Postman/Newman, complete email servers (SPF/DKIM/DMARC)** |
| `cross-platform-apps-master` | 6 | **Desktop (Electron/Tauri) + high-end mobile (iOS/Android) + one codebase web+desktop+mobile (Expo/RN Web/Tauri), store deploy, native bridges** |
| `ride-hailing-maps-master` | 8 | **Uber/Careem-style apps + maps mastery: matching/dispatch, live tracking, Mapbox/MapLibre/Google maps design, routing/ETA, geocoding, surge, super-app** |
| `gps-tracking-master` | 7 | **GPS/GNSS all kinds: fundamentals/NMEA, web+mobile geolocation, device protocols (Teltonika/GT06), RTK cm-precision, geofencing, fleet tracking, PostGIS** |
| `cybersecurity-master` | 9 | **Protect sites from hackers: OWASP Top 10, hardening (CSP/TLS/cookies), auth/account-takeover, secrets/supply-chain, cloud/network, pentest, DDoS/WAF/bot, SecOps/IR/compliance** |
| `visual-5d-master` | 5 | **Ultra-premium "5D" creative: cinematic video, photoreal/3D images, premium 3D logos, 3D render/motion graphics, cinematic color grading** |
| `fullstack-stacks-master` | 4 | **Compatible full-stack stacks: TypeScript unified (Node+Next+React+TS), Python (FastAPI/Django), Go/Rust/Laravel/Java/.NET + OpenAPI contracts** |
| `ads-agent` | 5 | **ADS Agent** — Cursor Composer max power, Claude ultimate, Xcode native, multi-agent orchestration (code+design), ship workflows |
| `skills-meta-master` | 15 | Authoring skills, rules, hooks, subagents, skill scanning |
| `productivity-master` | 14 | Context saving, onboarding, parallel exploration, project switching |

**Total: 426 bundled skills across 33 domain masters + Yasser super-hub.**

---

## Usage

Just describe your goal, or name a hub:

```
/yasser build a travel booking platform with payments and RTL UI
```

Or one domain only:

```
use integrations-master and connect GitHub webhooks + Slack alerts + HubSpot sync
```
```
use video-ai-master and create a 30s TikTok ad with Veo + captions + 9:16 export
```
```
use color-design-master and harmonize a fintech palette with OKLCH + WCAG + dark mode
```
```
use tailwind-master and set up Next.js 15 + shadcn + design tokens + RTL Arabic
```
```
use ui-master and build a SaaS landing page with a design system
```
```
use code-quality-master to review this PR for security and performance
```
```
use devops-master to add a Dockerfile and a GitHub Actions pipeline
```

The master opens, scans its bundled skills, reads the relevant `GUIDE.md`, and executes.
You can also invoke any master from chat with `/ui-master`, `/devops-master`, etc.

---

## How it works (structure)

```text
~/.cursor/skills/
└── ui-master/
    ├── SKILL.md                 # discoverable by Cursor — the hub/index
    └── skills/
        ├── ui-ux-pro-max/
        │   ├── GUIDE.md         # full instructions (hidden from Cursor's list)
        │   ├── scripts/         # original assets preserved
        │   └── data/
        ├── anthropic-frontend-design/
        │   └── GUIDE.md
        └── ...
```

Sub-skill files are named `GUIDE.md` (not `SKILL.md`) so **only the masters register** as Cursor skills. The agent reads a `GUIDE.md` on demand when the master routes to it.

---

## Credits

Skills are aggregated from their original authors. All rights and licenses remain with the
respective sources, including:
[anthropics/skills](https://github.com/anthropics/skills),
[vercel-labs/agent-skills](https://github.com/vercel-labs/agent-skills),
[getsentry/skills](https://github.com/getsentry/skills),
[PostHog/skills](https://github.com/PostHog/skills),
[cloudflare/skills](https://github.com/cloudflare/skills),
[stripe/agent-toolkit](https://github.com/stripe/agent-toolkit),
[mattpocock/skills](https://github.com/mattpocock/skills),
[blastum/AgentSkills](https://github.com/blastum/AgentSkills),
[spencerpauly/awesome-cursor-skills](https://github.com/spencerpauly/awesome-cursor-skills).

This repository only **reorganizes** them into master hubs for easier use in Cursor.

## License

The packaging/installer in this repo is MIT (see [LICENSE](LICENSE)). Individual bundled
skills retain the licenses of their original authors.
