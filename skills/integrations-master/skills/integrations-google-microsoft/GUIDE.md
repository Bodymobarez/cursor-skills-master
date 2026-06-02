---
name: integrations-google-microsoft
description: >-
  Staff-level Google Workspace + Microsoft 365 integration: OAuth scopes & incremental sync (Gmail
  history, Drive/Calendar syncToken), Google push via Pub/Sub watch, Microsoft Graph change-notification
  subscriptions (validationToken echo, clientState, lifecycleNotificationUrl, reauthorization, expiry
  limits), delta queries, service accounts / domain-wide delegation, and renewal jobs.
---

# Google Workspace & Microsoft 365

**Mandate: never full-scan a mailbox or calendar — use the provider's incremental tokens (Gmail
`historyId`, Drive/Calendar `syncToken`, Graph `delta`) and renew push subscriptions before they
expire.** These APIs throttle hard; a naive poller burns quota and gets your app rate-limited within
the hour.

## Decision — push vs delta vs full sync

| Need | Google | Microsoft Graph |
|------|--------|-----------------|
| Real-time change push | Gmail watch → **Pub/Sub**; Drive `changes.watch` | **subscription** (change notifications/webhook) |
| Incremental pull | `history.list(startHistoryId)`, `changes.list(pageToken)` | **delta query** (`/delta` + `@odata.deltaLink`) |
| First load / repair | full list, then store the token | full list, then store the deltaLink |
| Enterprise, no user UI | **service account + domain-wide delegation** | app-only token + admin consent |

Push tells you *something changed*; you then **delta-pull** the actual changes. Treat push as a
hint, never as the full payload.

## Google — auth & scopes

| Product | Scope (least-priv) | Tasks |
|---------|-------------------|-------|
| Gmail | `gmail.readonly`, `gmail.send`, `gmail.modify` | read/send/label |
| Drive | `drive.file` (only files your app touches) | upload/export |
| Calendar | `calendar.events` | sync meetings |
| Sheets | `spreadsheets` | report export |

```ts
import { google } from "googleapis";
const auth = new google.auth.OAuth2(clientId, clientSecret, redirectUri);
auth.setCredentials({ refresh_token });                          // googleapis auto-refreshes access
const cal = google.calendar({ version: "v3", auth });

// Incremental calendar sync — store nextSyncToken; reuse it next run
let pageToken: string | undefined, syncToken = await loadSyncToken(integrationId);
do {
  const { data } = await cal.events.list({ calendarId: "primary",
    syncToken, pageToken });                                     // 410 GONE → token expired, full resync
  for (const ev of data.items ?? []) await upsertEvent(ev);      // ev.status==='cancelled' = delete
  pageToken = data.nextPageToken ?? undefined;
  if (data.nextSyncToken) await saveSyncToken(integrationId, data.nextSyncToken);
} while (pageToken);
```

**Gmail push**: `users.watch({ topicName })` → Gmail publishes to Pub/Sub on change; your subscriber
gets a `historyId`, then call `history.list(startHistoryId)`. **`watch` expires ~7 days — renew daily.**
**Service account / domain-wide delegation** only for Workspace-wide automation (impersonate users in
the domain); request the narrowest scopes the admin will approve.

## Microsoft Graph — change-notification subscriptions (verified detail)

```
Base: https://graph.microsoft.com/v1.0/   Auth: Entra ID OAuth (delegated or app-only + admin consent)
```

Create a subscription; Graph immediately POSTs a **validation handshake** you must echo within ~10s.

```ts
// 1. create subscription
await graph.post("/subscriptions", {
  changeType: "created,updated",
  notificationUrl: "https://api.acme.com/webhooks/graph",
  lifecycleNotificationUrl: "https://api.acme.com/webhooks/graph-lifecycle",  // strongly recommended
  resource: "/users/{id}/messages",
  expirationDateTime: new Date(Date.now() + 60 * 60 * 1000).toISOString(),    // ≤ resource max
  clientState: process.env.GRAPH_CLIENT_STATE,                                 // secret, ≤128 chars
});

// 2. validation handshake — echo the token as text/plain, 200
export async function POST(req: Request) {
  const token = new URL(req.url).searchParams.get("validationToken");
  if (token) return new Response(token, { status: 200, headers: { "content-type": "text/plain" } });
  const body = await req.json();
  for (const n of body.value) {
    if (n.clientState !== process.env.GRAPH_CLIENT_STATE) return new Response("bad", { status: 202 });
    await queue.enqueue("graph-events", n);                                    // n.resource → delta-pull
  }
  return new Response(null, { status: 202 });                                  // 202 within seconds
}
```

