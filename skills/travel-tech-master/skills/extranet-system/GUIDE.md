---
name: extranet-system
description: >-
  Build a travel supplier extranet at staff/principal depth — the supplier-facing portal where hotels/
  DMCs/transfer/activity providers self-load inventory, rates, availability, content, promotions, and
  contracts that then become bookable in your CRS. Ships the normalized data model (contract→season→
  rateplan→rate-calendar→allotment), a calendar bulk-update engine, allotment vs free-sale vs on-request
  with release periods, contract-driven rate derivation, a hard validation gate before publish, roles/
  approval workflow, full audit, and multi-language/multi-currency content. Feeds the channel manager.
---

# Extranet System

**Mandate: the contract is the source of truth; nothing publishes to the CRS without passing a hard
validation gate.** An extranet's failure modes are unglamorous but expensive: selling allotment past its
release date, a missing cancellation policy that you can't enforce at refund time, overlapping rates that
make pricing ambiguous, and no audit trail when a supplier disputes "I never set that price." Model
contracts and rules structurally, validate aggressively, and log every change.

## When to use this skill
- Suppliers (hotels, DMCs, transfer/activity providers) need a self-service portal to manage their product.
- You hold *contracted* (direct) inventory and need contracting, allotment, and a publish pipeline into the CRS.
- **Not** for distributing inventory OUT to OTAs (`channel-manager-system`) or consuming external supply
  (`supplier-api-integration`). The extranet is upstream of both — it produces the ARI they move.

## Who uses it
- **Supplier** (hotel/DMC/provider): properties, rooms, rate plans, **allotment**, availability calendar,
  restrictions, content/photos, promotions, contracts.
- **Your ops team**: review/approve, set commissions, audit, resolve disputes.

## DECISION MATRIX — inventory release model

| Model | How it sells | Oversell risk | Use when | Release behavior |
|-------|-------------|---------------|----------|------------------|
| **Free-sale** | Sell freely up to a cap (or uncapped) | Higher — you trust the supplier's stock | Large hotels, low season | n/a |
| **Allotment** | Sell from a contracted block of N rooms | Low while block lasts | Committed/guaranteed inventory | **Release period**: unsold rooms return to the hotel `X` days before arrival |
| **On-request** | Booking pends supplier confirmation | None (no commitment) | Scarce/premium product | Confirm/reject SLA; queue in mid-office |

> Most contracts mix all three by season. The **release period** (cut-off) is the rule juniors miss — after
> it, your remaining allotment is no longer yours to sell.

## Data model (structural, not free text)

```
Supplier (account, base currency, payment terms, markets, commission)
 └─ Property (name, address, geo, category, content[multi-lang], amenities, photos)
     └─ RoomType (name, max occupancy, count)
         └─ RatePlan (board[RO/BB/HB/FB/AI], refundable?, cancellation policy, market/channel, min/max stay)
             ├─ RateCalendar  (date → net price, minLos, closed?, stop-sell)
             └─ Allotment     (date → rooms, sellMode[free-sale|allotment|on-request], releaseDays)
Contract (validFrom/To, seasons[], board basis, child/infant policy, cancellation tiers, special offers)
Promotion (early-bird | last-minute | LOS deal | free-night N-for-M; combinable rules; date windows)
```

```sql
-- Date-grain calendar tables are the heart of an extranet. One row per (rate plan, date).
CREATE TABLE rate_calendar (
  rate_plan_id  BIGINT NOT NULL,
  date          DATE   NOT NULL,
  net_amount    INTEGER NOT NULL,            -- minor units; currency from the supplier/contract
  min_los       SMALLINT DEFAULT 1,
  closed        BOOLEAN  DEFAULT FALSE,      -- stop-sell
  PRIMARY KEY (rate_plan_id, date)
);
CREATE TABLE allotment (
  room_type_id  BIGINT NOT NULL,
  date          DATE   NOT NULL,
  rooms         SMALLINT NOT NULL CHECK (rooms >= 0),
  sell_mode     TEXT   NOT NULL,             -- 'free_sale' | 'allotment' | 'on_request'
  release_days  SMALLINT DEFAULT 0,          -- days before arrival the block returns to the hotel
  PRIMARY KEY (room_type_id, date)
);
```

## Calendar bulk editor (the feature suppliers live in)

Suppliers edit by date *ranges*, day-of-week filters, and copy-week/season — never cell-by-cell. The engine
expands a range op into per-date upserts inside one transaction.

```ts
interface BulkRateOp {
  ratePlanId: string;
  from: string; to: string;                 // inclusive ISO dates
  daysOfWeek?: number[];                     // 0–6; e.g. weekend-only pricing
  set: { net?: Money; minLos?: number; closed?: boolean };
}

async function applyBulkRate(op: BulkRateOp, actor: Actor) {
  const dates = expandDates(op.from, op.to, op.daysOfWeek);
  await db.transaction(async (tx) => {
    for (const d of dates) {
      const before = await tx.rateCalendar.find(op.ratePlanId, d);
      await tx.rateCalendar.upsert({ ratePlanId: op.ratePlanId, date: d, ...materialize(op.set) });
      await audit(tx, { entity: "rate_calendar", key: `${op.ratePlanId}:${d}`, before, after: op.set, actor });
    }
  });
}
```

Every write produces an **audit row** (who/what/when, before→after) — rate disputes are routine and you must
be able to prove the timeline.

## Contract-driven rate derivation

The contract defines seasons, board uplifts, child policy, and cancellation tiers; rate plans *derive* from
it rather than being hand-keyed independently.

