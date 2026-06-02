---
name: integrations-crm-salesforce-hubspot
description: >-
  Staff-level CRM integration: Salesforce JWT-bearer/Client-Credentials, REST + Bulk API 2.0, Platform
  Events/CDC, external-id upsert; HubSpot private-app/OAuth, batch upsert by idProperty, X-HubSpot-
  Signature-v3 webhooks, Search API; Pipedrive/Zoho/Dynamics. Upsert idempotently by external id,
  map fields per tenant, and respect the (low) rate limits with batch endpoints.
---

# CRM: Salesforce, HubSpot & Others

**Mandate: external systems own the identity — always upsert by *your* external id, never blind-create.**
CRMs are duplicate-magnets and have punishing rate limits. Batch everything, idempotent-upsert by a
stable external key, and keep a per-tenant field map; hardcoded property names are a future outage.

## Decision — auth & bulk strategy

| Need | Salesforce | HubSpot |
|------|-----------|---------|
| Server-to-server, no UI | **JWT-bearer** (cert) or **Client Credentials** | **Private app** access token |
| User-context / marketplace | Web Server (Auth Code + PKCE) | **OAuth** app |
| Large sync (10k+ rows) | **Bulk API 2.0** (async jobs, CSV) | **Batch** endpoints (≤100/req) |
| Real-time inbound | **Platform Events / Change Data Capture** (CometD/Pub-Sub API) | **Webhooks** (v3 signed) |

## Salesforce

**Auth (JWT-bearer, no secret on the wire):** sign an RS256 assertion → POST to the token endpoint →
use the returned `instance_url` as your API base. (Full JWT details in `integrations-oauth-api-keys`.)

```ts
// idempotent upsert by an EXTERNAL ID field — never duplicates, no pre-query
await fetch(`${instanceUrl}/services/data/v60.0/sobjects/Contact/External_Id__c/${externalId}`, {
  method: "PATCH",
  headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
  body: JSON.stringify({ FirstName: first, LastName: last, Email: email }),
});  // 201 created / 204 updated — atomic upsert keyed by External_Id__c
```

- **Bulk API 2.0** for large loads: create job → upload CSV → close → poll `state` (`JobComplete`) →
  fetch failed/successful results. Use `composite/sobjects` (≤200) for mixed mid-size writes.
- **Real-time**: Change Data Capture / Platform Events via the **Pub/Sub API** (gRPC) — durable, replayable
  by `replayId`; far better than legacy Streaming CometD for new builds.
- Objects: Lead, Contact, Account, Opportunity. SOQL for queries (`/query?q=`); watch governor limits.

## HubSpot

**Auth:** private-app token (single account) or OAuth (multi-account marketplace). CRM objects:
contacts, companies, deals, tickets.

```ts
// batch upsert by a unique property (idProperty) — idempotent, up to 100 per call
await fetch("https://api.hubapi.com/crm/v3/objects/contacts/batch/upsert", {
  method: "POST",
  headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
  body: JSON.stringify({ inputs: rows.map((r) => ({
    idProperty: "email", id: r.email, properties: { firstname: r.first, email: r.email } })) }),
});
```

- **Search API** (`/crm/v3/objects/contacts/search`) to find by property — but it's heavily rate-limited
  and eventually-consistent; prefer upsert-by-id over search-then-create.
- Webhooks: verify **`X-HubSpot-Signature-v3`** = base64 HMAC-SHA256 of `method + fullURL + rawBody +
  X-HubSpot-Request-Timestamp` (key = app client secret); timestamp is **milliseconds**, reject > 5 min.
  Events: `contact.creation`, `deal.propertyChange`, etc.

```ts
const base = "POST" + fullUrl + raw.toString("utf8") + tsMs;            // fullUrl incl. query string
const expected = createHmac("sha256", clientSecret).update(base, "utf8").digest("base64");
```

## Pipedrive / Zoho / Dynamics 365

