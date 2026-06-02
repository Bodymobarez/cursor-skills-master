---
name: booking-orchestration
description: >-
  Orchestrate the travel booking saga at staff/principal depth — the reliable, idempotent, compensable
  flow that turns a chosen offer into a confirmed PNR/voucher with money moved correctly. Ships a booking
  state machine, an idempotency-key store (exactly-once book), a saga runner with compensation, the
  mandatory recheck gate, payment↔supplier money-movement ordering, the "never retry book — reconcile via
  retrieve" rule, ticketing time-limit/on-request handling, a mid-office queue for stuck bookings, and
  reconciliation. Use whenever a booking spans supplier + payment + your DB (it always does).
---

# Booking Orchestration (the booking saga)

**Mandate: a booking is a distributed saga, not a database transaction — design for partial failure, make
every step idempotent, and never leave money and reservations out of sync.** Steps span your DB, a supplier,
and a payment provider with no shared commit. A naïve `await book(); await charge()` will eventually charge a
customer with no reservation, or create a reservation you never charged for. This skill is the connective
tissue the architecture promised.

## When to use this skill
- Any flow that creates a real booking — it inherently spans supplier + payment + your DB.
- Designing idempotency, retries, compensation, on-request/ticketing lifecycles, or fixing duplicate bookings
  / stuck reservations / orphaned charges.
- **Not** the supplier wire format (`supplier-api-integration`) or the pricing/credit UI
  (`b2b-b2c-booking-platform`) — this owns the *coordination* between them.

## DECISION MATRIX — the orchestration choices

| Decision | Option A | Option B | Default |
|----------|----------|----------|---------|
| **Coordination** | **Orchestration** (central saga owns steps) | Choreography (events only) | **Orchestration** — booking needs a clear owner, timeouts, and compensation order |
| **Money order** | **Book-first**, then capture customer | Capture-first, then book | **Book-first** for instant-confirm suppliers; **auth→confirm→capture** when you must hold funds early |
| **Inventory** | Instant confirm | **Hold/Resume** (e.g. EAN hold, GDS time limit) | Use hold for packaging/multi-item; capture on resume within the window |
| **On book timeout** | Auto-retry book | **Reconcile via `retrieve()`** + idempotency key | **Never auto-retry book**; resolve the unknown outcome |
| **Confirm latency** | Synchronous | **Async** (on-request, ticketing queue) | Model `ON_REQUEST`/`TICKETING` as real states, not failures |

## The booking state machine

```
QUOTED ─recheck─► RECHECKED ─reserve─► PENDING ─supplier ok─► CONFIRMED ─issue─► TICKETED / VOUCHERED
   │                  │                   │                       │
   │                  │ price drift       │ supplier on-request   │ pay fail → compensate (cancel supplier)
   │                  ▼                   ▼                       ▼
   └──────────────► REPRICE         ON_REQUEST ──confirm/expire──► CONFIRMED / FAILED
                                         │
                          FAILED ◄───────┴─ timeout/unknown ─► RECONCILE (retrieve → CONFIRMED|FAILED)
```

`CONFIRMED` means "supplier reference exists." `TICKETED`/`VOUCHERED` means "documents issued + money settled."
Don't collapse them — the gap between them is where ticketing time limits and capture live.

## Idempotency store (exactly-once book)

One client-generated key per booking attempt. The store guarantees a given key books **once**, even across
retries, double-clicks, and network timeouts.

```ts
interface IdempotencyRecord { key: string; status: "in_flight" | "done"; response?: unknown; createdAt: string; }

async function withIdempotency<T>(key: string, fn: () => Promise<T>): Promise<T> {
  // Atomic insert-if-absent. If the key exists & done → return stored response (no second supplier call).
  const inserted = await store.insertIfAbsent({ key, status: "in_flight", createdAt: now() });
  if (!inserted) {
    const rec = await store.get(key);
    if (rec.status === "done") return rec.response as T;            // replay: identical result, no double-book
    throw new BookingInFlight(key);                                  // concurrent attempt — caller backs off
  }
  const res = await fn();
  await store.complete(key, res);                                    // persist response under the key
  return res;
}
```

