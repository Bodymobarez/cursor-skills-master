---
name: integrations-ipaas-n8n-zapier
description: >-
  Staff-level iPaaS: build Zapier/Make/n8n/Workato connectors (REST Hooks vs polling, performSubscribe/
  Unsubscribe/perform/performList, dedup, 410 cleanup, expiration resubscribe), expose your product AS
  an integration platform (trigger/action catalog + OAuth app), embed n8n for tenant workflows, and
  decide iPaaS vs native adapter. Prefer REST Hooks over polling; build OAuth, not API-key-only.
---

# iPaaS: Zapier, Make, n8n & Workato

**Mandate: ship REST Hooks (instant, push) over polling, and expose OAuth — not just an API key — if
you want enterprise installs.** Polling triggers hammer your API every 1–15 min per Zap for data that
rarely changed; REST Hooks fire in near-real-time and cut load by orders of magnitude.

## Decision — iPaaS vs native adapter

| Build on iPaaS | Build a native adapter |
|----------------|------------------------|
| Internal ops glue, low volume | Core product feature, brand-critical path |
| Ship 50 integrations fast (long tail) | High-volume / strict SLA / custom logic |
| Non-engineers own the flow | Needs your domain rules, transactions, retries |
| "Connect to anything" marketing checkbox | Latency/consistency guarantees matter |

Most products do **both**: native adapters for the top 5 integrations that drive revenue; an iPaaS
presence (esp. a public Zapier app) for the long tail you'll never staff.

## Two trigger types (and why hooks win)

| | Polling | REST Hook (instant) |
|-|---------|---------------------|
| Mechanism | Zapier calls `performList` every 1–15 min | Your app POSTs to a per-Zap `targetUrl` |
| Latency | minutes | seconds |
| Your API load | constant, mostly wasteful | only on real events |
| Setup | `performList` + dedup by id | `performSubscribe`/`performUnsubscribe` + `perform` |

## Building a Zapier REST Hook trigger (Platform CLI)

```js
// triggers/new_order.js
module.exports = {
  key: "new_order", noun: "Order",
  display: { label: "New Order", description: "Fires when an order is created." },
  operation: {
    type: "hook",
    // Called when a Zap turns ON: store bundle.targetUrl, return id + data for unsubscribe (201)
    performSubscribe: (z, bundle) =>
      z.request({ url: "https://api.acme.com/zapier/subscribe", method: "POST",
        body: { url: bundle.targetUrl, event: "order.created", tenant: bundle.authData.tenant_id } })
       .then((r) => r.data),                       // { id } stored in bundle.subscribeData
    // Called when the Zap turns OFF: delete the subscription using stored data
    performUnsubscribe: (z, bundle) =>
      z.request({ url: `https://api.acme.com/zapier/subscribe/${bundle.subscribeData.id}`, method: "DELETE" }),
    // Called for EACH payload your app POSTs to targetUrl — parse + return an ARRAY
    perform: (z, bundle) => [bundle.cleanedRequest],
    // Sample data + polling fallback for the Zap editor
    performList: (z) => z.request({ url: "https://api.acme.com/orders?limit=3" }).then((r) => r.data),
    sample: { id: 1, total: "99.00", currency: "AED" },
  },
};
```

On your side: store each `(targetUrl, event, tenant)`; on the event, POST the payload to every matching
`targetUrl`. If Zapier returns **410 Gone**, the Zap is off — delete the subscription. Some APIs require
an `expiration_date` (ISO8601) in the subscribe response so Zapier auto-resubscribes before it lapses.
Polling triggers must **dedup by a stable `id`** (Zapier dedupes on it).

## Make (Integromat) / n8n / Workato

- **Make**: HTTP/webhook modules + visual scenarios; build a custom app with connections (OAuth) +
  modules. Similar trigger model to Zapier.
- **n8n**: open-source, **self-hostable**; a Webhook node calls your API. You can **embed n8n as the
  workflow engine for your own tenants** (credentials live in n8n's encrypted store). Great for
  white-label automation inside your product.
- **Workato / Tray.io**: enterprise iPaaS (governance, recipes); connectors via their SDK; common in
  large B2B where security review matters.

## Expose YOUR product as an integration platform

If you want to be the thing others connect to:
- **OAuth 2.1 app** (not just API keys) so users authorize without sharing secrets — see
  `integrations-oauth-api-keys`. API-key-only severely limits enterprise adoption.
- A **trigger/action catalog**: stable, versioned endpoints; document inputs/outputs/sample payloads.
- **REST Hook subscribe/unsubscribe** endpoints; per-subscription delivery with retries + signing.
- Publish rate limits and pagination. Treat partner traffic as multi-tenant (token bucket per app).
- **2026 angle**: also expose an **MCP server** so AI agents can call your tools directly — increasingly
  a peer to Zapier as a distribution channel (see `ai-mcp-master`).

## Reliability & security

- Deliveries to `targetUrl` are outbound webhooks — sign them, retry with backoff, DLQ + replay
  (see `integrations-webhooks-events`).
- SSRF-guard any user/iPaaS-supplied URL; the `targetUrl` is provider-controlled but validate scheme/host.
- Encrypt stored connection credentials; scope partner OAuth tokens minimally; rotate connector secrets.
- Idempotency: include an event id so downstream Zaps/recipes can dedupe.

## Testing & observability

- Zapier CLI: `zapier test`, `zapier validate`, push a private version and test live before promoting.
  Changing trigger type is **breaking** — ship a `_v2` trigger and hide the old one.
- Metrics: active subscriptions, delivery success rate, `410_cleanup_total`, resubscribe count,
  partner rate-limit hits.

## Anti-patterns

- Polling when REST Hooks are available (wasteful, slow, rate-limit pressure).
- API-key-only auth for a public connector (blocks enterprise).
- Not cleaning up on 410 → posting forever to dead Zaps.
- No dedup id on polling triggers → duplicate Zap runs.
- Mutating an existing trigger's type/key in place (breaks every user's Zap) — version instead.

## Agent checklist

```
- [ ] REST Hooks (subscribe/unsubscribe/perform) over polling where possible
- [ ] Store targetUrl per Zap; delete on 410; honor expiration/resubscribe
- [ ] Polling fallback (performList) returns dedupable, id-stable samples
- [ ] Outbound deliveries signed + retried + DLQ; SSRF-guarded
- [ ] Public connector exposes OAuth 2.1 (+ optional MCP), versioned trigger/action catalog
- [ ] Connector changes shipped as new versions, not in-place type changes
```

## References

- Zapier REST Hooks (CLI): https://docs.zapier.com/integrations/build/cli-hook-trigger · Platform: https://docs.zapier.com/platform
- Make apps: https://developers.make.com · n8n: https://docs.n8n.io · Workato connector SDK: https://docs.workato.com/developing-connectors/sdk.html

## Related

`integrations-webhooks-events`, `integrations-oauth-api-keys`, `integrations-architecture-foundation`,
`ai-mcp-master` (expose tools to AI agents via MCP)
