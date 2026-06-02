---
name: cart-checkout-orders
description: >-
  Build multi-vendor cart, idempotent split-checkout, and order lifecycle at staff
  depth — the one-cart→many-sub-orders saga with compensations, idempotency keys +
  transactional outbox, atomic inventory commit, per-sub-order state-machine FSMs
  (product + food), partial fulfillment, returns/RMA, and refunds with proportional
  payout clawback. The orchestration core where money, inventory, and fulfillment meet.
---

# Cart, Checkout & Orders — The Split Saga

**Checkout is the most dangerous code in a marketplace.** It moves money, decrements inventory, and
spawns N independent fulfillment obligations — all across services that fail and retry. The buyer
fills *one* cart from *many* sellers, pays *once*, and the order **splits into per-seller sub-orders**
that live and die independently. The two rules that keep this correct: **idempotency** (a retry must
never double-charge or double-create) and **compensation** (every step that can fail has a defined
undo). Everything else is detail.

---

## 1. Mandate

- **One cart → one payment → many sub-orders.** The sub-order is the unit of fulfillment, refund, and payout. The buyer-facing `Order` exists only to tie the payment together.
- **Checkout is an idempotent saga.** Client supplies an idempotency key; the same key returns the same result; partial failures compensate (release stock, void/refund).
- **Reserve inventory atomically at order creation, commit at fulfillment, release on timeout.** Cart ≠ reservation; cart ≠ price quote.
- **State is an enforced FSM**, not a free-text column. Every transition is validated and audit-logged.

## 2. When to use / when NOT

**Use when:** building the cart, checkout, order splitting, lifecycle/FSM, returns/RMA, cancellations, refunds, tracking. **Pairs tightly with** `marketplace-payments-payouts` (it executes the charge/transfers; this skill orchestrates) and `multi-vendor-catalog` (reservation).

**Skip the saga when:** single-seller cart with a single synchronous payment confirm — a plain DB transaction + webhook reconciliation is enough. Don't stand up Temporal for a one-seller checkout.

## 3. Cart — server-authoritative, grouped by seller

```sql
create table carts ( id uuid primary key, buyer_id uuid, currency char(3), updated_at timestamptz );
create table cart_items (
  cart_id   uuid references carts(id) on delete cascade,
  offer_id  uuid not null,                       -- resolves seller + variant
  seller_id uuid not null,                        -- denormalized for grouping
  qty       int not null check (qty > 0),
  modifiers jsonb default '[]',                   -- food add-ons
  added_at  timestamptz default now(),
  primary key (cart_id, offer_id, md5(modifiers::text))
);
```

- **Server-side cart** keyed by user (Redis for hot reads + Postgres for durability); merge guest cart on login.
- **Group by `seller_id`** in model and UI — each group becomes a sub-order and may have its own delivery method, fee, and minimum.
- **Re-validate at view + checkout:** live price, stock/availability, min-order (food), delivery zone, modifier min/max. **The cart is not a quote** — prices can move; lock them only at order creation.

## 4. The idempotent split-checkout saga

```ts
// One handler, fully idempotent. Returns existing result on replay of the same key.
export async function checkout(req: CheckoutReq, idemKey: string): Promise<Order> {
  // 0) Idempotency gate (see marketplace-architecture §8) — claim or replay.
  const prior = await idem.claim(idemKey, "checkout", hash(req));
  if (prior?.status === "done") return prior.response as Order;

  return await db.tx(async (tx) => {
    // 1) Re-price + validate every line against LIVE offers (anti-tamper: trust server prices only).
    const groups = await repriceBySeller(tx, req.cartId);          // throws on stale price/stock

    // 2) Reserve inventory ATOMICALLY per line; collect failures (best-effort vs all-or-nothing).
    const { ok, failed } = await reserveAll(tx, groups);           // §6 multi-vendor §3 atomic UPDATE
    if (failed.length && req.mode === "all_or_nothing") throw new PartialStockError(failed);

    // 3) Create Order + per-seller SubOrders + items in ONE transaction. Freeze prices/commission.
    const order = await insertOrder(tx, ok, groups);

    // 4) Write the "create payment" intent to the OUTBOX (don't call Stripe inside the DB txn).
    await tx.outbox.add("order", order.id, "OrderPlaced", { orderId: order.id, total: order.total });

    await idem.complete(idemKey, order);
    return order;                                                  // status = 'pending_payment'
  });
  // 5) PaymentIntent is created/confirmed by the OrderPlaced consumer; the payment webhook drives
  //    the order to 'paid' and emits SubOrderConfirmed → sellers notified. On failure → compensate.
}
```

**Why payment is *outside* the DB transaction:** you cannot hold a Postgres transaction open across a
multi-second network call to Stripe. Create the order as `pending_payment`, drive payment via the
outbox + webhook, and reconcile. The webhook is the only thing that flips an order to `paid`.

**Compensation table (every step has an undo):**

