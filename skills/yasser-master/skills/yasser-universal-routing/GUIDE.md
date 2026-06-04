---
name: yasser-universal-routing
description: >-
  Keyword and intent router for Yasser super-hub: maps user requests to the correct
  domain master(s). Read when yasser is invoked and the task domain is unclear.
---

# Yasser Universal Routing

## Keyword → Master

| Keywords (any language) | Master |
|-------------------------|--------|
| UI, frontend, redesign, premium UI, Stripe, Linear, Notion, glassmorphism, dashboard, Framer Motion, elite design, عربي, تصميم | `ui-master` → **`elite-ui-ux-design-system`** + `tailwind-master` |
| فيديو, video, Veo, Kling, reel, TikTok, avatar | `video-ai-master` |
| Remotion, create-video, React MP4, programmatic video, نصوص على فيديو, install remotion | `video-ai-master` → **`remotion-programmatic-video/GUIDE.md`** (run `npx create-video@latest`) |
| integration, GitHub, GitLab, webhook, OAuth, Slack, Jira, Notion, API, ربط, تكامل | `integrations-master` |
| API, backend, database, auth, MFA, GraphQL, REST, سيرفر | `backend-api-master` |
| payment, Stripe, Paymob, Fawry, wallet, checkout, دفع | `payments-master` |
| WhatsApp, chat, ticket, helpdesk, email, support | `communications-master` |
| marketplace, multi-vendor, seller, Talabat, Amazon, متجر | `marketplace-master` |
| travel, hotel, GDS, OTA, booking, سياحة, فنادق | `travel-tech-master` |
| CRM, ERP, accounting, محاسبة, affiliate, white-label, multi-tenant, VAT, e-invoice, ZATCA | `business-master` |
| Database Studio, SQL IDE, schema browser, table editor, ER diagram, migrations UI, داتابيز ستوديو, لوحة قواعد بيانات, pgAdmin بديل | `systems-platforms-master` → **`database-studio-complete`** |
| MongoDB, Supabase, Neon, Cloudflare, Postman, email server, سيرفر ايميل, database setup | `systems-platforms-master` |
| desktop app, Electron, Tauri, mobile app, iOS, Android, one codebase, ديسكتوب, موبايل | `cross-platform-apps-master` |
| Uber, Careem, ride-hailing, taxi, dispatch, live tracking, maps, خرائط, mapbox, routing | `ride-hailing-maps-master` |
| GPS, GNSS, RTK, geofence, tracker, fleet, تتبع, جي بي اس, NMEA, PostGIS | `gps-tracking-master` |
| security, hacker, hacked, OWASP, XSS, pentest, WAF, DDoS, امن, اختراق, سيكيورتي | `cybersecurity-master` |
| cinematic, 5D, 3D logo, premium image, color grade, لوجو, سينمائي, صور 5D | `visual-5d-master` |
| PDF, Excel, contract, عقد, شيت اكسل, فاتورة PDF | `documents-master` |
| colloquial, بالبلدي, كلام عشوائي, ترجمة حرفية, نفّذ بالحذافير | `ai-mcp-master` → **`colloquial-arabic-intent-execution/GUIDE.md`** |
| Docker, K8s, Terraform, deploy, CI/CD, Cloudflare | `devops-master` |
| git, commit, PR, branch, gh | `git-workflow-master` |
| QA audit, test everything, dead buttons, broken routes, crawl app, Playwright audit, اختبار شامل, تدقيق جودة, QA_AUDIT_REPORT | `testing-master` → **`autonomous-qa-audit-complete`** |
| test, Playwright, E2E, unit test | `testing-master` |
| review, security, audit, bug, performance | `code-quality-master` |
| debug, error, crash, slow | `debugging-master` |
| PRD, plan, architecture, ADR | `planning-master` |
| PDF, DOCX, PPTX, documentation, docs site | `documents-master` |
| PostHog, analytics, feature flag, experiment | `analytics-master` |
| MCP, prompt, LLM, Claude, GPT, vision, agent | `ai-mcp-master` |
| mobile, React Native, Expo, Flutter, iOS | `mobile-master` |
| browser, screenshot, visual QA | `browser-automation-master` |
| SEO, blog, copywriting, content | `content-seo-master` |
| Next.js, FastAPI, full stack, stack | `fullstack-stacks-master` |
| skill, rule, hook, Cursor meta | `skills-meta-master` |
| productivity, context, explore | `productivity-master` |
| Composer, ship, god mode, max power | `ads-agent` |

## Decision flow

```
Is task exactly one domain?
  YES → route to that *-master only (faster)
  NO  → pick 2–4 masters, read each SKILL.md, merge GUIDEs
Does task need code + design + infra?
  YES → planning → domain → git-workflow + devops + testing
```

## File read order

1. `yasser-master/SKILL.md` (this hub)
2. Chosen `<domain>-master/SKILL.md`
3. Specific `skills/<skill>/GUIDE.md`

## Anti-patterns

- Loading every GUIDE in the repo for a one-line CSS fix
- Ignoring specialized masters when user named one (`/payments-master`)
- Duplicating payment logic without reading `payments-architecture` GUIDE
