---
name: support-helpdesk-system
description: >-
  Build a complete, advanced customer support / helpdesk module. Use for ticketing,
  omnichannel inbox, SLAs, routing/assignment, macros/canned replies, knowledge
  base, CSAT/CES surveys, escalations, agent workspace, and reporting. Covers the
  full Zendesk/Intercom-grade support stack and its data model.
---

# Support / Helpdesk System (full, advanced)

Build a Zendesk/Intercom-grade support module: tickets across channels, SLAs, smart routing,
agent tools, self-service, and analytics.

## Data model

```
Ticket (subject, requester(customer), assignee(agent), team/group, channel[email|chat|whatsapp|
        web|phone|social], status[new|open|pending|on_hold|solved|closed], priority,
        type[question|incident|problem|task], tags[], sla_policy, due_at, satisfaction)
 └─ Message/Comment (author, body, public|internal_note, attachments, channel_meta)
Customer (contacts, orgs/companies, custom fields, history)
SLA Policy (conditions → first-response & resolution targets per priority/business-hours)
Macro (canned action set), View (saved filter), Trigger/Automation (event → conditions → actions)
KnowledgeBase: Article (category, body, status, locale, helpful votes)
```

## Core features

- **Omnichannel inbox**: email, live chat, WhatsApp, web form, social → all become tickets in one
  queue (pair with `omnichannel-inbox-chatbot`, `whatsapp-business-integration`, `email-integration-advanced`).
- **Ticket lifecycle**: state machine (new→open→pending→solved→closed) with reopen rules; merge,
  split, link related tickets.
- **Conversation threading**: public replies vs **internal notes**; @mention agents; full history.
- **Assignment & routing**: round-robin, load-based, skills-based, or queue/group; auto-assign by
  rules; reassign/escalate.
- **SLA management**: first-response & resolution targets per priority + **business hours**;
  pause on `pending` (waiting on customer); breach warnings + escalation.
- **Macros / canned replies**: one-click apply text + status + tags + assignment.
- **Automations/triggers**: on create/update → conditions → actions (route, tag, notify, escalate,
  auto-close stale, follow-up reminders).
- **Knowledge base / help center**: searchable articles, categories, multilingual, suggested
  articles in the agent + customer UI (deflection).
- **CSAT / CES / NPS**: post-resolution survey; track score per agent/team/channel.
- **Agent workspace**: unified view (ticket + customer 360 + order history + KB suggestions),
  keyboard shortcuts, collision detection (who's viewing/replying).

## SLA logic (get it right)
```
target = ticket.created_at + policy.first_response_time   (computed in BUSINESS HOURS)
clock pauses while status = pending (awaiting customer); resumes on customer reply
breach → notify + escalate (reassign, raise priority, alert manager)
```

## Reporting & QA
- Volume, first-response/resolution time, SLA compliance, backlog, reopen rate, CSAT, agent
  productivity, channel mix (pair with `charts-and-dashboards`).
- QA/IQS scorecards on a sample of tickets; tag analytics for top issues.

## Integrations
- Link to CRM (`crm-builder`), orders/marketplace, billing/payments; webhooks; AI assist
  (suggested replies, summarization, auto-triage) via `omnichannel-inbox-chatbot`.

## Checklist
```
- [ ] Ticket model + state machine + merge/split/link
- [ ] Omnichannel intake (email/chat/whatsapp/web/social) → unified queue
- [ ] Public reply vs internal note; collision detection; @mentions
- [ ] Routing (round-robin/load/skill) + escalation
- [ ] SLA policies w/ business hours + pause-on-pending + breach escalation
- [ ] Macros, triggers/automations, saved views
- [ ] Knowledge base + suggested articles (agent & customer)
- [ ] CSAT/CES + reporting dashboards + QA scorecards
```

## Anti-patterns
- Treating support as a shared email inbox (no SLAs, routing, history, reporting).
- SLA clocks ignoring business hours or not pausing on customer wait.
- No internal notes / collision detection → double replies, leaked notes.
- No knowledge base → agents retype answers; no deflection.
- Channels siloed instead of unified into one ticket/customer view.
