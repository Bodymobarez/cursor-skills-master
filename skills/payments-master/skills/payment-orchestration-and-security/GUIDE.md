---
name: payment-orchestration-and-security
description: >-
  The reliability + safety layer at staff depth: multi-gateway routing & failover (cascading
  retries on technical declines only), decline classification + smart retries/dunning, fraud
  (3DS2/SCA liability shift, Radar/RevenueProtect, velocity/device), subscriptions & off-session
  MIT mandates, refunds/disputes/chargebacks with ratio monitoring, and PCI scope strategy. Pairs
  with payment-webhooks-and-idempotency and reconciliation-and-ledger for the full backbone.
---

# Payment Orchestration & Security

**Single-gateway is a single point of revenue failure; retrying a hard decline is a self-inflicted
wound.** This layer routes each payment to the best provider, fails over on *technical* errors,
retries *soft* declines intelligently, blocks fraud without strangling good customers, and runs
subscriptions/refunds/disputes correctly. It sits on the `payments-architecture` adapters and assumes
webhooks (`payment-webhooks-and-idempotency`) and the ledger (`reconciliation-and-ledger`) exist.

## When to use / when NOT

- **Use** once you have ≥1 working adapter and need auth-rate, resilience, fraud control, recurring
  billing, or dispute handling.
- **NOT** for first integration (`payments-architecture` + a gateway skill), webhook plumbing (its own
  skill), or settlement accounting (`reconciliation-and-ledger`).

## 1. Routing & failover

```ts
// Route by country/currency/method/cost/health; fail over ONLY on technical errors, never hard declines.
type Candidate = { provider: PaymentProvider; mdrBps: number; healthy: boolean };
function route(req: CreatePaymentInput, all: Candidate[]): PaymentProvider[] {
  return all
    .filter((c) => c.healthy && supports(c.provider, req))      // supports country+currency+method
    .sort((a, b) => a.mdrBps - b.mdrBps)                         // least-cost first (tie-break on auth rate)
    .map((c) => c.provider);
}

async function charge(req: CreatePaymentInput, chain: PaymentProvider[]) {
  let lastErr: unknown;
  for (const p of chain) {
    try {
      const r = await p.createPayment(req);                     // SAME derived idempotency key throughout
      if (r.status !== "failed") return r;
      if (isHardDecline(r.raw)) throw new HardDecline(r.raw);    // do NOT cascade to provider B
    } catch (e) {
      if (e instanceof HardDecline) throw e;                    // stop: stolen/invalid/do-not-honor
      lastErr = e;                                              // technical (5xx/timeout/outage) → try next
    }
  }
  throw lastErr;                                                // all technically failed
}
```

- **Least-cost / load-balance** across acquirers; A/B test routing on auth-rate, not just price.
- Keep tokens **provider-agnostic** (network tokens, or an orchestrator like Spreedly, or your own token
  map) so failover and migration don't require re-collecting cards.
- A provider's health = recent error rate + latency (from your metrics); a circuit-breaker drops an
  unhealthy provider out of the chain automatically.

## 2. Decline classification & smart retries (recover revenue, avoid harm)

| Class | Examples | Action |
|-------|----------|--------|
| **Hard** (do-not-retry) | stolen card, invalid card, do-not-honor, lost card, fraud | fail fast; never re-attempt; don't cascade |
| **Soft** (retryable) | insufficient funds, issuer timeout, rate limit, try-again | backoff + jitter; cap attempts; dunning for subs |
| **Technical** (provider/network) | 5xx, timeout, connection reset | cascade to next provider; same idempotency key |
| **Auth required** | `authentication_required` | bring the customer back on-session for 3DS2 |

```ts
const HARD = new Set(["stolen_card","lost_card","pickup_card","fraudulent","do_not_honor","invalid_account"]);
const SOFT = new Set(["insufficient_funds","issuer_not_available","processing_error","try_again_later","rate_limit"]);
const classify = (code: string) =>
  HARD.has(code) ? "hard" : SOFT.has(code) ? "soft" : "technical";
```

