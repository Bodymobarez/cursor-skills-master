---
name: support-helpdesk-system
description: >-
  Zendesk/Intercom-grade helpdesk at staff depth: ticket state machine, omnichannel intake,
  SLA engine computed in BUSINESS HOURS with pause-on-pending and breach escalation, routing
  (round-robin/load/skills), macros/triggers, knowledge base + deflection, CSAT/CES/NPS
  modeling, agent workspace with collision detection, and reporting. Includes production SLA
  math. Use for ticketing, queues, SLAs, automations, and support analytics.
---

# Support / Helpdesk System — Full, Advanced

**The two things a helpdesk must get right are the ticket state machine and the SLA clock.**
Everything else (macros, KB, reporting) is value-add. The SLA clock is where teams ship bugs: a
real SLA is measured in **business hours**, **pauses while you wait on the customer**, and
**escalates on breach** — a naïve `created_at + 4h` is wrong by an entire weekend and will make you
miss contractual targets. Treat the ticket as a **state machine with an auditable event log**, not a
row you mutate and forget.

---

## 1. When to use / when NOT

**Use** when support volume outgrows a shared mailbox: you need SLAs, routing, history, internal
notes, reporting, and self-service deflection across channels.

**Do NOT** rebuild this if an off-the-shelf tool (Zendesk/Intercom/Front/HelpScout/Plain) fits and
support isn't your product — integrate instead. Build when you need deep product embedding, data
ownership, custom SLA/CSAT logic, or marketplace/multi-tenant support at a scale where seat pricing
hurts. For the conversation *transport* see `realtime-chat-messaging`; for the AI triage/handoff
layer see `omnichannel-inbox-chatbot`; for channel adapters see `whatsapp-/email-/voice-sms-`.

---

## 2. Architecture

```
Channels ─► intake adapters ─► Ticket (state machine + event log)
 email/chat/WA/voice/web/social      │
                                     ├─ SLA engine (business-hours clock, pause/resume, breach jobs)
                                     ├─ Routing (round-robin / load / skills / queues)
                                     ├─ Automations (triggers: event→conditions→actions)
                                     ├─ KB + deflection (suggested articles, agent + customer)
                                     └─ CSAT/CES/NPS + reporting (warehouse)
Agent workspace: ticket + customer-360 + collision detection + macros + KB suggestions
```

- **Append-only event log** (`ticket_events`) is the source of truth; current ticket state is a
  projection. This makes SLA recompute, audit, and "who changed what" trivially correct.

---

## 3. Decision matrices

**Routing strategy**

| Strategy | Balances on | Use when |
|----------|-------------|----------|
| **Round-robin** | count | Small homogeneous teams; simple fairness |
| **Load-based** ⭐ | open/active ticket count per agent | Most teams — avoids dumping on whoever's idle-in-name-only |
| **Skills-based** | tags/skills × language × tier | Specialized queues (billing vs technical), multilingual (Arabic desk) |
| **Omnichannel "serial"** | one live convo at a time, async backfill | Chat/voice realtime + email async mix |

**SLA target type**

| Target | Clock starts | Clock pauses | Stops at |
|--------|-------------|--------------|----------|
| **First Response** | ticket created / reopened | (usually not) | first public agent reply |
| **Next Response** | each customer reply | n/a | next agent reply (per reply) |
| **Resolution** ⭐ | created | while `pending`/`on_hold` (waiting on customer) | solved |
| **Periodic update** | last agent update | n/a | each required update interval |

**Build vs buy**

| Option | Best for |
|--------|----------|
| **Zendesk / Intercom / Front / Plain** | Standard support, fast, integrate via API/webhooks |
| **Build** ⭐ (this guide) | Product-embedded support, custom SLA/CSAT, multi-tenant marketplace, data residency |

---

## 4. Production code

### 4a. Ticket state machine (guarded transitions + event log)