| Step | Failure | Compensation |
|------|---------|-------------|
| Reserve stock | insufficient | reject line (best-effort) or abort (all-or-nothing) → release prior holds |
| Create order | DB error | txn rollback (nothing persisted) |
| Payment | declined/3DS abandoned | release reservations, mark order `payment_failed`, notify buyer |
| Split/transfers | seller acct issue | capture stands; retry transfer; hold that sub-order's payout (see payments §6) |

## 5. Order model — the split

```sql
create table orders (
  id          uuid primary key default uuidv7(),
  buyer_id    uuid not null,
  currency    char(3) not null,
  items_total bigint not null, tax_total bigint not null, ship_total bigint not null,
  grand_total bigint not null,
  payment_intent_id text,
  status      text not null default 'pending_payment',
  created_at  timestamptz not null default now()
);
create table sub_orders (
  id          uuid primary key default uuidv7(),
  order_id    uuid not null references orders(id),
  seller_id   uuid not null references sellers(id),
  subtotal    bigint not null,
  commission  bigint not null,                    -- frozen at order time (seller-vendor-management §5)
  payout_net  bigint not null,
  fulfillment_type text not null check (fulfillment_type in ('ship','delivery','digital','service')),
  status      text not null default 'placed',
  version     int not null default 0
);
create table order_items (
  id uuid primary key default uuidv7(),
  sub_order_id uuid not null references sub_orders(id),
  offer_id uuid not null, variant_id uuid not null,
  qty int not null, unit_price bigint not null,    -- frozen price
  modifiers jsonb default '[]', tax bigint not null default 0
);
```

A buyer order can be **partly delivered, partly cancelled, partly refunded** — because each sub-order
owns its own lifecycle and money.

## 6. DECISION MATRIX — multi-seller checkout failure policy

| Policy | Behavior when one seller's stock fails | Use |
|--------|----------------------------------------|-----|
| **All-or-nothing** | Abort whole checkout, release everything | High-trust B2B, bundles, "complete the look" |
| **Best-effort (recommended for retail)** ⭐ | Drop the failed seller's items, proceed with the rest, tell the buyer | General marketplaces — maximizes conversion |
| **Hold & notify** | Place order, mark failed lines `awaiting_restock` | Pre-order/backorder flows |

Default to **best-effort** for consumer retail; never silently drop items — surface exactly what was
removed and why.

## 7. Order lifecycle — enforced FSM (per sub-order)

```
PRODUCT: placed → confirmed → packed → shipped → out_for_delivery → delivered → completed
              ↘ cancelled              ↘ return_requested → returned → refunded
FOOD:    placed → accepted → preparing → ready → picked_up → delivered → completed
              ↘ rejected (auto-refund)            ↘ cancelled
```

```ts
const TRANSITIONS: Record<string, string[]> = {
  placed: ["confirmed", "cancelled", "rejected"],
  confirmed: ["packed", "preparing", "cancelled"],
  packed: ["shipped"], shipped: ["out_for_delivery", "delivered"],
  out_for_delivery: ["delivered"], delivered: ["completed", "return_requested"],
  return_requested: ["returned", "delivered"], returned: ["refunded"],
  // terminal: completed, cancelled, rejected, refunded
};
export function transition(curr: string, next: string): void {
  if (!(TRANSITIONS[curr] ?? []).includes(next))
    throw new IllegalTransition(`${curr} → ${next}`);
  // caller persists with optimistic version check + appends an audit row (who/when/reason)
}
```

- **Vendor accept/reject window** (food): auto-cancel + auto-refund on timeout (a timer/workflow, not a cron guess).
- **Audit every transition** (`order_events`: sub_order_id, from, to, actor, reason, at) — this *is* your tracking timeline and your dispute evidence.

## 8. Returns / RMA, cancellations, partial refunds

```
return_requested (reason, items, photos) → seller/admin review → approve/deny
   → return label / pickup → inspect → refund (full | partial) → payout clawback
```

- **Cancellation rules by state:** free before `shipped`/`accepted`; penalty/blocked after (configurable per category).
- **Partial refund math:** refund only the affected `order_items` (+ proportional tax/shipping per policy); the refund triggers a **proportional transfer reversal + commission clawback** on *that seller's* sub-order only (see `marketplace-payments-payouts` §8). Never refund the buyer without clawing back the seller.
- **RMA is its own mini-FSM** with SLA timers; link disputes to `reviews-ratings-trust-safety`.

## 9. Edge cases