- Exponential backoff + jitter; cap attempts. For subscriptions use **dunning** (a smart retry schedule
  over days + reminder emails + grace period) before cancelling — and try retries when the issuer is
  likeliest to approve (e.g., after payday windows; Stripe's Smart Retries does this for you).
- **Every retry reuses the same idempotency key for that attempt** so you never double-charge.

## 3. Fraud prevention (balance loss vs false declines)

| Layer | Control |
|-------|---------|
| Authentication | **3DS2 / SCA** — shifts chargeback liability to the issuer on authenticated txns |
| Risk scoring | Stripe **Radar**, Adyen **RevenueProtect**, or Sift/Riskified |
| Signals | device fingerprint, IP/geo/velocity, AVS/CVV result, BIN checks, email/age |
| Rules | block/allow lists, amount & velocity caps, **3DS step-up on risk** |
| Account | MFA (`mfa-authenticator-security`), takeover detection, payout-change cool-downs |

> A false decline is also a cost (lost good customer + support). Tune thresholds with data; use 3DS
> step-up on *risky* transactions rather than blanket challenges (which kill conversion and forfeit
> the frictionless/exemption path).

## 4. PSD2 / SCA strategy (EEA/UK)

SCA is mandatory for customer-initiated electronic payments in the EEA/UK; design **frictionless-first**
and tag exemptions/MITs so the issuer can skip the challenge (it always has final say):

| Exemption / scope | Threshold (verify current) | Note |
|-------------------|-----------------------------|------|
| **Low value** | < €30 (cumulative < €100 or 5 txns since last SCA) | issuer tracks the counter |
| **TRA** (acquirer fraud-rate based) | ≤ €100 @ RFR 0.13% · ≤ €250 @ 0.06% · ≤ €500 @ 0.01% | none above €500 |
| **MIT / off-session** (subscriptions) | out of scope if initial txn authenticated + mandate stored | mark as MIT |
| **Trusted beneficiary** | customer allowlisted the merchant at a prior SCA | issuer-maintained |

## 5. Subscriptions & recurring (off-session, SCA-safe)

```ts
// Authenticate the card when SAVING it (on-session SetupIntent → 3DS2 once), store a mandate, then
// charge off-session as a Merchant-Initiated Transaction. authentication_required ⇒ pull the user back.
const si = await stripe.setupIntents.create({ customer, payment_method_types: ["card"], usage: "off_session" });
// …client confirms SetupIntent (3DS2 once)… later, renewal:
try {
  await stripe.paymentIntents.create(
    { amount: plan.minor, currency: plan.ccy, customer, payment_method: pm,
      off_session: true, confirm: true },           // off_session + confirm = MIT
    { idempotencyKey: `renew:${subId}:${period}` },
  );
} catch (e: any) {
  if (e.code === "authentication_required") await emailReauthLink(subId);  // bring customer on-session
}
```

- Proration on upgrade/downgrade; trials; grace periods; dunning on failed renewals; store the mandate
  and the timestamp of the customer's agreement. Deep Stripe specifics: `stripe-best-practices`.

## 6. Refunds, disputes & chargebacks

- **Refunds** idempotent (key includes amount), partial/full, posted to the ledger
  (`reconciliation-and-ledger`); in a marketplace, claw back the seller's share.
- **Disputes/chargebacks**: a `dispute.created` webhook starts a clock — assemble evidence (AVS/CVV,
  3DS2 result, delivery proof, prior history) and submit before the deadline; track win/loss.
- **Monitor the chargeback ratio** (disputes ÷ transactions): exceeding scheme thresholds (~0.9–1%)
  triggers monitoring programs (Visa VAMP / Mastercard) and, unaddressed, account termination.
  Authenticated (3DS2) transactions move fraud liability to the issuer — a key lever.

## 7. Reliability, performance & observability

- **Webhooks are the source of truth** for state — verify, dedupe, async, idempotent reduce. (Full
  pattern + replay/dead-letter: `payment-webhooks-and-idempotency`.)
- Idempotent, queue-backed processing so retries/outages never double-apply.
- **Reconcile daily**: provider settlement ↔ payments ↔ ledger; flag mismatches (`reconciliation-and-ledger`).
- Dashboards/alerts: auth rate by provider/BIN/country, decline-code mix, retry-recovery rate,
  failover rate, dispute ratio trend, webhook lag, settlement variance. Page on auth-rate cliffs and
  rising dispute ratio.

## Testing

- Force each decline class with test cards (Stripe `4000000000009995` insufficient,
  `4000000000000259` dispute/chargeback) and assert: hard → no retry, technical → failover, soft → backoff.
- Simulate provider A outage → confirm cascade to B with the same idempotency key (one charge only).
- Replay a `charge.dispute.created` and verify the evidence workflow + ledger postings.

## Anti-patterns

- Single gateway, no failover (outage = 100% lost sales); no least-cost routing.
- Retrying hard declines → wasted attempts, issuer flags, higher decline rates.
- Blanket 3DS on everything → forfeits frictionless/exemptions, tanks conversion.
- Storing PAN (SAQ-D) when a provider token keeps you SAQ-A.
- Off-session charges without a stored mandate / without handling `authentication_required`.
- Ignoring the chargeback ratio until the acquirer terminates the MID.
- Treating the client redirect as truth or processing webhooks non-idempotently.

## Agent checklist

```
- [ ] Routing by country/method/cost + circuit-breaker failover on TECHNICAL declines only
- [ ] Decline classification (hard/soft/technical/auth) + backoff/jitter + dunning; same idempotency key
- [ ] Fraud: 3DS2/SCA + risk scoring + velocity/device/AVS + targeted step-up (not blanket)
- [ ] SCA: frictionless-first; exemptions/MIT tagged; off-session subs use stored mandate
- [ ] Refunds idempotent + ledgered; dispute evidence before deadline; chargeback-ratio alerting
- [ ] Webhooks (own skill) = source of truth; reconciliation (own skill) daily; rich per-provider metrics
```

## References (current 2026)

- Stripe Radar/Smart Retries/billing: https://docs.stripe.com/radar · https://docs.stripe.com/billing/revenue-recovery · https://docs.stripe.com/billing/subscriptions/overview
- SCA exemptions: https://docs.stripe.com/payments/3d-secure/strong-customer-authentication-exemptions
- Adyen RevenueProtect/disputes: https://docs.adyen.com/risk-management/ · https://docs.adyen.com/risk-management/disputes-api
- Visa/Mastercard dispute-monitoring overviews (scheme docs): consult your acquirer's current thresholds

## Related

`payments-architecture`, `payment-webhooks-and-idempotency`, `reconciliation-and-ledger`,
`global-payment-gateways`, `africa-payment-gateways`, `checkout-and-payment-pages`;
`stripe-best-practices`, `mfa-authenticator-security` (backend-api-master).