```ts
// ticketState.ts — transitions are explicit and audited. No "just set status = x" anywhere else.
type Status = "new" | "open" | "pending" | "on_hold" | "solved" | "closed";

const ALLOWED: Record<Status, Status[]> = {
  new:     ["open", "pending", "on_hold", "solved"],
  open:    ["pending", "on_hold", "solved"],
  pending: ["open", "solved", "on_hold"],          // customer replied → back to open
  on_hold: ["open", "pending", "solved"],
  solved:  ["open", "closed"],                      // reopen window, then auto-close
  closed:  ["open"],                                // reopen creates a NEW sla cycle
};

export async function transition(ticketId: string, to: Status, actor: string, reason?: string) {
  const t = await db.getTicket(ticketId);
  if (!ALLOWED[t.status as Status].includes(to))
    throw new Error(`Illegal transition ${t.status} → ${to}`);

  await db.tx(async (q) => {
    await q.appendEvent(ticketId, { kind: "status_changed", from: t.status, to, actor, reason });
    await q.updateTicket(ticketId, { status: to });
    // SLA side effects are driven by the transition, in the same tx (see 4b).
    if (to === "pending" || to === "on_hold") await q.pauseSla(ticketId, "waiting_on_customer");
    if (to === "open" && (t.status === "pending" || t.status === "on_hold")) await q.resumeSla(ticketId);
    if (to === "solved") await q.stopSla(ticketId), await q.scheduleAutoClose(ticketId, hours(72));
  });
}
```

### 4b. SLA engine — business-hours clock with pause/resume (the hard part, done right)

```ts
// sla.ts — compute an SLA deadline by ADDING target minutes across a business calendar,
// skipping nights, weekends, holidays, and any paused (waiting-on-customer) intervals.
type Interval = { start: Date; end: Date };
type Schedule = {                              // per business-hours calendar (supports a TZ)
  tz: string;
  // minutes-from-midnight ranges per weekday (0=Sun..6=Sat), local to tz
  hours: Record<number, { open: number; close: number }[]>;
  holidays: Set<string>;                       // 'YYYY-MM-DD' in tz
};

/** Sum business minutes between two instants, excluding paused intervals. */
function businessMinutesBetween(from: Date, to: Date, s: Schedule, paused: Interval[]): number {
  let total = 0;
  for (const win of businessWindows(from, to, s)) {
    let segs: Interval[] = [win];
    for (const p of paused) segs = segs.flatMap((seg) => subtract(seg, p)); // remove paused overlap
    for (const seg of segs) total += (seg.end.getTime() - seg.start.getTime()) / 60000;
  }
  return total;
}

/** Find the instant at which `targetMinutes` of business time will have elapsed after `start`. */
export function slaDeadline(start: Date, targetMinutes: number, s: Schedule, paused: Interval[]): Date {
  let remaining = targetMinutes;
  // Walk forward business window by business window, subtracting paused time, until budget is spent.
  for (const win of businessWindowsFrom(start, s)) {        // lazy generator, day by day
    let segs: Interval[] = [win];
    for (const p of paused) segs = segs.flatMap((seg) => subtract(seg, p));
    for (const seg of segs) {
      const mins = (seg.end.getTime() - seg.start.getTime()) / 60000;
      if (mins >= remaining) return new Date(seg.start.getTime() + remaining * 60000); // breach moment
      remaining -= mins;
    }
  }
  throw new Error("schedule exhausted"); // generator should be effectively infinite
}

// On pause: persist the open paused interval. On resume: close it and RECOMPUTE due_at.
export async function pauseSla(ticketId: string, reason: string) {
  await db.openPause(ticketId, { start: new Date(), reason });
}
export async function resumeSla(ticketId: string) {
  await db.closePause(ticketId, new Date());
  const t = await db.getTicket(ticketId);
  const due = slaDeadline(t.sla_start, t.policy.resolution_minutes, t.schedule, await db.pauses(ticketId));
  await db.updateTicket(ticketId, { due_at: due });
  await scheduleBreachJob(ticketId, due);                   // delayed job; cancel on solve
}
```

> Why a generator over business windows + interval subtraction? Because **breach time isn't
> `start + target`** — it's "the wall-clock instant by which `target` *business* minutes elapse,
> minus any time the ball was in the customer's court." Recompute `due_at` on every pause/resume and
> on schedule/holiday changes. Drive breach via a **delayed job** (BullMQ/SQS-delay), cancelled when
> the ticket solves — don't poll every ticket every minute.

### 4c. Load-based + skills routing

