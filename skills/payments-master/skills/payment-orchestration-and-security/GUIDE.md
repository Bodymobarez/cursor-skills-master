---
name: payment-orchestration-and-security
description: >-
  Orchestrate multiple payment providers and secure payments. Use for multi-gateway
  routing/failover, smart retries, PCI DSS compliance, fraud prevention, webhooks,
  idempotency, reconciliation, subscriptions/recurring billing, refunds, disputes/
  chargebacks, and multi-currency. The reliability + safety + money-accuracy layer.
---

# Payment Orchestration & Security

The layer that makes payments **reliable, safe, and accurate** across many providers. Sits on top
of `payments-architecture` adapters.

## 1. Orchestration (multi-gateway routing)
- **Route** each payment to the best provider by: country, currency, method, cost (MDR), and health.
- **Failover/retry**: if provider A declines/errors (technical), retry on provider B (cascading) —
  improves auth rates. Don't re-attempt hard declines (insufficient funds/fraud).
- **Least-cost routing** + load balancing across acquirers; A/B test routing for auth-rate.
- Vault tokens in a **provider-agnostic** way (network tokens / orchestration platforms like
  Spreedly, or your own token map) so you're not locked in.

## 2. Smart retries (recover revenue, avoid harm)
- Classify declines: **hard** (do-not-retry: stolen, invalid, do-not-honor) vs **soft**
  (retry-able: insufficient funds, issuer timeout, rate limit).
- Exponential backoff + jitter; cap attempts; for subscriptions use **dunning** (smart retry
  schedule + reminder emails) before cancelling.
- Always idempotent so retries never double-charge.

## 3. PCI DSS compliance
- Minimize scope: **never store/transmit PAN/CVV** — use hosted fields/tokenization → **SAQ-A**.
- If you touch card data you're **SAQ-D** (audits, scans, heavy controls) — avoid.
- Secrets in a vault; TLS everywhere; access control + audit logs; quarterly scans if in scope.

## 4. Fraud prevention
| Layer | Control |
|-------|---------|
| Authentication | 3-D Secure / SCA (shifts liability to issuer) |
| Risk scoring | Provider tools (Stripe Radar, Adyen RevenueProtect) or Sift/Riskified |
| Signals | Device fingerprint, IP/geo/velocity, AVS/CVV checks, BIN checks |
| Rules | Block/allow lists, amount/velocity limits, 3DS step-up on risk |
| Account | MFA (see `mfa-authenticator-security`), takeover detection |
Tune to balance fraud loss vs false declines (good-customer friction is also a cost).

## 5. Webhooks (source of truth)
```
- [ ] Verify signature (provider HMAC) using the RAW body
- [ ] Return 2xx fast; process async (queue)
- [ ] Idempotent: dedupe by provider event id; ignore replays/out-of-order
- [ ] Reconcile state machine; never advance order on client redirect alone
- [ ] Log raw events for replay/audit; expose manual replay
```

## 6. Subscriptions / recurring
- Store payment-method tokens; bill on schedule; **proration** on upgrade/downgrade; trials;
  grace periods; **dunning** for failed renewals; SCA-friendly off-session charges
  (mandates/`setup_intent`). Pair with `adding-stripe` / `stripe-stripe-best-practices`.

## 7. Refunds, disputes & chargebacks
- Refunds idempotent; partial/full; reflect in ledger + (marketplace) seller clawback.
- **Disputes/chargebacks**: receive webhook → submit evidence before deadline → track win/loss;
  monitor chargeback ratio (too high → acquirer penalties/termination).

## 8. Money accuracy & reconciliation
- Integer minor units + currency everywhere (pair with `accounting-finance`).
- **Reconcile daily**: provider settlement report ↔ your payments ↔ ledger; account for fees, FX,
  refunds, chargebacks; flag mismatches.
- Multi-currency: presentment vs settlement currency; store FX rate used.

## Checklist
```
- [ ] Routing by country/method/cost + failover for technical declines
- [ ] Decline classification + smart retry/dunning (idempotent)
- [ ] PCI scope minimized to SAQ-A (hosted fields/tokenization)
- [ ] Fraud: 3DS/SCA + risk scoring + velocity/device signals + rules
- [ ] Webhooks verified, idempotent, async = source of truth
- [ ] Subscriptions: tokens, proration, trials, dunning, off-session SCA
- [ ] Refunds/disputes/chargeback workflow + ratio monitoring
- [ ] Daily reconciliation provider↔ledger; minor units + FX correct
```

## Anti-patterns
- Single gateway, no failover → outages = lost sales; no least-cost routing.
- Retrying hard declines → wasted attempts + issuer flags.
- Storing PAN (SAQ-D) when tokenization would keep you SAQ-A.
- Trusting client redirect over webhooks; non-idempotent webhook processing.
- No reconciliation → silent money leakage and unnoticed mismatches.
- Ignoring chargeback ratio until the acquirer terminates the account.