## Saga runner with compensation

Each step has a forward action and a compensation. On failure, run compensations in reverse for completed
steps. Persist saga state after every step so a crash resumes, not restarts.

```ts
interface SagaStep<C> { name: string; run: (c: C) => Promise<void>; compensate: (c: C) => Promise<void>; }

async function runSaga<C extends { id: string }>(ctx: C, steps: SagaStep<C>[]) {
  const done: SagaStep<C>[] = [];
  try {
    for (const s of steps) {
      await persistSagaState(ctx.id, s.name, "running");
      await s.run(ctx);
      await persistSagaState(ctx.id, s.name, "done");
      done.push(s);
    }
  } catch (err) {
    for (const s of done.reverse()) {
      try { await s.compensate(ctx); }
      catch (e) { await deadLetter(ctx.id, s.name, e); }            // compensation failed → mid-office, not silent
    }
    throw err;
  }
}
```

```ts
// A hotel booking as a saga: recheck → hold credit/auth → supplier book → capture → issue voucher.
const hotelBookingSaga: SagaStep<BookingCtx>[] = [
  { name: "recheck",
    run: async (c) => { c.rate = await adapter.recheck(c.rateKey, c.signal);
                        if (priceDrift(c.rate, c.quotedSell)) throw new PriceChanged(c.rate); },
    compensate: async () => {} },                                   // read-only, nothing to undo
  { name: "reserve-funds",
    run: async (c) => { c.fundsRef = await holdFunds(c); },         // B2B credit hold OR card auth
    compensate: async (c) => { await releaseFunds(c.fundsRef); } },
  { name: "supplier-book",
    run: async (c) => { c.supplierRef = (await withIdempotency(c.idempotencyKey,
                        () => adapter.book(c.bookRequest))).supplierRef; },
    compensate: async (c) => { if (c.supplierRef) await adapter.cancel(c.supplierRef); } },
  { name: "capture",
    run: async (c) => { await captureFunds(c.fundsRef); },          // capture only AFTER supplierRef exists
    compensate: async (c) => { await refund(c.fundsRef); } },
  { name: "issue-docs",
    run: async (c) => { await issueVoucher(c); },
    compensate: async () => {} },                                   // doc issuance is safe to re-run
];
```

## The book-timeout rule (the single most important reliability decision)

A timeout/5xx on `book()` is an **unknown outcome**, not a failure — the supplier may have created the
reservation. **Never auto-retry `book()`.** Instead:

```ts
async function resolveUnknownBook(c: BookingCtx) {
  // Same idempotency key first; if the supplier honors it, you get the original result back.
  // Otherwise reconcile by retrieving with your clientRef.
  const found = await adapter.retrieve(c.clientRef).catch(() => null);
  if (found?.status === "CONFIRMED") return promote(c, found.supplierRef);   // it succeeded after all
  await markFailed(c, "supplier_unknown_then_absent");                       // safe to fail; no orphan
  await enqueueMidOffice(c, "verify_no_orphan_reservation");                 // human/automated double-check
}
```

## PNR / voucher lifecycle & time limits
- **Air (GDS/NDC):** `book` creates a PNR/Order that must be **paid/ticketed within the ticketing time limit**
  (Amadeus/Sabre ≈ 24h, sometimes negotiable). Persist `lastTicketingDate`; queue auto-ticket or auto-cancel.
- **Hotel (bed bank):** `CONFIRMED` yields a voucher; **on-request** rates pend supplier confirmation — hold
  funds, don't capture, auto-expire if unconfirmed by SLA.
- **Hold/Resume (e.g. Expedia Rapid):** booking is held with no charge; you **resume** (capture+commit) within
  the hold window — ideal for packaging multiple items before charging once.

## Mid-office queue (where stuck bookings go to be resolved, not lost)
- Every non-terminal/abnormal state lands in a durable queue with an owner + SLA: `PENDING` too long,
  `ON_REQUEST` awaiting supplier, failed compensation (dead-letter), ticketing deadline approaching,
  reconcile-needed.