```ts
// routing.ts — pick the eligible agent with the least open load. Atomic claim avoids double-assign.
export async function assign(ticket: { id: string; skills: string[]; language: string; tier: string }) {
  const eligible = await db.agents({                       // online + has required skills + language
    online: true, skills: ticket.skills, language: ticket.language, group: tier2group(ticket.tier),
  });
  if (!eligible.length) return enqueue(ticket.id, "unassigned");   // overflow queue + alert

  const withLoad = await db.openLoadFor(eligible.map((a) => a.id)); // {agentId: openCount}
  const best = eligible.sort((a, b) => (withLoad[a.id] ?? 0) - (withLoad[b.id] ?? 0))[0];

  // Atomic: only assign if still unassigned (prevents two routers grabbing the same ticket).
  const ok = await db.claim(ticket.id, best.id);
  return ok ? best.id : assign(ticket);                    // lost the race → retry
}
```

### 4d. CSAT / CES / NPS modeling

```ts
// survey.ts — send after solve; store raw + normalized; attribute to agent/team/channel.
type SurveyKind = "csat" | "ces" | "nps";
// CSAT: 1–5 (or thumbs) → satisfied = score >= 4.  CES: 1–7 "how easy".  NPS: 0–10.
export const csatScore = (responses: { score: number }[]) => {
  const satisfied = responses.filter((r) => r.score >= 4).length;
  return responses.length ? Math.round((satisfied / responses.length) * 100) : null; // % satisfied
};
export const nps = (responses: { score: number }[]) => {
  const promoters = responses.filter((r) => r.score >= 9).length;
  const detractors = responses.filter((r) => r.score <= 6).length;
  return responses.length ? Math.round(((promoters - detractors) / responses.length) * 100) : null; // -100..100
};
```

---

## 5. Edge cases

- **Reopen after solve/close** must start a **new SLA cycle**, not resurrect a breached one — and log
  it as a distinct event for reporting (reopen rate is a quality KPI).
- **Customer replies while `pending`** → auto-flip to `open` and **resume** the clock; agent reply
  while `open` doesn't pause it.
- **Multiple paused intervals** (ping-pong of pending/open) must all be subtracted — store an array,
  not a single `paused_at`.
- **Timezone & DST:** business hours are local to the *schedule's* tz; compute in tz, store UTC.
  A 09:00–17:00 Riyadh schedule and a London customer must agree on the same breach instant.
- **Holidays / one-off closures:** holiday set + ad-hoc overrides; recompute affected open tickets.
- **Merge/split/link:** merging tickets must reconcile SLA (keep the *earliest* due), dedupe events,
  and redirect future replies; splitting clones context but starts fresh SLA.
- **Collision:** two agents replying simultaneously → show "Agent X is replying" + soft-lock; never
  leak an **internal note** as a public reply (separate types, separate UI affordances, confirm).

---

## 6. Performance

- **Don't poll for breaches** — schedule one delayed job per active SLA target; cancel on solve.
- **Projections/materialized views** for queue counts and agent load (don't `COUNT(*)` the tickets
  table on every routing decision under load).
- Keyset pagination on ticket lists/views; index on `(status, group_id, due_at)`.
- Push KB search behind a vector/full-text index; cache top deflection articles.
- Stream reporting to a warehouse (BigQuery/ClickHouse); never run analytics on the OLTP DB.

---

## 7. Security & privacy

- **RBAC**: agent vs lead vs admin; restrict cross-group ticket visibility; field-level perms for
  PII/payment data.
- **Internal notes are never customer-visible** — enforce at the API layer, not just the UI.
- **PII/PCI:** redact card/secret patterns from ticket bodies on intake; encrypt attachments;
  retention + right-to-erasure (GDPR/CCPA) jobs that purge linked customer data.
- **Audit log** every status/assignment/visibility change (the event log gives you this for free).
- **Multi-tenant:** every query scoped by `tenant_id`; row-level security so one org never sees another's tickets.

---

## 8. Scale & reliability

- **Event-sourced ticket**: append-only `ticket_events` → rebuild state, recompute SLA, audit.
- **Idempotent intake:** dedupe inbound by channel message id so a webhook retry doesn't create
  duplicate tickets (one ticket per `(channel, external_thread_id)`).
- **Atomic assignment** (conditional claim) prevents double-routing across workers.
- **Outbox pattern** for side effects (notify customer, fire webhook) so they're transactional with
  the state change and retried on failure.
