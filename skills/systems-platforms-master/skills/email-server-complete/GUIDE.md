---
name: email-server-complete
description: >-
  Email done right at staff depth (2026): managed (Resend/Postmark/SES/Mailgun) vs self-hosted
  (Postfix+Dovecot+Rspamd) decision, real SPF/DKIM/DMARC/MX/PTR/MTA-STS DNS records, Gmail/Yahoo/
  Microsoft bulk-sender rules, deliverability (warmup, reputation, FBLs), a durable sending queue with
  retries + idempotency, bounce/complaint suppression, inbound parsing, and Postmaster monitoring.
  Use for transactional sending AND full mail-server ops.
---

# Email — Complete (deliverability is the product, not "send an email")

**Mandate:** Getting bytes to an SMTP server is trivial; landing in the **inbox** is the hard engineering.
Authenticate every message (SPF **and** DKIM, both aligned under DMARC), warm reputation, suppress
bounces/complaints, and meet the Gmail/Yahoo/Microsoft bulk-sender rules — or you'll be silently spam-foldered
or rejected at SMTP. **In 2026, use a managed sender for transactional mail; self-host only for inbound or
sovereignty reasons.**

## When to use / when NOT to use
- **Use** for any product that sends email (signup, receipts, password reset, notifications, newsletters) or
  needs to receive/parse inbound mail (support@, reply-to-thread, email-to-ticket).
- **NOT** as your in-app chat/notification system (→ `communications-master`). And **do not self-host
  outbound SMTP to save $20/mo** unless you accept owning IP reputation, blocklists, patching, and 24/7
  deliverability ops — managed wins for almost everyone.

## Mental model
Email trust = **authentication + reputation**. Authentication proves *you sent it* (SPF authorizes the IP,
DKIM signs the content, **DMARC** requires one of them to *align* with the visible `From:` domain). Reputation
is the receiver's running score of your domain+IP (complaint rate, spam-trap hits, engagement). You can have
perfect auth and still hit spam if reputation is bad; you can't fix bad auth with good content. Build both:
authenticate correctly **and** send wanted mail to engaged recipients, ramping volume slowly.

---

## 1. DECISION MATRIX — managed vs self-hosted (and which managed)

| Option | Best for | Inbound? | Ops burden | Cost shape | Watch out |
|---|---|---|---|---|---|
| **Resend** | modern transactional, React Email, great DX | webhooks/inbound (limited) | none | per-email, generous free | newer; single stream (no msg-stream split) |
| **Postmark** | transactional with best-in-class deliverability + analytics | inbound parsing ✅ | none | per-email, premium | strict on bulk/marketing (separate streams) |
| **AWS SES** | high volume, cheapest at scale, already on AWS | inbound (S3/Lambda) ✅ | low–medium (IAM, sandbox) | cheapest/email | verbose SDK, sandbox, you own warmup |
| **Mailgun** | EU/region options, validation, routes | inbound routes ✅ | low | per-email | UI/deliverability varies |
| **Self-host (Postfix+Dovecot+Rspamd)** | inbound mailboxes, data sovereignty, full control | ✅ full | **high** | VPS + your time | IP reputation, blocklists, PTR, patching, 24/7 |

**Default:** transactional → **Resend or Postmark**; cost-sensitive high volume / on AWS → **SES**;
you must host mailboxes or can't use US clouds → **self-host**. Many shops run **managed for outbound** +
**self-host/managed inbound** — that's fine and common.

---

## 2. DNS records — the foundation (copy-paste, then verify)

Use a **subdomain** for app mail (`mail.example.com` / `send.example.com`) so app reputation is isolated from
your corporate domain. Real records (zone-file style):

