---
name: whatsapp-business-integration
description: >-
  WhatsApp Business Platform at staff depth (Cloud API / Graph v25.0): the 24-hour service
  window vs pre-approved templates (HSM), per-message pricing (post-July-2025), interactive
  buttons/lists/Flows, media, signed webhooks (X-Hub-Signature-256), status receipts, opt-in/
  consent, quality rating & messaging limits, BSP abstraction, and idempotent at-least-once
  intake. Use for notifications, support, and chatbots over WhatsApp.
---

# WhatsApp Business Integration — Cloud API (Graph v25.0)

**Two rules govern everything on WhatsApp: the 24-hour service window and pre-approved templates.**
Inside the window (24h after the user's last inbound) you send free-form anything, free. Outside it,
the *only* way to reach a user is an **approved template (HSM)**, and since **July 1, 2025 you pay
per delivered template message** by category. Internalize that and the rest is plumbing. Everything
async (templates approval, delivery status, BSP differences) must be **idempotent and at-least-once**
— Meta batches webhooks, retries for up to 7 days, and guarantees no ordering.

---

## 1. When to use / when NOT

**Use** for: transactional notifications (OTP, order/shipping/payment updates, reminders), two-way
support, and commerce chatbots — where customers already live in WhatsApp and open rates dwarf email.

**Do NOT** use WhatsApp for: unsolicited cold marketing (fastest way to get your number quality-rated
red and blocked); bulk one-way blasts you could do by email/SMS for 1/10th the cost; anything to a
user who hasn't **opted in**. For SMS/voice fallback → `voice-sms-telephony`; to unify WA with other
channels in one agent inbox → `omnichannel-inbox-chatbot`; to turn WA threads into tickets →
`support-helpdesk-system`.

---

## 2. Architecture

```
Meta Cloud API (graph.facebook.com/v25.0)
   ▲  send: POST /{phone_number_id}/messages           (templates + free-form)
   │
Your app  ──► outbound: window-aware router (free-form if open, else template)
   │          ◄── inbound webhook /webhooks/whatsapp  (GET verify · POST messages+statuses)
   ▼              └─ verify X-Hub-Signature-256 → 200 fast → enqueue → process async
Postgres: contacts(+consent), wa_window(last_inbound_at), messages, message_status, templates
Redis/queue: dedupe set (wamid), async workers, rate-limit, retry
```

- **Webhook handler does almost nothing synchronously**: verify signature → dedupe → `200 OK` →
  push to a queue. All business logic runs in workers. Meta's timeout is ~10s and it *retries*.

---

## 3. Decision matrices

**Access path**

| Path | Onboarding | Billing | Pick when |
|------|-----------|---------|-----------|
| **Meta Cloud API (direct)** ⭐ | Embedded Signup | Meta + your card | Default — REST, webhooks, lowest markup, full control |
| **BSP** (Twilio, 360dialog, Infobip, MessageBird, Vonage) | guided | via BSP | Want consolidated billing, helpdesk extras, easier KYC, multi-country numbers |
| **On-Premises API** | ❌ deprecated | — | Never — migrate to Cloud API |

**Message type by window state** (this table *is* the product logic)

| User state | Allowed | Cost (post 2025-07-01) |
|------------|---------|------------------------|
| **Inside 24h window** | free-form text/media/interactive **+** templates | free-form = free; **marketing template still charged**; utility template **free** in-window |
| **Outside 24h window** | **templates only** | charged per delivered template by category |
| **First 72h after a free entry point** (ad/click-to-WA, FB page CTA) | anything | **free for 72h** |

**Template category** (set correctly or Meta re-categorizes and you misbill / get rejected)

| Category | Use | Billing |
|----------|-----|---------|
| **Utility** | order/account updates tied to a transaction | free in-window; charged out-of-window (volume tiers) |
| **Authentication** | OTP / login codes | **always** charged per message (volume tiers) |
| **Marketing** | promos, re-engagement, announcements | **always** charged (highest rate), even in-window |
| **Service** | free-form replies (not a template) | free |

> Pricing is **per delivered template message**, by category **and recipient country code** —
> conversation-based pricing was deprecated 2025-07-01. The `statuses[].pricing` object
> (`billable`, `category`, `pricing_model`) tells you exactly what you were charged; log it.

---

## 4. Production code

### 4a. Window-aware send router (free-form when open, template when not)

```ts
// wa.ts — Cloud API client + the only send function you should call from app code.
const GRAPH = "https://graph.facebook.com/v25.0";
const PNID = process.env.WA_PHONE_NUMBER_ID!;
const TOKEN = process.env.WA_TOKEN!;           // long-lived system-user token

async function graph(path: string, body: unknown) {
  const res = await fetch(`${GRAPH}/${path}`, {
    method: "POST",
    headers: { Authorization: `Bearer ${TOKEN}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const json = await res.json();
  if (!res.ok) throw new WaError(json.error);  // {code, message, error_data, fbtrace_id}
  return json;                                  // { messages:[{id: "wamid..."}] }
}

