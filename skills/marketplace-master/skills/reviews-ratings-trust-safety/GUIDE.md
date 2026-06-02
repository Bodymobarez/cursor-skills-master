---
name: reviews-ratings-trust-safety
description: >-
  Build the trust layer at staff depth — verified-purchase reviews, statistically honest
  aggregation (Bayesian shrinkage + Wilson lower-bound, not naive averages), two-sided
  ratings, layered moderation (rules → ML/LLM → human queue), fake-review + fraud-ring
  detection (velocity, device graph, collusion), buyer/seller protection, a dispute FSM
  with SLA timers wired to PSP chargebacks, and reputation that feeds ranking + payout speed.
---

# Reviews, Ratings, Trust & Safety — Trust IS the Product

**A marketplace sells trust; products are incidental.** Buyers transact with strangers because the
platform vouches: verified reviews, honest ratings, fraud caught, disputes resolved fairly. The
staff-level discipline here is **statistical honesty** (a 5.0 from 1 review must not outrank a 4.7 from
900) and **adversarial thinking** (every signal you trust — reviews, "not received" claims, new
accounts — is being gamed for money right now). Build the trust layer like a security system, because
it is one.

---

## 1. Mandate

- **Reviews are tied to verified purchases.** Unverified content is flagged or excluded; a review without an order behind it is noise (or fraud).
- **Aggregate statistically, never naively.** Bayesian shrinkage toward the global mean + Wilson lower-bound for ranking; show count + distribution, not a lone average.
- **Moderation is layered and adversarial.** Rules → ML/LLM → human queue; assume fake reviews, review bombing, and collusion rings are active.
- **Disputes have SLA timers and a clawback path.** No-response auto-resolves; outcomes wire to PSP chargebacks and seller payout reversal.

## 2. When to use / when NOT

**Use when:** building reviews/ratings (product/seller/courier), aggregation, moderation, fraud/fake-review detection, buyer/seller protection, disputes, or reputation scoring. **Feeds** ranking (`search-discovery-recommendations`), seller SLAs (`seller-vendor-management`), and refund clawback (`marketplace-payments-payouts`).

**Trim when:** pre-launch MVP — start with verified reviews + basic profanity/spam filter + manual disputes; add ML moderation and graph fraud detection once volume (and abuse) appears. Don't build a fraud graph for 50 orders.

## 3. Review data model

```sql
create table reviews (
  id            uuid primary key default uuidv7(),
  author_id     uuid not null,
  target_type   text not null check (target_type in ('product','seller','courier','order')),
  target_id     uuid not null,
  order_id      uuid,                                  -- the proof of purchase
  rating        int  not null check (rating between 1 and 5),
  body          text, photos jsonb default '[]',
  verified_purchase bool not null default false,
  status        text not null default 'pending'
                check (status in ('pending','published','removed','quarantined')),
  helpful_votes int not null default 0,
  created_at    timestamptz not null default now(),
  unique (author_id, target_type, target_id, order_id)  -- one review per purchase
);
```

- **Verified-purchase** set by joining to a real `delivered` sub-order; flag/exclude the rest.
- **Two-sided**: buyers rate sellers/couriers **and** sellers rate buyers (food/services) — both feed reputation.
- **Seller responses**, report/flag, edit window; photos run through image moderation.

## 4. Honest aggregation (the math juniors skip)

Naive `AVG(rating)` lies: it lets tiny samples and brigading dominate. Use two tools:

```ts
// Bayesian average — shrink toward the global mean by a confidence prior C (e.g. 20 "virtual" votes).
// Display value: stable, fair to low-count items. (IMDb Top-250 formula.)
export function bayesianAverage(sum: number, n: number, globalMean = 4.2, C = 20): number {
  return (C * globalMean + sum) / (C + n);
}

// Wilson lower-bound on the positive proportion — for RANKING "best rated" (penalizes small n).
// p̂ = positives/n; z = 1.96 (95%). A 5/5 from n=2 ranks below 90/100.
export function wilsonLowerBound(positives: number, n: number, z = 1.96): number {
  if (n === 0) return 0;
  const p = positives / n;
  const z2 = z * z;
  return (p + z2 / (2 * n) - z * Math.sqrt((p * (1 - p) + z2 / (4 * n)) / n)) / (1 + z2 / n);
}
```

**Rules:** show **count + star distribution** (not just the number); **weight recent reviews** (decay);
use **Bayesian** for the displayed average and **Wilson lower-bound** for "top rated" sorts. Cache the
aggregate per target; recompute on new/removed review (event-driven).