```ts
// Net for a stay = base seasonal rate + board uplift + occupancy/child rules, clamped to contract validity.
function deriveNet(contract: Contract, plan: RatePlan, date: string, occ: Occupancy): Money {
  const season = contract.seasons.find(s => within(date, s.from, s.to));
  if (!season) throw new ContractGap(plan.id, date);          // no season ⇒ not sellable; surface, don't guess
  let net = season.baseNet[plan.roomTypeId];
  net = add(net, boardUplift(contract, plan.board));
  net = add(net, childCharges(contract.childPolicy, occ));
  return net;
}
```

## Validation gate (publish is a privilege, not a default)

Reject before publish — never let a structurally broken product reach the CRS/channel manager.

```ts
function validateForPublish(p: PublishCandidate): ValidationError[] {
  const errs: ValidationError[] = [];
  if (!p.ratePlan.cancellationPolicy) errs.push(err("MISSING_CANCELLATION_POLICY"));
  if (hasOverlappingRates(p.rateCalendar)) errs.push(err("OVERLAPPING_RATES"));
  if (p.allotment.some(a => a.rooms < 0)) errs.push(err("NEGATIVE_ALLOTMENT"));
  if (p.ratePlan.currency !== p.contract.currency) errs.push(err("CURRENCY_MISMATCH"));
  if (gapDatesInSeason(p.contract)) errs.push(err("UNCOVERED_DATES"));
  if (p.allotment.some(a => a.sellMode === "allotment" && a.releaseDays == null))
    errs.push(err("MISSING_RELEASE_PERIOD"));
  return errs;                               // non-empty ⇒ block publish, show inline on the calendar
}
```

## Publishing pipeline

```
Supplier edits → VALIDATE (hard gate) → (optional) ops APPROVAL → publish to CRS
   → searchable/bookable in B2B/B2C → optionally distributed via channel-manager-system
```

## Roles, approval & multi-property
- Chain admin vs single-property manager vs read-only/finance; per-property and per-action permissions.
- **Approval workflow** for sensitive changes (rate drops beyond a threshold, allotment increases) — propose →
  review → publish, with the diff visible to the approver.
- Multi-property bulk ops (copy a season across a chain) with per-property override.

## Edge cases
- **Release period at the boundary:** compute "today + releaseDays ≥ arrival" in the property's timezone, or
  you'll release a day early/late. After release, drop the block from sellable availability automatically.
- **On-request SLA:** a pending booking that the supplier never confirms must auto-expire and notify — don't
  leave the customer hanging or the room blocked.
- **Overlapping/duplicate rate plans:** detect and block; ambiguous pricing is a silent revenue leak.
- **Currency vs contract:** a rate plan must be in the contract currency; conversion happens later at the
  pricing layer, never in the extranet.
- **Content drift:** photos/descriptions changed by the supplier shouldn't silently overwrite a curated set —
  version content and let ops approve.

## Performance / scale
- Calendars are date-grained and huge (rooms × rate plans × 730 days). Bulk ops must be set-based (one
  transaction, batched upserts), never N round-trips. Index `(rate_plan_id, date)` / `(room_type_id, date)`.
- Cache published availability for search; invalidate on publish.

## Security
- Multi-tenant isolation: a supplier can only ever see/edit *their* properties — enforce at the query layer,
  not just the UI. Row-level security or mandatory tenant scoping.
- Audit log is tamper-evident (append-only). Guest data isn't here (extranet is pre-booking) but contract
  rates are commercially sensitive — scope access tightly.

## Testing
- Property-test release-period and season-gap math across timezones and DST boundaries.
- Snapshot the validation gate: each rule has a fixture that must fail (and a clean one that must pass).

## Observability
- Track unpublished/blocked products and *why* (top validation failures), supplier activity, time-to-approve,
  allotment utilization, and release-driven inventory returns.

## i18n / RTL & currency
- Content is multi-language (Arabic/Hebrew RTL — pair `ui-master`); calendar UI must localize week start,
  date format, and number/currency formatting. Supplier base currency is set on the account.

## Anti-patterns
- No release-period/cut-off logic → selling allotment you can't fulfil.
- Publishing without validation (overlaps, missing cancellation policy, negative allotment).
- One rate plan trying to express board/cancellation/market variants → model them explicitly.
- Free text for board/cancellation instead of structured, machine-usable rules.
- No audit trail of rate/availability changes → unwinnable disputes.
- Cell-by-cell calendar writes instead of set-based bulk ops → unusable at chain scale.

## Checklist
```
- [ ] Supplier accounts + multi-property + roles + approval workflow + tenant isolation
- [ ] Contract→season→rateplan→rate-calendar→allotment model (structured, date-grained)
- [ ] Calendar bulk editor: range + day-of-week + copy-week/season, set-based, audited
- [ ] Allotment vs free-sale vs on-request + release-period (cut-off) logic in property TZ
- [ ] Contract-driven rate derivation (board uplift, child policy, seasons)
- [ ] Hard validation gate (overlap, missing policy, negative allotment, currency, gaps) before publish
- [ ] Promotions engine (early-bird/last-minute/LOS/free-night) with combinability rules
- [ ] Multi-language + multi-currency content; append-only audit; publish→CRS→channel manager
```

## References (2026-current)
- OpenTravel Alliance (hotel content/ARI message shapes): https://opentravel.org
- HTNG specifications (hotel data interchange): https://www.htng.org
- Booking.com room/rate setup (model parity reference): https://developers.booking.com/connectivity/docs

## Related
`channel-manager-system`, `supplier-api-integration`, `mapping-system`, `travel-tech-architecture`;
pairs with `backend-api-master` (data model, RBAC), `business-master` (accounting-finance for commissions).
