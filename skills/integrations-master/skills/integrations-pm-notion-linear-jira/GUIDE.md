---
name: integrations-pm-notion-linear-jira
description: >-
  Staff-level project-management integration: Linear GraphQL + Linear-Signature webhooks, Jira Cloud
  REST v3 + 3LO OAuth/Connect, Notion's 2026 API webhooks (verification_token + X-Notion-Signature)
  with sparse-payload follow-up, Asana/Monday/ClickUp, and loop-safe bi-directional sync with an
  external↔internal mapping table and origin tagging.
---

# PM Tools: Jira, Linear, Notion & More

**Mandate: two-way sync without an `external_id ↔ internal_id` mapping table and an origin tag is an
infinite echo loop waiting to fire.** Decide a conflict policy *before* writing code, ignore events
you originated, and make every write an idempotent upsert keyed by the mapping.

## Decision — API shape & change feed

| Tool | API | Auth | Change feed |
|------|-----|------|-------------|
| **Linear** | GraphQL | OAuth (`admin` scope) or API key | Webhooks (`Linear-Signature` HMAC) |
| **Jira Cloud** | REST v3 | 3LO OAuth / Connect (JWT) / API token | Webhooks (Connect-signed or registered) |
| **Notion** | REST | integration token / OAuth | **API webhooks (2026)** + automation webhooks |
| **Asana** | REST | OAuth/PAT | Webhooks (X-Hook-Secret handshake) |
| **Monday** | GraphQL | OAuth/token | Webhooks |
| **ClickUp** | REST | OAuth/token | Webhooks (signature) |

## Linear (developer-first, GraphQL)

```ts
// create issue
const r = await fetch("https://api.linear.app/graphql", { method: "POST",
  headers: { Authorization: apiKeyOrBearer, "Content-Type": "application/json" },
  body: JSON.stringify({ query: `mutation($i: IssueCreateInput!){ issueCreate(input:$i){ issue{ id identifier url } } }`,
    variables: { i: { teamId, title, description } } }) });
```

Webhooks: `Linear-Signature` = hex HMAC-SHA256 of the **raw body** (key = webhook signing secret),
plus `Linear-Delivery` (dedupe id) and `Linear-Event` (resource type). Reject if `body.webhookTimestamp`
is > 60s old. The `@linear/sdk` ships `LinearWebhookClient` that verifies + types handlers. GitHub link:
branch named `ENG-123` auto-links the PR.

## Jira Cloud (REST v3)

- Auth: **3LO OAuth 2.0** for user-context apps, **Connect (JWT)** or **Forge** for Marketplace apps,
  API token for scripts. Cloud base: `https://api.atlassian.com/ex/jira/{cloudId}/rest/api/3/`.
- Create issue `POST /rest/api/3/issue`; body uses **ADF** (Atlassian Document Format) for rich text.
- Webhooks: registered webhooks or Connect lifecycle; Connect requests carry a JWT (`qsh` query-string
  hash) you must validate. Map Epic → Story → your internal `work_item`; transitions go through
  `POST /issue/{key}/transitions` (you must look up valid transition ids, not set status directly).
- Pagination is `startAt`/`maxResults` (classic) or new token cursors on some endpoints — check the
  resource.

## Notion (2026 API webhooks)

Notion shipped real API webhooks in 2026 (API version `2026-03-01`). Setup is a one-time handshake:
Notion POSTs `{ verification_token }` to your URL; you paste it back into the integration dashboard.
That token becomes the HMAC key.

```ts
// every event: X-Notion-Signature: sha256=<hex HMAC-SHA256(verification_token, rawBody)>
const expected = "sha256=" + createHmac("sha256", verificationToken).update(raw).digest("hex");
if (!timingSafeEqual(Buffer.from(sig), Buffer.from(expected))) return res.status(401).end();
```

Payloads are **sparse** (ids + metadata) — fetch the full page/block via the API after verifying.
Limit ~50 subscriptions/integration; at-most-once delivery with ~24h retry. Pages must be shared with
the integration. (Automation webhooks are the no-code, unsigned variant for Zapier-style triggers.)

