---
name: email-integration-advanced
description: >-
  Advanced email at staff depth: ESP send (Resend/SendGrid/SES) with deliverability done right —
  SPF + DKIM + DMARC alignment, RFC 8058 one-click unsubscribe, Gmail/Yahoo/Microsoft 2024–2025
  bulk-sender rules, MJML/React Email, inbound parse (Resend email.received, SendGrid Inbound
  Parse), IMAP/Gmail/Graph two-way sync, RFC 5322 threading, email-to-ticket, and bounce/complaint
  suppression. Use for transactional/bulk send, inbound, and mailbox sync.
---

# Email Integration (advanced)

**Deliverability is authentication + reputation, not copywriting.** Since 2024 the inbox is gated:
Gmail and Yahoo (Feb 2024) and **Microsoft (May 5, 2025)** *reject* — not spam-folder — bulk mail
(5,000+/day) that lacks **SPF + DKIM + DMARC**, RFC 8058 **one-click unsubscribe**, and a user-spam
rate **under 0.3%**. So the rules in order: authenticate every stream, keep complaints low, send via
an **ESP API** (never raw SMTP from an app box), and make inbound a **structured, idempotent**
pipeline — not a script that polls IMAP. Always ship a plain-text part and test in Outlook.

---

## 1. When to use / when NOT

**Use** for transactional email (receipts, OTP, notifications), lifecycle/bulk, **inbound** parsing
(email→app/ticket), and **two-way mailbox sync** (show a customer's Gmail/Outlook thread inside your
app). Pairs with `support-helpdesk-system` (email-to-ticket) and `omnichannel-inbox-chatbot` (email
as a channel).

**Do NOT** send bulk from raw SMTP on your app server (reputation + deliverability death). Don't put
marketing and transactional on the **same domain/IP** (one bad campaign tanks your password resets).
Don't poll IMAP every 30s when IDLE/push + incremental sync exists. For real-time chat use
`realtime-chat-messaging`; for SMS/WhatsApp use those skills.

---

## 2. Architecture

```
OUTBOUND  app ─► ESP API (Resend/SendGrid/SES) ─► inbox
                   ▲ DNS: SPF + DKIM + DMARC (+BIMI)        ESP webhooks ─► delivered/open/click/
                   │ separate subdomains: tx vs mkt                         bounce/complaint ─► suppression list
INBOUND   inbox ─► [Inbound Parse webhook  | IMAP IDLE | Gmail/Graph push] ─► MIME parse ─►
                   thread (Message-ID/In-Reply-To/References) ─► quote-strip ─► Conversation/Ticket
SYNC      OAuth per user ─► historyId(Gmail)/delta(Graph) incremental + push ─► two-way thread mirror
```

- **Send and receive are different problems.** Send = reputation + templates. Receive = MIME parsing,
  threading, and idempotency. Sync = OAuth + delta + push. Don't conflate them.

---

## 3. Decision matrices

**Sending provider**

| Provider | Sweet spot | Notes |
|----------|-----------|-------|
| **Resend** ⭐ | transactional, DX, React Email | first-class React templates; inbound via `email.received` |
| **Postmark** | transactional, speed/clarity | strict on marketing; great deliverability + analytics |
| **SendGrid / Mailgun** | tx + bulk at scale | mature; Inbound Parse webhook for receiving |
| **Amazon SES** | cheapest at volume | bring your own templates/suppression; most assembly required |
| **Customer.io / Braze** | lifecycle/marketing automation | journeys on top of an ESP |

**Receiving method**

| Method | Effort | Best for |
|--------|--------|----------|
| **Inbound parse webhook** (Resend `email.received` / SendGrid Inbound Parse) ⭐ | low | email→app/ticket; point MX at provider |
| **IMAP IDLE** | medium | sync an existing arbitrary mailbox; full folder access |
| **Gmail API / Microsoft Graph** | medium-high | OAuth, scoped, push (watch/subscriptions), rich metadata |

**Authentication record (all required for bulk)**