```dns
; ---- MX (where YOUR domain receives mail; managed senders usually don't need MX for sending) ----
example.com.            IN  MX  10 mx1.yourmailhost.com.
example.com.            IN  MX  20 mx2.yourmailhost.com.

; ---- SPF (authorize sending sources; ONE TXT record, <=10 DNS lookups, end with ~all) ----
; Managed example (Resend/SES include mechanism varies by provider — use the one they give you):
send.example.com.       IN  TXT "v=spf1 include:amazonses.com ~all"
; Self-host example (authorize your MTA's IPs by A record):
mail.example.com.       IN  TXT "v=spf1 a mx ip4:203.0.113.10 ~all"

; ---- DKIM (publish the PUBLIC key at <selector>._domainkey; the provider gives you selector+key) ----
resend._domainkey.send.example.com.  IN  TXT "v=DKIM1; k=rsa; p=MIGfMA0GCSq...big-public-key...IDAQAB"
; Rotate keys by adding a NEW selector (e.g. s2026b) and switching signing to it, then retiring the old.

; ---- DMARC (tie it together; START at p=none, escalate to reject) ----
_dmarc.example.com.     IN  TXT "v=DMARC1; p=none; rua=mailto:dmarc@example.com; fo=1; pct=100; adkim=s; aspf=s"

; ---- MTA-STS (require TLS to your MX) + TLS-RPT (get TLS failure reports) ----
_mta-sts.example.com.   IN  TXT "v=STSv1; id=20260602T000000Z"
_smtp._tls.example.com. IN  TXT "v=TLSRPTv1; rua=mailto:tlsrpt@example.com"
; plus an HTTPS policy file served at https://mta-sts.example.com/.well-known/mta-sts.txt:
;   version: STSv1
;   mode: enforce
;   mx: mx1.yourmailhost.com
;   max_age: 604800

; ---- PTR (reverse DNS) — set on the IP via your hosting provider, NOT your zone ----
; 10.113.0.203.in-addr.arpa. IN PTR mail.example.com.   (must match HELO; non-generic; forward A must match back)
```

| Record | Proves | Required by Gmail/Yahoo/MS (bulk) | Gotcha |
|---|---|---|---|
| SPF | sending IP authorized | ✅ | one record; ≤10 lookups; `~all` (soft) over `-all` until confident |
| DKIM | content signed & untampered | ✅ | must **align** (`d=` = your From domain), not the ESP's domain |
| DMARC | SPF/DKIM alignment + policy | ✅ (≥`p=none`) | publishing ≠ passing; you must actually align |
| PTR | IP ↔ hostname match | ✅ | set on the IP; "meaningful, non-generic" (Yahoo) |
| MTA-STS/TLS | TLS enforced inbound | recommended | needs the HTTPS policy file too |

**DMARC escalation (the single most-stalled step):** `p=none` (monitor, read `rua` reports 30–90 days, find
every legit sender) → `p=quarantine; pct=25→100` → `p=reject`. 80% of teams stall because their ESP signs
DKIM with **its** domain — fix with **custom DKIM** (`d=yourdomain.com`) + a **custom Return-Path/bounce
subdomain** so SPF aligns too. BIMI (logo in inbox) requires `p=quarantine`+ and a VMC.

---

## 3. Bulk-sender rules (Gmail + Yahoo since Feb 2024, Microsoft since May 2025)

If you send **5,000+/day** to consumer mailboxes (and increasingly *any* volume), you MUST:
- **SPF + DKIM published and passing**, **DMARC** at least `p=none` with **alignment**.
- **One-click unsubscribe (RFC 8058)** on marketing/subscribed mail: both `List-Unsubscribe` (with an HTTPS
  URL) **and** `List-Unsubscribe-Post: List-Unsubscribe=One-Click`, returning **200** to the POST, processed
  within **2 days** — plus a visible unsubscribe link in the body.
- **Spam complaint rate < 0.3%** (target **< 0.1%**) in Postmaster Tools. ≥0.3% = throttled/ineligible.
- **Valid PTR** (forward+reverse match), **TLS** on SMTP.

Non-compliance is **SMTP rejection**, not spam-foldering: Gmail `550 5.7.26`, Yahoo `550 5.7.9`, Microsoft
`550 5.7.515`.

```
List-Unsubscribe: <https://example.com/u/abc123>, <mailto:unsub@example.com?subject=unsub>
List-Unsubscribe-Post: List-Unsubscribe=One-Click
```

---

## 4. Transactional sending (managed) — with idempotency & error handling

