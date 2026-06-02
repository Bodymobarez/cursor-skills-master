---
name: b2b-b2c-booking-platform
description: >-
  Build B2B and B2C travel booking platforms at staff/principal depth — OTA/IBE, agent portal, tour
  operator/DMC — on top of your supplier/CRS layer. Ships a configurable pricing engine (markup/
  commission rule resolution with explicit precedence + multi-currency FX), atomic agent credit/wallet
  holds, the B2C↔B2B difference map, customer-in payments (3DS2/SCA/PSD2) vs supplier-out (VCC/BSP),
  mid/back-office queues, vouchers/invoices, and B2B API-out. Composes supplier-api-integration,
  mapping-system, and booking-orchestration into a sellable product.
---

# B2B / B2C Booking Platform

**Mandate: markup is a rule engine, not scattered code; agent credit is enforced atomically at book time;
and you never charge before a fresh recheck.** This is the demand side — where money is made and lost. The
two classic failures are revenue leakage (markup logic duplicated and inconsistent) and credit blowouts
(agents booking past their limit because the check raced the charge). Make pricing declarative and credit
holds transactional.

## When to use this skill
- Building the customer/agent-facing product: search UI/IBE, agent portal, pricing, payments, mid-office.
- Adding markup/commission rules, agent hierarchy + credit/wallet, vouchers, or B2B API-out.
- **Not** the supplier connectivity (`supplier-api-integration`), dedupe (`mapping-system`), or the booking
  saga mechanics (`booking-orchestration`) — this skill *composes* those into a sellable platform.

## DECISION MATRIX — B2C vs B2B (they are different products)

| Aspect | B2C | B2B |
|--------|-----|-----|
| User | End traveller | Agency → sub-agents → corporate users |
| Price shown | **Sell only** (net hidden) | Net + agent markup; commission visible |
| Payment | Card (3DS2/SCA), wallet, BNPL | **Credit limit / deposit wallet** + invoice/statement |
| Pricing rules | Promotions, coupons, loyalty | Tiered markup per agent/group, negotiated/contract fares |
| Identity | Single user | Hierarchy with roles, per-node limits & markup |
| Docs | Voucher / e-ticket to traveller | Agent vouchers, statements, invoices |
| Failure tolerance | Retry/refund | Credit must never be exceeded; reconciliation is contractual |

## Search → book (composition)

```
SEARCH → fan-out (supplier-api-integration) → dedupe (mapping-system) → PRICING RULES → present
  → RECHECK price → BOOK saga (booking-orchestration) → PAY (in/out) → CONFIRM (voucher/ticket) → mid-office
```

## Pricing engine (declarative rules + explicit precedence)

Net → matched markup rule(s) → taxes/fees → sell. Rules are data (market, channel, agent tier, supplier,
product, date window, %-or-flat). **Precedence and combinability are explicit** — never "whatever the last
loop wins."

```ts
interface MarkupRule {
  id: string; scope: { market?: string; channel?: "B2C" | "B2B"; agentTier?: string;
                        supplier?: string; product?: "hotel" | "flight"; from?: string; to?: string };
  kind: "percent" | "flat"; value: number; currency?: string;  // flat needs a currency
  priority: number;          // higher wins when not combinable
  combinable: boolean;       // can it stack with the next-best rule?
  specificity: number;       // computed from scope; tiebreak within equal priority
}

function priceOffer(net: Money, ctx: PricingContext, rules: MarkupRule[], fx: FxTable): Money {
  const matched = rules.filter(r => matchesScope(r, ctx))
    .sort((a, b) => b.priority - a.priority || b.specificity - a.specificity);
  if (matched.length === 0) throw new NoMarkupRule(ctx);        // fail loud — never sell at net by accident
  let markup = money(0, net.currency);
  for (const r of matched) {
    markup = add(markup, applyRule(r, net, fx));
    if (!r.combinable) break;                                   // first non-combinable rule closes the stack
  }
  const sell = add(net, markup);
  return convert(sell, ctx.displayCurrency, fx);                // FX pinned at quote time, carried to booking
}
```

- **B2B:** persist `net + commission` and show the agent their margin. **B2C:** persist net internally, expose
  **sell only** — never leak net or supplier identity to consumers.
- Round once, at the display-currency boundary, per a documented policy (see `travel-tech-architecture`).

## Agent credit / wallet (atomic hold — the part juniors get wrong)

A credit check that isn't part of the same atomic operation as the booking will be raced. Hold inside the
transaction; release/settle in the saga's compensation/confirm steps.

```sql
-- Reserve credit ONLY if available; the guard makes overspend impossible at the DB layer.
UPDATE agent_wallet
   SET held = held + :sell
 WHERE agent_id = :agent
   AND (credit_limit + deposit_balance) - (used + held) >= :sell
RETURNING (credit_limit + deposit_balance) - (used + held) AS remaining;
-- 0 rows ⇒ insufficient credit ⇒ block booking BEFORE any supplier call.
```

```ts
async function bookForAgent(agentId: string, sell: Money, book: () => Promise<Booking>) {
  const held = await holdCredit(agentId, sell);                 // atomic; throws InsufficientCredit on 0 rows
  try {
    const booking = await book();                               // supplier book via the saga
    await settleHold(agentId, held, "used");                    // hold → used (real spend)
    return booking;
  } catch (e) {
    await releaseHold(agentId, held);                           // compensation: give the credit back
    throw e;
  }
}
```

Statements & reconciliation: every hold/use/release/top-up is a ledger entry (pair `accounting-finance`).

## Payments — customer-in vs supplier-out

