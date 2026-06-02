---
name: reconciliation-and-ledger
description: >-
  Money accuracy at staff depth — an append-only double-entry ledger in integer minor units,
  posting rules for the full lifecycle (authorize/capture/fee/refund/chargeback/FX/payout),
  daily settlement reconciliation (provider report ↔ payments ↔ ledger), break detection &
  resolution, and marketplace split payouts. The layer that proves every cent is accounted for and
  catches silent money leakage. Pairs with payments-architecture and accounting-finance.
---

# Reconciliation & Ledger

**If you can't prove, to the cent, that what the processor settled equals what your ledger says, you
are losing money you can't see.** Payments without a double-entry ledger and daily reconciliation
drift: fees, FX, refunds, chargebacks, and rounding silently desync your books from the bank. This
skill builds the append-only ledger and the reconciliation job that makes money provable.

## When to use / when NOT

- **Use** the moment real money moves — to record balances, match settlements, detect breaks, and pay
  out sellers. Mandatory before scale, audits, or marketplace payouts.
- **NOT** the place for gateway/webhook code (`global-`/`africa-payment-gateways`,
  `payment-webhooks-and-idempotency`). For full corporate accounting/GAAP, hand the journal to
  `accounting-finance` (business-master); this is the operational money ledger feeding it.

## Principles

- **Double-entry, append-only.** Every event posts ≥2 entries that **sum to zero per currency**. You
  never UPDATE or DELETE a posting — you post a **reversal**. The ledger is the immutable truth.
- **Integer minor units + currency** on every entry (`payments-architecture` `Money`). No floats, ever.
- **One currency per balanced transaction.** FX is modeled as two single-currency legs joined by an FX
  gain/loss account — never mix currencies inside one balanced set.
- **Idempotent postings.** Keyed by `(source, source_id)` so a replayed webhook can't double-post.

## Account model (minimum viable chart)

| Account | Type | Holds |
|---------|------|-------|
| `customer_clearing` | asset | authorized/captured not-yet-settled funds |
| `cash_<provider>` | asset | settled cash in the PSP/bank account |
| `processor_fees` | expense | MDR + fixed fees |
| `revenue` | income | recognized sale |
| `refunds` | contra-income | money returned |
| `chargebacks` | expense | disputed/lost funds + dispute fees |
| `fx_gain_loss` | income/expense | presentment↔settlement FX difference |
| `seller_payable_<id>` | liability | marketplace: owed to each seller |
| `platform_revenue` | income | marketplace commission |

## Posting rules (each set sums to zero, single currency)

```
CAPTURE (succeeded), amount A:
   DR customer_clearing  A
   CR revenue            A

SETTLEMENT (payout lands), gross A, fee F:
   DR cash_<provider>    A − F
   DR processor_fees     F
   CR customer_clearing  A

REFUND, amount R:
   DR refunds            R
   CR cash_<provider>    R         (or customer_clearing if pre-settlement)

CHARGEBACK lost, amount C, dispute fee D:
   DR chargebacks        C + D
   CR cash_<provider>    C + D

FX (charge EUR, settle USD):  two single-currency sets linked by fx_gain_loss,
   booked at the settlement rate you STORE on the posting.

MARKETPLACE capture A, commission K:
   DR customer_clearing  A
   CR platform_revenue   K
   CR seller_payable_<s> A − K
```

## Ledger schema + balanced-post helper

```sql
CREATE TABLE ledger_entries (
  id          bigserial PRIMARY KEY,
  txn_id      uuid        NOT NULL,        -- groups the balanced set
  account     text        NOT NULL,
  direction   text        NOT NULL CHECK (direction IN ('debit','credit')),
  amount      bigint      NOT NULL CHECK (amount > 0),   -- integer minor units
  currency    text        NOT NULL,
  source      text        NOT NULL,        -- 'stripe_event' | 'settlement_row' | 'manual'
  source_id   text        NOT NULL,        -- provider event id / settlement line id
  fx_rate     numeric,                     -- stored when this leg crosses currencies
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (source, source_id, account, direction)        -- idempotent: replay can't double-post
);
```

```ts
// Post a balanced set atomically; reject if debits ≠ credits per currency (the core invariant).
type Leg = { account: string; direction: "debit" | "credit"; amount: number; currency: Currency };
async function post(tx: Tx, txnId: string, source: string, sourceId: string, legs: Leg[]) {
  const byCcy: Record<string, number> = {};
  for (const l of legs) byCcy[l.currency] = (byCcy[l.currency] ?? 0) + (l.direction === "debit" ? l.amount : -l.amount);
  for (const [ccy, net] of Object.entries(byCcy))
    if (net !== 0) throw new Error(`unbalanced ${ccy}: net ${net} minor units`);   // refuse to post
  for (const l of legs)
    await tx.query(
      `INSERT INTO ledger_entries(txn_id,account,direction,amount,currency,source,source_id)
       VALUES ($1,$2,$3,$4,$5,$6,$7) ON CONFLICT DO NOTHING`,                       // idempotent
      [txnId, l.account, l.direction, l.amount, l.currency, source, sourceId]);
}
```

## Daily reconciliation (provider report ↔ payments ↔ ledger)