/** Send free-form ONLY if the 24h window is open; otherwise require an approved template. */
export async function sendSmart(to: string, content:
  | { kind: "text"; body: string }
  | { kind: "template"; name: string; lang: string; vars: string[] }) {
  const windowOpen = await isWindowOpen(to);   // last_inbound_at within 24h (see 4d)

  if (content.kind === "text") {
    if (!windowOpen) throw new Error("WINDOW_CLOSED: free-form not allowed; send an approved template");
    return graph(`${PNID}/messages`, {
      messaging_product: "whatsapp", recipient_type: "individual",
      to, type: "text", text: { preview_url: false, body: content.body },
    });
  }
  // Templates work in or out of window (required out of window).
  return graph(`${PNID}/messages`, {
    messaging_product: "whatsapp", to, type: "template",
    template: {
      name: content.name, language: { code: content.lang },
      components: [{ type: "body", parameters: content.vars.map((text) => ({ type: "text", text })) }],
    },
  });
}

class WaError extends Error { constructor(public e: any) { super(e?.message); } }
```

### 4b. Interactive reply buttons & list (menus/support flows)

```ts
// Reply buttons: max 3, each title <= 20 chars. Lists: up to 10 rows per section.
export const sendButtons = (to: string, body: string, buttons: { id: string; title: string }[]) =>
  graph(`${PNID}/messages`, {
    messaging_product: "whatsapp", to, type: "interactive",
    interactive: { type: "button", body: { text: body },
      action: { buttons: buttons.slice(0, 3).map((b) => ({ type: "reply", reply: b })) } },
  });

export const sendList = (to: string, body: string, button: string,
  sections: { title: string; rows: { id: string; title: string; description?: string }[] }[]) =>
  graph(`${PNID}/messages`, {
    messaging_product: "whatsapp", to, type: "interactive",
    interactive: { type: "list", body: { text: body }, action: { button, sections } },
  });
```

> For multi-field data capture (booking, KYC, lead forms) use **WhatsApp Flows** (`type: "flow"`)
> instead of chaining buttons — a native form inside the chat. Flow completions arrive as an inbound
> `interactive` message with `nfm_reply` JSON.

### 4c. Webhook: GET verify + POST signature check, fast 200, async

```ts
// webhook.ts (Next.js route handlers) — verify, dedupe, enqueue, ack fast.
import crypto from "node:crypto";

// 1) GET — subscription handshake (Meta echoes hub.challenge)
export function GET(req: Request) {
  const u = new URL(req.url);
  if (u.searchParams.get("hub.mode") === "subscribe" &&
      u.searchParams.get("hub.verify_token") === process.env.WA_VERIFY_TOKEN)
    return new Response(u.searchParams.get("hub.challenge") ?? "", { status: 200 });
  return new Response("forbidden", { status: 403 });
}

// 2) POST — verify HMAC over the RAW body, then return 200 immediately
export async function POST(req: Request) {
  const raw = await req.text();                                   // RAW bytes — do NOT re-stringify JSON
  const sig = req.headers.get("x-hub-signature-256") ?? "";
  const expected = "sha256=" + crypto.createHmac("sha256", process.env.WA_APP_SECRET!)
    .update(raw, "utf8").digest("hex");
  const ok = sig.length === expected.length &&
    crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(expected)); // constant-time
  if (!ok) return new Response("bad signature", { status: 401 });

  const body = JSON.parse(raw);
  for (const entry of body.entry ?? [])
    for (const change of entry.changes ?? []) {
      const v = change.value;
      for (const m of v.messages ?? []) await enqueue("wa.inbound", m, v.metadata);  // arrays can be batched
      for (const s of v.statuses ?? []) await enqueue("wa.status", s);               // sent|delivered|read|failed
    }
  return new Response("ok", { status: 200 });                    // ack FAST; workers do the rest
}
```

### 4d. Inbound worker: idempotent dedupe + window tracking

```ts
// worker.ts — at-least-once: Meta re-delivers, so dedupe by wamid before doing anything.
import { Redis } from "ioredis";
const redis = new Redis(process.env.REDIS_URL!);