**Expiry limits (renew before they hit):** mail/events/todo ≈ **4230 min (~3 days)**, Teams chat
messages ≈ **60 min** (and require a `lifecycleNotificationUrl` if > 1h). Run a renewal job at ~75% of
lifetime. **Lifecycle events** — `reauthorizationRequired` (re-auth the endpoint token),
`subscriptionRemoved` (recreate), `missed` (do a delta-pull to backfill). Graph retries deliveries up
to 4 hours. Notifications are **sparse** (ids only) unless you use rich/encrypted notifications
(`includeResourceData` + `encryptionCertificate`, and validate the `validationTokens` JWTs).

| Graph resource | Path |
|----------------|------|
| Me / user | `/me`, `/users/{id}` |
| Mail | `/me/messages`, `/me/mailFolders/{id}/messages/delta` |
| Calendar | `/me/events`, `/me/calendarView/delta` |
| OneDrive/SharePoint | `/me/drive/root/delta` |
| Teams channel message | `/teams/{id}/channels/{id}/messages` |

## Sync semantics & gotchas

- **Tombstones**: deletes arrive as `status:'cancelled'` (Google) or `@removed` (Graph) — handle them
  or you'll keep ghosts.
- **Token expiry**: Google returns **410 GONE** → discard token, full resync. Graph delta links don't
  expire but the subscription does.
- **Clock skew** on Entra app tokens → back-date `iat`; refresh app token independently of the
  subscription (lifecycles differ — that's what `reauthorizationRequired` is for).
- **Throttling**: both return 429 + `Retry-After`; Graph also emits `RateLimit-*`. Batch Graph calls
  via `$batch` (≤20 per request).

## Security

- Least-privilege scopes; `drive.file` over `drive` whenever possible.
- `clientState` is your "did this come from Graph" check — keep it secret, compare every notification.
- Validate Graph rich-notification `validationTokens` against `login.microsoftonline.com` keys; reject
  expired/wrong-audience tokens.
- Store refresh tokens encrypted per tenant (see oauth skill); admin-consent app-only tokens are
  org-wide — guard them.

## Testing & observability

- Graph: dev tenant + `https://developer.microsoft.com/graph/graph-explorer`; ngrok for the validation
  handshake. Google: test Workspace + Pub/Sub emulator.
- Metrics: `subscription_active`, `subscription_renew_fail`, `sync_token_reset_total` (410s),
  `graph_throttle_total`, delta lag.
- Alert on subscriptions nearing expiry without renewal.

## Anti-patterns

- Polling `messages.list`/full calendar instead of history/delta tokens.
- Ignoring the Graph validation handshake (subscription never activates).
- Letting `watch`/subscription expire (silent: changes just stop arriving).
- Treating sparse Graph notifications as the full resource (you must fetch).
- Requesting `Mail.ReadWrite`/`drive` broad scopes when `.file`/`.Read` suffices.

## Agent checklist

```
- [ ] Incremental sync via historyId/syncToken/delta; full scan only on first load or 410
- [ ] Google watch / Graph subscription renewed before expiry (job at ~75% lifetime)
- [ ] Graph validationToken echoed text/plain 200; clientState verified on every notification
- [ ] Lifecycle events handled: reauthorizationRequired / subscriptionRemoved / missed → backfill
- [ ] Tombstones (cancelled/@removed) applied; least-priv scopes; refresh tokens encrypted
```

## References

- Graph change notifications: https://learn.microsoft.com/en-us/graph/change-notifications-delivery-webhooks
- Graph lifecycle + expiry table: https://learn.microsoft.com/en-us/graph/api/resources/subscription
- Gmail push: https://developers.google.com/workspace/gmail/api/guides/push · Calendar sync: https://developers.google.com/workspace/calendar/api/guides/sync
- Drive changes: https://developers.google.com/workspace/drive/api/guides/manage-changes

## Related

`integrations-oauth-api-keys`, `integrations-webhooks-events`, `integrations-slack-discord-teams` (Teams),
`google-sign-in` (backend-api-master)
