---
name: marketplace-payments-payouts
description: >-
  Split one buyer payment to many sellers minus commission, compliantly, at staff
  depth — Stripe Connect 2026 (Accounts v2 / controller properties), separate charges
  & transfers vs destination charges, transfer_group + source_transaction, escrow via
  delayed transfers, refunds with proportional transfer reversals + commission clawback,
  a double-entry ledger as source of truth, negative balances, idempotent webhooks, and
  PCI/SCA. The hardest money problem in a marketplace — get it provably correct.
---

# Marketplace Payments & Payouts — Split, Escrow, Clawback, Ledger

**You are moving other people's money, so the bar is "provably correct," not "looks right."** Collect
*one* payment from the buyer, take your commission, route the rest to *N* sellers, hold it through the
refund window, and pay it out — while a refund or chargeback can hit *any single seller's* slice at
any time. Two non-negotiables: **a double-entry ledger you own is the source of truth** (Stripe is a
rail, not your books), and **every money call is idempotent**. If you can't reconcile the ledger to
Stripe to the penny every day, you don't have a payments system, you have a liability.

> For PSP-agnostic depth (Adyen, Mangopay, regional MENA gateways, PCI scope, 3DS/SCA), pair with
> **`payments-master`**. This skill is the *marketplace* flow-of-funds layer on top of it.

---

## 1. Mandate

- **Don't custody funds without a license.** Route money through a licensed provider (Stripe Connect / Adyen for Platforms / Mangopay). Sweeping buyer funds through your own bank account = unlicensed money transmission.
- **Your double-entry ledger is the source of truth**, not the PSP balance. Every cent is a balanced, append-only, idempotent posting you can re-derive.
- **Capture and transfer are decoupled.** Refunding a charge does **not** auto-reverse transfers — you reverse each seller's transfer explicitly.
- **Escrow by default for risky categories:** transfer to the seller only after delivery/return-window, not at capture.

## 2. When to use / when NOT

**Use when:** integrating split payments; choosing the Connect charge type; building commission/escrow/payouts; refunds + chargeback clawback; the ledger; payment webhooks. **Read with** `cart-checkout-orders` (orchestration) and `seller-vendor-management` (KYC/capabilities, seller balance).

**Skip when:** single-seller storefront → a normal PaymentIntent, no Connect. Sub-$X GMV with < ~20 sellers and manual reconciliation may defer Connect — but still keep the ledger.

## 3. DECISION MATRIX — Stripe Connect charge type

| Charge type | Funds flow | Merchant of record | Best for | Commission via |
|-------------|-----------|---------------------|----------|----------------|
| **Separate charges & transfers** ⭐ | Charge on **platform**; you create a `Transfer` per seller later | **Platform** | **Multi-seller carts** (the canonical marketplace case), escrow, delayed/split payout | You keep the remainder; `application_fee` not used — fee is implicit in transfer amounts |
| **Destination charge** | Charge on platform; funds auto-routed to **one** connected account | Platform (or seller via `on_behalf_of`) | **Single-seller** order, simple split | `application_fee_amount` (or `transfer_data[amount]` = net) |
| **Direct charge** | Charge created **on the connected account** | **Seller** | Seller "owns" the buyer relationship; seller bears fees/disputes | `application_fee_amount` on the charge |

**Principled default for a multi-vendor cart: separate charges & transfers.** One PaymentIntent for
the whole cart on the platform, then one `Transfer` per sub-order. The platform is **merchant of
record** (owns VAT, disputes, chargebacks — important for MENA e-invoicing) and you control timing
(escrow) and per-seller amounts cleanly. Destination charges shine for single-seller orders.

## 4. Account model (2026 — Accounts v2 / controller properties)

Stripe now recommends the **Accounts v2 API** and **controller properties** over the legacy
Standard/Express/Custom *types* (types remain as presets mapping to controller props). Pick by who
bears fees/losses and which dashboard the seller gets — `stripe_dashboard.type` is **immutable**.

| Preset | `losses.payments` | `fees.payer` | `requirement_collection` | `stripe_dashboard.type` | Feel |
|--------|-------------------|--------------|--------------------------|--------------------------|------|
| **Standard** | `stripe` | `account` | `stripe` | `full` | Seller is a full Stripe merchant; least platform liability |
| **Express** ⭐ | `application` | `application_express` | `stripe` | `express` | Platform-controlled, light seller dashboard — typical marketplace |
| **Custom** | `application` | `application_custom` | `application` | `none` | Fully white-label; you own the entire UX + all requirements |