| Record | Does | Minimum |
|--------|------|---------|
| **SPF** | authorizes sending IPs | TXT `v=spf1 include:_esp_ -all`, ≤10 DNS lookups |
| **DKIM** | signs the message | 2048-bit key (1024 floor), per sending domain |
| **DMARC** | policy + alignment + reports | `v=DMARC1; p=none; rua=mailto:dmarc@…` (move to `quarantine`/`reject`) |
| **BIMI** | logo in inbox | optional; needs DMARC **enforced** + a VMC/CMC certificate |

---

## 4. Production code

### 4a. Transactional send + RFC 8058 one-click unsubscribe (Resend + React Email)

```ts
// send.ts — every bulk/marketing send MUST carry one-click unsubscribe headers or Gmail/Yahoo reject it.
import { Resend } from "resend";
import { render } from "@react-email/render";
import { OrderShipped } from "./emails/OrderShipped";

const resend = new Resend(process.env.RESEND_API_KEY!);

export async function sendOrderShipped(to: string, data: { name: string; orderId: string; trackUrl: string }) {
  if (await isSuppressed(to)) return;                       // honor suppression BEFORE sending
  const unsubUrl = `https://acme.com/u/${signUnsub(to, "tx")}`; // signed token → /u handler one-click unsubs

  const html = await render(OrderShipped(data));
  const { data: res, error } = await resend.emails.send({
    from: "Acme <orders@tx.acme.com>",                     // transactional SUBDOMAIN (isolated reputation)
    to,
    subject: `Your order ${data.orderId} shipped`,
    html,
    text: await render(OrderShipped(data), { plainText: true }), // ALWAYS a plain-text part
    headers: {
      // RFC 8058 one-click unsubscribe (required for bulk; good practice for tx with prefs):
      "List-Unsubscribe": `<${unsubUrl}>, <mailto:unsub@acme.com?subject=unsub>`,
      "List-Unsubscribe-Post": "List-Unsubscribe=One-Click",
      "Idempotency-Key": `order-shipped:${data.orderId}`,   // dedupe retried sends
    },
  });
  if (error) throw error;
  await logSend(res!.id, to, "order_shipped");
}
```

> The unsubscribe endpoint must accept a **POST** (one-click) and process the opt-out **within 2
> days**. A visible in-body unsubscribe link is also required for marketing.

### 4b. DNS records (the part that actually decides inbox vs reject)

```dns
; SPF — authorize your ESP, single record, <=10 lookups
tx.acme.com.   TXT  "v=spf1 include:_spf.resend.com -all"
; DKIM — ESP gives you the selector + public key (2048-bit)
resend._domainkey.tx.acme.com.  CNAME  resend._domainkey.resend.com.
; DMARC — start at none w/ reports, then tighten to quarantine→reject once aligned
_dmarc.acme.com.  TXT  "v=DMARC1; p=quarantine; rua=mailto:dmarc@acme.com; adkim=s; aspf=s; pct=100"
```

### 4c. Inbound — Resend `email.received` (verify, then fetch body) → ticket

```ts
// inbound-resend.ts — webhooks carry METADATA only; fetch the body via the Received API, then route.
import { Resend } from "resend";
import { Webhook } from "svix";                              // Resend signs webhooks (svix-compatible)

const resend = new Resend(process.env.RESEND_API_KEY!);

