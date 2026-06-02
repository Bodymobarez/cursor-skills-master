---
name: realtime-chat-messaging
description: >-
  Production real-time chat at staff depth: a stateless WebSocket gateway over a Redis
  Pub/Sub (or Streams/Kafka) backplane, server-assigned total ordering, client-idempotent
  send, delivery/read receipts, presence with TTL, reconnect+replay, fan-out scaling,
  backpressure, and per-conversation authz. Build-vs-buy (Ably/Pusher/Stream) included.
  Use for in-app chat, DMs, group/channel chat, and live support chat.
---

# Real-Time Chat & Messaging — Production Architecture

**A chat system is a replicated, ordered log with a UI bolted on.** Get three things right —
**total ordering per conversation, idempotency on send, and fan-out across nodes** — and every
feature (receipts, reactions, threads, presence) is cheap product work on top. Get them wrong and
no amount of UI polish saves you: users see dupes, out-of-order messages, and "sent" spinners that
never resolve. **Push, never poll. Server assigns order, client supplies an idempotency key.**

---

## 1. When to use / when NOT

**Use** for: in-app 1:1 DMs, group/channel chat, live customer-support chat, collaborative presence
(who's online/typing), anything needing sub-second bidirectional delivery.

**Do NOT use this** for: fire-and-forget alerts to offline users → `push-notifications-advanced`;
email-style async threads → `email-integration-advanced`; WhatsApp/SMS as a channel →
`whatsapp-business-integration` / `voice-sms-telephony` (this skill is the *transport*, those are
*channels* that feed into it via `omnichannel-inbox-chatbot`).

**Build vs buy:** if chat is not your core differentiator and you have <2 backend engineers, **buy**
(Ably / Pusher / Stream / Supabase Realtime) — you get presence, history, and fan-out for free.
**Build** when you need data residency/ownership, custom moderation/E2EE, deep product integration,
or per-message cost control at >10M msg/day where managed pricing hurts.

---

## 2. Architecture (the only diagram that matters)

```
                    ┌───────────────── stateless gateway tier ─────────────────┐
  Client ⇄ WSS ⇄ LB │  gw-node-1        gw-node-2        gw-node-3  (autoscale) │
   (native WS,       │     ⇅                ⇅                ⇅                   │
    SSE fallback)    │  ───────────── Redis Pub/Sub backplane ──────────────────│  ← fan-out
                    └──────────────────────────┬───────────────────────────────┘
                                               │
        Redis (presence TTL, recent, ratelimit)│        Postgres (messages, durable log)
                                               │        Redis Streams / Kafka (replay, async)
                                    Object store (S3) for attachments via presigned URLs
```

- **Gateway is stateless**: any node can serve any user. A message published on node A must reach
  sockets on nodes B/C → that is the **backplane's** entire job.
- **Persistence is the source of truth** for ordering and history; the realtime layer is a cache +
  delivery mechanism. Never let "what's in memory" be the only copy of a message.

---

## 3. Decision matrices

**Transport**

| Transport | Direction | Reconnect | Binary | Use when |
|-----------|-----------|-----------|--------|----------|
| **WebSocket** ⭐ | bidirectional | manual (you build) | yes | Default for chat — typing, presence, low latency |
| **SSE** | server→client only | built-in (`Last-Event-ID`) | no (text) | Read-heavy feeds; send via plain POST; great over HTTP/2 |
| **Long-poll** | half-duplex | n/a | no | Last-resort fallback behind corporate proxies |

> SSE is underrated for **support chat** where the customer mostly receives: POST to send, SSE to
> receive, automatic reconnection with `Last-Event-ID` replay. Over HTTP/1.1 it eats a connection
> from the 6-per-origin budget — **serve it over HTTP/2** and the limit disappears.

**Fan-out backplane**

| Backplane | Durability | Replay | Ordering | Use when |
|-----------|-----------|--------|----------|----------|
| **Redis Pub/Sub** | none (fire-and-forget) | no | per-channel | Simplest; pair with Postgres for durability ⭐ default |
| **Redis Streams** | yes (capped) | yes (`XADD`/`XREAD`) | yes per stream | Want replay/at-least-once without Kafka |
| **NATS JetStream** | yes | yes | yes | Polyglot services, low-latency, lighter than Kafka |
| **Kafka** | yes (long retention) | yes | per-partition | Already on Kafka; analytics/event-sourcing at scale |

**Build vs buy**

| Option | You own | Best for |
|--------|---------|----------|
| **Self-host** (ws + Redis + PG) ⭐ | everything | Scale economics, custom moderation/E2EE, data residency |
| **Ably / Pusher** | nothing | Fast launch, global edge, presence built-in |
| **Stream / Sendbird / Twilio Conversations** | nothing | Turnkey chat UI + moderation + push, less code |
| **Supabase Realtime** | DB | Already on Supabase/Postgres; row-level realtime |

**Sortable message IDs**

| Scheme | Sortable | Distributed | Notes |
|--------|----------|-------------|-------|
| **ULID** ⭐ | lexicographic, ms-precision | yes | 26 chars, URL-safe, no coordination |
| **UUIDv7** | time-ordered (RFC 9562) | yes | Standard, great Postgres index locality |
| **Snowflake** | yes | needs worker IDs | Twitter-style; 64-bit int, compact |
| ❌ UUIDv4 / `created_at` | no / clock-skew | — | **Never** for ordering — random or skewed |

---

## 4. Production code (copy-paste quality)

### 4a. Data model (Postgres) — `last_read_at` is the key trick

```sql
create table conversations (
  id            uuid primary key default gen_random_uuid(),
  type          text not null check (type in ('dm','group','channel','support')),
  title         text,
  last_message_at timestamptz,
  created_at    timestamptz not null default now()
);

create table members (
  conversation_id uuid not null references conversations(id) on delete cascade,
  user_id         uuid not null,
  role            text not null default 'member',     -- member|admin|agent
  last_read_at    timestamptz not null default 'epoch',-- unread = messages after this
  muted           boolean not null default false,
  primary key (conversation_id, user_id)
);

create table messages (
  id              text primary key,                    -- ULID (sortable!)
  conversation_id uuid not null references conversations(id) on delete cascade,
  seq             bigint not null,                     -- per-conversation total order
  sender_id       uuid not null,
  type            text not null default 'text',        -- text|image|file|system
  body            text,
  attachments     jsonb not null default '[]',
  reply_to        text references messages(id),
  client_msg_id   text not null,                       -- idempotency key from client
  created_at      timestamptz not null default now(),
  edited_at       timestamptz,
  deleted_at      timestamptz,
  unique (conversation_id, client_msg_id)              -- ← idempotent send, enforced by DB
);
-- keyset pagination index (NEVER OFFSET on this table)
create index on messages (conversation_id, seq desc);
create index on messages (conversation_id, id desc);
```

`unique (conversation_id, client_msg_id)` makes idempotency a **database invariant**, not hopeful
app logic. A retried send collides and you return the existing row.

### 4b. Idempotent, totally-ordered send + fan-out

```ts
// send.ts — one durable write, then fan-out. Order is assigned by the DB, not the client.
import { ulid } from "ulid";
import { Pool } from "pg";
import { Redis } from "ioredis";

const pg = new Pool();
const pub = new Redis(process.env.REDIS_URL!);

export async function sendMessage(input: {
  conversationId: string; senderId: string; body: string; clientMsgId: string; replyTo?: string;
}) {
  const id = ulid();
  // Single statement: assign next seq atomically and dedupe by (conversation_id, client_msg_id).
  const { rows } = await pg.query(
    `with next as (
       select coalesce(max(seq), 0) + 1 as seq
       from messages where conversation_id = $1
     )
     insert into messages (id, conversation_id, seq, sender_id, body, client_msg_id, reply_to, created_at)
     select $2, $1, next.seq, $3, $4, $5, $6, now() from next
     on conflict (conversation_id, client_msg_id) do nothing
     returning id, seq, created_at`,
    [input.conversationId, id, input.senderId, input.body, input.clientMsgId, input.replyTo ?? null],
  );

  // Conflict → retry of an already-accepted send. Return the existing row; do NOT re-fan-out.
  const row = rows[0] ?? (await pg.query(
    `select id, seq, created_at from messages where conversation_id=$1 and client_msg_id=$2`,
    [input.conversationId, input.clientMsgId])).rows[0];

  await pg.query(`update conversations set last_message_at = now() where id = $1`, [input.conversationId]);

  const event = {
    type: "message.new",
    conversationId: input.conversationId,
    message: { id: row.id, seq: Number(row.seq), senderId: input.senderId, body: input.body,
               clientMsgId: input.clientMsgId, createdAt: row.created_at },
  };
  // Fan-out to every gateway node subscribed to this conversation channel.
  await pub.publish(`conv:${input.conversationId}`, JSON.stringify(event));
  return event.message; // client reconciles its optimistic temp message by clientMsgId
}
```

### 4c. WebSocket gateway — auth on connect, authz per event, backplane subscribe

```ts
// gateway.ts — native ws + ioredis. Stateless: scale to N nodes behind a TCP/HTTP LB.
import { WebSocketServer, WebSocket } from "ws";
import { Redis } from "ioredis";
import { verifyJwt } from "./auth";
import { isMember, sendMessage } from "./db";

const wss = new WebSocketServer({ noServer: true });
const sub = new Redis(process.env.REDIS_URL!);

// userId -> set of sockets (multi-device / multi-tab)
const sockets = new Map<string, Set<WebSocket>>();
// conversationId -> userIds present on THIS node (so we only handle relevant fan-out)
const localRooms = new Map<string, Set<string>>();

sub.psubscribe("conv:*");
sub.on("pmessage", (_pat, channel, payload) => {
  const convId = channel.slice("conv:".length);
  const local = localRooms.get(convId);
  if (!local) return;                          // no one here cares — skip
  const event = JSON.parse(payload);
  for (const uid of local)
    for (const ws of sockets.get(uid) ?? [])
      safeSend(ws, payload);                   // payload already serialized
});

// HTTP upgrade → authenticate the SOCKET before accepting it
export function handleUpgrade(req: any, socket: any, head: Buffer) {
  const token = new URL(req.url, "http://x").searchParams.get("token");
  const claims = token && verifyJwt(token);
  if (!claims) { socket.write("HTTP/1.1 401 Unauthorized\r\n\r\n"); socket.destroy(); return; }
  wss.handleUpgrade(req, socket, head, (ws) => onConnect(ws, claims.sub));
}

function onConnect(ws: WebSocket, userId: string) {
  const set = sockets.get(userId) ?? new Set(); set.add(ws); sockets.set(userId, set);
  let alive = true; ws.on("pong", () => (alive = true));
  const hb = setInterval(() => { if (!alive) return ws.terminate(); alive = false; ws.ping(); }, 30_000);

  ws.on("message", async (raw) => {
    let msg: any; try { msg = JSON.parse(raw.toString()); } catch { return; }
    if (!(await isMember(msg.conversationId, userId))) return;   // authz on EVERY event

    if (msg.op === "subscribe") {
      const r = localRooms.get(msg.conversationId) ?? new Set(); r.add(userId);
      localRooms.set(msg.conversationId, r);
    } else if (msg.op === "send") {
      // ack the client's optimistic message by clientMsgId; fan-out happens via backplane
      const saved = await sendMessage({ ...msg, senderId: userId });
      safeSend(ws, JSON.stringify({ type: "message.ack", clientMsgId: msg.clientMsgId, id: saved.id, seq: saved.seq }));
    }
  });

  ws.on("close", () => { clearInterval(hb); set.delete(ws);
    if (set.size === 0) for (const r of localRooms.values()) r.delete(userId); });
}

function safeSend(ws: WebSocket, data: string) {
  // BACKPRESSURE: never let a slow consumer balloon memory. Drop+disconnect if buffer is huge.
  if (ws.readyState !== WebSocket.OPEN) return;
  if (ws.bufferedAmount > 1_000_000) { ws.terminate(); return; }
  ws.send(data);
}
```

### 4d. Client hook — optimistic send, ACK reconcile, reconnect + replay

```ts
// useChat.ts — optimistic UI, idempotent retry, gap-free reconnect via last seq.
import { useEffect, useRef, useState } from "react";
import { ulid } from "ulid";

export function useChat(conversationId: string, token: string) {
  const [messages, setMessages] = useState<any[]>([]);
  const ws = useRef<WebSocket | null>(null);
  const lastSeq = useRef(0);
  const backoff = useRef(500);

  useEffect(() => {
    let stop = false;
    const connect = () => {
      const sock = new WebSocket(`wss://api.example.com/chat?token=${token}`);
      ws.current = sock;
      sock.onopen = async () => {
        backoff.current = 500;
        sock.send(JSON.stringify({ op: "subscribe", conversationId }));
        // REPLAY the gap we missed while disconnected (keyset, not offset)
        const missed = await fetch(`/api/conversations/${conversationId}/messages?after_seq=${lastSeq.current}`).then(r => r.json());
        if (missed.length) setMessages((m) => dedupe([...m, ...missed]));
      };
      sock.onmessage = (e) => {
        const ev = JSON.parse(e.data);
        if (ev.type === "message.new") { lastSeq.current = Math.max(lastSeq.current, ev.message.seq);
          setMessages((m) => dedupe([...m, ev.message])); }
        if (ev.type === "message.ack")  // replace optimistic temp with server id/seq
          setMessages((m) => m.map((x) => x.clientMsgId === ev.clientMsgId ? { ...x, id: ev.id, seq: ev.seq, pending: false } : x));
      };
      sock.onclose = () => { if (stop) return;
        const jitter = Math.random() * 300;                       // avoid reconnect thundering herd
        setTimeout(connect, Math.min(backoff.current *= 2, 15_000) + jitter); };
    };
    connect();
    return () => { stop = true; ws.current?.close(); };
  }, [conversationId, token]);

  const send = (body: string) => {
    const clientMsgId = ulid();                                   // idempotency key
    setMessages((m) => [...m, { clientMsgId, body, pending: true, seq: Number.MAX_SAFE_INTEGER }]); // optimistic
    ws.current?.send(JSON.stringify({ op: "send", conversationId, body, clientMsgId }));
  };
  return { messages: [...messages].sort((a, b) => a.seq - b.seq), send };
}