## 5. Moderation — layered & adversarial

```
new review → (1) RULES: profanity, PII, links, banned terms, length/lang  → reject/quarantine
           → (2) ML/LLM: toxicity, spam, off-topic, AI-generated, image safety → score
                 high-confidence bad → remove; borderline → (3) HUMAN QUEUE
           → (4) FRAUD signals: velocity, device/IP graph, incentivized → quarantine + investigate
           → publish + recompute aggregate
```

- **Rules layer**: cheap, deterministic (profanity/PII/link/competitor-mention). **ML/LLM layer**: toxicity + spam + on-topic + image NSFW/counterfeit (route to `ai-mcp-master` vision). **Human queue** for the uncertain band — never fully automate removals at the margin.
- Keep an **audit trail** of every moderation decision (appealable, defensible).

## 6. Fake-review & fraud detection (it's a graph problem)

| Vector | Defense |
|--------|---------|
| Fake accounts | Email/phone verify, **device fingerprint**, velocity limits, age gating |
| Fake / incentivized reviews | Verified-purchase, burst detection (many 5★ in a window), same device/IP cluster, text similarity, "free product for review" language |
| Review bombing (coordinated 1★) | Spike anomaly vs baseline, shared signals across authors, temporary aggregate freeze |
| Seller fraud | KYC, payout holds, performance monitoring, escrow (`seller-vendor-management`) |
| Account takeover | MFA, anomalous-login alerts (`backend-api-master` mfa) |
| **Collusion / wash trading** | **Graph analysis**: detect circular/dense buyer↔seller↔reviewer subgraphs, self-purchase rings |

```ts
// Cheap, high-signal first pass: flag review bursts on a target from clustered identities.
function burstSuspicion(reviews: {authorId:string; deviceId:string; ip:string; at:Date; rating:number}[]) {
  const recent = reviews.filter(r => Date.now() - +r.at < 24*3600e3);
  const devices = new Set(recent.map(r => r.deviceId));
  const fiveStars = recent.filter(r => r.rating === 5).length;
  const concentration = 1 - devices.size / Math.max(recent.length, 1);  // →1 = same few devices
  return { suspect: recent.length > 15 && (concentration > 0.5 || fiveStars/recent.length > 0.9),
           concentration };
}
// Escalate suspects to a graph job (Neo4j / pgRouting / GNN) for ring detection.
```

## 7. Buyer & seller protection

- **Buyer protection**: refund if item not received / not as described; escrow released only on confirm or window pass (`marketplace-payments-payouts` §6). Clear, published policy.
- **Seller protection**: evidence-based defense against fraudulent "item not received" (POD photo/OTP from `delivery-logistics-dispatch`, tracking); abuse detection on serial-refunders.
- **Consistent, transparent enforcement** — opaque/arbitrary decisions churn both sides.

## 8. Disputes — FSM + SLA + chargeback wiring

```
opened (reason, evidence) → seller responds (SLA Th) → mediation (auto rules or agent)
   → decision (full/partial refund | reject) → execute (refund + proportional payout clawback) → closed
```

```ts
const DISPUTE_SLA = { sellerResponseHours: 48, mediationHours: 72 };
// No seller response within SLA → auto-decide for the buyer (and record). Timers via a workflow,
// not a hopeful cron. Track outcome per seller → feeds defect rate (seller-vendor-management §7).
```

- Each step has an **SLA timer**; no-response auto-resolves. Execution reuses the refund + transfer-reversal path (payments §8).
- **Chargeback integration**: when a buyer disputes via their bank, gather evidence and **represent to the PSP** (`charge.dispute.created`); reflect win/loss in the ledger; decide platform-vs-seller liability up front.

## 9. Reputation system

Seller/courier score = f(rating (Bayesian), on-time, cancel/defect rate, dispute rate, response time),
**decayed** over time and rewarding consistency. The score drives **search ranking, visibility,
payout speed, and badges** (Top Seller / Superhost-style). One number, many consequences — so it must
be fraud-clean before it's trusted (clean signals before they hit ranking, per search §12).

## 10. Edge cases

- **5.0 from 1 review** → Bayesian/Wilson prevents it outranking high-volume sellers.
- **Retaliatory ratings** (seller 1★s a buyer who complained) → detect tit-for-tat; weight/withhold.
- **Review for a refunded/cancelled order** → mark context (or exclude); don't let a non-fulfillment skew product quality.
- **Incentivized reviews** ("review for a gift card") → language detection + verified-purchase + burst signals → quarantine.
- **Deleted product/seller** → retain reviews for history/appeals; anonymize per policy.
- **Brigading after a viral incident** → temporary aggregate freeze + manual review, not silent suppression.

