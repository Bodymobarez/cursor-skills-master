---
name: composer-ship-workflows
description: >-
  End-to-end Composer workflows that ship real features — from idea to tested PR.
  Use for complete delivery loops in Cursor combining coding, design, native apps,
  payments, and QA. Pre-built playbooks for SaaS features, mobile screens, landing
  pages, and marketplace modules — all optimized for Composer + master skills.
---

# Composer Ship Workflows

**Playbooks** that chain masters + Composer into repeatable ship loops — not theory, step-by-step.

## Workflow A: SaaS feature (web full-stack)

```
1. use fullstack-stack-architecture + typescript-unified-stack
2. @apps/web @packages/db — explore existing patterns
3. Schema migration (Prisma) + Zod validators in packages/types
4. Server Action or tRPC + RSC page
5. use ui-master + figma-grade-design-system — UI in packages/ui
6. use advanced-forms-architecture if forms
7. Vitest + Playwright; browser MCP smoke test
8. use human-natural-code — polish; use code-quality-master — review
9. git commit; gh pr create (if asked)
```
**Skills**: `god-mode-autonomous-agent` throughout.

## Workflow B: Landing + motion (design-heavy)

```
1. use brand-identity-creator — tokens if new brand
2. use award-winning-ui-effects + ultra-hd-visual-rendering
3. Next.js page in app/; 60fps check; reduced-motion fallback
4. use content-seo-master — meta/OG
5. Lighthouse + browser screenshot review
```

## Workflow C: iOS native screen (Xcode)

```
1. use xcode-native-full-power + mobile-master/blastum-xcode-build
2. @MyApp/ — SwiftUI View + @Observable model
3. xcodebuild test until green
4. Simulator screenshot → compare HIG
5. Commit; TestFlight notes if release
```

## Workflow D: Payments checkout

```
1. use payments-master — architecture + checkout-and-payment-pages
2. use payments-architecture — server amount from DB only
3. Stripe Connect or Paystack/Flutterwave per market (africa-payment-gateways)
4. Webhook handler idempotent (integrations-pro)
5. use accounting-finance — ledger posting
6. Test 3DS + webhook replay in staging
```

## Workflow E: Marketplace module

```
1. use marketplace-master — pick pattern (catalog / cart / seller)
2. use typescript-unified-stack — implement
3. use marketplace-payments-payouts if money moves
4. use search-discovery-recommendations if catalog
5. E2E: search → cart → checkout → webhook
```

## Workflow F: Support + WhatsApp

```
1. use communications-master — support-helpdesk-system
2. whatsapp-business-integration — template + webhook
3. omnichannel-inbox-chatbot — RAG on KB
4. email-integration-advanced — email-to-ticket
```

## Workflow G: Full product slice (multi-agent)

```
use elite-multi-agent-composer:
  Parallel: Explorer (codebase) + Designer (ui tokens)
  Architect: plan + ADR
  Builder: API + DB
  Designer: components
  Integrator: wire pages
  Reviewer: security + perf
  QA: tests + browser
```

## Definition of done (every workflow)

```
- [ ] Types check / build green
- [ ] Tests added or updated for changed behavior
- [ ] No secrets committed; env documented
- [ ] UI: a11y basics (labels, contrast)
- [ ] Diff reviewed; human-natural-code pass
- [ ] README or inline doc if new module
```

## One-shot mega prompt (Composer)

```
Ship [FEATURE] end-to-end in this repo.
use composer-ship-workflows workflow A.
use god-mode-autonomous-agent + cursor-composer-max-power + claude-ultimate-in-cursor.
Stack: typescript-unified-stack. Invoke ui-master for UI.
Run all verify commands. Don't stop until definition of done passes.
```

## Anti-patterns
- Skipping tests "will add later".
- Workflow B without checking perf on mobile.
- Workflow D without webhook idempotency test.
- Starting Workflow G without clear feature boundary.
