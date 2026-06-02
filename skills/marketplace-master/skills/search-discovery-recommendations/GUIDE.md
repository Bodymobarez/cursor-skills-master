---
name: search-discovery-recommendations
description: >-
  Build marketplace search, discovery, and recs at staff depth — denormalized search
  read models fed by an outbox, typo-tolerant faceted search, the Algolia ranking
  pipeline (8 tie-break criteria + customRanking + Rules + Dynamic Re-Ranking) and
  OpenSearch hybrid search (BM25 + kNN via the normalization-processor pipeline),
  geo/zone-aware results, buy-box surfacing, vector recommendations + cold start,
  and sponsored-listing auctions. Search drives most marketplace conversion.
---

# Search, Discovery & Recommendations — The Conversion Engine

**Search is where marketplace revenue is won or lost.** Most buyers arrive with intent and a query
box; if the right item isn't in the top results, it doesn't exist. The staff-level mindset: **search
is a read model, not a query against your catalog** — denormalized documents in a purpose-built engine,
reindexed from events, ranked by a *blend* of text relevance + business signals + personalization +
availability, and constantly measured against click→purchase. Single-signal ranking (price-only,
recency-only) and `LIKE '%query%'` are how marketplaces leak conversion.

---

## 1. Mandate

- **Search is a read model fed by events** (`Catalog.OfferChanged` → reindex). Buyers never touch the OLTP.
- **Rank by a blend, tuned by experiments.** Text relevance + business signals (popularity/conversion/rating) + personalization + availability/geo − penalties. A/B test every weight change.
- **Availability- and zone-aware always.** Never surface out-of-stock, closed, or out-of-delivery-zone results (especially food/local).
- **Sponsored ≠ organic, and it must be labeled.** Ads are an auction layered on relevance, clearly disclosed.

## 2. When to use / when NOT

**Use when:** building product/restaurant search, faceting/filters, autocomplete, ranking/relevance, buy-box surfacing, recommendations, merchandising, or sponsored listings. **Consumes** the search docs from `multi-vendor-catalog` §8.

**Skip the heavy engine when:** tiny catalog (< ~10k items, simple filters) → Postgres FTS + `pg_trgm` is fine until it isn't. Don't stand up OpenSearch + vectors for an MVP with 200 products.

## 3. DECISION MATRIX — search engine

| Engine | Strengths | Watch-outs | Pick when |
|--------|-----------|------------|-----------|
| **Algolia** ⭐ | Best-in-class relevance/UX out of the box, instant, Recommend + NeuralSearch, Rules, A/B, analytics | $$ at scale; hosted only | You want great relevance fast, can pay, value DX |
| **OpenSearch / Elasticsearch** | Powerful, self-hostable, **hybrid (BM25 + kNN) + neural search**, full control | You operate it; relevance is your job | Scale, cost control, custom ranking/vectors, data residency (MENA) |
| **Meilisearch / Typesense** | Fast, typo-tolerant, easy facets, cheap/self-host | Fewer ranking/recs/AI features | Small-mid catalogs, great default before Algolia/OpenSearch |
| **Postgres FTS + pg_trgm** | No new infra | No real faceting/typo/ranking at scale | MVP / tiny catalog only |
| **Vespa** | Serving + ranking + vectors at very large scale | Steep learning curve | Amazon-scale ranking/recs |

## 4. The search document (denormalized, one per product/restaurant)

Built by the catalog consumer (`multi-vendor-catalog` §8) and **reindexed incrementally on change** —
never nightly-only. Carry everything ranking + faceting + display needs so the buyer path makes zero
OLTP calls.

```jsonc
{
  "objectID": "prod_123",
  "title": "Galaxy S25 256GB", "brand": "Samsung",
  "category_path": ["Electronics", "Phones", "Smartphones"],   // hierarchical facet
  "facets": { "storage": "256GB", "color": "Black", "ram": "12GB" },
  "price": 329900, "in_stock": true, "seller_count": 7,
  "rating": 4.6, "rating_count": 912, "popularity": 8421,      // custom-ranking signals
  "fast_delivery": true, "sponsored_bid": 0,
  "_geoloc": { "lat": 25.2, "lng": 55.27 },                    // food/local geo-ranking
  "buybox_offer_id": "off_55", "title_ar": "جالاكسي اس ٢٥"
}
```

## 5. Ranking — Algolia pipeline (verified order)

Algolia ranks with **8 tie-break criteria** applied in order — `typo, geo, words, filters, proximity,
attribute, exact, custom` — where `custom` consults your `customRanking` (business signals). The full
result-building order is: **textual relevance → custom ranking → personalization → Rules
(boost/bury) / query categorization → Dynamic Re-Ranking → Rules (pin/hide).**

