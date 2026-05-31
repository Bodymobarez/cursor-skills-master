---
name: search-discovery-recommendations
description: >-
  Build marketplace search, discovery, and recommendations. Use for product/
  restaurant search, faceted filtering, ranking/relevance, autocomplete, personalized
  recommendations, "buy box" winner selection, and merchandising. Covers search
  engines (Meilisearch/Typesense/Elastic), ranking signals, and recsys patterns.
---

# Search, Discovery & Recommendations

Help buyers find the right item fast. Search + discovery drives most marketplace conversion.

## Search engine choice

| Engine | Strength |
|--------|----------|
| **Meilisearch / Typesense** ⭐ | Fast, typo-tolerant, easy facets/instant-search; great default |
| **Elasticsearch / OpenSearch** | Powerful, scalable, complex ranking, analytics |
| **Algolia** | Hosted, excellent relevance/UX (paid) |
| **Postgres FTS + pg_trgm** | Small catalogs / MVP |

Index a denormalized **search document** per product/restaurant (title, brand, category,
attributes/facets, price, rating, location, availability, popularity) — re-index on catalog changes.

## Faceted search & filters
- Facets from structured attributes (category, brand, price range, size/color, rating, dietary…).
- Filters must respect availability + delivery zone (food: only show open + in-zone restaurants).
- Autocomplete/typeahead (typo-tolerant) + search suggestions + recent/popular searches.

## Ranking / relevance (the core)
```
score = text_relevance
      + business_signals (popularity, conversion rate, rating, recency)
      + personalization (user history, location proximity)
      + availability/boosts (in-stock, fast delivery, sponsored)
      − penalties (low rating, frequent cancels, out-of-zone)
```
- Tune weights; A/B test ranking changes; log search→click→purchase to measure relevance.
- **Geo-ranking** for food/local: distance + ETA heavily weighted.

## Buy box (shared-product marketplaces)
When multiple sellers offer the same product, pick the default "Add to cart" offer by:
**price + shipping/delivery speed + seller rating + fulfillment + stock.** Show "other offers".

## Recommendations (recsys)
| Type | Method |
|------|--------|
| "Related / similar" | Content-based (attributes/embeddings) |
| "Customers also bought" | Collaborative filtering / co-purchase |
| "Recommended for you" | Personalized (history, embeddings, vector search) |
| "Frequently bought together" | Market-basket / association rules |
| Trending / new / nearby | Popularity + recency + geo |

- Start simple (popularity + co-purchase + content similarity); add embeddings/vector search later.
- Surface recs on home, product page, cart, post-purchase, empty-search.

## Merchandising & monetization
- Curated collections, category landing pages, banners, seasonal.
- **Sponsored listings / ads** (clearly labeled) — boost in ranking with budget pacing.
- Boost/bury rules for ops (promote verified sellers, demote poor performers).

## Checklist
```
- [ ] Search engine + denormalized search docs + re-index pipeline
- [ ] Typo-tolerant search, autocomplete, faceted filters
- [ ] Availability/zone-aware results (esp. food/local)
- [ ] Ranking with text + business + personalization signals; A/B tested
- [ ] Buy box selection for shared products
- [ ] Recommendations (related, also-bought, personalized, trending)
- [ ] Search analytics (zero-result queries, CTR, conversion) to improve relevance
- [ ] Sponsored/merchandising with labeling
```

## Anti-patterns
- DB `LIKE` queries as "search" (no typos, no facets, slow).
- Showing out-of-stock / out-of-zone / closed results.
- Ranking by a single signal (e.g. price only) — combine signals.
- No search analytics → can't fix zero-result/bad queries.
- Unlabeled sponsored results (trust + legal issues).
