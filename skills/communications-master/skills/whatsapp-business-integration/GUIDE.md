---
name: whatsapp-business-integration
description: >-
  Integrate WhatsApp for business messaging. Use for WhatsApp Business Platform
  (Cloud API), sending/receiving messages, message templates (HSM), interactive
  messages (buttons/lists), media, webhooks, 24-hour session window, opt-in, and
  BSP providers (Twilio, 360dialog, MessageBird). Covers notifications, support,
  and chatbots over WhatsApp.
---

# WhatsApp Business Integration

Send and receive WhatsApp messages at scale via the **WhatsApp Business Platform (Cloud API)** —
for notifications, support, and chatbots.

## Access options

| Path | Notes |
|------|-------|
| **Meta Cloud API** (direct) ⭐ | Hosted by Meta, free to start, REST + webhooks; best default |
| **On-Premises API** | Deprecated → migrate to Cloud API |
| **BSP / aggregator** | Twilio, 360dialog, MessageBird, Infobip, Vonage — easier onboarding, billing, extras |

Setup: Meta Business account → WhatsApp Business Account (WABA) → phone number → **display-name
approval** → access token + phone_number_id. Verify the business for higher limits.

## The two message types (this rules everything)

```
1. SESSION (free-form) messages — only within the 24-hour CUSTOMER SERVICE WINDOW
   (the 24h after the user's last message). Any content allowed.
2. TEMPLATE (HSM) messages — required to message a user OUTSIDE the 24h window
   (notifications, re-engagement). Must be PRE-APPROVED by Meta. Categories:
   UTILITY / AUTHENTICATION / MARKETING (pricing & limits differ).
```
> If you message a user outside 24h with free-form text, it fails. Use an approved **template** to
> (re)open the conversation; once they reply, the 24h session opens for free-form.

## Sending

```
POST https://graph.facebook.com/v20.0/{phone_number_id}/messages
Authorization: Bearer {token}
{ "messaging_product":"whatsapp", "to":"<E.164 no +>",
  "type":"template",
  "template": { "name":"order_update", "language":{"code":"en"},
    "components":[{"type":"body","parameters":[{"type":"text","text":"#12345"}]}] } }
```
- Free-form (in session): `type:"text"|"image"|"document"|"interactive"|...`.
- **Interactive**: reply **buttons** (≤3) and **list** messages — great for menus/support flows.
- **Media**: upload → media_id, or send by link; supports image/doc/audio/video/sticker/location.

## Receiving (webhooks)
```
- [ ] Verify webhook (GET hub.challenge with verify_token)
- [ ] On POST: messages[], statuses[] (sent/delivered/read/failed)
- [ ] Validate X-Hub-Signature-256 (HMAC); return 200 fast; process async
- [ ] Dedupe by message id; map to a conversation (link to realtime-chat / support-helpdesk)
- [ ] Track the 24h window per contact (timestamp of last inbound)
```

## Compliance & best practices
- **Opt-in required** before messaging users (collect + store consent).
- Template quality affects your **messaging limits & quality rating** (don't get flagged/blocked).
- Respect **per-conversation pricing** (Meta charges per 24h conversation by category).
- Don't spam marketing; honor stop/unsubscribe; keep templates accurate to category.

## Use cases
- **Notifications** (templates): OTP/auth, order/shipping/payment updates, reminders.
- **Support** (session + interactive): route into helpdesk; agent handoff; quick-reply menus.
- **Chatbot/commerce**: catalogs, flows; pair with `omnichannel-inbox-chatbot`.

## Checklist
```
- [ ] WABA + verified number + display name approved; token + phone_number_id
- [ ] Cloud API (or BSP) adapter; webhook verified + signature-checked + async
- [ ] Approved templates per category; opt-in/consent store
- [ ] 24h session-window tracking; template fallback outside window
- [ ] Interactive buttons/lists for menus; media via media_id/link
- [ ] Status handling (delivered/read/failed) + dedupe; quality/limit monitoring
```

## Anti-patterns
- Free-form messages outside the 24h window (will fail) — use approved templates.
- Messaging without opt-in / spamming marketing → number flagged, quality dropped, blocked.
- Ignoring delivery/read/failed statuses and message dedupe.
- Hardcoding to one BSP instead of an adapter; not tracking the session window.
