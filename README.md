# Cursor Skills Master

A curated, **organized** collection of **319 advanced agent skills** for [Cursor](https://cursor.com), bundled into **23 master "hub" skills** — one per domain.

Instead of flooding your skills list with 319 entries, you get **23 clean masters**. Each master knows about all the skills in its domain and routes the agent to the right one(s) on demand.

> Sourced from the best public skill repos — Anthropic, Vercel, Sentry, PostHog, Cloudflare, Stripe, Matt Pocock, and curated community collections — then categorized and deduplicated.

---

## Why masters?

Cursor shows **every** `SKILL.md` in a flat list. With 319 skills that's noisy. This repo merges them so:

- ✅ Only **23 masters** appear in your Skills list.
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

## The 23 masters

| Master | Skills | What it covers |
|--------|:--:|----------------|
| `ui-master` | 27 | UI, frontend, **Tailwind CSS v4.3+ latest**, **advanced forms**, **brand identity**, **charts & dashboards**, **Figma-grade design systems**, **ultra-HD/8K rendering**, **award-winning effects**, CSS→Tailwind v4, responsive/a11y |
| `planning-master` | 11 | PRDs, issues, architecture (ADRs), prototyping, plan grilling |
| `testing-master` | 9 | Unit, integration, E2E (Playwright), TDD, smoke testing |
| `code-quality-master` | 16 | Code review, security audits, find-bugs, perf, simplification |
| `git-workflow-master` | 14 | Commits, branches, PRs, CI triage, `gh` CLI |
| `devops-master` | 20 | Docker, Kubernetes, Terraform, CI/CD, Cloudflare, Vercel deploy |
| `documents-master` | 18 | DOCX, PDF, PPTX, XLSX, Markdown, diagrams, images, **pro video production (AI + Remotion)**, **pro documentation/docs sites** |
| `analytics-master` | 73 | PostHog, feature flags, error/LLM tracking, experiments, warehouse |
| `debugging-master` | 8 | Systematic debugging, port conflicts, profiling, build monitoring |
| `browser-automation-master` | 7 | Visual QA, network auditing, flow recording, Puppeteer |
| `ai-mcp-master` | 14 | MCP server building, **advanced prompt & context engineering**, **camera + AI vision analytics**, **human-natural code (anti AI-detector)**, **God-mode autonomous agent**, model APIs |
| `content-seo-master` | 9 | Copywriting, blogs, brand/comms, SEO auditing |
| `mobile-master` | 6 | React Native, Expo, iOS/Swift, Flutter, Xcode |
| `backend-api-master` | 19 | REST/GraphQL, auth, **MFA/2FA authenticator security**, databases, Stripe, **integrations-pro/webhooks**, **QR & GS1 barcodes**, **Google Sign-In**, **GPS & GIS maps** |
| `business-master` | 5 | **CRM, ERP, accounting/finance, affiliate/referral, white-label/multi-tenant** |
| `travel-tech-master` | 6 | **Travel/tourism tech: GDS/NDC/bed-bank integration, channel manager, extranet, hotel/room mapping, B2B/B2C booking** |
| `marketplace-master` | 8 | **Multi-vendor marketplaces (Amazon/Talabat-style): catalog, sellers, cart/order-split, split payments/payouts, delivery dispatch, search/recs, reviews/trust** |
| `payments-master` | 6 | **Payment pages + every gateway/wallet worldwide & in Africa: Stripe/Adyen/PayPal, Paystack/Flutterwave/Fawry/Paymob/M-Pesa/Ozow, mobile money (MTN/Airtel/Orange/Vodafone Cash/Wave), orchestration, PCI/fraud** |
| `communications-master` | 5 | **Real-time chat, WhatsApp Business, full helpdesk/support (tickets/SLA/KB/CSAT), omnichannel inbox + AI chatbot, advanced email (deliverability/inbound/2-way sync)** |
| `fullstack-stacks-master` | 4 | **Compatible full-stack stacks: TypeScript unified (Node+Next+React+TS), Python (FastAPI/Django), Go/Rust/Laravel/Java/.NET + OpenAPI contracts** |
| `ads-agent` | 5 | **ADS Agent** — Cursor Composer max power, Claude ultimate, Xcode native, multi-agent orchestration (code+design), ship workflows |
| `skills-meta-master` | 15 | Authoring skills, rules, hooks, subagents, skill scanning |
| `productivity-master` | 14 | Context saving, onboarding, parallel exploration, project switching |

**Total: 319 bundled skills across 23 masters.**

---

## Usage

Just describe your goal, or name a master directly:

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