export async function POST(req: Request) {
  const raw = await req.text();
  const evt = new Webhook(process.env.RESEND_WEBHOOK_SECRET!)
    .verify(raw, Object.fromEntries(req.headers)) as any;    // throws on bad signature
  if (evt.type !== "email.received") return new Response("ok");

  const { email_id, from, to, subject } = evt.data;
  if (!(await dedupe("email", email_id))) return new Response("ok"); // idempotent

  const email = await resend.emails.received.get(email_id);  // body/html/text + attachments metadata
  const cleaned = stripQuotedReply(email.data!.text ?? "");  // remove ">" history + signature
  await routeToTicket({
    channel: "email", externalThreadId: threadKeyOf(to, subject), externalMessageId: email_id,
    from: { email: from }, text: cleaned,
  });
  return new Response("ok", { status: 200 });
}
```

```ts
// inbound-sendgrid.ts — alternative: SendGrid Inbound Parse POSTs multipart/form-data (parsed fields).
export async function POST(req: Request) {
  const form = await req.formData();
  const messageId = (form.get("headers") as string).match(/Message-ID:\s*(<[^>]+>)/i)?.[1] ?? crypto.randomUUID();
  if (!(await dedupe("email", messageId))) return new Response("ok");
  await routeToTicket({
    channel: "email",
    externalThreadId: threadKeyOf(form.get("to") as string, form.get("subject") as string),
    externalMessageId: messageId,
    from: { email: parseAddr(form.get("from") as string) },
    text: stripQuotedReply((form.get("text") as string) ?? ""),
    // attachments: form.get("attachment1")… (set "POST raw MIME" off for parsed fields)
  });
  return new Response("ok", { status: 200 });
}
```

### 4d. Threading + email-to-ticket mapping (RFC 5322 + plus-addressing)

```ts
// threading.ts — make replies thread in clients AND map back to your ticket deterministically.
export function buildReplyHeaders(ticketId: string, lastInboundMessageId?: string) {
  const myMessageId = `<${ticketId}.${Date.now()}@acme.com>`;
  return {
    "Message-ID": myMessageId,
    ...(lastInboundMessageId && {
      "In-Reply-To": lastInboundMessageId,
      "References": lastInboundMessageId,                    // append the chain for proper threading
    }),
    // Plus-address + VERP so the customer's reply maps straight back to the ticket:
    "Reply-To": `support+${ticketId}@acme.com`,
  };
}
// On inbound, recover the ticket from the plus-address first, then Message-ID/References as fallback.
export const ticketFromInbound = (toAddr: string, references?: string) =>
  toAddr.match(/support\+([a-z0-9]+)@/i)?.[1] ?? references?.match(/<([a-z0-9]+)\./i)?.[1] ?? null;
