---
name: multi-vendor-catalog
description: >-
  Build a multi-vendor product catalog. Use for catalog data modeling — categories/
  taxonomy, products, variants/SKUs, multiple sellers per product (offers + buy
  box), attributes, inventory, digital/physical, and bulk import. Covers the
  Amazon-style product↔offer split and food-menu modeling.
---

# Multi-Vendor Catalog

Model a catalog where **many sellers** sell products. The key idea: separate the **Product**
(shared definition) from the **Offer** (each seller's price + stock).

## Data model (product ↔ offer split — Amazon style)

```
Category (tree/taxonomy, slug, parent)         AttributeSet per category
Product  (canonical: title, brand, descr, images, specs, gtin)   ← shared across sellers
 └─ Variant / SKU (option combo: size/color, own gtin, images)
Offer    (seller_id, variant_id, price, currency, stock, condition[new/used], handling_time)
   → multiple sellers can have an Offer on the SAME variant → "Buy Box" picks the winner
Inventory (offer_id, qty, reserved, warehouse/location)
```

- **Single-seller catalogs** (Etsy-style): seller owns the product directly (skip shared product).
- **Shared catalogs** (Amazon-style): one product page, many offers → **buy box** ranking
  (price + shipping + seller rating + fulfillment).

## Attributes & taxonomy
- Category-specific **attribute sets** (e.g. Phones: storage, color; Shoes: size, material).
- Store structured attributes (JSONB or EAV) for filtering/facets (feeds search).
- Variants = combinations of variant-defining options; non-defining attrs live on the product.

## Food / quick-commerce menu model (Talabat style)
```
Restaurant (vendor) → MenuCategory → MenuItem (price, prep_time, photo, availability hours)
 └─ ModifierGroup (e.g. "Size", "Add-ons", min/max select, required?)
     └─ Modifier (e.g. "Large +$2", "Extra cheese +$1")
Item availability toggles (86'd/out-of-stock), schedule (breakfast menu), per-branch pricing.
```

## Inventory rules
- Reserve stock at **order/payment**, not at add-to-cart; release on timeout/cancel.
- Track `qty`, `reserved`, `available = qty − reserved`; prevent oversell with atomic decrement.
- Backorder / pre-order flags; low-stock alerts to sellers.
- Multi-warehouse / multi-branch (pick nearest for delivery).

## Catalog operations
- **Bulk import/export** (CSV/feed) + image upload; validation + error report per row.
- **Moderation/approval** workflow for new seller products (quality + prohibited items).
- Content quality: required fields, image specs, duplicate detection (link to `mapping-system` ideas).
- Multi-language + multi-currency; per-market availability.

## Checklist
```
- [ ] Decide shared-product+offer (Amazon) vs seller-owned product (Etsy) — or menu model (food)
- [ ] Category taxonomy + per-category attribute sets (facets)
- [ ] Product → Variant/SKU → Offer (seller price+stock); buy box if shared
- [ ] Inventory with reserved/available + atomic decrement at order time
- [ ] Bulk import + validation + moderation/approval
- [ ] Multi-language/currency/market; images pipeline
- [ ] Feed catalog into search index (search-discovery)
```

## Anti-patterns
- Duplicating product data per seller instead of product↔offer (kills the buy box + search).
- Variants as separate unrelated products (breaks filtering and stock).
- Free-text attributes → no usable facets/filters.
- Decrementing stock at cart add; no reservation/timeout → oversell or stuck stock.
- No moderation → prohibited/low-quality listings.