- **Payment succeeds, split/transfer fails** → money is captured (don't refund the buyer); retry the transfer, hold that seller's payout, alert ops. The capture and the transfer are decoupled (payments §3).
- **Webhook arrives before the order row is committed** (race) → idempotent webhook handler that can create-or-update; key off the PaymentIntent id.
- **Duplicate submit / network retry** → idempotency key returns the first result; no second order.
- **Stock vanishes between reserve and capture** → reservation already holds it; if reservation expired (slow payment), re-reserve or fail gracefully.
- **Buyer cancels while courier en route** (food) → cancellation fee + courier compensation; sub-order → `cancelled`, partial charge.
- **Partial delivery** → sub-order A `delivered`, B `cancelled` → order shows mixed status; payout/refund per sub-order.
- **Coupon re-validation** → re-check promotion validity + budget at checkout (promo can expire between cart and pay — see `marketplace-promotions-pricing`).

## 10. Performance & scale

- **Cart** in Redis (hot) with Postgres durability; cap line items; debounce re-pricing.
- **Checkout throughput:** keep DB transactions short (no external calls inside); offload payment + notifications to the outbox/queue. Target checkout p99 < a few hundred ms for the synchronous part.
- **Inventory contention** (flash sale on one SKU) → Redis atomic counter as the admission gate, Postgres as durable truth; queue excess.
- **Idempotency + outbox** tables get hot — partition/prune the outbox after publish; index idempotency keys.

## 11. Security

- **Server-authoritative pricing:** never trust client-sent prices/totals; recompute from offers + promotions. Price tampering is a top exploit.
- **IDOR:** authorize every order/sub-order read+mutation by buyer (own orders) / seller (own sub-orders, via RLS) / admin. Treat cross-tenant order access as Sev-1.
- **Idempotency-key abuse:** bind the key to a request hash to reject key reuse with a different body.
- **Refund authorization:** only seller/admin can approve; rate-limit and audit (refund fraud).

## 12. Observability

- **Checkout funnel:** cart → checkout start → reserve ok → payment ok → split ok (drop-off per step).
- **Stuck orders:** count per state with age; alert on sub-orders stuck in `placed`/`confirmed` past SLA (a stuck checkout = lost GMV + a furious buyer).
- **Money safety:** payment-succeeded-but-not-split count (must trend 0), reservation leak rate, duplicate-order rate.
- **Saga health:** compensation rate, retry counts, outbox lag.

## 13. i18n / RTL (MENA)

- **Order currency is fixed at creation**; show buyer-locale formatting (ICU), store minor units. Multi-currency carts (rare) → split by currency or settle in one.
- **Tax lines on the order** drive e-invoice generation (VAT 5% UAE/Saudi 15%, Egypt) — the order is the source for the ZATCA/Peppol/ETA invoice (`marketplace-architecture` §14). Capture buyer + seller tax IDs where required for B2B.
- **COD (cash on delivery)** is still huge in MENA — model it as a payment method with reconciliation-on-delivery and courier cash handling (`delivery-logistics-dispatch`).
- RTL checkout + Arabic order/status emails (`ui-master`).

## 14. Anti-patterns

- **One flat order, no sub-orders** → can't fulfill/refund/pay out per seller. The cardinal sin.
- **Non-idempotent checkout** → duplicate orders/charges on retry.
- **Calling Stripe inside the DB transaction** → long-held locks, connection exhaustion; use the outbox.
- **Trusting client-submitted prices/totals** → revenue leak via tampering.
- **Free-text status** instead of an enforced FSM → illegal states, untrackable orders.
- **Reserving stock at add-to-cart** / not releasing on abandonment → phantom out-of-stock.
- **Refunding the buyer without clawing back the seller payout** → you eat the loss.
- **No timeout on vendor accept (food)** → orders rot in `placed`.

## 15. Agent checklist

```
- [ ] Server cart grouped by seller; re-validate price/stock/min-order/zone at checkout
- [ ] Idempotent checkout (client key + request-hash) returning same result on replay
- [ ] Atomic reservation; best-effort vs all-or-nothing policy chosen
- [ ] Order + per-seller SubOrders + items in one txn; prices + commission frozen
- [ ] Payment created via OUTBOX/webhook, NOT inside the DB transaction
- [ ] Per-sub-order FSM with validated transitions + full audit (= tracking + dispute evidence)
- [ ] Vendor accept/reject timeout → auto-cancel + refund (food)
- [ ] Returns/RMA mini-FSM; partial refunds → proportional transfer reversal + commission clawback
- [ ] Checkout funnel + stuck-order + payment-not-split metrics
- [ ] MENA: fixed order currency, tax lines → e-invoice, COD support, RTL
```

## References (verify current — 2026)
- Stripe PaymentIntents + idempotency: https://docs.stripe.com/api/idempotent_requests
- Saga pattern: https://microservices.io/patterns/data/saga.html
- Temporal order-management sample: https://docs.temporal.io/develop
- State machines (XState, if modeling client-side too): https://stately.ai/docs

## Related
`marketplace-payments-payouts` (charge/transfer/refund execution), `multi-vendor-catalog` (reservation), `delivery-logistics-dispatch` (fulfillment), `marketplace-promotions-pricing` (coupon re-validation), `marketplace-architecture` (saga, outbox, idempotency)
