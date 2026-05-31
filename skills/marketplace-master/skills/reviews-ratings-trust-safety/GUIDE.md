---
name: reviews-ratings-trust-safety
description: >-
  Build reviews, ratings, trust & safety, and dispute resolution for a marketplace.
  Use for product/seller/courier ratings, verified reviews, moderation, fraud
  prevention, buyer/seller protection, disputes/chargebacks, and reputation systems.
  Trust is what makes a marketplace work.
---

# Reviews, Ratings, Trust & Safety

Trust is the real product of a marketplace. Build reputation, moderation, fraud prevention, and
fair dispute resolution.

## Reviews & ratings

```
Review (author, target[product|seller|courier|order], rating 1–5, text, photos,
        verified_purchase?, order_id, status[pending|published|removed], helpful_votes)
```
- **Verified-purchase only** (or clearly flag unverified) — tie reviews to a real order.
- Aggregate carefully: show count + distribution, not just an average; weight recent reviews;
  Bayesian/Wilson score to avoid "5.0 from 1 review" beating "4.7 from 900".
- Two-sided: buyers rate sellers/couriers **and** sellers rate buyers (food/services).
- Seller responses; report/flag abusive reviews; edit window.

## Moderation
- Auto-filter: profanity, PII, spam, competitor/self-review detection, link spam.
- ML/LLM moderation for text + image (pair with `camera-ai-vision`/vision models) → queue
  borderline for human review.
- Prohibited-content + fake-review detection (burst patterns, same IP/device, incentivized).

## Fraud prevention
| Vector | Defense |
|--------|---------|
| Fake accounts | Email/phone verification, device fingerprint, velocity limits |
| Payment fraud | 3DS/SCA, risk scoring, address/AVS, block on chargeback history |
| Fake reviews | Verified purchase, anomaly detection, graph analysis |
| Seller fraud | KYC, payout holds, performance monitoring, escrow |
| Account takeover | MFA (see `mfa-authenticator-security`), anomaly login alerts |
| Collusion/wash trading | Detect circular buyer↔seller patterns |

## Buyer & seller protection
- **Buyer protection**: refund if item not received / not as described; escrow release on confirm.
- **Seller protection**: evidence-based defense against fraudulent "not received" claims.
- Clear, published policies; consistent enforcement.

## Disputes & resolution
```
Dispute opened (reason, evidence) → vendor responds → mediation (auto rules or agent)
 → decision (refund full/partial / reject) → execute (refund + payout clawback) → close + record
```
- SLA timers for each step; auto-resolve on no-response.
- Track outcomes per seller (dispute rate feeds performance/SLA).
- Integrate with payment **chargeback** flow (represent evidence to the PSP).

## Reputation system
- Seller/courier score from rating + on-time + cancel/defect + dispute rate → affects ranking,
  visibility, payout speed, and badges (Top Seller / Superhost-style).
- Decay old behavior; reward consistency.

## Checklist
```
- [ ] Verified-purchase reviews + photos + helpful votes + seller response
- [ ] Smart aggregation (distribution + Bayesian/recency weighting)
- [ ] Moderation: auto-filter + ML/LLM + human review queue
- [ ] Fake-review + fraud detection (velocity, device, graph)
- [ ] Buyer/seller protection policies + escrow release rules
- [ ] Dispute workflow with SLAs + payment chargeback integration
- [ ] Reputation score feeding ranking/visibility/payout
```

## Anti-patterns
- Unverified reviews / no fake-review defense → ratings become noise.
- Showing only an average (hides distribution and review count).
- No dispute SLA → complaints rot, trust erodes.
- Inconsistent / opaque enforcement → seller and buyer churn.
- Refunding without evidence or without seller clawback.