## 11. Performance & scale

- **Aggregates are a cached read model**, recomputed on review events (incremental), never `AVG()` over all rows on each page view.
- Moderation + fraud jobs run **async** off a queue; the publish path stays fast.
- Graph/fraud analysis is **batch/near-real-time**, not inline; precompute risk scores.

## 12. Security

- **PII in reviews/photos**: strip/redact contact info, faces where required; honor deletion requests.
- **Dispute evidence** stored securely with access controls (it contains addresses, POD, payment refs).
- **Authorization**: only the verified buyer can review their order; only seller/admin can respond/decide disputes; RLS on dispute records.
- **Fraud feedback loop**: caught rings feed account bans + payout holds; keep humans in the loop on irreversible actions.

## 13. Observability

- **Trust health**: dispute rate, dispute resolution time (SLA adherence), chargeback rate + win rate.
- **Moderation**: queue depth + age, auto vs human decisions, false-positive/appeal-overturn rate.
- **Fraud**: fake-reviews caught vs estimated, ring detections, $ fraud loss, % verified reviews.
- **Reputation**: score distribution, badge counts, correlation of score → conversion.

## 14. i18n / RTL (MENA)

- **Arabic moderation**: profanity/toxicity models tuned for **Arabic + dialects + transliterated (Arabizi, "7"=ح etc.)** text — English-only filters miss most abuse. Normalize diacritics; handle code-switching.
- **Cultural content norms**: region-specific banned content; localized policy + appeals in Arabic.
- **RTL review UI**, Arabic star/aggregate rendering, bilingual dispute correspondence (`ui-master`).
- **Identity/fraud**: phone-first verification (high mobile penetration); device fingerprinting across iOS/Android prevalent in MENA.

## 15. Anti-patterns

- **Unverified reviews / no fake-review defense** → ratings become noise, then a liability.
- **Naive `AVG()`** → small samples + brigading dominate; use Bayesian + Wilson.
- **Showing only an average** (hiding count + distribution) → misleads buyers.
- **Fully automated removals at the margin** → false positives, censorship complaints; keep a human band.
- **No dispute SLA / no auto-resolve** → complaints rot, both sides churn.
- **Refunding without clawback or without evidence** → you eat losses + invite refund fraud.
- **Feeding unclean rating/popularity signals into search ranking** → fraud amplifies itself.
- **English-only moderation for Arabic content** → abuse sails through.

## 16. Agent checklist

```
- [ ] Verified-purchase reviews tied to delivered orders; one review per purchase
- [ ] Bayesian average (display) + Wilson lower-bound (ranking); show count + distribution
- [ ] Two-sided ratings (buyer↔seller↔courier); recency decay
- [ ] Layered moderation: rules → ML/LLM → human queue; full audit trail
- [ ] Fake-review/fraud: velocity, device/IP cluster, burst, graph/collusion detection
- [ ] Buyer + seller protection policies; POD-based seller defense
- [ ] Dispute FSM with SLA timers + auto-resolve; PSP chargeback representation + clawback
- [ ] Reputation score → ranking/visibility/payout; fraud-clean before trusted
- [ ] Cached aggregate read model; async moderation/fraud jobs
- [ ] Arabic/dialect/Arabizi moderation + RTL; phone-first verification (MENA)
```

## References (verify current — 2026)
- Wilson score interval (ranking): https://en.wikipedia.org/wiki/Binomial_proportion_confidence_interval#Wilson_score_interval
- "How not to sort by average rating" (Evan Miller): https://www.evanmiller.org/how-not-to-sort-by-average-rating.html
- Bayesian average: https://en.wikipedia.org/wiki/Bayesian_average
- Stripe disputes/chargebacks: https://docs.stripe.com/disputes
- OpenAI moderation (text/image): https://platform.openai.com/docs/guides/moderation

## Related
`search-discovery-recommendations` (reputation → ranking, clean signals), `seller-vendor-management` (defect rate, suspension), `marketplace-payments-payouts` (refund/clawback, chargebacks), `delivery-logistics-dispatch` (POD evidence) · cross-master: `ai-mcp-master` (LLM/vision moderation), `backend-api-master` (MFA, anomaly detection)