```ts
// Pull the provider's settlement (Stripe balance_transactions/payout report, Adyen settlement detail,
// Paystack settlements, M-Pesa statement). Match by providerRef; classify every break.
async function reconcile(day: string, provider: string) {
  const settled = await fetchSettlement(provider, day);     // [{ providerRef, gross, fee, net, currency }]
  const breaks: Break[] = [];
  for (const row of settled) {
    const pay = await findPaymentByRef(row.providerRef);
    if (!pay)                         breaks.push({ kind: "in_processor_not_system", row });
    else if (pay.amount !== row.gross) breaks.push({ kind: "amount_mismatch", row, pay });
    else {
      await postSettlement(row);      // DR cash net, DR fees, CR clearing — idempotent
    }
  }
  // The reverse direction: succeeded in our system but absent from settlement past T+expected.
  for (const p of await succeededUnsettledOlderThan(provider, expectedSettlementWindow(provider)))
    breaks.push({ kind: "in_system_not_processor", pay: p });
  await record(day, provider, breaks);
  if (breaks.length) alert(`recon ${provider} ${day}: ${breaks.length} breaks`);   // page on breaks
  // INVARIANT: after posting, SUM(customer_clearing) for settled txns → 0; fees explain the delta.
}
```

| Break type | Likely cause | Resolution |
|------------|--------------|-----------|
| **in_processor_not_system** | webhook lost / created out-of-band | sweeper re-fetch by ref; backfill payment + postings |
| **in_system_not_processor** | not settled yet / failed late | wait for window, else investigate; expire if truly failed |
| **amount_mismatch** | partial capture/refund, FX, fee miscalc | re-derive from events; post adjustment, never edit |
| **fee variance** | MDR/interchange change | update fee model; post actual fee from the report |
| **fx variance** | rate moved presentment→settlement | book `fx_gain_loss` at the stored settlement rate |

## Edge cases

- **Fees vary** (interchange++, blended vs IC+) → always post the **actual** fee from the settlement
  report, not your estimate; reconcile the estimate vs actual.
- **FX** → store the settlement rate on the posting; the residual is `fx_gain_loss`. Never reconstruct it later.
- **Partial capture/refund** → multiple balanced sets against the same payment; clearing nets correctly.
- **Chargeback reversal** (you win) → post the reversal set; don't delete the original chargeback postings.
- **Rounding** (M-Pesa whole-shilling, allocations) → use `allocate()` (largest-remainder) so splits sum
  exactly; book any residual to a rounding account, never drop cents.
- **Multi-currency payouts** → reconcile per settlement currency; one balanced set per currency.

## Marketplace payouts

- Hold each seller's share in `seller_payable_<id>`; pay out via the PSP's split/Connect/transfer (or
  B2C/disbursement for mobile money). The payout posts `DR seller_payable / CR cash`.
- A refund/chargeback after payout → **claw back** from future payable or via a debit; reflect both legs.

## Observability

- Daily: break count by type, unmatched amount, fee variance %, FX P&L, settlement lag vs expected
  window, clearing-account balance trend (should trend to ~0 for settled cohorts).
- Alert on: any unresolved break > 24h, clearing balance not converging, fee variance beyond tolerance.

## Testing

- Property test: random lifecycle sequences (capture/partial-refund/chargeback/FX) → ledger stays
  balanced per currency and replaying any event posts nothing new.
- Golden settlement file → reconciliation produces zero breaks; inject a mismatch → exactly one
  correctly-classified break.

## Anti-patterns

- A `balance` column you `UPDATE` instead of an append-only double-entry ledger (no audit, races, drift).
- Storing money as float/decimal-major; mixing currencies in one balanced set.
- Estimating fees and never reconciling against the actual settlement report.
- Editing/deleting postings to "fix" a number instead of posting a reversal/adjustment.
- No reconciliation, or reconciling only one direction (misses in-system-not-processor breaks).
- Paying out sellers from gross before fees/refund-risk are accounted for.

## Agent checklist

```
- [ ] Append-only double-entry ledger; every set sums to zero per currency; integer minor units
- [ ] Postings idempotent by (source, source_id); replays post nothing new
- [ ] Lifecycle posting rules: capture/settlement/fee/refund/chargeback/FX/payout
- [ ] Daily reconciliation provider report ↔ payments ↔ ledger; breaks classified + alerted
- [ ] Actual fees & stored FX rate from settlement (not estimates); rounding booked, never dropped
- [ ] Marketplace: seller_payable held; payout + clawback post both legs
- [ ] Metrics/alerts on breaks, clearing convergence, fee/FX variance, settlement lag
```

## References (current 2026)

- Stripe balance transactions & payout reconciliation: https://docs.stripe.com/reports/reconciliation · https://docs.stripe.com/api/balance_transactions
- Adyen settlement detail reports: https://docs.adyen.com/reporting/settlement-detail-report
- Double-entry for engineers (Modern Treasury / Square ledgers): https://www.moderntreasury.com/journal/accounting-for-developers
- Paystack settlements: https://paystack.com/docs/payments/settlements/

## Related

`payments-architecture`, `payment-orchestration-and-security`, `payment-webhooks-and-idempotency`,
`global-payment-gateways`, `africa-payment-gateways`; `accounting-finance` (business-master),
`marketplace-master` (split payments/payouts).