```ts
// Resend — modern DX. ALWAYS pass an idempotency key so a retry can't double-send (24h window).
import { Resend } from "resend";
const resend = new Resend(process.env.RESEND_API_KEY!);   // server-side secret only

async function sendReceipt(orderId: string, to: string, html: string) {
  const { data, error } = await resend.emails.send(
    {
      from: "Acme <receipts@send.example.com>",   // a verified, aligned sending domain
      to: [to],
      subject: "Your receipt",
      html,
      headers: { "List-Unsubscribe": "<https://example.com/u/" + orderId + ">" },
    },
    { idempotencyKey: `receipt/${orderId}` }       // 409 invalid_idempotent_request if payload changed
  );
  if (error) {
    // 429/5xx → retry w/ backoff; 4xx validation/auth → fix, don't retry (see error table in docs)
    throw new Error(`resend ${error.name}: ${error.message}`);
  }
  return data!.id;
}
```

```ts
// AWS SES v2 — cheapest at scale; verbose but fine. Use a configuration set for event tracking.
import { SESv2Client, SendEmailCommand } from "@aws-sdk/client-sesv2";
const ses = new SESv2Client({ region: "us-east-1" });
await ses.send(new SendEmailCommand({
  FromEmailAddress: "receipts@send.example.com",
  Destination: { ToAddresses: [to] },
  Content: { Simple: { Subject: { Data: "Your receipt" }, Body: { Html: { Data: html } } } },
  ConfigurationSetName: "transactional",          // routes bounce/complaint/delivery events to SNS
}));
```

```ts
// Postmark — separate Message Streams keep transactional and broadcast reputations apart
import { ServerClient } from "postmark";
const pm = new ServerClient(process.env.POSTMARK_TOKEN!);
await pm.sendEmail({ From: "receipts@send.example.com", To: to, Subject: "Your receipt",
  HtmlBody: html, MessageStream: "outbound" });
```

**Test addresses (no real deliverability risk):** Resend `delivered@resend.dev`, `bounced@resend.dev`,
`complained@resend.dev`; SES `success@`/`bounce@`/`complaint@simulator.amazonses.com`.

---

## 5. A durable sending queue (the part people skip and regret)

Never send inline in the request path. **Enqueue → worker sends → record result → retry transient.**

```ts
// Outbox pattern: write the intent in the same DB txn as the business event (no lost/dup mail on crash)
// emails(id, to, template, payload jsonb, status, attempts, idempotency_key, last_error, send_after)
async function enqueue(tx, msg) {
  await tx.query(
    `INSERT INTO emails (id, "to", template, payload, status, idempotency_key)
     VALUES ($1,$2,$3,$4,'pending',$5) ON CONFLICT (idempotency_key) DO NOTHING`,
    [crypto.randomUUID(), msg.to, msg.template, msg.payload, msg.idempotencyKey]
  );
}

// Worker: claim a batch, send with exponential backoff + jitter, respect provider 429s.
async function drain() {
  const { rows } = await db.query(
    `UPDATE emails SET status='sending', attempts=attempts+1
     WHERE id IN (SELECT id FROM emails WHERE status='pending' AND send_after<=now()
                  ORDER BY send_after LIMIT 50 FOR UPDATE SKIP LOCKED) RETURNING *`);
  for (const e of rows) {
    try {
      const id = await sendViaProvider(e);          // pass idempotency_key through
      await db.query(`UPDATE emails SET status='sent', provider_id=$2 WHERE id=$1`, [e.id, id]);
    } catch (err) {
      const transient = isRetryable(err);            // 429/5xx/network = transient; 4xx = permanent
      const backoff = Math.min(2 ** e.attempts, 3600) * 1000 + Math.random() * 1000; // jitter
      await db.query(
        `UPDATE emails SET status=$2, send_after=now() + ($3||' ms')::interval, last_error=$4 WHERE id=$1`,
        [e.id, transient && e.attempts < 6 ? "pending" : "failed", String(backoff), String(err)]);
    }
  }
}
```
On Cloudflare, back this with **Queues** (→ `cloudflare-platform-complete`); on AWS, SQS + Lambda. The
**idempotency key** end-to-end is what makes retries safe.

---

## 6. Bounce & complaint handling (suppression is mandatory)