```ts
// Express-equivalent via controller properties (platform pays fees + bears losses):
const account = await stripe.accounts.create({
  country: "AE",
  controller: {
    fees: { payer: "application" },
    losses: { payments: "application" },
    requirement_collection: "stripe",
    stripe_dashboard: { type: "express" },
  },
  capabilities: { card_payments: { requested: true }, transfers: { requested: true } },
});
// KYC/onboarding + capability gating → seller-vendor-management §4
```

## 5. Collect one payment + split to many sellers (separate charges & transfers)

```ts
// 1) ONE PaymentIntent for the whole cart, charged on the PLATFORM. transfer_group ties it together.
const intent = await stripe.paymentIntents.create(
  {
    amount: order.grandTotal,                 // minor units, all sellers + tax + shipping
    currency: order.currency,
    automatic_payment_methods: { enabled: true },
    transfer_group: order.id,                 // links charge ↔ future transfers (reconciliation)
    metadata: { order_id: order.id },
  },
  { idempotencyKey: `pi_${order.id}` },       // idempotent: retries never double-charge
);

// 2) After payment SUCCEEDS (webhook payment_intent.succeeded), create one Transfer per sub-order.
//    source_transaction = the charge → Stripe won't execute the transfer until funds are available,
//    and it won't fail if the platform balance is momentarily zero.
for (const so of order.subOrders) {
  await stripe.transfers.create(
    {
      amount: so.payoutNet,                   // subtotal − commission (your take stays on platform)
      currency: order.currency,
      destination: so.seller.connectedAccountId,
      transfer_group: order.id,
      source_transaction: intent.latest_charge as string,
      metadata: { sub_order_id: so.id },
    },
    { idempotencyKey: `tr_${so.id}` },        // one transfer per sub-order, ever
  );
}
```

- **Commission** = the amount you *don't* transfer. `Σ transfers + your_take = charge − stripe_fee` (the platform bears Stripe's processing fee in this model).
- **Async payment methods** (ACH/SEPA): wait for `charge.succeeded` before transferring — Stripe does **not** auto-reverse transfers if an async payment later fails, so a premature transfer becomes your loss.
- **Destination-charge variant** (single seller): set `transfer_data: { destination, amount }` (+ `on_behalf_of` if cross-region) on the PaymentIntent and skip step 2.

## 6. Escrow / hold (the timing is the whole game)

Separate charges & transfers *is* your escrow primitive: **capture now, transfer later.** Hold the
funds on the platform balance and create the transfer only when the release condition is met.

```ts
// Release worker: runs when a sub-order hits 'delivered' + return window elapsed (or dispute closed).
async function releaseEscrow(subOrderId: string) {
  const so = await getSubOrder(subOrderId);
  if (so.status !== "delivered" || now() < so.returnWindowEndsAt) return;  // not yet
  await stripe.transfers.create(
    { amount: so.payoutNet, currency: so.currency, destination: so.seller.connectedAccountId,
      transfer_group: so.orderId, source_transaction: so.chargeId },
    { idempotencyKey: `tr_${so.id}` },
  );
  await ledger.post(transferPostings(so));    // mirror into YOUR ledger
}
```

Escrow is mandatory for services/high-value/new sellers; optional (instant transfer) for trusted
food sellers where speed matters. Gate the release on KYC (`payouts_enabled`) and dispute state.

## 7. The double-entry ledger (your source of truth)

Stripe tells you what *it* did; the ledger is what *you* owe. Post balanced legs for every event
(table from `marketplace-architecture` §5). Example postings for a $100 order, 15% commission:

```
CAPTURE      Dr buyer_clearing 10000      Cr platform_payable 10000
COMMISSION   Dr platform_payable 1500     Cr platform_revenue 1500
TRANSFER     Dr platform_payable 8500     Cr seller:S1 8500          (separate charge to seller balance)
PAYOUT       Dr seller:S1 8500            Cr seller_bank_clearing 8500
-- REFUND of a $40 item from S1 later:
REFUND       Dr platform_payable 4000     Cr buyer_clearing 4000
REVERSAL     Dr seller:S1 3400            Cr platform_payable 3400   (proportional transfer reversal)
CLAWBACK     Dr platform_revenue 600      Cr platform_payable 600    (commission given back)
```

**Invariant:** every `txn_id` balances (Σdebit = Σcredit) per currency — assert in CI and a nightly
reconciliation job that also diffs ledger vs Stripe balance transactions. A non-zero imbalance is a
Sev-1. See `marketplace-data-platform` for the balance read-model + reconciliation pipeline.

## 8. Refunds, chargebacks & clawback (cross-seller correctness)

**Refunding a charge does not reverse the transfer** — two separate operations. For a multi-seller
order you must reverse **only the affected seller's** slice:

