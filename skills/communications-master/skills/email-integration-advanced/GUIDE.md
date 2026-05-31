---
name: email-integration-advanced
description: >-
  Advanced email integration — sending, receiving, and deliverability. Use for
  transactional & bulk email, inbound email parsing, IMAP/SMTP, Gmail/Microsoft
  Graph APIs, SPF/DKIM/DMARC/BIMI, templates (MJML/React Email), threading,
  bounce/complaint handling, and email-to-ticket. Covers ESPs, deliverability,
  and two-way sync.
---

# Email Integration (advanced)

Send, receive, and reliably deliver email — transactional, inbound parsing, and full mailbox sync.

## Sending: transactional & bulk

| Provider | Use |
|----------|-----|
| **Resend** ⭐ / Postmark | Transactional, great DX, React Email/templates |
| **SendGrid / Mailgun / SES** | Transactional + bulk at scale; SES cheapest |
| **Customer.io / Braze** | Lifecycle/marketing automation |

```
- [ ] Send via ESP API (not raw SMTP) for deliverability + analytics + webhooks
- [ ] Separate sending domains/subdomains for transactional vs marketing (protect reputation)
- [ ] Idempotency on send; per-recipient suppression list honored
- [ ] Track delivered/open/click/bounce/complaint via ESP webhooks
```

## Deliverability (the part everyone gets wrong)

```
SPF   — TXT record authorizing senders for your domain
DKIM  — cryptographic signature (publish public key; ESP signs)
DMARC — policy (none→quarantine→reject) + alignment + reports (rua)
BIMI  — your logo in inbox (needs DMARC enforced + VMC) — optional, premium
```
- Warm up new domains/IPs; keep complaint rate < 0.1% and bounce rate low.
- Authenticate ALL streams; align From domain; avoid spammy content; include unsubscribe
  (one-click for bulk per Gmail/Yahoo 2024+ rules).
- Monitor: Google Postmaster Tools, ESP reputation, seed/inbox-placement tests.

## Templates
- **MJML** or **React Email** → responsive, dark-mode-aware, client-compatible (Outlook!) HTML.
- Always ship a **plain-text part** (multipart) — improves deliverability + accessibility.
- Inline CSS; test across clients (Litmus/Email on Acid); preheader text.

## Receiving / inbound

| Method | Use |
|--------|-----|
| **Inbound parse webhook** (SendGrid/Mailgun/Postmark) | Easiest: email → HTTP POST (parsed) |
| **IMAP** | Poll/IDLE a mailbox; full folder access |
| **Gmail API / Microsoft Graph** | OAuth, push (Pub/Sub / webhooks), rich, scoped |

```
Inbound flow: receive → parse (MIME: text/html, attachments, headers) →
  thread (Message-ID / In-Reply-To / References) → strip quoted history & signatures →
  route to conversation/ticket (email-to-ticket for support-helpdesk-system)
```

## Two-way mailbox sync (Gmail/Graph)
- OAuth per user; store refresh token (encrypted); incremental sync via **historyId** (Gmail) /
  **delta** (Graph); push notifications (Gmail watch + Pub/Sub, Graph subscriptions) instead of polling.
- Map threads/labels/folders; send-as; handle token refresh + revocation.

## Threading & email-to-ticket
- Preserve `Message-ID`, set `In-Reply-To`/`References` so replies thread in clients.
- Quote-strip incoming replies (remove `>` history + signatures) before storing as a ticket comment.
- Embed a hidden token/plus-address (`support+TICKET123@`) to map replies back to the ticket.

## Bounce / complaint / suppression
- Process ESP bounce (hard/soft) + complaint (FBL) webhooks → **suppress** hard bounces &
  complainers automatically; retry soft bounces with backoff.
- Maintain a suppression list checked before every send.

## Checklist
```
- [ ] ESP API send + separate transactional/marketing domains
- [ ] SPF + DKIM + DMARC (enforced) + one-click unsubscribe; monitor reputation
- [ ] Responsive templates (MJML/React Email) + plain-text part + client testing
- [ ] Inbound: parse webhook or IMAP or Gmail/Graph; MIME parse + threading
- [ ] Two-way sync via historyId/delta + push (not polling); tokens encrypted
- [ ] Email-to-ticket with quote-stripping + reply mapping token
- [ ] Bounce/complaint webhooks → auto-suppression
```

## Anti-patterns
- Raw SMTP from your app server (poor deliverability, lands in spam).
- Missing SPF/DKIM/DMARC → spam folder or rejection.
- HTML-only emails; untested in Outlook; no plain-text part.
- Polling IMAP/Gmail constantly instead of IDLE/push + incremental sync.
- Not suppressing hard bounces/complaints → reputation tanks, domain blacklisted.
- Storing full quoted reply chains as ticket comments (strip them).
