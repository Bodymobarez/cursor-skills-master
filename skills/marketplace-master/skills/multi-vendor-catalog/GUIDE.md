---
name: multi-vendor-catalog
description: >-
  Model a multi-vendor catalog at staff depth — the Product↔Offer split (one product
  page, many sellers), buy-box selection, variant/SKU explosion, JSONB-vs-EAV facets,
  oversell-proof inventory with atomic reservation + optimistic locking, food menu/
  modifiers, denormalized search documents fed by an outbox, bulk import + moderation,
  and catalog dedup at scale. The data layer search, cart, and payouts all depend on.
---

# Multi-Vendor Catalog — Product↔Offer, Buy Box, Inventory

**The catalog's one job: separate what is *true about the thing* from what is *true about a seller's
deal on the thing*.** The `Product` (canonical: title, brand, GTIN, specs, images) is shared; the
`Offer` (this seller's price, stock, condition, handling time) is per-seller. Conflate them and you
get duplicate product pages, a dead buy box, garbage facets, and unsearchable junk. This split is the
hill to die on — it's what lets Amazon show *one* iPhone page with 40 sellers competing on it.

---

## 1. Mandate

- **Product is canonical and shared; Offer is per-seller.** Many offers → one variant → one product. Never duplicate product rows per seller (Etsy-style single-seller catalogs are the documented exception).
- **Inventory is decremented at order time via atomic, oversell-proof reservation** — never at add-to-cart, never with a read-then-write race.
- **The catalog OLTP is not the search index.** Emit `Catalog.OfferChanged` to a denormalized search read model; buyers never query these tables.
- **Structured attributes only.** Facets come from typed, constrained attributes — free text is not a filter.

## 2. When to use / when NOT

**Use when:** modeling categories/products/variants/offers; building the buy box; designing inventory reservation; food menu modeling; bulk import + moderation; feeding search.

**Skip the shared-product split when:** truly single-seller-per-listing (handmade/Etsy, classifieds) — the seller *owns* the product row, no buy box. **Skip variants** for services/rentals (use capacity/calendar instead — see `marketplace-architecture` types). Don't build EAV if a JSONB column + GIN index covers your facet needs (it usually does until very large scale).

## 3. Data model — the Product↔Offer split

```sql
create table categories (
  id          uuid primary key default uuidv7(),
  parent_id   uuid references categories(id),
  slug        text not null unique,
  path        ltree not null,                  -- 'electronics.phones.smartphones' → fast subtree queries
  attribute_set_id uuid references attribute_sets(id)
);
create index on categories using gist (path);

create table products (                          -- CANONICAL, shared across sellers
  id          uuid primary key default uuidv7(),
  category_id uuid not null references categories(id),
  gtin        text,                              -- UPC/EAN/ISBN — the dedup key for shared catalogs
  brand       text,
  title       text not null,                     -- default-locale; translations in product_i18n
  specs       jsonb not null default '{}',       -- non-variant-defining attributes (facets)
  status      text not null default 'draft' check (status in ('draft','pending','active','blocked')),
  created_at  timestamptz not null default now()
);
create unique index on products (gtin) where gtin is not null;   -- one product per real-world GTIN

create table variants (                          -- a buyable configuration (size/color)
  id          uuid primary key default uuidv7(),
  product_id  uuid not null references products(id) on delete cascade,
  sku         text,
  options     jsonb not null,                    -- {"size":"M","color":"Black"} — variant-DEFINING only
  gtin        text,
  unique (product_id, options)
);

create table offers (                            -- PER-SELLER deal on a variant
  id          uuid primary key default uuidv7(),
  seller_id   uuid not null references sellers(id),
  variant_id  uuid not null references variants(id),
  price       bigint not null check (price > 0), -- minor units
  currency    char(3) not null,
  condition   text not null default 'new' check (condition in ('new','refurb','used')),
  handling_hours int not null default 24,
  status      text not null default 'active' check (status in ('active','paused','out_of_stock')),
  version     int not null default 0,            -- optimistic lock
  unique (seller_id, variant_id, condition)      -- one offer per seller/variant/condition
);
create index on offers (variant_id) where status = 'active';      -- buy-box candidate scan
```

> Single-seller catalogs collapse `products`↔`offers` (seller owns the product). Shared catalogs keep
> them separate so N sellers compete on one page → **buy box**.

## 4. DECISION MATRIX — how to store attributes/facets

| Strategy | When | Trade-off |
|----------|------|-----------|
| **JSONB column + GIN index** ⭐ | Default. Flexible per-category attrs, moderate scale | Simple, indexable (`@>`, `?`), no joins. Weak typing → validate on write against the attribute set. |
| **EAV (entity-attribute-value)** | Huge attribute sparsity, attribute-level audit, RDBMS-only analytics | Query/maintenance pain (the classic EAV tax). Avoid unless you've measured the need. |
| **Typed columns** | A handful of universal, queried-everywhere attrs (price, brand) | Fast + constrained, but rigid — no per-category flexibility. |
| **Push to search engine** | Faceting/filtering is *read-side* | Correct end state: facets are computed and served by Algolia/OpenSearch from the search doc, not the OLTP. |

**Principled default:** JSONB in OLTP (validated against a per-category **attribute set**) + faceting
in the search engine. EAV is a last resort.

```sql
create table attribute_sets ( id uuid primary key, name text );
create table attribute_defs (
  set_id   uuid references attribute_sets(id),
  key      text not null,                 -- 'storage'
  data_type text not null,               -- 'enum'|'int'|'bool'|'text'
  is_variant_defining bool not null default false,
  is_facet bool not null default true,
  options  jsonb,                         -- enum values for validation + facet rendering
  primary key (set_id, key)
);
```

## 5. Buy box — choosing the default offer (shared catalogs)

When many sellers offer the same variant, pick the **one** "Add to cart" winner. This is a ranking,
not a min(price): a 1-AED-cheaper offer from a 3-star seller with 7-day handling should lose to a
trusted, fast one.

```ts
type Offer = {
  id: string; sellerId: string; price: number; shipping: number;
  sellerRating: number;        // 0..5
  handlingHours: number;
  inStock: boolean; fbaLike: boolean; // platform-fulfilled?
};

// Landed price + weighted quality. Tune weights with A/B tests; log winner for audit.
export function pickBuyBox(offers: Offer[]): Offer | null {
  const eligible = offers.filter(o => o.inStock && o.sellerRating >= 3.5);
  if (eligible.length === 0) return null;
  const score = (o: Offer) => {
    const landed = o.price + o.shipping;
    const cheapest = Math.min(...eligible.map(e => e.price + e.shipping));
    const priceScore = cheapest / landed;                 // 1.0 = cheapest
    const speedScore = 1 / (1 + o.handlingHours / 24);
    const trust = o.sellerRating / 5;
    const fulfill = o.fbaLike ? 1.1 : 1.0;                 // platform fulfillment boost
    return (priceScore * 0.45 + trust * 0.30 + speedScore * 0.25) * fulfill;
  };
  return eligible.sort((a, b) => score(b) - score(a))[0];
}
```

Show "N other offers" below the buy box. Recompute on offer/stock/price change (event-driven) and
**cache the winner per variant** — it's read on every product view. See `search-discovery-recommendations`
for surfacing it in listings.

## 6. Inventory — oversell-proof reservation (the part everyone gets wrong)

Stock has three numbers: `on_hand`, `reserved`, `available = on_hand − reserved`. Reserve at **order
creation**, release on timeout/cancel, decrement `on_hand` on fulfillment. The decrement must be
**atomic** — a read-then-write loses races under concurrency.

```sql
create table inventory (
  offer_id   uuid primary key references offers(id),
  on_hand    int not null check (on_hand >= 0),
  reserved   int not null default 0 check (reserved >= 0),
  version    int not null default 0,
  check (reserved <= on_hand)
);

create table reservations (
  id         uuid primary key default uuidv7(),
  offer_id   uuid not null references inventory(offer_id),
  order_id   uuid not null,
  qty        int not null check (qty > 0),
  status     text not null default 'held' check (status in ('held','committed','released')),
  expires_at timestamptz not null,         -- e.g. now() + 15 min; a sweeper releases stale holds
  unique (order_id, offer_id)
);
```

```sql
-- Atomic reserve: the WHERE clause is the lock. 0 rows updated = insufficient stock (no race).
UPDATE inventory
   SET reserved = reserved + $qty, version = version + 1
 WHERE offer_id = $offer
   AND on_hand - reserved >= $qty
RETURNING version;          -- rowCount = 0 → reject this line item, compensate the saga
```

```ts
// Release sweeper (cron, every minute): reclaim abandoned holds. Idempotent.
await sql`
  WITH expired AS (
    UPDATE reservations SET status = 'released'
     WHERE status = 'held' AND expires_at < now()
     RETURNING offer_id, qty)
  UPDATE inventory i SET reserved = i.reserved - e.qty
    FROM expired e WHERE i.offer_id = e.offer_id`;
```

**Rules:** never decrement at add-to-cart; high-contention SKUs (flash sales) → consider a Redis
atomic counter as the gate with Postgres as the durable truth; backorder/pre-order via an explicit
flag, not negative stock. Multi-warehouse/multi-branch: reservation picks the nearest fulfilling
location (feeds delivery zone logic in `delivery-logistics-dispatch`).

## 7. Food / quick-commerce menu model (Talabat-style)

```sql
create table menu_items (
  id         uuid primary key default uuidv7(),
  branch_id  uuid not null references seller_branches(id),  -- per-branch pricing/availability
  name       text not null,
  price      bigint not null,
  prep_minutes int not null default 15,
  available  bool not null default true,        -- the "86" toggle (out of stock NOW)
  schedule   jsonb                               -- breakfast 06:00-11:00 etc.
);
create table modifier_groups (
  id uuid primary key, menu_item_id uuid references menu_items(id),
  name text, min_select int default 0, max_select int default 1, required bool default false
);
create table modifiers (
  id uuid primary key, group_id uuid references modifier_groups(id),
  name text, price_delta bigint not null default 0   -- "Extra cheese +200"
);
```

Food inventory is mostly **availability toggles** (86-ing) + prep-time, not unit counts. Per-branch
price/availability is mandatory for chains. Validate modifier min/max at cart time (see `cart-checkout-orders`).

## 8. Catalog → search read model (event-driven, never query OLTP for search)

```ts
// On offer/price/stock change, emit via the transactional outbox (see marketplace-architecture §8).
// A consumer builds the DENORMALIZED search doc (one per product) and upserts to Algolia/OpenSearch.
function toSearchDoc(p: ProductWithOffers): SearchDoc {
  const winner = pickBuyBox(p.offers);
  return {
    objectID: p.id, title: p.title, brand: p.brand,
    category_path: p.categoryPath,                 // for hierarchical facets
    facets: p.specs,                               // flattened structured attributes
    price: winner?.price ?? null, in_stock: !!winner,
    seller_count: p.offers.length, rating: p.rating,
    popularity: p.salesVelocity,                   // a custom-ranking signal
    _geoloc: p.branchGeo,                          // food/local
  };
}
```

Re-index incrementally on change (not nightly full rebuilds). See `search-discovery-recommendations`
for the index settings and ranking.

## 9. Edge cases

- **Duplicate listings** (two sellers create separate products for the same real item) → dedup by GTIN/UPC on ingest; fuzzy match (title + brand + image hash) queued for moderation; merge tooling that re-points offers.
- **Variant explosion** (5 sizes × 8 colors × 3 materials = 120) → generate lazily, only persist variants with at least one offer.
- **Price/stock drift between cart and checkout** → re-validate offer price + availability at checkout (cart is not a quote).
- **Seller pauses an offer that's the buy-box winner** → recompute winner immediately; fall back to next eligible.
- **Out-of-zone / closed branch** (food) → item exists but is unbuyable now; search must hide it (zone/availability aware).

## 10. Performance & catalog scale

- **Partial indexes** for hot scans (`where status='active'`); covering indexes for buy-box candidate reads.
- **Cache the buy-box winner** per variant (Redis), invalidated by `OfferChanged`.
- **Don't N+1 offers** when rendering listings — the search doc already carries the winning price/stock.
- **Large imports** run async in batches with backpressure; never block the API on a 100k-row feed.
- **Media** off Postgres: images in object storage + CDN, store keys only; generate responsive/AVIF variants in a pipeline.

## 11. Security

- **Seller isolation on `offers`/`inventory` via RLS** (`marketplace-architecture` §9) — a seller can only mutate their own offers, never another's or the shared product record.
- **Moderation gate:** new seller products land `pending`; prohibited/counterfeit detection (keyword + image classifier, route to `ai-mcp-master` vision) before `active`.
- **Validate attributes on write** against the attribute set — block injection of arbitrary facet keys that pollute the index.
- **Bulk import** is a privilege-escalation vector: validate seller ownership per row, cap row counts, sandbox image URLs.

## 12. Observability

- **Catalog health:** % products with images/specs complete, % offers in stock, duplicate-rate, moderation queue depth + age.
- **Buy-box churn:** how often the winner flips (instability hurts conversion).
- **Reindex lag:** event → searchable latency (alert if p99 > target).
- **Inventory:** oversell incidents (must trend 0), stale-reservation sweep volume.

## 13. i18n / RTL (MENA)

```sql
create table product_i18n (
  product_id uuid references products(id), locale text,    -- 'ar','en'
  title text, description text, facets jsonb,              -- localized facet labels
  primary key (product_id, locale)
);
```

Store translations as rows, not columns; index a per-locale search doc (Arabic analyzer + Latin
brand). Currency/units per market; Arabic facet labels and RTL rendering (`ui-master`). Bidi titles
("سامسونج Galaxy S25") need isolation marks so the Latin model name doesn't reorder.

## 14. Anti-patterns

- **Duplicating product data per seller** instead of product↔offer → kills the buy box + splits search relevance.
- **Variants as unrelated standalone products** → breaks filtering, stock, and "other colors".
- **Free-text attributes** → no usable facets; "Red", "red", "RED" become three filters.
- **Decrementing stock at add-to-cart**, or read-then-write decrement → held-hostage stock + oversell.
- **Querying OLTP for buyer search/facets** → melts the primary DB; use the read model.
- **Nightly full reindex** as the only path → stale prices, race with sales. Use incremental + events.
- **Storing images as bytea in Postgres** → bloated tables, slow backups; object storage + CDN.

## 15. Agent checklist

```
- [ ] Product (canonical) vs Offer (per-seller) split — or seller-owned for single-seller/Etsy
- [ ] Category tree (ltree) + per-category attribute sets; JSONB facets validated on write
- [ ] Variant/SKU with variant-defining options only; lazy generation
- [ ] Buy box = weighted score (price+trust+speed+fulfillment), cached, recomputed on change
- [ ] Inventory: on_hand/reserved/available, ATOMIC reserve at order time, expiry sweeper
- [ ] Food: per-branch menu, modifier min/max, 86 toggle, prep time, schedule
- [ ] Denormalized search doc emitted via outbox; incremental reindex; never query OLTP for search
- [ ] GTIN dedup + fuzzy duplicate detection + moderation gate before active
- [ ] RLS seller isolation on offers/inventory; attribute validation
- [ ] product_i18n translations + per-locale index; RTL/bidi handling (MENA)
```

## References (verify current — 2026)
- Postgres JSONB / GIN indexing: https://www.postgresql.org/docs/current/datatype-json.html
- ltree (hierarchies): https://www.postgresql.org/docs/current/ltree.html
- GS1 GTIN (product identity/dedup): https://www.gs1.org/standards/id-keys/gtin
- Algolia records & faceting: https://www.algolia.com/doc/guides/managing-results/refine-results/faceting/

## Related
`search-discovery-recommendations` (faceting/ranking), `cart-checkout-orders` (reservation commit), `seller-vendor-management` (who can list), `marketplace-architecture` (outbox, RLS) · cross-master: `ui-master` (charts-and-dashboards), `ai-mcp-master` (camera-ai-vision for moderation)
