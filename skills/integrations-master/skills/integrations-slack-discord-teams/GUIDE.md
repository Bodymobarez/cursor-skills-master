---
name: integrations-slack-discord-teams
description: >-
  Staff-level chat-platform integration: Slack v0 request signing + 3-second ACK / response_url,
  Block Kit, Events API vs Socket Mode, Discord Ed25519 interactions + deferred responses, Teams
  Graph / Bot Framework / Adaptive Cards, OAuth installs with per-workspace bot tokens, and
  rate-limit-aware posting. Verify every request; ACK fast; do work async.
---

# Slack, Discord & Microsoft Teams

**Mandate: every inbound request is signed — verify it on the raw body — and you have ~3 seconds to
ACK, so defer the real work.** Slack/Discord both fail your app if you compute a response inline.
Post with a bot token; verify with a *separate* signing secret/public key. Don't conflate the two.

## Decision — Slack interaction model

| Surface | Mechanism | ACK rule |
|---------|-----------|----------|
| Bot posts/reads | `chat.postMessage` (bot token `xoxb-`) | n/a |
| Slash command `/deploy` | HTTP POST to your URL | respond ≤3s or use `response_url` (30 min, 5 uses) |
| Events (`app_mention`, `message`) | Events API (signed POST) **or** Socket Mode (WS) | return 200 ≤3s, process async |
| Buttons/modals | Interactivity payload (signed) | `ack()` immediately, then update |
| One-way notify | Incoming webhook URL | no OAuth, single channel |

Socket Mode (WebSocket) avoids exposing a public URL — great for internal tools/dev; HTTP + Events API
is the scalable production default.

## Slack — verify (v0) then ACK

```ts
// X-Slack-Signature = "v0=" + HMAC-SHA256(signingSecret, `v0:{ts}:{rawBody}`); reject ts > 5 min old
import { createHmac, timingSafeEqual } from "crypto";
export function verifySlack(raw: Buffer, sig = "", ts = "", secret: string) {
  if (Math.abs(Date.now() / 1000 - Number(ts)) > 300) return false;     // replay defense
  const expected = "v0=" + createHmac("sha256", secret).update(`v0:${ts}:${raw}`).digest("hex");
  return sig.length === expected.length && timingSafeEqual(Buffer.from(sig), Buffer.from(expected));
}
```

```ts
import { WebClient } from "@slack/web-api";
const slack = new WebClient(workspaceBotToken);                         // per-workspace, from OAuth install
await slack.chat.postMessage({ channel: "C123",
  text: "Deploy v1.4.2 succeeded",                                      // text = notification fallback
  blocks: [{ type: "section", text: { type: "mrkdwn", text: "*Deploy* :white_check_mark: `v1.4.2`" } }] });
```

Slash command can't finish in 3s? Return 200 immediately, then POST the result to `payload.response_url`.
URL verification: Events API first sends `{type:"url_verification", challenge}` — echo `challenge`.

## Discord — Ed25519 (asymmetric, not HMAC) + deferred responses

```ts
import nacl from "tweetnacl";
// verify {timestamp}{rawBody} against your app PUBLIC KEY (Developer Portal). No shared secret.
const ok = nacl.sign.detached.verify(
  Buffer.concat([Buffer.from(req.headers["x-signature-timestamp"]), raw]),
  Buffer.from(req.headers["x-signature-ed25519"], "hex"),
  Buffer.from(process.env.DISCORD_PUBLIC_KEY!, "hex"));
if (!ok) return new Response("invalid", { status: 401 });
const i = JSON.parse(raw.toString());
if (i.type === 1) return Response.json({ type: 1 });                    // PING handshake
// work will take >3s? defer, then PATCH the original response via the webhook later
return Response.json({ type: 5 });                                      // DEFERRED_CHANNEL_MESSAGE_WITH_SOURCE
```

Bots use Gateway (WS) for live events or REST for sending. `discord-interactions` ships a
`verifyKeyMiddleware`. Slash commands are registered via the application-commands API.

## Microsoft Teams

| Need | Use |
|------|-----|
| Post to a channel programmatically | **Graph** `/teams/{id}/channels/{id}/messages` (org consent) |
| Rich interactive bot | **Bot Framework** + **Adaptive Cards** |
| Simple inbound notify | Incoming webhook connector (legacy; being phased toward Workflows/Power Automate) |

Teams channel-message change notifications need a Graph subscription with a short expiry +
`lifecycleNotificationUrl` (see `integrations-google-microsoft`).

## Common patterns

| Pattern | Stack |
|---------|-------|
| Alert on error | Sentry → worker → `chat.postMessage` (dedupe by fingerprint) |
| Approval flow | Block Kit buttons → signed interactivity → `ack()` → update message in place |
| Daily digest | Cron → aggregate → single threaded message (avoid N posts) |
| ChatOps `/deploy` | Slash cmd → verify → 200 → CI dispatch → `response_url` result |

## Rate limits & scale

- Slack: per-method tiers (Web API) + ~1 msg/sec/channel sustained; honor `Retry-After` on 429.
- Discord: per-route buckets via `X-RateLimit-*` + a global limit; the SDK queues for you — don't bypass it.
- Multi-workspace/guild: store a bot token **per install** (OAuth `v2.access`), token-bucket per
  workspace, and never reuse one workspace's token for another.

## Security

- Signing secret / public key ≠ bot token — store both, rotate independently.
- Scope OAuth to the minimum bot scopes; request user-token scopes only when acting as a user.
- Don't log message content with PII; redact tokens.
- Verify before parsing; SSRF-guard any user-provided webhook URLs you store.

## i18n

Localize message copy by the team/user locale (Slack `users.info` → `locale`; Discord interaction
`locale`). Keep emoji/right-to-left aware formatting; Block Kit/Adaptive Cards render RTL when content is.

## Testing & observability

- Slack: ngrok + a dev workspace; replay payloads from the request log. Signature unit tests
  (valid/tampered/stale).
- Discord: register a test app, use the "Interactions Endpoint URL" validation (it sends a PING).
- Metrics: `slack_post_total{result}`, `signature_fail_total`, `ack_latency_p95` (must be < 3s),
  `rate_limited_total`.

## Anti-patterns

- Computing the response inline and blowing the 3s window (use `response_url`/deferred).
- Using `crypto.createHmac` for Discord (it's Ed25519 — will never match).
- Parsing the body before verifying (breaks Slack/Discord signatures).
- One global bot token across workspaces.
- Posting N messages where one threaded/updated message suffices (rate-limit + noise).

## Agent checklist

```
- [ ] Slack v0 verified on raw body, ts ≤5 min; Discord Ed25519 against public key; PING/challenge handled
- [ ] ACK ≤3s; heavy work via response_url / deferred / worker
- [ ] Per-workspace/guild bot token from OAuth install; token-bucket per workspace
- [ ] Signing secret/public key stored separately from bot token; both rotatable
- [ ] Block Kit/Adaptive Cards with text fallback; locale-aware copy
- [ ] Rate limits (Retry-After / X-RateLimit-*) honored
```

## References

- Slack verifying requests: https://docs.slack.dev/authentication/verifying-requests-from-slack · Block Kit: https://api.slack.com/block-kit
- Discord interactions: https://discord.com/developers/docs/interactions/receiving-and-responding
- Teams Graph messages: https://learn.microsoft.com/en-us/graph/api/channel-post-messages · Adaptive Cards: https://adaptivecards.io

## Related

`integrations-webhooks-events`, `integrations-google-microsoft` (Teams/Graph), `communications-master`,
`debugging-master`