## Asana / Monday / ClickUp

- **Asana** webhooks use an `X-Hook-Secret` handshake (echo it once to establish), then `X-Hook-Signature`
  HMAC on events. **Monday** is GraphQL with webhook events. **ClickUp** signs webhooks with a secret.
- Universal pattern: store *your* record id in a custom field on their object for round-trip mapping.

## Loop-safe bi-directional sync (the core problem)

```ts
// mapping table: (provider, external_id) ↔ internal_id, last_synced_hash, last_origin
async function onExternalChange(ev: PmEvent) {
  if (ev.actor === OUR_BOT_ACCOUNT) return;                  // 1. ignore changes WE made (origin guard)
  const map = await mapping.find(ev.provider, ev.externalId);
  const hash = stableHash(normalize(ev.payload));
  if (map && map.lastSyncedHash === hash) return;            // 2. no-op if content unchanged (anti-echo)
  await applyToInternal(ev, map);                            // 3. idempotent upsert by mapping
  await mapping.upsert(ev.provider, ev.externalId, { lastSyncedHash: hash, lastOrigin: "external" });
}
```

**Conflict policy — pick one and document it:** last-write-wins by timestamp, field-level merge, or a
designated source-of-truth per field (e.g. "Jira owns status, we own priority"). Never leave it
implicit. Use a dedicated bot/service account so origin filtering is reliable.

## Rate limits & pagination

- Linear/Monday GraphQL: **complexity-based** budgets — request only fields you need; cursor paginate.
- Jira: per-tenant limits + `Retry-After`; Notion: ~3 req/sec average; ClickUp/Asana have per-token caps.
- Always cursor/`startAt` paginate; never assume a single page.

## Security & multi-tenant

- One credential per workspace/tenant, encrypted (oauth skill). Notion verification_token is shown
  once — store it securely; lose it and you must recreate the subscription.
- Verify every webhook on the raw body; dedupe by delivery id; SSRF-guard stored callback URLs.
- Least-priv: share only required Notion pages; minimal Jira/Linear scopes.

## Testing & observability

- Fixtures per provider; signature tests (valid/tampered/stale). Sandbox: free Linear/Jira/Notion dev
  workspaces; smee.io tunnel.
- Metrics: `sync_apply_total{direction}`, `echo_suppressed_total`, `mapping_miss_total`,
  `webhook_verify_fail_total`, conflict count.

## Anti-patterns

- No origin guard → infinite update ping-pong between systems.
- Hardcoding property/field names instead of a per-tenant field map.
- Treating sparse Notion payloads as full content.
- Setting Jira status directly instead of via valid transitions.
- Restringifying JSON before verifying Linear/Notion signatures.

## Agent checklist

```
- [ ] external_id ↔ internal_id mapping table; idempotent upserts
- [ ] Origin tag (bot account) + content-hash to suppress echo loops
- [ ] Explicit, documented conflict policy (LWW / field-owner / source-of-truth)
- [ ] Webhooks verified on raw body (Linear hex / Notion sha256= / Asana handshake), deduped
- [ ] Sparse payloads followed up via API; cursor pagination; Retry-After honored
- [ ] Per-tenant field map (no hardcoded property names)
```

## References

- Linear webhooks/SDK: https://linear.app/developers/webhooks · API: https://linear.app/developers
- Jira Cloud REST v3: https://developer.atlassian.com/cloud/jira/platform/rest/v3/ · Connect JWT: https://developer.atlassian.com/cloud/jira/platform/understanding-jwt-for-connect-apps/
- Notion webhooks: https://developers.notion.com/reference/webhooks · Asana webhooks: https://developers.asana.com/docs/webhooks

## Related

`integrations-github-gitlab-bitbucket`, `integrations-architecture-foundation`,
`integrations-sync-engine-cdc`, `integrations-webhooks-events`
