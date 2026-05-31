---
name: omnichannel-inbox-chatbot
description: >-
  Build an omnichannel inbox and AI chatbot/automation layer. Use to unify chat,
  WhatsApp, email, social, and web widget into one inbox, and to add AI agents
  (intent detection, RAG over knowledge base, automated replies, triage, and
  human handoff). Covers the website chat widget, bot framework, AI assist, and
  routing across channels.
---

# Omnichannel Inbox & AI Chatbot

Unify every conversation channel into one inbox, and automate with an AI agent that resolves what
it can and hands off the rest to humans.

## Omnichannel unification

```
Channels → Channel Adapters → Unified Conversation model → Inbox + Routing + Bot
  web chat widget · WhatsApp (whatsapp-business-integration) · email (email-integration-advanced)
  · in-app chat (realtime-chat-messaging) · Instagram/FB Messenger · SMS · Telegram
```
- Normalize every channel into one **Conversation + Message** model with `channel` + `channel_meta`.
- Identity resolution: merge the same person across channels (email/phone/user_id) → one customer.
- Route into the helpdesk (`support-helpdesk-system`) as tickets when human help is needed.

## Website chat widget
- Embeddable script → iframe/web component; async load, no blocking; mobile responsive.
- Features: launcher, unread badge, typing, file upload, history, proactive messages (triggers by
  page/time/behavior), pre-chat form, offline → email capture.
- Realtime via your `realtime-chat-messaging` layer (WebSocket) or a provider.

## AI chatbot / agent layer

```
incoming message → intent/triage → 
  if FAQ/known → RAG answer from knowledge base (cite sources)
  if action (order status, refund) → tool/function call to your APIs
  if low confidence / requested / sensitive → HUMAN HANDOFF (route to agent + context)
```
- **RAG over the knowledge base**: embed KB articles → vector search → ground the LLM answer (no
  hallucinated policies). Pair with `prompt-engineering-advanced` + `anthropic-mcp-builder`.
- **Tools/function calling**: let the bot do real actions (lookup order, create ticket, schedule)
  via your APIs — with auth + guardrails.
- **Confidence + escalation**: thresholds → escalate to human; never loop a frustrated user.
- **Agent assist** (human-in-the-loop): suggested replies, summarize thread, auto-tag/triage,
  draft from KB, translate — agent approves before sending.

## Bot design
- Hybrid: **rules/flows** for deterministic journeys (menus, forms, qualification) + **LLM** for
  open Q&A. Don't force everything through one or the other.
- Multilingual; tone matches brand; clear "talk to a human" always available.
- Business hours: bot 24/7, set expectations + collect contact when agents offline.

## Handoff (critical UX)
- Pass full context (transcript, customer, intent, sentiment) to the agent.
- Warm transfer: tell the user; show queue position/ETA; don't drop the thread.
- Bot ↔ human can co-exist on one conversation (bot pauses while agent active).

## Checklist
```
- [ ] Channel adapters → unified Conversation/Message + identity resolution
- [ ] Web chat widget (async, proactive triggers, offline capture)
- [ ] Intent/triage + RAG over KB (grounded, cited) + tool calling for actions
- [ ] Confidence thresholds → human handoff with full context
- [ ] Agent assist (suggest/summarize/triage/translate) human-approved
- [ ] Routing into helpdesk tickets + SLAs; analytics (deflection, CSAT, containment)
```

## Anti-patterns
- Dead-end bots with no human escape → angry customers.
- Ungrounded LLM answers (no RAG) → made-up policies/prices.
- Siloed channels (separate inboxes) instead of one unified conversation/customer.
- Bot actions without auth/guardrails (e.g. issuing refunds unchecked).
- No identity resolution → fragmented history across channels.