| Direction | Mechanism (2026) | Notes |
|-----------|------------------|-------|
| **Customer in (B2C)** | PSP card with **3DS2 / SCA** (PSD2 in EU/UK), wallets (Apple/Google Pay), BNPL | Tokenize via PSP → keep PANs out of scope (SAQ A). Charge only after recheck. |
| **Customer in (B2B)** | Credit limit / deposit wallet + invoice | Atomic hold above; no card per booking. |
| **Supplier out** | **VCC** per booking (bed banks), **BSP/ARC** (air ticketing), bank transfer (contracted) | VCC limits card exposure & matches the exact net + currency; reconcile net-vs-sell margin. |

> **Order of operations matters.** Either confirm the supplier first then capture the customer, or
> authorize→confirm→capture with compensation — never capture-then-hope. The saga in `booking-orchestration`
> owns this; this skill wires the PSP and VCC providers into its steps.

## Mid / back office (not optional)
- Booking queues: pending, **on-request**, failed, amendment, cancellation, refund — each with an owner and SLA.
- Document generation: itinerary, voucher, e-ticket, invoice, agent statement (pair `documents-master`);
  email/notifications.
- Cancellation with **penalty calc from the stored policy**; refund workflow; supplier reconciliation; reporting
  (sales, margin, top suppliers/agents — pair `charts-and-dashboards`).

## B2B essentials
- **Agent hierarchy**: agency → sub-agencies → users, roles & per-node markup; impersonation for support (audited).
- **API-out**: expose your inventory to B2B clients (REST/JSON or OTA-style XML) — you become *their* supplier;
  apply the same recheck + idempotency contract you demand of your suppliers.
- White-label per agency (pair `white-label-platform`); negotiated/contracted fares per agent.

## B2C essentials
- Fast faceted search, maps (`gis-maps`), reviews, promotions/coupons, loyalty; abandoned-cart recovery.
- Clear "price updated since search" UX driven by the recheck — never silently change the total at payment.

## Edge cases
- **Recheck price drift at checkout:** show the new price and re-consent before charging; for B2B, re-validate
  the credit hold against the new sell amount.
- **Partial-success multi-item cart** (flight ok, hotel sold out): the saga must compensate; refund/release the
  succeeded leg per policy and surface a clear partial state.
- **Multi-currency rounding:** present and charge in display currency; settle suppliers in net currency; keep
  the FX rate/timestamp on the booking for reconciliation.
- **On-request bookings:** money is authorized/held but not captured until the supplier confirms; auto-expire.
- **Refund ≠ reverse of charge:** penalties, FX movement, and supplier refund timing mean refund amount is
  computed from policy, not the original charge.

## Performance / scale
- Pricing runs on every search result × every rule — precompile/match rules efficiently and cache rule sets;
  keep `priceOffer` allocation-light. Cache search; never cache the recheck/charge price.

## Security
- PCI: PSP tokenization, SAQ A scope; never store raw PANs. Passport/PII encrypted, masked in logs, retained
  minimally. Enforce tenant isolation for agencies; audit impersonation and rate/markup changes.

## Testing
- Unit-test the pricing engine against a rule matrix (precedence, combinability, currency, no-rule → throw).
- Property-test credit holds under concurrency (overspend must be impossible). Use PSP + supplier sandboxes;
  simulate 3DS challenge, declined card, VCC issuance, and refund/penalty paths.

## Observability
- **Look-to-book** and booking-funnel conversion; margin per booking (sell − net − fees); credit utilization
  per agent; refund/penalty rates; payment auth/capture/3DS-challenge success; reconciliation gap (sell vs net).

## i18n / RTL & currency
- Full multi-language UI incl. Arabic/Hebrew **RTL** (pair `ui-master`/`tailwind-master`); localized dates,
  numbers, name order; **multi-currency** display with FX, settlement in supplier currency.

## Anti-patterns
- Markup logic scattered in code instead of a configurable rule engine with explicit precedence.
- Showing net price / supplier identity to B2C consumers.
- Non-atomic credit check → agents overspend their limit under concurrency.
- Capturing the customer before a confirmed supplier reference (or charging on a stale price).
- No mid-office → failed/on-request bookings silently lost; no reconciliation → margin leaks.
- Single-currency assumptions; inconsistent rounding.

## Checklist
```
- [ ] Search+book composed on supplier-api-integration + mapping-system + booking-orchestration
- [ ] Declarative pricing engine: markup/commission rules, explicit precedence + combinability, FX
- [ ] B2C: sell-only display, 3DS2/SCA payments, promos/coupons, voucher/itinerary
- [ ] B2B: agent hierarchy + roles, per-tier markup, ATOMIC credit/wallet hold + statements
- [ ] Supplier-out payments (VCC/BSP) + net-vs-sell margin reconciliation
- [ ] Mid-office queues (fail/on-request/amend/cancel/refund) + docs + notifications
- [ ] B2B API-out (recheck + idempotency contract) + white-label
- [ ] Multi-currency + RTL i18n; audit log; reporting/dashboards
```

## References (2026-current)
- PSD2 SCA / 3-D Secure 2 (EMVCo): https://www.emvco.com/emv-technologies/3d-secure/
- IATA BSP (air settlement): https://www.iata.org/en/services/finance/bsp/
- Stripe payments & 3DS (customer-in reference): https://stripe.com/docs/payments

## Related
`supplier-api-integration`, `booking-orchestration`, `mapping-system`, `travel-tech-architecture`;
pairs with `payments-master` (PSPs/wallets/VCC), `business-master` (accounting-finance, white-label),
`ui-master` (dashboards/RTL), `documents-master` (vouchers/invoices).
