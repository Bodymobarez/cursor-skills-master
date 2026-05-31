---
name: affiliate-system
description: >-
  Build a professional affiliate / referral marketing system. Use when the user
  wants affiliate tracking, referral links, commissions, payouts, partner
  dashboards, or an ambassador program. Covers attribution, link/coupon tracking,
  commission models, fraud prevention, and payouts.
---

# Affiliate / Referral System

Build a trackable, fraud-resistant affiliate program: **partners → links → clicks → conversions
→ commissions → payouts**.

## Data model

```
Affiliate (user, code, status, payout_method, tax_info)
ReferralLink (affiliate_id, slug/ref_code, destination_url, campaign)
Click (link_id, ts, ip_hash, ua, referrer, landing_url, click_id)  -- cookie/click id stored
Conversion (click_id?, affiliate_id, order_id, amount, status[pending|approved|rejected])
CommissionRule (type[percent|flat|tiered], value, scope[global|product|affiliate], window_days)
Commission (conversion_id, amount, status) → Payout (affiliate_id, period, total, status)
```

## Attribution (get this right)

- On click: set first/last-touch **cookie** + a server-side **click_id** (cookieless fallback).
- Default **last-click within attribution window** (e.g. 30 days); make it configurable.
- On conversion (purchase/signup): match by click_id → cookie → coupon code (in that order).
- Support **coupon-code attribution** (affiliate's code at checkout) for cookieless/in-store.
- Dedupe conversions by `order_id` (idempotent).

## Commission models

| Model | Use |
|-------|-----|
| Percent of sale | Most e-commerce |
| Flat per action (CPA) | Signups, leads |
| Tiered | Reward volume (e.g. 10% → 15% after N sales) |
| Recurring | SaaS subscriptions (commission each renewal) |

Hold commissions as **pending** until refund/return window passes, then **approve** → payable.

## Build checklist

```
- [ ] 1. Affiliate signup + unique ref codes + partner dashboard (clicks, conv, earnings)
- [ ] 2. Link/redirect service that logs clicks and sets cookie + click_id
- [ ] 3. Conversion tracking: pixel/server-side postback/webhook from checkout
- [ ] 4. Attribution engine (last-click + window + coupon fallback), idempotent by order_id
- [ ] 5. Commission rules (percent/flat/tiered/recurring) + pending→approved lifecycle
- [ ] 6. Fraud checks (below)
- [ ] 7. Payouts (min threshold, schedule, method) + statements + tax forms
- [ ] 8. Reporting: EPC, conversion rate, top affiliates, refunds clawback
```

## Fraud prevention
- Reject self-referrals (match buyer == affiliate by email/IP/device).
- Rate-limit + de-bot clicks; hash IPs; flag abnormal CTR/conv ratios.
- Clawback commissions on refunds/chargebacks.
- Cap cookie stuffing (ignore rapid multi-link clicks).

## Stack
- Redirect service (edge/worker) for fast tracked links; Postgres for ledgered commissions
  (pair with `accounting-finance` for payout accounting). Use webhooks for conversions
  (`integrations-pro`).

## Anti-patterns
- Client-only conversion tracking (easily blocked/spoofed) → use server-side postbacks.
- Paying commissions immediately (no refund hold) → clawback nightmares.
- Non-unique/ guessable ref codes; no idempotency on conversions.