```ts
// Partial refund of S1's items only — S2 untouched.
async function refundSubOrderItems(so: SubOrder, refundAmount: number) {
  // 1) Refund the buyer (from the platform charge).
  await stripe.refunds.create(
    { payment_intent: so.order.paymentIntentId, amount: refundAmount, metadata: { sub_order_id: so.id } },
    { idempotencyKey: `rf_${so.id}_${refundAmount}` },
  );
  // 2) Claw back proportionally from THIS seller's transfer (+ refund the commission you took).
  const reverseAmount = Math.round(refundAmount * (so.payoutNet / so.subtotal));
  await stripe.transfers.createReversal(
    so.transferId,
    { amount: reverseAmount, refund_application_fee: true, metadata: { sub_order_id: so.id } },
    { idempotencyKey: `rev_${so.id}_${refundAmount}` },
  );
  await ledger.post(refundPostings(so, refundAmount, reverseAmount));
}
```

- **Destination charges**: refund with `reverse_transfer: true` + `refund_application_fee: true` to claw back in one call; by default the seller keeps the funds and the platform eats the loss (`ConnectTransferLoss`).
- **Chargebacks**: decide policy up front — **platform-absorbs** (simpler, you eat fraud) vs **seller-liable** (reverse the transfer + a dispute fee from their balance). Represent evidence to the PSP via the dispute API; reflect the outcome in the ledger either way.
- **Reversal limits**: you can only reverse up to the transferred amount, and a `transfer_group` reversal needs the destination to have balance — hence escrow + negative-balance handling.

## 9. Payouts, transfer vs payout, negative balances

| | **Transfer** | **Payout** |
|---|---|---|
| Moves | platform balance → connected account balance | connected account balance → seller's bank |
| Speed | instant ledger movement | 1–3 business days (country-dependent); **Instant Payouts** for eligible debit rails |
| Trigger | you (`transfers.create`) | Stripe, on the account's payout schedule (or manual) |
| Lifecycle | immediate | `pending → in_transit → paid | failed` (track via webhooks) |

- **Schedule** per seller: daily/weekly/monthly/manual + min threshold (set on the connected account, or manage payouts manually for full control).
- **Negative balance** (refund/chargeback exceeds seller balance): Stripe debits the connected account; if it can't cover, the platform covers and you carry a negative seller balance in **your** ledger, netting it from future earnings (or collections). Model this explicitly — it *will* happen.

## 10. Webhooks — verified + idempotent (the system's spine)

```ts
export async function handleStripeWebhook(req: Request) {
  const sig = req.headers["stripe-signature"]!;
  let event;
  try {
    event = stripe.webhooks.constructEvent(req.rawBody, sig, process.env.STRIPE_WH_SECRET!);
  } catch { return res(400, "bad signature"); }          // ALWAYS verify the signature

  if (await seen(event.id)) return res(200, "dup");        // idempotent on event.id
  switch (event.type) {
    case "payment_intent.succeeded": await onPaid(event.data.object); break;   // → create transfers / split
    case "charge.refunded":          await onRefunded(event.data.object); break;
    case "transfer.created":         await onTransfer(event.data.object); break;
    case "payout.paid": case "payout.failed": await onPayout(event.data.object); break;
    case "charge.dispute.created":   await onChargeback(event.data.object); break;
    case "account.updated":          await onAccountUpdated(event.data.object); break; // capability gating
  }
  await markSeen(event.id);
  return res(200, "ok");
}
```

**Post to the ledger only on confirmed events** (e.g. `payment_intent.succeeded`), never optimistically
on the client. Return 200 fast; do heavy work async. Reconcile missed webhooks via the events API.

## 11. Edge cases

- **Cross-region** platform/seller → set `on_behalf_of` (destination charges) or ensure the connected account has the right capabilities; fees follow the seller's country.
- **Multi-currency**: buyer pays AED, seller settles USD → FX happens at transfer/payout; record the rate as a ledger event; don't lose the spread silently.
- **Partial capture / auth-only** (rentals/deposits): authorize, capture later or partially; hold deposits as separate intents.
- **Tip added after delivery** (food) → additional transfer to courier/seller on the same `transfer_group`.
- **Seller offboarded with pending escrow** → release valid funds, hold disputed, settle final payout after last return window.
- **Refund after payout** → seller balance may be zero → negative balance handling (§9).

## 12. Performance & scale

- Money calls are **idempotent + queued** (outbox), never inline in the request path or DB txn.
- Webhook handler is fast + async; partition the dedupe store; backfill from the events API on outage.
- Batch transfers where possible; respect PSP rate limits with backoff.
- Ledger is append-only + partitioned by month; balances are a **read model** (materialized), not a live `SUM()` over all history.

## 13. Security & compliance

