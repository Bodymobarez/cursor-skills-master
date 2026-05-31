---
name: communications-master
description: >-
  Master hub for Communications — chat, WhatsApp, support/helpdesk, omnichannel
  AI chatbots, and advanced email. Use to build real-time in-app chat, WhatsApp
  Business messaging, a full advanced support/helpdesk module (tickets/SLA/KB/CSAT),
  an omnichannel inbox with AI chatbot + human handoff, and advanced email
  integration (transactional/inbound, deliverability, two-way sync, email-to-ticket).
  Bundles 5 specialized skills (in skills/<name>/GUIDE.md). Use for any chat,
  messaging, support, or email task.
---

# Communications — Master Hub

Use to build chat, WhatsApp, customer support, omnichannel inbox + AI chatbot, and advanced email.

## How to use this hub

This single skill bundles **all 5 communications skills**. Each bundled skill's full instructions
live in `skills/<name>/GUIDE.md`.

**Workflow:**
1. Match the request to one or more skills below; read its `GUIDE.md` before acting.
2. Combine them — a real support product spans chat + WhatsApp + email + helpdesk + bot.

## Bundled skills

- **realtime-chat-messaging** — Production real-time chat: WebSocket + Pub/Sub architecture, DMs/groups/channels, presence, typing, delivery/read receipts, reactions, attachments, offline sync, ordering, and security.  
  → `skills/realtime-chat-messaging/GUIDE.md`
- **whatsapp-business-integration** — WhatsApp Business Platform (Cloud API / BSPs): templates (HSM) & the 24-hour session window, interactive buttons/lists, media, webhooks, opt-in/compliance, and notification/support/chatbot use cases.  
  → `skills/whatsapp-business-integration/GUIDE.md`
- **support-helpdesk-system** — Full advanced helpdesk: ticketing + state machine, omnichannel intake, SLA policies (business hours, pause-on-pending), routing/escalation, macros/automations, knowledge base, CSAT/CES, agent workspace, and reporting.  
  → `skills/support-helpdesk-system/GUIDE.md`
- **omnichannel-inbox-chatbot** — Unify chat/WhatsApp/email/social/web into one inbox + AI agent: web chat widget, intent/triage, RAG over the knowledge base, tool/function calling, confidence-based human handoff, and agent assist.  
  → `skills/omnichannel-inbox-chatbot/GUIDE.md`
- **email-integration-advanced** — Advanced email: transactional/bulk via ESPs, deliverability (SPF/DKIM/DMARC/BIMI, one-click unsubscribe), MJML/React Email templates, inbound parsing, IMAP/Gmail/Graph two-way sync, threading, email-to-ticket, and bounce/complaint suppression.  
  → `skills/email-integration-advanced/GUIDE.md`

## Pairs well with
`ai-mcp-master` (prompt-engineering-advanced, mcp-builder, camera-ai-vision for the chatbot),
`business-master` (crm-builder for customer context), `backend-api-master` (integrations-pro
webhooks, auth), and `ui-master` (chat widget + dashboards).

## Note

These bundled skills are intentionally not registered as separate Cursor skills (their files are
`GUIDE.md`, not `SKILL.md`) so only this master appears in the skills list. Read the relevant
`GUIDE.md` on demand.