- Operators (and automated jobs) can retry issuance, cancel orphans, re-attempt capture, or refund — every
  action audited.

## Reconciliation (close the money loop)
- Daily: match `supplierRef` ↔ supplier statement ↔ your captures/refunds ↔ net-vs-sell margin.
- Detect **orphans** (supplier reservation with no charge) and **phantoms** (charge with no supplier ref) —
  both are saga bugs and both are alertable.

## Edge cases
- **Double-click / client retry:** same idempotency key → one booking, stored response replayed.
- **Compensation fails** (cancel API down): dead-letter to mid-office; never swallow — an un-cancelled hold
  costs real money.
- **Partial multi-item cart:** per-item sagas with a parent; compensate succeeded items per policy; surface a
  clear partial state to the user.
- **Price drift at recheck:** stop the saga, re-consent (and for B2B re-validate the credit hold) before funds.
- **Crash mid-saga:** persisted step state lets a worker resume from the last completed step idempotently.

## Performance / scale
- Sagas are I/O-bound and long-lived — run them on a durable queue/worker (or a workflow engine like Temporal),
  not in the request thread. Bound concurrency per supplier (shares the look-to-book/rate budget).

## Security
- Idempotency keys and saga payloads may reference PII/payment tokens — encrypt at rest, mask in logs, never
  store raw PANs (PSP tokens only). Audit every compensation and mid-office action.

## Testing
- Inject failure at every step + every compensation; assert no orphan reservation and no orphan charge in any
  ordering. Simulate book-timeout-then-success (the killer case) and verify reconcile promotes it.
- Property-test idempotency: N concurrent calls with one key ⇒ exactly one supplier book.

## Observability
- **Look-to-book** and full booking-funnel conversion; per-step success/latency; compensation rate; dead-letter
  depth; on-request confirm rate; ticketing-deadline misses; reconciliation orphan/phantom counts. Alert on
  rising compensation or dead-letter rates — they precede revenue loss.

## i18n / multi-currency
- Carry the FX rate/timestamp from quote through capture so settle (net currency) and charge (sell currency)
  reconcile. Localize confirmation docs/notifications (RTL where needed — pair `documents-master`/`ui-master`).

## Anti-patterns
- Treating a booking as one DB transaction → charged customers with no reservation (or the reverse).
- Auto-retrying `book()` on timeout → duplicate PNRs/reservations.
- Capturing payment before a confirmed `supplierRef` (or skipping recheck before charge).
- Swallowing compensation failures → silent orphaned holds/reservations.
- Running sagas in the request thread → lost on deploy/crash, no resume.
- No reconciliation → orphans/phantoms accumulate invisibly.

## Checklist
```
- [ ] Booking state machine with explicit CONFIRMED vs TICKETED/VOUCHERED
- [ ] Idempotency-key store guaranteeing exactly-once book
- [ ] Saga runner with per-step compensation + persisted state (crash-resumable)
- [ ] Mandatory recheck gate before reserving funds; re-consent on price drift
- [ ] Money order: supplierRef exists BEFORE capture; auth/hold else compensate
- [ ] NEVER auto-retry book(); reconcile unknown outcomes via retrieve()
- [ ] Ticketing time limits + on-request/hold lifecycles modeled and queued
- [ ] Mid-office dead-letter queue + daily reconciliation (orphans/phantoms)
- [ ] Saga observability: funnel, compensation rate, dead-letter, reconcile gaps
```

## References (2026-current)
- Saga pattern (microservices.io): https://microservices.io/patterns/data/saga.html
- Temporal (durable workflow engine, common for booking sagas): https://docs.temporal.io
- Amadeus Flight Create Orders (PNR + 24h ticketing): https://developers.amadeus.com/self-service
- Expedia Rapid Hold & Resume: https://developers.expediagroup.com/rapid/lodging/booking/hold-resume

## Related
`supplier-api-integration`, `b2b-b2c-booking-platform`, `travel-tech-architecture`;
pairs with `payments-master` (capture/refund/VCC), `backend-api-master` (queues/workflows), `devops-master`.