Sending to addresses that hard-bounce, or to people who hit "spam", **destroys reputation**. Consume the
provider's webhooks and **suppress** automatically.

```ts
// Webhook receiver — verify signature, then suppress hard bounces & complaints (idempotent on event id)
app.post("/webhooks/email", verifySignature, async (req, res) => {
  const e = req.body;                               // shape varies by provider; normalize it
  switch (e.type) {
    case "email.bounced":                            // hard bounce → never send again
    case "email.complained":                         // spam complaint → suppress + stop all marketing
      await db.query(
        `INSERT INTO suppressions (email, reason, event_id) VALUES ($1,$2,$3)
         ON CONFLICT (event_id) DO NOTHING`, [e.to, e.type, e.id]);
      break;
    case "email.delivery_delayed": /* soft bounce — let the queue retry */ break;
  }
  res.sendStatus(200);                                // ack fast; events can be delivered >once → idempotent
});
// Before every send: SELECT 1 FROM suppressions WHERE email=$1  → skip if present.
```
**Hard bounce / complaint → permanent suppression.** Soft bounces (mailbox full, greylist) → bounded retry,
then suppress. Honor unsubscribes immediately. A clean list is the cheapest deliverability win there is.

---

## 7. Inbound parsing (receiving mail)
- **Managed:** point your MX (or a subdomain like `inbound.example.com`) at the provider; they POST parsed
  JSON (from/to/subject/text/html/attachments/headers) to your webhook. Postmark inbound, Mailgun routes,
  SES → S3+Lambda, Cloudflare Email Workers.
- **Self-host:** Postfix receives → pipe/LMTP to your app or Dovecot mailbox; parse MIME server-side.
- Always **verify the webhook signature**, strip/sanitize HTML, scan attachments, and thread by
  `Message-ID`/`In-Reply-To`/`References` (for email-to-ticket/reply-to-thread).

## 8. Self-host stack (when you must)
**Postfix** (MTA: SMTP send/receive) + **Dovecot** (IMAP/POP + LMTP delivery to mailboxes) + **Rspamd**
(spam filtering, **DKIM signing**, DMARC/SPF checks, greylisting). Real ops you now own: a clean static IP
with **PTR**, IP **warmup**, **blocklist** monitoring (Spamhaus/Barracuda), `requireTLS`, Fail2ban, OS/CVE
patching, and reading DMARC/TLS-RPT reports. This is a standing operational commitment — budget for it or use
managed.

---

## Edge cases & war stories
- **DKIM passes but DMARC fails.** ESP signs with `d=sendgrid.net`, not your domain → no alignment → DMARC
  fail → spam. Fix: **custom DKIM** (`d=yourdomain.com`) + custom Return-Path. The #1 reason teams stall.
- **Two SPF records** on one domain = **permerror**, SPF fails entirely. There must be exactly **one** SPF
  TXT, under 10 DNS lookups (`include:` bloat blows the limit silently).
- **New IP/domain blast.** Sending 50k on day one from a cold IP/domain → throttled/blocked. **Warm up:**
  start ~50/day to your most engaged users, ramp ~2× every few days over weeks.
- **Jumped to `p=reject` too fast.** A forgotten legit sender (billing system, CRM) starts bouncing for real
  customers. Sit at `p=none` and read `rua` reports until every source aligns.
- **Ignored complaints.** Reputation cratered because the app kept emailing people who marked spam. Suppress
  on `complained` immediately; stop all non-essential mail to them.
- **`postmaster@`/`abuse@` missing.** RFC-required role addresses bounce → looks abandoned to receivers.
- **PTR generic** (`ec2-203-0-113-10.compute.amazonaws.com`) → Yahoo flags it. Set a meaningful PTR (managed
  senders handle this; self-host must).

## Performance
- Async via the queue, batch where the provider supports it, reuse SMTP connections (self-host). Template +
  pre-render; don't block the request. Parallelize the worker with `FOR UPDATE SKIP LOCKED`.

## Security
- API keys server-side only, scoped + rotatable. **Verify every inbound/webhook signature.** TLS everywhere
  (MTA-STS enforce). DMARC `p=reject` stops spoofing of your domain. Rate-limit your own send endpoints to
  prevent an account takeover from torching your reputation. Sanitize inbound HTML; treat attachments as hostile.