- **PCI:** never touch raw PAN — use Stripe Elements/Checkout tokenization; your servers see tokens only (keeps you in SAQ-A scope).
- **SCA/3DS:** rely on `automatic_payment_methods` + the PaymentIntents 3DS flow (mandatory in EU; increasingly enforced in MENA).
- **Idempotency keys** on *every* charge/transfer/refund/reversal — the single most important correctness control.
- **Webhook signature verification** always; reject unsigned/expired.
- **Payout fraud**: bank-change step-up + payout pause (`seller-vendor-management` §9); anomaly detection on payout destination/amount (`reviews-ratings-trust-safety`).
- **Least privilege** on Stripe API keys; restricted keys per service; rotate.

## 14. Observability — the money metrics

- **GMV**, **Take rate** (= platform revenue / GMV), **Net revenue**, **processing cost %**.
- **Money safety:** ledger imbalance (must be 0), ledger-vs-Stripe reconciliation diff, unreconciled events, payout failure rate, negative-balance count + age.
- **Escrow:** funds held, average hold duration, release backlog.
- **Disputes:** chargeback rate, win rate, $ lost to `ConnectTransferLoss`.

## 15. i18n / RTL (MENA)

- **Provider coverage varies:** Stripe Connect availability differs by MENA market — verify per country; otherwise use Adyen, Checkout.com, or regional PSPs (Paymob, Fawry, HyperPay, PayTabs, Tap) via `payments-master`. Some regions require a local acquiring entity.
- **Merchant of record + VAT:** as platform-MoR you issue the VAT invoice → wire the capture/refund events into ZATCA (Saudi) / UAE Peppol / Egypt ETA e-invoicing (`marketplace-architecture` §14). Commission may itself be a VATable service to the seller.
- **COD reconciliation:** model cash-on-delivery as a payment method settled by the courier — reconcile collected cash → platform → seller payout (`delivery-logistics-dispatch`).
- **Local payout rails:** IBAN payouts, sometimes local wallets; Arabic statements/invoices (RTL, `ui-master`).

## 16. Anti-patterns

- **Treating Stripe's balance as your ledger** → can't compute take-rate/seller balance, can't reconcile, can't audit.
- **Routing funds through your own bank account** → unlicensed money transmission.
- **Refunding the buyer without reversing the seller's transfer** → you silently eat every refund.
- **No idempotency keys** → double charges / double payouts under retry.
- **Transferring before an async payment clears** → Stripe won't auto-reverse; it's your loss.
- **Paying out before the return/dispute window** → unrecoverable money.
- **Trusting unverified webhooks / acting on client-side success** → fraud + ledger corruption.
- **One application_fee model bolted onto multi-seller carts** → use separate charges & transfers; don't fake N sellers through one destination.

## 17. Agent checklist

```
- [ ] Licensed provider (Stripe Connect/Adyen/Mangopay); never self-custody funds
- [ ] Account model chosen (Accounts v2 / controller props); capability-gated selling
- [ ] Multi-seller cart = separate charges & transfers (transfer_group + source_transaction)
- [ ] One PaymentIntent per cart + idempotency key; one Transfer per sub-order + idempotency key
- [ ] Commission = retained amount (or application_fee_amount for destination); frozen at order time
- [ ] Escrow: transfer on delivery + return-window/dispute clear, gated on payouts_enabled
- [ ] Double-entry ledger as source of truth; per-txn balance invariant asserted; daily reconcile
- [ ] Refund = buyer refund + proportional transfer reversal + commission clawback (per seller only)
- [ ] Chargeback policy (platform vs seller liable); negative-balance handling
- [ ] Webhooks signature-verified + idempotent on event.id; ledger posts on confirmed events only
- [ ] GMV / take-rate / reconciliation-diff / payout-failure metrics
- [ ] MENA: provider coverage, MoR VAT e-invoicing, COD reconciliation, IBAN payouts
```

## References (verify current — 2026)
- Connect charge types overview: https://docs.stripe.com/connect/charges
- Separate charges & transfers: https://docs.stripe.com/connect/separate-charges-and-transfers
- Destination charges: https://docs.stripe.com/connect/destination-charges
- Transfer reversals (clawback): https://docs.stripe.com/connect/charges-transfers#reverse-transfers · https://docs.stripe.com/api/transfer_reversals
- Accounts v2 / controller properties: https://docs.stripe.com/connect/accounts-v2 · https://docs.stripe.com/connect/migrate-to-controller-properties
- Payouts: https://docs.stripe.com/connect/manage-payout-schedule · Webhooks: https://docs.stripe.com/webhooks

## Related
`cart-checkout-orders` (orchestration), `seller-vendor-management` (KYC/capabilities, balance), `marketplace-data-platform` (ledger read-model, reconciliation, GMV) · cross-master: `payments-master` (PSP/PCI/SCA/regional rails), `business-master` (accounting-finance), `backend-api-master` (Stripe integration, webhooks)