export async function onInbound(m: any, meta: any) {
  // Dedupe: SET NX with TTL; if it already existed, this is a redelivery → drop.
  const fresh = await redis.set(`wa:seen:${m.id}`, "1", "EX", 60 * 60 * 24, "NX");
  if (!fresh) return;

  // Any inbound message (re)opens the 24h service window for this contact.
  await db.upsertWindow(m.from, new Date(Number(m.timestamp) * 1000));
  await db.upsertContact(m.from, meta.display_phone_number);

  if (m.type === "text")         await routeToInbox(m.from, m.text.body);
  else if (m.type === "interactive") {
    const r = m.interactive;
    const payload = r.button_reply?.id ?? r.list_reply?.id ?? r.nfm_reply?.response_json;
    await handleMenuSelection(m.from, payload);
  } else if (["image","document","audio","video","sticker"].includes(m.type)) {
    const mediaId = m[m.type].id;
    await ingestMedia(m.from, mediaId);          // GET /{mediaId} → url → download with auth header
  }
}

export const isWindowOpen = async (to: string) => {
  const last = await db.lastInboundAt(to);
  return !!last && Date.now() - last.getTime() < 24 * 60 * 60 * 1000;
};
```

---

## 5. Edge cases

- **Status webhooks arrive out of order & multiple times** per message (`sent`→`delivered`→`read`,
  up to 3 separate POSTs, plus possible `failed`). Store the **highest** status reached; never
  downgrade `read` back to `sent`. Dedupe by `(wamid, status)`.
- **`failed` statuses** carry `errors[]` with codes: `131047` (re-engagement / outside window),
  `131026` (undeliverable), `132xxx` (template paused/disabled). Map to a retry-vs-give-up policy.
- **Template gotchas:** newlines/tabs/4+ consecutive spaces in variables → rejected; `{{1}}` order
  must match `parameters` order; a low-quality template can be **paused mid-campaign** — handle the
  `message_template_status_update` webhook.
- **Media is two-step:** webhook gives a `media_id`; you `GET /{media_id}` for a short-lived URL,
  then download **with the auth header**. URLs expire (~5 min) — fetch promptly, store in your S3.
- **24h boundary races:** a free-form send can fail if the window closed between your check and the
  API call — catch `131047` and fall back to a template.
- **Number/quality:** sending limits (1K→10K→100K→unlimited tiers) and a green/yellow/red quality
  rating gate throughput; watch `phone_number_quality_update`.

---

## 6. Performance & throughput

- **Default ~80 messages/sec** per number (Cloud API), upgradable to higher MPS tiers; queue and
  rate-limit your sender to stay under the cap or you'll get `131056`/throttling.
- **Batch fan-out through a queue with concurrency control** (e.g. BullMQ limiter) — never loop a
  marketing list with naked `await` in a request handler.
- **Respect messaging tier**: a 1K-tier number can't blast 50K; ramp by maintaining high quality.
- **Webhook ingestion** must be O(1) sync work; all heavy lifting (media download, NLP, ticketing)
  is async so you always `200` within Meta's timeout and avoid the 7-day retry storm.

---

## 7. Security & compliance

- **Verify `X-Hub-Signature-256`** on every POST (HMAC-SHA256 of the **raw** body with your **App
  Secret**, `sha256=` prefix, **constant-time** compare). No signature → reject. (§4c)
- **Opt-in is mandatory** before the first message — capture *where/when/how* consent was given and
  store it; Meta and (in the EU) GDPR require it. Honor STOP/unsubscribe immediately.
- **Token hygiene:** use a **system-user long-lived token**, store encrypted, rotate; never ship the
  temporary 24h token to prod.
- **PII:** phone numbers are PII — encrypt at rest, restrict access, set retention; don't log full
  message bodies with PII in plaintext.
- **Quality protection:** match template category to content (mislabeled marketing-as-utility gets
  re-categorized and can trigger enforcement); throttle marketing; segment opt-outs.

---

## 8. Scale & reliability

- **At-least-once intake:** dedupe by `wamid` (Redis `SET NX` / DB unique) before side effects.
- **Idempotent outbound:** key sends by your own `(template, recipient, business_event_id)` so a
  retry after a network blip doesn't double-send an OTP.
- **BSP abstraction:** put a thin `WaProvider` interface (`send`, `verify`, `parse`) over Cloud API
  vs Twilio/360dialog so you can switch without rewriting business logic.
- **Backpressure:** queue + concurrency limiter for sends; exponential backoff on `5xx`/throttle.
- **Reconcile billing** from `statuses[].pricing` rather than guessing costs from sends.

---

## 9. Testing

- **Webhook signature:** unit-test that a tampered body fails and a correctly-signed one passes;
  test with the **raw** body (a JSON re-encode breaks Unicode and the HMAC).
- **Window logic:** table-test free-form-in-window (ok), free-form-out-of-window (must template),
  72h free-entry-point (anything ok).
- **Idempotency:** deliver the same `wamid` twice → exactly one ticket/side effect.
- **Status ordering:** feed `read` then a late `delivered` → final stored status stays `read`.
- Use the **Cloud API test number** + Graph API Explorer for staging; never test against a customer list.

---

## 10. Observability

- **Delivery funnel:** sent → delivered → read rate per template/category; alert on delivery drop.
- **Failure breakdown** by error code (`131047`, `131026`, `132xxx`, `131056`).
- **Quality rating** & messaging tier (green/yellow/red; current limit) — alert on yellow.
- **Spend** reconciled from `pricing` objects, split by category/country.
- **Webhook health:** verification failures, processing lag, dedupe hit-rate, 200-latency p99.

---

## 11. i18n / RTL (Arabic) & templates

- **Templates are per-language**: create `order_update` in `ar` *and* `en`; pick `language.code`
  by the contact's locale. Don't machine-translate at send time — submit and get each locale approved.
- **Arabic templates render RTL automatically** in the WhatsApp client; keep variables free of
  emoji-adjacent ambiguity and **wrap LTR tokens (order numbers, URLs, prices) in bidi isolates**
  in your own UI mirrors so they don't scramble.
- **Authentication templates**: use the dedicated OTP/auth template type (with copy-code button) —
  localize the body, keep the code as `{{1}}`.
- Numerals: decide Western (`123`) vs Eastern-Arabic (`١٢٣`) per market; be consistent with the brand.

---

## 12. Anti-patterns

- **Free-form outside the 24h window** → silent `131047` failures; always template to re-open.
- **No opt-in / cold marketing** → quality drops to red, number blocked. Unrecoverable trust loss.
- **Ignoring `statuses[]`** (delivered/read/failed) and `pricing` → blind to delivery and spend.
- **Skipping signature verification** or hashing parsed JSON instead of the raw body.
- **Synchronous webhook processing** (media download in the handler) → timeouts → Meta retry storm.
- **Hardcoding one BSP** instead of a provider interface; **not tracking the window** per contact.
- **Mislabeling marketing as utility** to dodge cost → re-categorization + enforcement.

## 13. Agent checklist

```
- [ ] WABA + verified number + approved display name; system-user token + phone_number_id (encrypted)
- [ ] Cloud API client on graph v25.0; thin BSP-swappable provider interface
- [ ] Webhook: GET verify token + POST X-Hub-Signature-256 (raw body, constant-time) → 200 fast → queue
- [ ] Inbound dedupe by wamid (SET NX); update 24h window on every inbound
- [ ] Window-aware sender: free-form in-window, approved template out-of-window (+72h entry point)
- [ ] Templates per locale + correct category; handle template_status_update (paused)
- [ ] Status worker: monotonic status, failed-code routing, pricing/spend logging
- [ ] Opt-in/consent store + STOP handling; PII encrypted; rate-limit to MPS tier
- [ ] Metrics: delivery/read rate, failure codes, quality tier, spend, webhook lag
```

## 14. References (2026)
- Cloud API messages (v25.0): https://developers.facebook.com/docs/whatsapp/cloud-api/reference/messages
- Webhooks (components, signature): https://developers.facebook.com/docs/whatsapp/cloud-api/webhooks
- Per-message pricing (since 2025-07-01): https://developers.facebook.com/docs/whatsapp/pricing/
- Message templates / categories: https://developers.facebook.com/docs/whatsapp/business-management-api/message-templates
- Interactive messages & Flows: https://developers.facebook.com/docs/whatsapp/cloud-api/messages/interactive-messages · https://developers.facebook.com/docs/whatsapp/flows
- Graph webhook security (X-Hub-Signature-256): https://developers.facebook.com/docs/graph-api/webhooks/getting-started#validate-payloads

## 15. Related
`omnichannel-inbox-chatbot`, `support-helpdesk-system`, `realtime-chat-messaging`,
`voice-sms-telephony`, `push-notifications-advanced` · `backend-api-master` (integrations-pro webhooks).