## Scale & reliability
- Dedicated IP(s) only at sustained volume (and then warm + monitor them); shared IP pools below that.
- Separate **subdomains/streams** for transactional vs marketing so a campaign can't sink your password-reset
  deliverability. Queue + retries + DLQ. Multi-provider failover for critical mail (e.g. SES + Postmark).

## Testing
- Use provider sandbox/test addresses. **mailpit/MailHog** locally to catch all outbound. Score content with
  **mail-tester.com**; validate DNS with **MXToolbox** + a DMARC report parser. Assert suppression-list checks
  in CI so you can't regress into mailing bounced addresses.

## Observability (monitoring)
- **Google Postmaster Tools** (domain/IP reputation, spam rate, auth pass %), **Yahoo Sender Hub** (CFL
  complaint feed), **Microsoft SNDS/JMRP**. Parse **DMARC `rua`** + **TLS-RPT** reports. Dashboard:
  delivered/bounced/complained/opened, complaint rate vs 0.3%, blocklist status weekly. Alert when complaint
  rate climbs or deliverability dips.

## Cost notes
- Managed is per-email (Resend/Postmark premium DX; SES cheapest at volume) — usually far cheaper than the
  **engineering time** to run Postfix well. Self-host = VPS + your ops hours + reputation risk. Dedicated IPs
  cost extra and require sustained volume to stay warm (an idle dedicated IP *loses* reputation).

## Anti-patterns
- Self-hosting outbound SMTP "to save money" without owning deliverability ops.
- SPF without DKIM (SPF breaks on forwarding; DKIM survives) — you need **both**, aligned.
- Two SPF records / >10 lookups. ESP-domain DKIM with no alignment. `p=reject` before reading reports.
- Sending inline in the request (no queue/retry/idempotency) → dup or lost mail.
- Ignoring bounces/complaints (no suppression). No `List-Unsubscribe` on bulk mail.
- Cold-blasting a new IP/domain at full volume. Mixing marketing + transactional on one domain/IP.

## Agent checklist
```
- [ ] Decision made: managed (Resend/Postmark/SES) for outbound unless inbound/sovereignty forces self-host
- [ ] Sending on a SUBDOMAIN; SPF (one record, ~all) + DKIM (aligned d=yourdomain) + DMARC published
- [ ] DMARC starts p=none, rua monitored, escalates none→quarantine→reject after alignment verified
- [ ] PTR set + matches HELO (forward/reverse agree); MTA-STS enforce + TLS-RPT; TLS on SMTP
- [ ] Bulk rules met: List-Unsubscribe + One-Click (200 OK), visible link, complaint <0.3%
- [ ] Outbound via durable queue: outbox + idempotency key + backoff/jitter + DLQ
- [ ] Bounce/complaint webhooks verified + suppress permanently; check suppressions before every send
- [ ] Inbound (if any): MX/route → signed webhook → sanitized parse → threaded by Message-ID
- [ ] New IP/domain warmed gradually; transactional vs marketing separated
- [ ] Postmaster Tools / Sender Hub / SNDS + DMARC report parsing wired; complaint-rate alert set
```

## References (2026-current)
- Google sender guidelines: https://support.google.com/a/answer/81126 · Postmaster Tools: https://postmaster.google.com
- Yahoo Sender Hub: https://senders.yahooinc.com/best-practices/ · Microsoft SNDS: https://sendersupport.olc.protection.outlook.com/snds/
- DMARC RFC 7489 · SPF RFC 7208 · DKIM RFC 6376 · One-click unsubscribe RFC 8058 · MTA-STS RFC 8461
- Resend docs: https://resend.com/docs (idempotency: https://resend.com/docs/dashboard/emails/idempotency-keys)
- Postmark: https://postmarkapp.com/developer · AWS SES: https://docs.aws.amazon.com/ses/ · Rspamd: https://rspamd.com/doc/

## Related
`systems-platforms-foundation`, `cloudflare-platform-complete` (Email Workers/Queues), `supabase-complete`
(custom SMTP for auth mail) (this hub) · `communications-master` (in-app/chat), `integrations-master` (webhooks).
