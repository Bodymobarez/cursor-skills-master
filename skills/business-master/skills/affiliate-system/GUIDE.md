---
name: affiliate-system
description: >-
  Build a trackable, fraud-resistant affiliate/referral program at principal depth: server-side
  click_id attribution with cookie + coupon fallback, idempotent conversions, percent/flat/tiered/
  recurring commissions, a pending→approved→paid lifecycle that survives refunds (clawback), ledgered
  payouts, and fraud defense (self-referral, cookie stuffing, click injection, bots). Postgres + TS.
---

# Affiliate / Referral System — Attribution, Money, Fraud

**The pipeline is: partner → link → click → conversion → commission → payout — and every stage is an
attack surface.** Affiliates are paid to send traffic, which means some will fake it. Two failure modes
sink programs: **wrong attribution** (you pay the wrong partner, or twice) and **paying before the refund
window** (clawback nightmares). Track server-side, hold money until it's real, and reconcile commissions
through the ledger.

---

## 1. Mandate
1. **Attribution is server-side** (a stored `click_id`), with cookie and coupon as fallbacks — never client-only.
2. **Conversions are idempotent** by `order_id`: a retried postback never double-pays.
3. **Commissions are held** (`pending`) through the refund/return window, then `approved` → payable.
4. **Refunds/chargebacks claw back** via reversing entries — money already paid is recovered or netted.
5. **Commissions are ledgered** as a liability (see **`accounting-finance`**), not a number in a dashboard.
6. **Fraud checks run before approval**, not after you've wired the cash.

## 2. When to use / when NOT
**Use** for affiliate, referral, ambassador, and partner/reseller programs that pay for performance.
**Don't hand-roll payments compliance** — use Stripe Connect / PayPal Payouts / Wise for KYC, tax, and
cross-border money movement. For a simple "refer a friend → credit" loop you may not need the full
attribution engine; for paid external affiliates at scale, you need all of it.

## 3. Data model

```
Program       tenant, cookie_window_days, hold_days, attribution[last|first], currency
Affiliate     user, code (unique), status, payout_method, tax_status[w9|w8ben|vat], min_payout
ReferralLink  affiliate_id, slug, destination_url, campaign
Click         link_id, click_id (uuid, server-set), ts, ip_hash, ua_hash, device_id, referrer, landing
Conversion    program_id, order_id (idempotent), affiliate_id, click_id?, gross_amount, currency,
              status[pending|approved|rejected|refunded], attributed_via[click|cookie|coupon]
CommissionRule type[percent|flat|tiered|recurring], value, scope[global|product|affiliate], priority
Commission    conversion_id, amount, status[pending|approved|paid|clawed_back], journal_entry_id
Payout        affiliate_id, period, total, status, external_ref (Stripe/Wise)
```

## 4. Attribution — get this exactly right

On click: set a first/last-touch **cookie** *and* persist a server-side **`click_id`** (cookieless
fallback for Safari ITP / blockers). On conversion match in priority order: **`click_id` → cookie →
coupon code**. Default to **last-click within the window**, configurable per program.

```sql
-- Resolve last-click attribution within the program window; falls back to coupon if no click matched.
-- $1 = click_id echoed back from checkout, $2 = conversion time, $3 = window days, $4 = coupon code
with by_click as (
  select c.affiliate_id, c.id as click_id, 'click'::text as via
  from click c
  where c.click_id = $1 and c.ts >= $2 - ($3 || ' days')::interval
  order by c.ts desc limit 1                              -- LAST click wins
),
by_coupon as (
  select a.id as affiliate_id, null::bigint, 'coupon'::text
  from affiliate a where a.code = $4
)
select * from by_click
union all
select * from by_coupon where not exists (select 1 from by_click)
limit 1;
```

```ts
/** Record a conversion exactly once. Idempotent on (program_id, order_id) → safe to retry postbacks. */
export async function recordConversion(c: PoolClient, x: {
  programId: number; orderId: string; affiliateId: number; clickId?: number;
  grossAmount: bigint; currency: string; via: 'click'|'cookie'|'coupon';
}) {
  const r = await c.query(
    `insert into conversion (tenant_id, program_id, order_id, affiliate_id, click_id,
                             gross_amount, currency, status, attributed_via)
     values (current_setting('app.tenant_id')::uuid,$1,$2,$3,$4,$5,$6,'pending',$7)
     on conflict (tenant_id, program_id, order_id) do nothing   -- ← idempotency: no double conversion
     returning id`,
    [x.programId, x.orderId, x.affiliateId, x.clickId ?? null,
     x.grossAmount.toString(), x.currency, x.via]);
  if (r.rowCount === 0) return null;                     // already recorded → no-op
  // compute commission (§5) and insert as 'pending'; do NOT post to ledger until approved.
  return r.rows[0].id;
}
```

## 5. Commission models — decision matrix

| Model | Payout basis | Use for | Watch out |
|-------|--------------|---------|-----------|
| **Percent of sale** | `gross × rate` | E-commerce | Define gross vs net (pre/post tax, shipping, discount) once |
| **Flat / CPA** | fixed per action | Signups, leads, installs | Lead quality fraud — verify the action |
| **Tiered** | rate rises with volume | Reward top partners | Define the window (per month? lifetime?) and retro vs prospective |
| **Recurring** | each renewal | SaaS subscriptions | Cap months; stop on churn; clawback first-period refunds |

Resolve **one** rule per conversion deterministically (scope priority: affiliate > product > global).
Compute on a clearly-defined base — **net of tax, shipping, and discounts** is the usual correct base;
write it down so finance and partners agree.

## 6. Lifecycle & ledger (hold the money until it's real)