```

### 4e. Bounce/complaint → suppression

```ts
// suppression.ts — process ESP webhooks; auto-suppress hard bounces & complaints; retry soft bounces.
export async function onEspEvent(e: { type: string; email: string; reason?: string }) {
  if (e.type === "bounce" && isHard(e.reason)) await suppress(e.email, "hard_bounce");
  else if (e.type === "bounce") await scheduleRetry(e.email, backoff());     // soft → retry w/ backoff
  else if (e.type === "complaint" || e.type === "spamreport") await suppress(e.email, "complaint");
  else if (e.type === "unsubscribe") await suppress(e.email, "unsubscribe");
}
export const isSuppressed = (email: string) => db.suppression.has(email.toLowerCase()); // checked before every send
```

---

## 5. Edge cases

- **Quoted-history bloat:** strip `>`-quoted chains and signatures before storing as a ticket comment,
  or every reply duplicates the whole thread. Use a robust library (`talon`-style) — naïve regex
  fails on Outlook/Apple Mail variants.
- **Threading without `In-Reply-To`:** some clients only set `References`, some neither — fall back to
  subject normalization (strip `Re:`/`Fwd:` and locale variants `RE:`,`AW:`,`SV:`,`رد:`) + participant set.
- **Inbound idempotency:** providers retry; dedupe by `Message-ID`/provider `email_id` (one comment per message).
- **Display name vs address:** parse `"Name <addr@x>"`; never match on display name.
- **HTML-only senders / encoding:** handle missing text part, base64/quoted-printable, charset (UTF-8,
  ISO-8859-x, Windows-1256 for Arabic) — decode to UTF-8 on ingest.
- **Auto-responders / loops:** detect `Auto-Submitted: auto-replied` and `Precedence: bulk`; never
  auto-reply to an auto-reply (mail loop).
- **Sync deletions/moves:** Gmail `historyId`/Graph `delta` report removals too — mirror them, and
  handle `historyId` expiry (full re-sync fallback).

---

## 6. Performance & deliverability ops

- **Warm up** new domains/IPs gradually (ramp volume over weeks); cold-blasting 50k from a fresh
  domain = instant spam folder.
- **Separate streams:** `tx.acme.com` (transactional) vs `mkt.acme.com` (marketing) — isolate
  reputation so a campaign can't sink your OTPs.
- **Keep spam complaints < 0.1%** (0.3% is the hard reject ceiling). Prune unengaged recipients;
  sunset-policy stale addresses.
- **Push, not poll:** Gmail `users.watch` + Pub/Sub, Graph subscriptions, or IMAP **IDLE** — and
  **incremental** sync via `historyId`/`delta`, never full mailbox scans.
- **Batch + throttle** bulk sends to your ESP's rate limits; use the ESP's batch endpoints.

---

## 7. Security & privacy

- **Verify inbound webhook signatures** (Resend/svix, SendGrid event signing) before processing.
- **OAuth tokens** (Gmail/Graph) for two-way sync: store **encrypted**, least-scope, handle refresh +
  revocation; never request full-mailbox scope if read-of-label suffices.
- **DMARC enforcement** (`p=quarantine`→`reject`) protects your domain from spoofing/phishing.
- **PII:** email content is PII; encrypt at rest, set retention, support erasure; strip secrets/cards
  before logging or sending to any LLM (agent-assist).
- **TLS** for SMTP/transmission; valid PTR/FCrDNS on any IP you control.
- **Link safety:** sign unsubscribe/action tokens (HMAC, expiring) so they can't be forged/enumerated.

---

## 8. Scale & reliability

- **Idempotent send** (`Idempotency-Key` per business event) + **idempotent inbound** (dedupe by
  Message-ID) = no double receipts, no double tickets.
- **Suppression list is sacred** — checked before *every* send, updated from bounce/complaint/unsub
  webhooks synchronously.
- **Outbox** for sends triggered by DB changes (transactional consistency).
- **Provider abstraction:** an `EmailProvider` interface (`send`, `parseInbound`, `verify`) so you can
  move ESP without touching product code; SES failover for transactional.
- **Backfill/replay:** keep raw inbound payloads so you can reprocess after a parser fix.

---

## 9. Testing

- **Auth check:** before launch, validate SPF/DKIM/DMARC pass + alignment (mail-tester / Google
  Postmaster); assert one-click headers present on marketing sends.
- **Inbound parse:** fixtures for Gmail/Outlook/Apple Mail replies → assert quote-strip + threading +
  ticket mapping; include an Arabic (Windows-1256) sample.
- **Idempotency:** same Message-ID twice → one ticket; same Idempotency-Key → one send.
- **Suppression:** suppressed address → send is skipped; hard bounce → auto-suppressed.
- **Rendering:** snapshot MJML/React Email across clients (Litmus/Email on Acid), incl. dark mode + Outlook.
- **Loop guard:** auto-reply input does not trigger an auto-reply.

---

## 10. Observability

- **Deliverability:** delivered / bounce / complaint / open / click rates per stream + domain.
- **Reputation:** Google **Postmaster Tools**, Yahoo Sender Hub/CFL, Microsoft **SNDS**; alert if
  spam rate approaches 0.1%.
- **DMARC reports** (`rua`) — monitor alignment + spoofing attempts (parse via a DMARC analyzer).
- **Inbound health:** parse success rate, dedupe hits, thread-match rate, webhook 200-latency.
- **Sync health:** `historyId`/`delta` lag, token-refresh failures, full-resync count.
- **SMTP rejects** by code (Gmail `550 5.7.26`, Yahoo `550 5.7.9`, Microsoft `550 5.7.515`) → auth gap signal.

---

## 11. i18n / RTL (Arabic) & templates

- **HTML email**: set `dir="rtl"` and `lang="ar"` on `<html>`/containers for Arabic; use table-based
  RTL layouts (mirror alignment), and **inline** styles (email clients strip `<style>`/logical props
  inconsistently). Test in Outlook (Word engine) specifically.
- **Encoding:** send UTF-8; decode inbound Arabic from Windows-1256/ISO-8859-6 → UTF-8.
- **Per-locale templates & subjects** (MJML/React Email components per language); pick by recipient
  locale, with a fallback. Localize the preheader and the unsubscribe copy.
- **Subject prefixes:** normalize reply prefixes across locales (`Re:`,`رد:`,`AW:`,`SV:`) when threading.
- Numerals/dates via locale-aware formatting; right-align numeric columns in RTL.

---

## 12. Anti-patterns

- **Raw SMTP from the app server** → poor deliverability, no analytics/webhooks, spam folder.
- **Missing/misaligned SPF/DKIM/DMARC** → 2024/2025 bulk rules **reject** you (not spam — bounced).
- **Same domain/IP for marketing + transactional** → a campaign sinks your password resets.
- **No one-click unsubscribe** on bulk → Gmail/Yahoo reject; complaints spike.
- **HTML-only, untested in Outlook, no plain-text part** → broken rendering + worse deliverability.
- **Polling IMAP/Gmail** instead of IDLE/push + incremental sync → rate limits, lag, cost.
- **Storing full quoted reply chains** as ticket comments → unreadable, bloated threads.
- **Not suppressing hard bounces/complaints** → reputation tanks, domain blacklisted.

## 13. Agent checklist

```
- [ ] ESP API send (not SMTP); separate tx vs marketing subdomains
- [ ] SPF + DKIM (2048) + DMARC (aligned, →quarantine/reject); BIMI optional
- [ ] RFC 8058 one-click unsubscribe headers + POST handler honored ≤2 days; visible link on marketing
- [ ] Responsive MJML/React Email + plain-text part; Outlook + dark-mode + Arabic RTL tested
- [ ] Inbound: parse webhook (verify sig) or IMAP IDLE or Gmail/Graph push; MIME decode to UTF-8
- [ ] Threading: Message-ID/In-Reply-To/References + plus-address ticket mapping; quote-strip
- [ ] Two-way sync via historyId/delta + push (not polling); OAuth tokens encrypted, least-scope
- [ ] Idempotent send (Idempotency-Key) + inbound (Message-ID); suppression checked before every send
- [ ] Bounce/complaint/unsub webhooks → auto-suppression; soft-bounce retry w/ backoff
- [ ] Monitor Postmaster/SNDS + DMARC rua; keep spam <0.1%; alert on reject codes
```

## 14. References (2026)
- Google bulk sender guidelines: https://support.google.com/mail/answer/81126
- Yahoo Sender Hub requirements: https://senders.yahooinc.com/best-practices/
- Microsoft (Outlook) bulk requirements (May 2025): https://techcommunity.microsoft.com/blog/microsoft-defender-for-office-365-blog/strengthening-email-ecosystem-outlooks-new-requirements-for-high%E2%80%90volume-senders/4399730
- RFC 8058 one-click unsubscribe: https://www.rfc-editor.org/rfc/rfc8058
- DMARC (RFC 7489): https://www.rfc-editor.org/rfc/rfc7489 · BIMI: https://bimigroup.org
- Resend (send + inbound): https://resend.com/docs · React Email: https://react.email/docs
- SendGrid Inbound Parse: https://www.twilio.com/docs/sendgrid/for-developers/parsing-email/setting-up-the-inbound-parse-webhook
- Gmail API push: https://developers.google.com/gmail/api/guides/push · Microsoft Graph delta: https://learn.microsoft.com/en-us/graph/delta-query-messages

## 15. Related
`support-helpdesk-system`, `omnichannel-inbox-chatbot`, `realtime-chat-messaging`,
`whatsapp-business-integration`, `push-notifications-advanced` · `backend-api-master` (integrations-pro),
`content-seo-master` (email copy).