```ts
import { algoliasearch } from "algoliasearch";
const client = algoliasearch(APP_ID, ADMIN_KEY);

await client.setSettings({
  indexName: "products",
  indexSettings: {
    searchableAttributes: ["title,brand", "category_path", "unordered(facets)"], // order = priority
    attributesForFaceting: ["filterOnly(in_stock)", "searchable(brand)", "category_path", "facets.storage", "facets.color"],
    // Business tie-breakers — only break ties AFTER textual relevance:
    customRanking: ["desc(popularity)", "desc(rating)", "asc(price)"],
    ranking: ["typo","geo","words","filters","proximity","attribute","exact","custom"],
  },
});
```

- **Don't reorder the default 8** without an A/B test — it's tuned for most cases; express business intent via `customRanking`, Rules, and Re-Ranking instead.
- **Dynamic Re-Ranking** reorders *eligible* results from click/conversion events (requires sending events) — it never adds new records.
- **Rules** = merchandising (boost/bury categories, pin/hide, query→filter); precedence is position/length/anchoring/context-based.
- **Geo-ranking** (food/local): `aroundLatLng` + the `geo` criterion weights distance heavily.

## 6. Ranking — OpenSearch hybrid (BM25 + vectors)

Keyword (BM25) nails exact terms; vectors nail intent/synonyms. Combine them with a **search pipeline +
`normalization-processor`** (scores live on different scales — you must normalize before combining).

```jsonc
// 1) One-time: a search pipeline that normalizes + weights the two clauses.
PUT /_search/pipeline/hybrid-pipeline
{ "phase_results_processors": [
  { "normalization-processor": {
      "normalization": { "technique": "min_max" },
      "combination": { "technique": "arithmetic_mean", "parameters": { "weights": [0.3, 0.7] } } } } ] }
```
```jsonc
// 2) Query: keyword + neural (vector) clauses combined by the pipeline.
GET /products/_search?search_pipeline=hybrid-pipeline
{ "query": { "hybrid": { "queries": [
  { "match": { "title": "wireless earbuds" } },
  { "neural": { "title_vector": { "query_text": "wireless earbuds", "model_id": "<model_id>", "k": 50 } } }
] } },
  "post_filter": { "term": { "in_stock": true } } }
```

`title_vector` is a `knn_vector` field (HNSW); embeddings generated by a `text_embedding` ingest
processor. Newer clusters can use the **score-ranker-processor** (RRF) instead of score normalization.
Apply business boosts via `function_score`/`rank_feature` on `popularity`/`rating`.

## 7. Faceting, autocomplete, buy box

- **Facets** come from the structured `facets`/`category_path` in the doc — typed, constrained (no free-text filters). Hierarchical category facets; price ranges; rating; dietary (food).
- **Autocomplete/typeahead**: typo-tolerant, with query suggestions + recent/popular searches; a separate suggestions index (Algolia Query Suggestions) or a lightweight prefix index.
- **Buy box in results**: the search doc carries `buybox_offer_id` + winning `price` (`multi-vendor-catalog` §5) — show one price per product, "N offers" link; never render N seller rows in search.

## 8. Recommendations (recsys)

| Surface | Method | Note |
|---------|--------|------|
| Related / similar | Content-based (attribute/embedding similarity) | Algolia Recommend "Related Products" / OpenSearch kNN on item vectors |
| Customers also bought | Collaborative / co-purchase | Algolia Recommend "FBT"/"Bought Together"; or co-occurrence matrix |
| Recommended for you | Personalized (history + embeddings, vector search) | Two-tower / sequence models at scale |
| Frequently bought together | Market-basket / association rules | Bundle suggestions at cart |
| Trending / new / nearby | Popularity + recency + geo | Cheap, high-ROI, great cold-start |

- **Cold start** (new user/item): fall back to popularity + geo + content similarity; vectors need data.
- **Start simple** (popularity + co-purchase + content) and add vector/personalization once you have event volume. Surface recs on home, PDP, cart, post-purchase, and *empty search*.

## 9. Merchandising & sponsored listings (ads)

- **Curated collections, category landing pages, seasonal banners, boost/bury rules** for ops (promote verified sellers, demote poor performers).
- **Sponsored listings = auction over relevance**: only relevant items can bid; rank by `bid × relevance × pCTR` (a quality-adjusted auction, à la Amazon), **budget pacing** so spend is even, and **clear "Sponsored" labels** (trust + legal). Ad revenue is a major marketplace P&L line — model it, but never let it tank organic relevance.

## 10. Edge cases