```
pending ──(hold_days elapsed, fraud-clean)──▶ approved ──(payout run)──▶ paid
   └────────(order refunded / fraud)─────────▶ rejected / clawed_back
```

Commissions are a **liability you owe affiliates** — model them in the ledger so payouts reconcile:

```
On APPROVE commission:        On PAY (payout run):         On CLAWBACK (refund/chargeback):
  Dr Commission Expense         Dr Affiliate Payable          reverse the approve entry
     Cr Affiliate Payable          Cr Bank/Clearing            (Dr Affiliate Payable / Cr Commission Exp)
```

Post via `postEntry()` from **`accounting-finance`** in the same transaction that flips the status, with
the conversion/payout id as the idempotency key. Hold for `hold_days` (≥ your refund/return window) before
approval; a refund during the hold just sets `rejected` (no clawback needed).

## 7. Fraud prevention (the program's survival)

| Attack | Signal | Defense |
|--------|--------|---------|
| **Self-referral** | buyer email/IP/device == affiliate | Block match on identity at conversion |
| **Cookie stuffing** | clicks with no user intent, hidden iframes/pixels | Require real navigation; ignore clicks with no engagement; same-IP burst caps |
| **Click injection / spam** (mobile) | click timestamp moments before install/convert | Min click→convert dwell time; drop sub-second attributions |
| **Bot clicks** | datacenter IPs, headless UA, impossible CTR | IP reputation, UA/device fingerprint, rate-limit per IP/device |
| **Fake leads** (CPA) | disposable emails, never activate | Verify the action (email confirm, activation) before commission |
| **Coupon leakage** | affiliate codes posted on public deal sites | Restrict/monitor codes; cap discount-site attribution |

Compute **EPC** (earnings per click), conversion rate, refund/reversal rate, and AOV per affiliate;
**anomalous ratios are your best fraud detector** (a partner with 10× everyone's conversion rate is
usually cheating, not gifted). Hash IPs (PII), fingerprint devices, and keep a manual-review queue for
flagged conversions before approval.

## 8. Payouts
- **Threshold + schedule** (e.g. ≥ \$50, net-30 after approval); batch into a `Payout` per affiliate/period.
- **Methods**: Stripe Connect / PayPal Payouts / Wise / bank transfer — they handle KYC + cross-border.
- **Tax**: collect W-9/W-8BEN (US) or VAT details; generate 1099/statements; some jurisdictions require
  the affiliate to invoice you (handle inbound VAT). Multi-currency payouts post FX gain/loss.
- **Idempotent payout execution**: an `external_ref` per payout; never double-send if a job retries.

## 9. Performance, security, scale
- **Click ingestion is the firehose** — make the redirect edge-fast (worker/edge fn), log clicks async
  (queue/stream), and don't block the redirect on the DB write. Aggregate clicks into rollups for dashboards.
- **Conversions are low-volume but money-critical** — strong consistency, idempotent, ledgered.
- **Multi-tenant** via RLS + `FORCE` (**`multi-tenant-isolation`**); affiliate PII (tax IDs, payout
  details) encrypted and access-audited.
- Index `click (tenant_id, click_id)` and `(tenant_id, link_id, ts)`; partition `click` by month at scale.

## 10. Testing & observability
- **Attribution tests**: click→convert within window attributes; outside window doesn't; coupon fallback works.
- **Idempotency test**: same `order_id` postback twice → one conversion, one commission.
- **Clawback test**: refund after payment produces a reversing entry; affiliate balance nets correctly.
- **Observe**: reversal rate, hold-queue age, payout failures, per-affiliate EPC/conversion anomalies, fraud-flag rate.

## 11. i18n / localization
Multi-currency commissions and payouts (store currency per amount; convert at payout-time rate, post FX);
localized partner dashboards and statements; Arabic/RTL; region-specific tax forms and payout rails.

## 12. Anti-patterns
- **Client-only conversion tracking** (pixel that can be blocked/spoofed) → use server-side postbacks.
- **Paying on conversion** with no refund hold → clawback nightmares.
- **Non-idempotent conversions** → duplicate postbacks pay twice.
- **Guessable/sequential ref codes** → fraud and enumeration.
- **Commissions only in a table, never in the ledger** → payouts don't reconcile with finance.
- **No anomaly monitoring** → fraud rings drain the budget before you notice.
- **Blocking the redirect on DB writes** → slow links lose clicks and attribution.

## 13. Agent checklist
```
- [ ] Server-side click_id + cookie + coupon fallback; last-click within configurable window
- [ ] Conversions idempotent on (program, order_id)
- [ ] Commission rule resolution deterministic; base (net/gross) defined explicitly
- [ ] pending→approved→paid with hold_days ≥ refund window; clawback = reversing entry
- [ ] Commissions ledgered (Commission Expense / Affiliate Payable) via accounting-finance
- [ ] Fraud: self-referral block, bot/stuffing/injection defenses, anomaly metrics, review queue
- [ ] Payouts: threshold/schedule, KYC/tax forms, idempotent external_ref, FX on multi-currency
- [ ] RLS + FORCE; PII encrypted; click ingestion async/edge-fast
```

## 14. References (2026-current)
- Stripe Connect payouts: https://docs.stripe.com/connect · PayPal Payouts: https://developer.paypal.com/docs/payouts/
- Mobile attribution & click-injection fraud (AppsFlyer/Adjust fraud guides): https://www.appsflyer.com/resources/
- Safari ITP / cookieless attribution context: https://webkit.org/tracking-prevention/

## Related
`accounting-finance`, `multi-tenant-isolation`, `crm-builder`, `payments-master`,
`stripe-stripe-best-practices` (backend-api-master), `analytics-master`