- **Pipedrive/Zoho**: REST + token/OAuth; map pipeline stages to your funnel enum (config, not code).
- **Dynamics 365**: Dataverse Web API (OData) via Entra ID; `$batch` for bulk, change tracking for delta.

## Sync architecture

```
Signup → enqueue → HubSpot/SF upsert (external id) → store crm_id in mapping
CRM webhook deal.won/Opportunity ClosedWon → enqueue → upgrade subscription in your app
Nightly reconcile poll (modified-since) catches missed webhooks
```

Bi-directional? Apply the loop-safe pattern (origin tag + mapping + conflict policy) from
`integrations-pm-notion-linear-jira`. Reconciliation/backfill belongs in `integrations-sync-engine-cdc`.

## Field mapping (per tenant, never hardcoded)

```ts
// crm_field_map config per tenant: internal field → CRM property name
const map = { firstName: "firstname", plan: "subscription_tier__c" };   // SF custom fields end in __c
const properties = Object.fromEntries(Object.entries(input).map(([k, v]) => [map[k] ?? k, v]));
```

## Rate limits & performance

- **HubSpot**: ~per-app/sec burst + daily caps; 429 → honor `Retry-After`; **batch ≤100** to cut call
  count 100×. **Salesforce**: 24h API request allocation + per-transaction governor limits; Bulk 2.0
  for volume; `composite` to merge dependent writes into one round-trip.
- Cache rarely-changing metadata (pipelines, stages, custom-field schema) — don't fetch per record.

## Security & multi-tenant

- One credential per tenant, encrypted (oauth skill). SF JWT private key in KMS; HubSpot client secret
  doubles as the webhook signing key — guard it.
- Least scopes (HubSpot granular scopes; SF connected-app OAuth scopes + "admin pre-authorized").
- PII: minimize fields synced; honor consent/GDPR; don't sync more than the integration needs.

## Testing & observability

- Sandboxes: SF Developer Edition / scratch orgs; HubSpot test account. Bulk-job dry runs on a sample.
- Signature test the HubSpot v3 verifier (note ms timestamp + full URL incl. query).
- Metrics: `crm_upsert_total{result}`, `dedup_conflict_total`, `bulk_job_fail_rows`, `rate_limited_total`,
  `webhook_verify_fail_total`.

## Anti-patterns

- Create-without-upsert → duplicate contacts/leads (the #1 CRM data-quality bug).
- Single-record loops where a batch endpoint exists (instant rate-limit death).
- Search-then-create races (use upsert by id/idProperty).
- Hardcoded property API names (`firstname` vs `FirstName` vs `first_name`) across tenants.
- HubSpot v3 verify with seconds instead of ms, or omitting the query string from the URL.

## Agent checklist

```
- [ ] Upsert by external id / idProperty (idempotent, no dupes)
- [ ] Batch / Bulk API 2.0 / composite for volume; metadata cached
- [ ] SF JWT-bearer or Client Credentials; HubSpot private-app/OAuth; creds encrypted per tenant
- [ ] HubSpot X-HubSpot-Signature-v3 (base64, ms ts, full URL) verified on raw body
- [ ] Per-tenant field map; conflict policy for two-way sync; reconcile poll as safety net
- [ ] Rate limits + Retry-After honored; PII minimized
```

## References

- Salesforce REST: https://developer.salesforce.com/docs/atlas.en-us.api_rest.meta/api_rest/ · Bulk 2.0: https://developer.salesforce.com/docs/atlas.en-us.api_asynch.meta/api_asynch/ · Pub/Sub API: https://developer.salesforce.com/docs/platform/pub-sub-api/overview
- HubSpot CRM v3: https://developers.hubspot.com/docs/api/crm/understanding-the-crm · Webhook validation: https://developers.hubspot.com/docs/apps/developer-platform/build-apps/authentication/request-validation

## Related

`integrations-architecture-foundation`, `integrations-oauth-api-keys`, `integrations-sync-engine-cdc`,
`business-master` (crm-builder), `integrations-marketing-analytics`
