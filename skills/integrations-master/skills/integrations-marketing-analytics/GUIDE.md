---
name: integrations-marketing-analytics
description: >-
  Staff-level marketing/analytics integration: server-side event pipelines (Segment/RudderStack CDP),
  Meta Conversions API + pixel dedup by event_id, GA4 Measurement Protocol, Google Ads enhanced/offline
  conversions, SHA-256 PII hashing, Consent Mode v2 / GDPR gating, identity resolution, and email/CDP
  list sync. Go server-side, dedupe browser↔server, hash PII, and gate on consent.
---

# Marketing & Analytics Integrations

**Mandate: send conversions server-side, dedupe them against the browser pixel by a shared `event_id`,
and hash PII with SHA-256 before it leaves your servers.** Client-only tracking loses 20–40% to ad
blockers/ITP; double-firing without dedup inflates ROAS and corrupts optimization. Consent gates the
whole thing — no consent, no send.

## Architecture — one pipeline, many destinations

```
your app (server) → CDP (Segment / RudderStack) → Mixpanel · GA4 · Amplitude · Meta CAPI · Google Ads
        └── browser SDK (pixel) ─ shares event_id ─┘   (dedup at the destination)
```

A CDP gives you one `track()` contract and fan-out + transformation. Self-host RudderStack for data
residency/cost; Segment for managed. PostHog is all-in-one (analytics + flags) → deep skills in
`analytics-master`.

## Decision — which integration per goal

| Goal | Integration | Key detail |
|------|-------------|-----------|
| Product analytics | Mixpanel/Amplitude/PostHog via CDP | server + client, `user_id` identity |
| Web analytics | **GA4 Measurement Protocol** | server events need `client_id` (+`user_id`) |
| Ad optimization (Meta) | **Conversions API** | `event_id` dedup w/ pixel; hashed PII; EMQ |
| Ad optimization (Google) | Enhanced conversions / offline import | hashed email/phone; `gclid` |
| Email/lifecycle | Klaviyo/Mailchimp/Customer.io | list sync + event triggers |

## Server-side event (CDP)

```ts
import { Analytics } from "@segment/analytics-node";
const analytics = new Analytics({ writeKey: process.env.SEGMENT_WRITE_KEY! });
analytics.track({
  userId, event: "Order Completed",
  properties: { orderId, revenue, currency: "AED" },
  context: { ip: req.ip, userAgent: req.headers["user-agent"] },        // for attribution/geo
  // messageId == event_id → dedup with the browser pixel firing the same purchase
  messageId: `order:${orderId}`,
});
```

## Meta Conversions API (CAPI) — dedup + hashing

```ts
// Send the SAME event_id from pixel and server; Meta dedupes. Hash all PII (sha256, lowercased+trimmed).
const sha256 = (v: string) => createHash("sha256").update(v.trim().toLowerCase()).digest("hex");
await fetch(`https://graph.facebook.com/v21.0/${PIXEL_ID}/events?access_token=${TOKEN}`, {
  method: "POST", headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ data: [{
    event_name: "Purchase", event_time: Math.floor(Date.now() / 1000),
    event_id: `order:${orderId}`,                                       // <-- dedup key (matches pixel)
    action_source: "website", event_source_url: url,
    user_data: { em: [sha256(email)], ph: [sha256(phone)],
                 fbp: cookies._fbp, fbc: cookies._fbc, client_ip_address: ip, client_user_agent: ua },
    custom_data: { currency: "AED", value: revenue, order_id: orderId },
  }] }),
});
```

Higher **Event Match Quality (EMQ)** = more matched parameters (em, ph, fbp/fbc, ip+ua). Google Ads
enhanced conversions follow the same shape: hashed email/phone + `gclid`/`wbraid`.

## GA4 Measurement Protocol

```ts
await fetch(`https://www.google-analytics.com/mp/collect?measurement_id=${MID}&api_secret=${SECRET}`, {
  method: "POST",
  body: JSON.stringify({ client_id, user_id,                            // client_id MUST match gtag
    events: [{ name: "purchase", params: { transaction_id, value: revenue, currency: "AED" } }] }),
});
```

## Consent & privacy (not optional)

- **Consent Mode v2** (EU/UK) + your CMP: gate analytics/ads signals on the user's consent state; if
  denied, don't send (or send consented-cookieless pings only). UAE PDPL/EU GDPR: document processing.
- Hash PII (SHA-256) for all ad-platform user_data; never send raw email/phone.
- Honor DSAR/delete: propagate suppression to destinations (Segment "Suppress & Delete", platform
  deletion APIs). Keep a consent audit trail.

## Reliability & performance

- Fire conversion sends **async** off the request path (queue) — never block checkout on an ad pixel.
- Batch where supported; retry 5xx/429 with backoff; CAPI/GA4 failures must not fail the order.
- Idempotency: stable `event_id`/`messageId` per business event so retries dedupe.
- Watch for **duplicate revenue** from pixel+server without a shared id (the classic 2× ROAS bug).

## Multi-tenant

- Per-tenant write keys/pixel ids/consent config; never cross-send one tenant's events to another's
  destination. Encrypt destination secrets (oauth skill).

## Testing & observability

- Meta **Test Events** tool + payload helper; GA4 DebugView; Segment source debugger.
- Validate dedup: fire pixel + server for one order, confirm one conversion at the destination.
- Metrics: `events_sent_total{destination,result}`, `capi_emq`, `dedup_rate`, `consent_blocked_total`,
  queue lag.

## Anti-patterns

- Client-only tracking (ad blockers/ITP eat conversions).
- Pixel + server with no shared `event_id` → double-counted conversions.
- Sending raw (unhashed) PII to ad platforms.
- Ignoring consent / Consent Mode v2 (regulatory + platform policy risk).
- Blocking the user request on analytics/ad sends.

## i18n

Send `currency` per locale (AED/SAR/EUR), localize value/units, and respect regional privacy regimes
(GDPR, UAE PDPL, CCPA) — consent UX and lawful basis differ by market.

## Agent checklist

```
- [ ] Server-side sends via CDP; async off the request path
- [ ] Shared event_id across pixel + server (dedup); GA4 client_id matches gtag
- [ ] PII SHA-256 hashed (lowercased/trimmed) for Meta/Google user_data
- [ ] Consent Mode v2 / CMP gating; DSAR suppression propagated
- [ ] Retries on 5xx/429; analytics failure never fails the order
- [ ] Per-tenant keys; destination secrets encrypted
```

## References

- Meta Conversions API: https://developers.facebook.com/docs/marketing-api/conversions-api · dedup: https://developers.facebook.com/docs/marketing-api/conversions-api/deduplicate-pixel-and-server-events
- GA4 Measurement Protocol: https://developers.google.com/analytics/devguides/collection/protocol/ga4
- Google enhanced conversions: https://developers.google.com/google-ads/api/docs/conversions/enhanced-conversions/web
- Segment HTTP/Node: https://segment.com/docs/connections/sources/catalog/libraries/server/node/ · Consent Mode v2: https://developers.google.com/tag-platform/security/guides/consent

## Related

`analytics-master` (PostHog, flags, deep analytics), `integrations-architecture-foundation`,
`integrations-commerce-shopify-woocommerce`