const dedupe = (arr: any[]) => {
  const seen = new Map(); for (const m of arr) seen.set(m.id ?? m.clientMsgId, m);
  return [...seen.values()];
};
```

---

## 5. Edge cases (where chat actually breaks)

- **Ordering:** trust **`seq`** (server-assigned, per-conversation), never client `created_at`.
  Render sorted by `seq`; optimistic messages use `MAX_SAFE_INTEGER` so they pin to the bottom until ACK.
- **Dedupe:** `(conversation_id, client_msg_id)` unique in DB + `dedupe()` on the client. A retried
  send is a no-op server-side and a reconcile client-side.
- **Delivery receipts:** mark `delivered` on durable persist + fan-out (not on TCP send). Mark `read`
  by advancing the member's `last_read_at`; **unread count = messages with `seq` after the reader's
  last-read seq** — one indexed query, not a per-message-per-user flag table.
- **Typing indicators:** ephemeral pub/sub only (**never persist**), debounce to 1 event / ~3s,
  auto-expire client-side after ~5s of silence.
- **Presence flapping:** Redis key `presence:{user}` with `SET ... EX 30` heartbeat; "offline" only
  after TTL lapse + a short grace, so a 2s blip doesn't toggle everyone's UI.
- **Multi-device:** a user has N sockets; fan-out to all, dedupe by `id`, and reconcile `last_read_at`
  as a max across devices.
- **Reconnect gap:** client keeps `lastSeq`; on reconnect it replays `after_seq=` via keyset — no
  missed messages, no full reload.

---

## 6. Performance (fan-out + connection scaling)

- **Fan-out is the cost center.** One message to a 10k-member channel = 1 publish → **10k socket
  writes**. Costs scale with *recipients*, not senders. For huge channels (>5–10k), shard the room
  across gateway nodes and/or switch big broadcast channels to a pull model (client fetches deltas).
- **Connections/node:** a tuned Node `ws` server holds ~50–100k idle sockets per node (raise
  `ulimit -n`, tune `net.ipv4.tcp_*`, ~1–2 KB/idle socket). Scale out horizontally; the backplane
  makes nodes interchangeable.
- **Don't touch the DB on the hot path** for reads: keep "recent N" messages and presence in Redis;
  hydrate history lazily with keyset pagination.
- **Batch receipts:** coalesce read-receipt updates (advance `last_read_at` once per ~1s burst), not
  one write per message.
- **HTTP/2 for SSE** to dodge the 6-connections-per-origin browser cap.

---

## 7. Security

- **AuthN the socket on connect** (JWT in the upgrade request — header or short-lived query token),
  and **re-authorize membership on every inbound event** (`isMember`). A valid token ≠ access to a
  given conversation.
- **Token expiry mid-session:** rotate via a `reauth` op; close sockets whose token TTL lapses.
- **XSS:** treat `body` as untrusted; sanitize/escape on render (never `dangerouslySetInnerHTML` raw).
- **Attachments:** presigned, short-TTL S3 URLs; validate content-type + size server-side; AV-scan
  before serving; never trust client-reported MIME.
- **Rate-limit per connection** (token bucket in Redis) and cap message size; reject oversized frames.
- **E2EE (optional):** for private DMs use **MLS (RFC 9420)** or the Signal protocol — server stores
  ciphertext only and cannot run server-side search/moderation on those rooms (a real trade-off).
- **Moderation hooks:** profanity/spam/abuse classification + report/block, with an audit trail.

---

## 8. Scale & reliability

- **Backplane is mandatory** the moment you run >1 gateway node — without it, users on different
  nodes can't see each other's messages.
- **Durability:** Pub/Sub is lossy; pair with Postgres (source of truth) and/or **Redis Streams**
  (`XADD` + consumer groups) for at-least-once async work (push, search indexing, webhooks).
- **Backpressure:** bound each socket's send buffer (`bufferedAmount` guard above); drop+disconnect
  slow consumers rather than OOM the node. Apply load-shedding under overload.
- **Idempotency everywhere:** at-least-once delivery + client-side dedupe by `id` = exactly-once
  *effect*. Never assume single delivery.
- **Sticky sessions:** native WS doesn't need them with a backplane; only Socket.IO's HTTP
  long-poll fallback does. Prefer native WS / `transports: ['websocket']` to avoid stickiness.
- **Graceful deploys:** drain — stop accepting upgrades, send a `reconnect` nudge, let clients
  reconnect to healthy nodes with jittered backoff.

---

## 9. Testing

- **Two-client integration test:** client A sends, assert client B receives in order within latency budget.
- **Idempotency:** send the same `client_msg_id` twice → exactly one row, one fan-out, both calls
  return the same `id`.
- **Ordering under concurrency:** fire 100 concurrent sends → assert `seq` is gap-free and monotonic.
- **Reconnect/replay:** kill the socket mid-stream, send 5 messages, reconnect → assert all 5 arrive
  via `after_seq` replay, none duplicated.
- **Load:** `k6`/`artillery` with a WS scenario or `autocannon`-style ws driver; measure p99
  publish→deliver latency and max stable connections/node before backpressure drops.

---

## 10. Observability

Track and alert on:
- `ws_connections` (gauge), `ws_connects/disconnects per sec`, **reconnect rate** (spike = bad deploy/LB).
- **Fan-out latency** publish→deliver p50/p99 (the number that *is* "is chat fast?").
- **Delivery success rate** and `messages_dropped_backpressure_total` (should be ~0).
- Send→ACK latency; idempotency-conflict rate (high = client retry storm).
- Presence accuracy (heartbeat misses), Redis backplane lag, per-node socket count for autoscaling.

---

## 11. i18n / RTL (Arabic)

- Message bodies are UTF-8; **set `dir="auto"` per message bubble** so a mixed Arabic+English thread
  renders each line correctly without a global flip. Wrap interpolations in Unicode bidi isolates
  (`\u2068 … \u2069`) to stop digits/links scrambling RTL text.
- Truncate by **grapheme** (`Intl.Segmenter`), not by `.slice()`, or you'll cut emoji/Arabic
  ligatures in half.
- System messages ("X joined") are **templated keys**, not concatenated strings — translate the
  template, interpolate names; never build sentences by string addition (word order differs in Arabic).
- Timestamps via `Intl.DateTimeFormat` with the user's locale + timezone, not hardcoded formats.

---

## 12. Anti-patterns

- **Polling the DB** for "new messages" instead of push — load + latency death spiral.
- **OFFSET pagination** on a hot messages table (it scans+discards); use keyset (`seq`/`id` cursor).
- **No backplane** with multiple nodes → chat silently breaks across instances.
- **Persisting typing events** / no debounce → write amplification and jittery UI.
- **Trusting client timestamps/order** or skipping `client_msg_id` → dupes on every retry.
- **Per-message-per-user read flags** instead of `last_read_at` → O(users×messages) writes.
- **Unbounded socket send buffers** → one slow client OOMs the node.
- **Blanket Socket.IO with long-poll + sticky LB** when native WS + backplane is simpler and scales better.

---

## 13. Agent checklist

```
- [ ] Stateless WS gateway + Redis Pub/Sub (or Streams/Kafka) backplane
- [ ] Postgres model; ULID/UUIDv7 ids; per-conversation seq for total order
- [ ] Idempotent send via unique (conversation_id, client_msg_id) + optimistic UI + ACK
- [ ] Receipts: delivered on persist; read via last_read_at; unread by seq
- [ ] Typing ephemeral (debounced, auto-expire); presence Redis SET EX heartbeat
- [ ] Reconnect: jittered backoff + after_seq keyset replay (no full reload)
- [ ] Backpressure guard on bufferedAmount; per-connection rate limit; size cap
- [ ] JWT on connect + membership authz on every event; sanitized bodies; presigned attachments
- [ ] dir="auto" per message + bidi isolates + grapheme-safe truncation (Arabic)
- [ ] Metrics: connections, reconnect rate, fan-out p99, drops, delivery rate
```

## 14. References (2026)
- MDN WebSocket API: https://developer.mozilla.org/en-US/docs/Web/API/WebSockets_API
- MDN Server-Sent Events: https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events
- Redis Pub/Sub: https://redis.io/docs/latest/develop/interact/pubsub/ · Streams: https://redis.io/docs/latest/develop/data-types/streams/
- Socket.IO Redis adapter: https://socket.io/docs/v4/redis-adapter/
- Ably: https://ably.com/docs · Pusher Channels: https://pusher.com/docs/channels/ · Stream Chat: https://getstream.io/chat/docs/
- ULID spec: https://github.com/ulid/spec · UUIDv7 (RFC 9562): https://www.rfc-editor.org/rfc/rfc9562
- MLS messaging (RFC 9420): https://www.rfc-editor.org/rfc/rfc9420

## 15. Related
`whatsapp-business-integration`, `omnichannel-inbox-chatbot`, `support-helpdesk-system`,
`push-notifications-advanced`, `voice-sms-telephony` · `backend-api-master` (auth, integrations-pro),
`ui-master` (chat widget).
