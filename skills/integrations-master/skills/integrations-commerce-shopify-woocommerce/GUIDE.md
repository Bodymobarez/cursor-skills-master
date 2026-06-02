---
name: integrations-commerce-shopify-woocommerce
description: >-
  Staff-level e-commerce integration: Shopify Admin GraphQL + mandatory HMAC (X-Shopify-Hmac-SHA256,
  base64), X-Shopify-Webhook-Id idempotency, leaky-bucket/GraphQL-cost rate limits, GDPR/compliance
  webhooks, bulk operations; WooCommerce REST + X-WC-Webhook-Signature; BigCommerce/Magento. Verify
  base64 HMAC on the raw body and route checkout/payments to payments-master.
---

# Commerce: Shopify & WooCommerce

**Mandate: Shopify HMAC is base64 over the raw body (not hex), webhooks are at-least-once so dedupe by
`X-Shopify-Webhook-Id`, and you must ship the mandatory GDPR compliance webhooks or App Store review
rejects you.** Inventory/order sync is high-volume and rate-limited — use bulk ops and reconcile.

## Decision — Shopify integration type & API

| Type | Use | API surface |
|------|-----|-------------|
| **Public app** (OAuth) | Listed on App Store, many merchants | Admin **GraphQL** (REST being deprecated for new) |
| **Custom app** (admin token) | One merchant you control | Admin GraphQL/REST |
| **Storefront API** | Headless storefront | Storefront GraphQL (separate token) |

Default to **Admin GraphQL** — REST is legacy and several objects are GraphQL-only. Pin the API
version (e.g. `2026-01`) and bump quarterly; versions age out.

## Shopify — auth + webhook verification

```ts
// X-Shopify-Hmac-SHA256 = base64( HMAC-SHA256(appClientSecret, rawBody) )  — BASE64, not hex
import { createHmac, timingSafeEqual } from "crypto";
export function verifyShopify(raw: Buffer, hmac = "", secret: string) {
  const expected = createHmac("sha256", secret).update(raw).digest("base64");
  return hmac.length === expected.length && timingSafeEqual(Buffer.from(hmac), Buffer.from(expected));
}
```

Key headers: `X-Shopify-Topic` (`orders/create`), `X-Shopify-Webhook-Id` (**dedupe key**, reused across
retries), `X-Shopify-Shop-Domain`, `X-Shopify-Api-Version`. Shopify retries **8× over ~4h**, then
auto-deletes the subscription — so a flaky endpoint silently loses its webhooks. ACK 200 in <5s.

```graphql
# Admin GraphQL: create product (mutation returns userErrors — always check them)
mutation Create($input: ProductInput!) {
  productCreate(input: $input) { product { id } userErrors { field message } }
}
```

**Mandatory compliance webhooks** (GDPR): `customers/data_request`, `customers/redact`, `shop/redact`
— implement them or fail review. Also handle `app/uninstalled` (revoke + clean up the merchant's data).

## Shopify rate limits (GraphQL cost vs REST leaky bucket)

- **GraphQL**: a **calculated query cost** with a leaky-bucket of points; the response
  `extensions.cost` tells you `actualQueryCost`, `throttleStatus.currentlyAvailable`, `restoreRate`.
  Throttle yourself off that, don't just retry on 429.
- **REST**: classic leaky bucket; read `X-Shopify-Shop-Api-Call-Limit` and back off near the cap.
- High volume (export all products/orders): use **bulkOperationRunQuery** (async → JSONL on a URL),
  not paginated live queries.

```ts
const remaining = resp.extensions?.cost?.throttleStatus?.currentlyAvailable ?? 1000;
if (remaining < 100) await sleep(1000);                       // self-throttle before Shopify does
```

## WooCommerce

- REST `https://store/wp-json/wc/v3/...` with consumer key/secret (Basic auth over HTTPS). Orders,
  products, customers.
- Webhooks: signed with **`X-WC-Webhook-Signature` = base64 HMAC-SHA256 of the raw body** (key = webhook
  secret). Verify on raw bytes (WordPress plugins/proxies mangle parsed bodies).
- Self-hosted reality: variable uptime, plugin conflicts, slow shared hosting → generous timeouts,
  retries, and IP allowlisting where possible.

## BigCommerce / Magento (Adobe Commerce)

- **BigCommerce**: REST/GraphQL + OAuth; webhooks signed; store-hash scoped tokens.
- **Magento**: REST/GraphQL + OAuth (or integration tokens); heavier, often async via message queues.

## Inventory & order sync (the hard part)

```
order webhook → verify → dedupe(webhook_id) → enqueue → fulfill/record → reconcile nightly (orders since cursor)
inventory: write through one source of truth; multi-location → map locationId; avoid oversell with reserves
```

- **Idempotency** on order processing: dedupe by webhook id AND key business actions by `order_id`
  (a retried webhook must not double-fulfill).
- **Reconcile poll** (orders/products updated since a cursor) catches the webhooks Shopify dropped
  during your downtime — webhooks alone are never complete. See `integrations-sync-engine-cdc`.

## Payments & marketplace

- Checkout/payments are **platform-managed** — route to **`payments-master`** (Shopify Payments, PCI).
  Don't reimplement card handling.
- Multi-vendor / split orders / seller payouts → **`marketplace-master`**.

## Security

- App client secret doubles as the webhook HMAC key — store encrypted, rotate carefully (rotation has
  up to ~1h propagation on Shopify; run dual-verify during overlap).
- Least-priv access scopes; request only the resources you touch.
- SSRF-guard any merchant-supplied callback/URL; verify shop domain (`*.myshopify.com`).

## Testing & observability

- Shopify CLI dev store + `app webhook trigger`; record fixtures per topic. Signature tests (base64!).
- WooCommerce: local WP + ngrok. Metrics: `order_webhook_lag`, `dedup_hits`, `throttle_status_remaining`,
  `webhook_verify_fail_total`, `mandatory_webhook_missing` (should be 0).

## Anti-patterns

- Hex instead of base64 for Shopify/Woo HMAC (silent verify failures).
- No dedupe → double-fulfilled/double-counted orders on retries.
- Skipping mandatory GDPR webhooks (App Store rejection) or `app/uninstalled` cleanup.
- Live paginating huge catalogs instead of bulk operations.
- Retrying past Shopify's 8-attempt window expecting redelivery (subscription is already gone).
- Re-implementing checkout/PCI instead of using `payments-master`.

## Agent checklist

```
- [ ] Shopify HMAC base64 verified on raw body; dedupe X-Shopify-Webhook-Id; ACK <5s
- [ ] API version pinned (e.g. 2026-01); Admin GraphQL preferred; check userErrors
- [ ] Mandatory GDPR webhooks + app/uninstalled implemented
- [ ] Self-throttle off GraphQL cost / REST call-limit; bulk ops for large reads
- [ ] WooCommerce X-WC-Webhook-Signature (base64) verified on raw body
- [ ] Order processing idempotent by order_id; nightly reconcile poll; payments → payments-master
```

## References

- Shopify webhook verify: https://shopify.dev/docs/apps/build/webhooks/verify-deliveries · GraphQL rate limits: https://shopify.dev/docs/api/usage/rate-limits · Mandatory webhooks: https://shopify.dev/docs/apps/build/privacy-law-compliance
- WooCommerce REST: https://woocommerce.github.io/woocommerce-rest-api-docs/ · BigCommerce: https://developer.bigcommerce.com

## Related

`integrations-webhooks-events`, `integrations-sync-engine-cdc`, `payments-master`, `marketplace-master`