- **Zero results** → typo expansion, synonym fallback, relax filters, show popular/related; log every zero-result query (it's a catalog or relevance gap).
- **Out-of-stock / closed / out-of-zone** → filter at query time (food: only open + in-zone restaurants); never rank a thing the buyer can't buy.
- **Stale index** (price/stock drift) → incremental reindex on event; show "price may have changed"; re-validate at checkout regardless.
- **Personalization vs privacy** → respect consent; degrade gracefully to non-personalized.
- **Query intent ambiguity** ("apple" = fruit or phone) → query categorization / Rules; let facets disambiguate.

## 11. Performance & scale

- **Incremental, event-driven reindex** (outbox consumer); measure event→searchable lag.
- **Shard/replica** for catalog size + QPS; cache hot queries + facet counts; keep p99 query latency low (search is on the critical conversion path).
- **Vector cost**: HNSW memory + embedding compute — quantize, cap `k`, hybrid-filter first.
- **Geo** (food): pre-filter by zone/H3 before ranking so you score a small set.

## 12. Security

- **Sponsored disclosure** is a legal requirement (FTC-style + local) — label unconditionally.
- **No ranking manipulation by sellers**: fake-review/velocity signals must be cleaned (`reviews-ratings-trust-safety`) before they feed `popularity`/`rating`.
- **Query injection / DoS**: validate/limit filters and pagination; use search-only API keys (never the admin key) on the client; scope keys per index.
- **PII in events**: hash user IDs in search analytics; honor consent for personalization.

## 13. Observability — relevance is measured, not vibed

- **Zero-result rate**, **CTR**, **search→add-to-cart→purchase conversion**, **mean reciprocal rank / NDCG** on judged queries.
- **A/B every ranking change**; track per-variant conversion + revenue-per-search.
- **Index health**: reindex lag, doc count vs catalog, failed indexing ops.
- **Ads**: sponsored CTR, ACoS, budget pace, organic cannibalization.

## 14. i18n / RTL (MENA)

- **Arabic search is hard, do it right:** use an **Arabic analyzer** (normalize ـ tatweel/kashida, alef/hamza variants أ/إ/ا, taa marbuta ة/ه, strip diacritics/tashkeel), stemming, and **transliteration matching** (buyers type "Samsung" or "سامسونج", "shawarma" or "شاورما"). Index `title` + `title_ar`; query both.
- **Bidi display**: isolate Latin model names inside Arabic titles. Localized facet labels.
- **Geo/zone search** per emirate/city; currency-aware price facets.
- Synonyms tuned for Arabic dialects + common misspellings; RTL instant-search UI (`ui-master`, `tailwind-master` RTL).

## 15. Anti-patterns

- **`LIKE '%q%'` as "search"** → no typo tolerance, no facets, full scans. Use an engine.
- **Querying OLTP / no read model** → melts the primary, stale ranking.
- **Single-signal ranking** (price-only, newest-only) → poor relevance. Blend signals.
- **Showing out-of-stock / closed / out-of-zone** results → dead clicks, lost trust.
- **Reordering Algolia's 8 criteria** instead of using `customRanking`/Rules → breaks tuned relevance.
- **Combining BM25 + kNN without score normalization** → one scale dominates; use the pipeline.
- **Unlabeled sponsored results** → legal + trust failure.
- **No search analytics** → you can't fix zero-result/low-CTR queries you can't see.
- **English-only analyzer for Arabic** → catastrophic recall on Arabic queries.

## 16. Agent checklist

```
- [ ] Engine chosen for scale/cost/relevance (Algolia / OpenSearch / Meili / PG-FTS)
- [ ] Denormalized search docs from outbox; incremental reindex; lag measured
- [ ] Typo-tolerant search + facets (typed) + autocomplete + query suggestions
- [ ] Ranking blends text + business (customRanking) + personalization + geo; A/B tested
- [ ] (Algolia) keep default 8 criteria; express intent via customRanking/Rules/Re-Ranking
- [ ] (OpenSearch) hybrid BM25 + kNN via normalization-processor pipeline
- [ ] Availability/zone/stock filtered at query time; buy-box price surfaced from doc
- [ ] Recs: trending/related/also-bought/personalized; cold-start fallback
- [ ] Sponsored = quality-adjusted auction, budget-paced, clearly labeled
- [ ] Zero-result / CTR / search→purchase / NDCG metrics; clean signals (no fake reviews)
- [ ] Arabic analyzer + transliteration + bidi; per-locale index (MENA)
```

## References (verify current — 2026)
- Algolia ranking & 8 criteria: https://www.algolia.com/doc/guides/managing-results/relevance-overview/in-depth/ranking-criteria/
- Algolia customRanking + Rules + Dynamic Re-Ranking: https://www.algolia.com/doc/api-reference/api-parameters/customRanking/ · https://www.algolia.com/doc/guides/algolia-ai/re-ranking/
- Algolia Recommend: https://www.algolia.com/doc/guides/algolia-recommend/overview/
- OpenSearch hybrid search: https://docs.opensearch.org/latest/vector-search/ai-search/hybrid-search/ · vectors: https://docs.opensearch.org/latest/vector-search/
- Arabic analysis (ICU/Arabic analyzer): https://www.elastic.co/guide/en/elasticsearch/reference/current/analysis-lang-analyzer.html#arabic-analyzer

## Related
`multi-vendor-catalog` (search doc source, buy box), `marketplace-promotions-pricing` (sponsored/merch budget), `reviews-ratings-trust-safety` (clean ranking signals), `marketplace-data-platform` (search analytics) · cross-master: `ai-mcp-master` (embeddings/recsys), `ui-master` (instant-search UI, RTL)
