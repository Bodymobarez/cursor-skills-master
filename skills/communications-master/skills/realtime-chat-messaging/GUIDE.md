---
name: realtime-chat-messaging
description: >-
  Build advanced real-time chat & messaging. Use for in-app chat, DMs, group/
  channel chat, live support chat, presence, typing indicators, delivery/read
  receipts, reactions, attachments, and message history. Covers WebSocket
  architecture, data model, scaling/fan-out, ordering, offline sync, and security.
---

# Real-Time Chat & Messaging

Build production chat: 1:1, groups, channels, and live-support chat — with presence, receipts,
typing, and reliable delivery.

## Transport & architecture

```
Client ⇄ WebSocket (Socket.IO / native WS / SSE fallback) ⇄ Gateway
Gateway ⇄ Pub/Sub (Redis / NATS / Kafka) ⇄ other gateway nodes  (horizontal scale)
Persistence: Postgres (messages) + Redis (presence, recent, rate limits)
```
- **WebSocket** for bi-directional; fall back to SSE/long-poll. Managed options: **Pusher,
  Ably, Supabase Realtime, PubNub, Stream Chat, Twilio Conversations** (buy vs build).
- Scale across nodes with a **Pub/Sub backplane** so a message on node A reaches sockets on node B.

## Data model

```
Conversation (type[dm|group|channel|support], title, member_count, last_message_at)
 └─ Member (conversation_id, user_id, role, last_read_at, muted, joined_at)
Message (id[sortable: ULID/snowflake], conversation_id, sender_id, body, type[text|image|file|system],
         attachments[], reply_to, created_at, edited_at, deleted_at, client_msg_id)
Receipt (message_id, user_id, delivered_at, read_at)
Reaction (message_id, user_id, emoji)
```
- Use **sortable IDs** (ULID/Snowflake) for stable ordering without clock issues.
- `client_msg_id` enables **idempotent send** + optimistic UI dedupe.

## Core features (do them right)

- **Delivery & read receipts**: `delivered` on socket ack/persist; `read` via `last_read_at` per
  member (compute unread counts from it — cheaper than per-message flags).
- **Typing indicators**: ephemeral events (don't persist); debounce + auto-expire (~5s).
- **Presence**: online/away/offline in Redis with heartbeat + TTL; broadcast to conversation members.
- **Ordering & history**: server assigns order; **cursor/keyset pagination** (before/after id),
  never OFFSET on big tables.
- **Offline sync**: client stores last_seen cursor → on reconnect, fetch missed messages; queue
  outbound while offline and flush (idempotent via client_msg_id).
- **Optimistic UI**: render immediately with temp id → reconcile on server ack.
- Reactions, replies/threads, edit/delete (soft), mentions, attachments (presigned upload to S3).

## Reliability
- ACK every send; retry unacked; dedupe by client_msg_id.
- At-least-once delivery + idempotent apply on client.
- Reconnect with backoff; resume subscriptions + replay missed via cursor.
- Backpressure/rate-limit per connection; cap message size; validate/scan attachments.

## Security
- AuthN the socket (JWT on connect); authorize per conversation membership on every event.
- Sanitize message content (XSS); signed/expiring attachment URLs; per-room access checks.
- Optional E2E encryption for private DMs (Signal protocol / libsodium) if required.
- Audit + moderation hooks (profanity, spam, report/block).

## Checklist
```
- [ ] WebSocket gateway + Pub/Sub backplane (or managed: Ably/Pusher/Stream)
- [ ] Conversation/Member/Message/Receipt/Reaction model; sortable IDs
- [ ] Idempotent send (client_msg_id) + optimistic UI + ACK/retry
- [ ] Receipts (delivered/read via last_read_at), typing (ephemeral), presence (Redis+TTL)
- [ ] Keyset pagination + offline reconnect/replay
- [ ] Attachments via presigned URLs; XSS sanitization
- [ ] Socket auth + per-conversation authorization; rate limits
```

## Anti-patterns
- Polling a DB for "new messages" instead of push (load + latency).
- OFFSET pagination on huge message tables; per-message read flags for every user.
- No Pub/Sub backplane → chat breaks across multiple server instances.
- Persisting typing events; no debounce/expiry.
- Trusting client ordering/timestamps; no idempotency → dupes on retry.