- Schedule/holiday changes trigger a **bounded recompute** of open tickets' `due_at`.

---

## 9. Testing

- **SLA math is the #1 thing to unit-test:** Friday-17:00 + 4h business hours = Monday-12:00 (not
  Friday-21:00); a 2-day pending pause pushes the deadline by exactly the business minutes paused;
  DST spring-forward day doesn't drop/gain an hour.
- **State machine:** every illegal transition throws; every legal one logs an event + correct SLA side effect.
- **Routing:** load-based picks least-loaded; atomic claim prevents double-assign under concurrency.
- **Intake idempotency:** same inbound message twice → one ticket.
- **CSAT/NPS:** boundary scores (4 vs 3, 9 vs 6) classify correctly.

---

## 10. Observability

- **SLA:** first-response time, resolution time, **% within SLA** (per priority/team/channel),
  breach count, time-to-breach distribution.
- **Volume/flow:** created vs solved (backlog trend), reopen rate, ticket age histogram.
- **Quality:** CSAT %, CES, NPS, QA/IQS scorecard sample.
- **Agent:** handle time, replies-to-resolve, concurrent load, occupancy.
- **Deflection:** KB views → ticket-avoided rate; bot containment (from `omnichannel-inbox-chatbot`).

---

## 11. i18n / RTL (Arabic) & templates

- **Localized macros/canned replies & KB articles** keyed by locale; route Arabic tickets to an
  Arabic-skilled queue (skills routing). Agent workspace must render replies `dir="auto"`.
- **Help center** fully mirrored RTL (logical CSS properties), with `hreflang` per locale and
  per-locale article status (don't show an untranslated `en` article to `ar` users — fall back explicitly).
- **CSAT survey copy** localized; store the response locale for segmentation.
- **Business hours per region** (e.g. Sun–Thu work week in parts of MENA) — the schedule model must
  support arbitrary weekday patterns, not assume Mon–Fri.

---

## 12. Anti-patterns

- **Shared email inbox as "support"** — no SLA, routing, history, or reporting; it doesn't scale.
- **SLA = `created_at + N hours`** ignoring business hours and pause-on-pending → contractual breaches.
- **Polling all tickets for breaches** instead of scheduled jobs → wasteful and laggy.
- **Mutating `status` directly** everywhere instead of one guarded, audited transition.
- **No internal-note/public-reply separation** → leaked notes, double replies.
- **Channels siloed** into separate tools → fragmented customer history (unify per `omnichannel-inbox-chatbot`).
- **No KB / deflection** → agents retype the same answer 500 times.
- **Analytics on the OLTP DB** → support app slows under reporting load.

## 13. Agent checklist

```
- [ ] Ticket = state machine + append-only event log; guarded transitions only
- [ ] Omnichannel intake adapters; idempotent (one ticket per channel thread)
- [ ] SLA engine: business-hours calendar (per region/TZ), pause-on-pending, recompute due_at, breach jobs
- [ ] Routing: load-based/skills + atomic claim; overflow queue + alerts
- [ ] Macros, triggers/automations (event→conditions→actions), saved views
- [ ] KB + suggested articles (agent + customer) for deflection
- [ ] CSAT/CES/NPS post-resolution; attributed to agent/team/channel/locale
- [ ] RBAC + internal-note enforcement at API; PII redaction/retention; tenant scoping
- [ ] Reporting to warehouse; SLA %, reopen rate, CSAT, backlog dashboards
- [ ] Arabic: localized macros/KB, RTL workspace, region work-week schedules
```

## 14. References (2026)
- Zendesk SLA policies: https://support.zendesk.com/hc/en-us/articles/4408821949314
- Intercom SLAs: https://www.intercom.com/help/en/articles/4533920-set-up-and-use-slas
- Plain (modern API-first helpdesk) docs: https://www.plain.com/docs
- CSAT/CES/NPS methodology: https://www.qualtrics.com/experience-management/customer/customer-satisfaction/
- BullMQ delayed jobs (breach scheduling): https://docs.bullmq.io/guide/jobs/delayed

## 15. Related
`omnichannel-inbox-chatbot`, `realtime-chat-messaging`, `email-integration-advanced`,
`whatsapp-business-integration`, `voice-sms-telephony` · `business-master` (crm-builder for customer-360),
`ui-master` (charts-and-dashboards for reporting).
