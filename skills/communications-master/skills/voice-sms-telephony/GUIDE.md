---
name: voice-sms-telephony
description: >-
  Programmable SMS/MMS and voice at staff depth: Twilio (and Vonage/Sinch/Telnyx/SNS) sending
  with Messaging Services, US A2P 10DLC + TCPA compliance (brand/campaign, opt-in, STOP/HELP),
  X-Twilio-Signature webhook validation, inbound routing, status callbacks, TwiML IVR, and
  real-time AI voice via Media Streams. E.164, sender selection, deliverability. Use for OTP,
  alerts, two-way SMS, IVR, and voice bots — the telephony channels of an omnichannel platform.
---

# Voice & SMS / Telephony

**SMS and voice are regulated channels — compliance *is* the deliverability.** In the US you cannot
send A2P SMS from a normal number until your **brand + campaign are registered (A2P 10DLC)**, and you
must honor **opt-in/STOP/HELP (TCPA)** or carriers filter and fine you. Get registration, consent,
and **webhook signature validation** right; the API itself (`messages.create`, TwiML) is the easy
part. Treat every inbound webhook as **untrusted until the `X-Twilio-Signature` checks out**, every
send as **idempotent**, and every recipient as **E.164**.

---

## 1. When to use / when NOT

**Use** for: OTP/2FA codes, transactional alerts (delivery, appointment, payment), two-way SMS
support, voice IVR / call routing, and **real-time AI voice agents** (speech ⇄ LLM via Media
Streams). This is the **telephony channel** that feeds `omnichannel-inbox-chatbot` and
`support-helpdesk-system`.

**Do NOT** use SMS for rich/marketing content where WhatsApp/email is cheaper and richer
(`whatsapp-business-integration`, `email-integration-advanced`) — SMS is expensive, 160-char
GSM-7 segmented, and tightly policed. Don't send US A2P traffic on an unregistered long code (it
gets filtered/blocked). Don't use SMS OTP as your *only* MFA factor for high-value accounts (SIM-swap
risk) — prefer app/passkey, SMS as fallback.

---

## 2. Architecture

```
OUTBOUND  app ─► provider API (Twilio messages.create / SNS / Vonage) ─► carrier ─► handset
                   via Messaging Service (sender pool, sticky sender, A2P campaign attached)
                   status callbacks ─► queued→sent→delivered|undelivered|failed ─► your DB
INBOUND   handset ─► carrier ─► provider ─► webhook /sms (validate X-Twilio-Signature)
                   ─► STOP/HELP/START auto-handled ─► route to inbox/ticket/bot
VOICE     call ─► webhook /voice ─► TwiML (<Say>/<Gather>/<Dial>/<Stream>) ─► IVR / AI voice agent
                   <Stream> ⇄ WebSocket ⇄ STT → LLM → TTS  (real-time voice bot)
```

---

## 3. Decision matrices

**Provider**

| Provider | Strength | Use when |
|----------|----------|----------|
| **Twilio** ⭐ | breadth (SMS/voice/WA/verify), docs, Messaging Services, Media Streams | Default; full omnichannel + voice |
| **Telnyx / Bandwidth** | own-carrier, cost at volume, voice quality | High volume, cost-sensitive, US voice |
| **Vonage / Sinch / Bird** | global reach, regional routes | International SMS, specific countries |
| **Amazon SNS / Pinpoint / End User Messaging** | cheap transactional SMS, AWS-native | Already on AWS, simple OTP/alerts |
| **Twilio Verify / equivalents** | managed OTP (SMS/voice/email/WA) | Don't hand-roll OTP delivery + rate limits |

**US sender type (A2P)**

| Sender | Throughput | Registration | Use |
|--------|-----------|--------------|-----|
| **10DLC** ⭐ | per-campaign trust tier | A2P brand + campaign (TCR) | Most business A2P SMS |
| **Toll-free** | high | TF verification (separate) | Quick-ish, higher TPS, no 10DLC campaign |
| **Short code** | highest | weeks, costly | Huge OTP/marketing volume |
| ❌ unregistered long code | filtered/blocked | — | Never for US A2P |

**SMS vs alternatives for a given job**

| Job | Best channel |
|-----|--------------|
| OTP/2FA | SMS or **Verify** (fallback to app/passkey) |
| Rich receipt w/ images/buttons | WhatsApp / email |
| Time-critical alert, any phone | SMS |
| Voice confirmation / IVR | Programmable Voice |

---

## 4. Production code

### 4a. Send SMS via a Messaging Service (sender pool + A2P campaign) with status callback

```ts
// sms.ts — use a Messaging Service (not a bare 'from') so A2P campaign, sender pool, and
// sticky sender are handled for you. Idempotent + E.164 validated.
import twilio from "twilio";
const client = twilio(process.env.TWILIO_ACCOUNT_SID!, process.env.TWILIO_AUTH_TOKEN!);

export async function sendSms(to: string, body: string, opts?: { idempotencyKey?: string }) {
  if (!/^\+[1-9]\d{6,14}$/.test(to)) throw new Error("to must be E.164, e.g. +9715XXXXXXXX");
  if (await isOptedOut(to)) return;                       // never message an opted-out number

  return client.messages.create({
    to,
    messagingServiceSid: process.env.TWILIO_MESSAGING_SERVICE_SID!, // A2P campaign attached here
    body,                                                 // keep <=160 GSM-7 to avoid multi-segment cost
    statusCallback: "https://api.acme.com/webhooks/sms-status", // delivery receipts
    // Twilio dedupes identical (to, body) within a short window; also dedupe in your own outbox.
  });
}
```

### 4b. Inbound SMS webhook — validate `X-Twilio-Signature`, then route

```ts
// inbound-sms.ts (Express) — NEVER trust the webhook before signature validation.
import twilio from "twilio";
import express from "express";

export const router = express.Router();
router.post("/webhooks/sms", express.urlencoded({ extended: false }), async (req, res) => {
  const signature = req.header("X-Twilio-Signature") ?? "";
  const url = "https://api.acme.com/webhooks/sms";        // the EXACT public URL Twilio called
  const valid = twilio.validateRequest(process.env.TWILIO_AUTH_TOKEN!, signature, url, req.body);
  if (!valid) return res.status(403).send("bad signature");

  const { From, Body, MessageSid } = req.body;            // From is E.164, Body is the text
  if (!(await dedupe("sms", MessageSid))) return res.type("text/xml").send("<Response/>");

  const text = (Body ?? "").trim().toUpperCase();
  if (["STOP", "STOPALL", "UNSUBSCRIBE", "CANCEL", "END", "QUIT"].includes(text)) {
    await optOut(From);                                   // honor immediately (TCPA)
    // With Advanced Opt-Out enabled, Twilio also auto-replies + blocks; otherwise reply here.
  } else if (["START", "YES", "UNSTOP"].includes(text)) {
    await optIn(From);
  } else if (text === "HELP" || text === "INFO") {
    return res.type("text/xml").send(twiml(`Acme support: help@acme.com. Reply STOP to opt out.`));
  } else {
    await routeToInbox({ channel: "sms", externalMessageId: MessageSid, from: { phone: From }, text: Body });
  }
  res.type("text/xml").send("<Response/>");               // empty TwiML = no auto-reply
});

const twiml = (msg: string) => `<Response><Message>${escapeXml(msg)}</Message></Response>`;
```

### 4c. Status callback — track the delivery funnel

```ts
// sms-status.ts — queued → sent → delivered | undelivered | failed (+ ErrorCode).
router.post("/webhooks/sms-status", express.urlencoded({ extended: false }), async (req, res) => {
  if (!validSig(req, "https://api.acme.com/webhooks/sms-status")) return res.sendStatus(403);
  const { MessageSid, MessageStatus, ErrorCode } = req.body;
  await db.updateDelivery(MessageSid, MessageStatus, ErrorCode); // 30007=carrier filtered, 21610=opted out
  res.sendStatus(204);
});
```

### 4d. Voice IVR (TwiML) + branch on keypad/speech

```ts
// voice.ts — return TwiML; <Gather> collects DTMF or speech and posts to /voice/handle.
router.post("/webhooks/voice", (req, res) => {
  if (!validSig(req, "https://api.acme.com/webhooks/voice")) return res.sendStatus(403);
  const vr = new twilio.twiml.VoiceResponse();
  const g = vr.gather({ numDigits: 1, input: ["dtmf", "speech"], action: "/webhooks/voice/handle", timeout: 5 });
  g.say({ voice: "Polly.Joanna", language: "en-US" }, "Welcome to Acme. Press 1 for support, 2 for billing.");
  vr.redirect("/webhooks/voice");                         // no input → repeat
  res.type("text/xml").send(vr.toString());
});

router.post("/webhooks/voice/handle", (req, res) => {
  const vr = new twilio.twiml.VoiceResponse();
  const choice = req.body.Digits || req.body.SpeechResult;
  if (choice === "1") vr.dial({ callerId: process.env.ACME_NUMBER! }, process.env.SUPPORT_QUEUE!);
  else if (choice === "2") vr.dial(process.env.BILLING_QUEUE!);
  else { vr.say("Sorry, I didn't catch that."); vr.redirect("/webhooks/voice"); }
  res.type("text/xml").send(vr.toString());
});
```

> **Real-time AI voice:** use `<Connect><Stream url="wss://…"/>` (Media Streams) to pipe call audio
> to a WebSocket → STT → LLM (`omnichannel-inbox-chatbot` brain) → TTS back. Handle barge-in
> (interrupt TTS on speech), and keep round-trip < ~700ms or it feels robotic.

---

## 5. Edge cases

- **Segmentation:** GSM-7 = 160 chars/segment (153 when concatenated); a single emoji/Arabic char
  forces **UCS-2 = 70 chars/segment**. Budget cost + length accordingly; show the user the segment count.
- **Opt-out variants & languages:** carriers honor STOP/UNSUBSCRIBE/CANCEL/END/QUIT (and localized
  forms) — handle all; once opted out, sends return error `21610`.
- **Delivery ≠ read:** SMS has no read receipt; `delivered` means handset-acknowledged. `sent` without
  `delivered` may still arrive (some carriers don't return DLRs).
- **Carrier filtering (30007 / 30034):** unregistered or spammy content gets silently filtered —
  looks "sent" but never arrives; monitor delivered-rate, not just sent.
- **Sticky sender / number pooling:** keep the same `from` per recipient (Messaging Service handles
  this) so the conversation looks continuous and avoids spam heuristics.
- **Voice:** handle no-input, machine/voicemail detection (AMD), call hang-ups mid-IVR, and DTMF vs
  speech ambiguity; always provide a path to a human.
- **International:** sender-ID rules differ by country (some require alphanumeric sender, some block
  two-way); SMS in UAE/KSA often needs pre-registered sender IDs.

---

## 6. Performance & throughput

- **MPS is sender-tier-gated:** 10DLC throughput depends on your campaign's trust score; toll-free
  and short codes are higher. Queue + rate-limit to your provisioned MPS or you'll hit `429`.
- **Use a Messaging Service sender pool** to scale throughput across multiple numbers with sticky
  routing — don't loop one long code for a 100k blast.
- **Batch + backoff** in a worker (BullMQ limiter), never in a request handler.
- **Voice concurrency** is capped (channels); size your queue and use call-queue TwiML for overflow.

---

## 7. Security & compliance

- **Validate `X-Twilio-Signature`** on *every* inbound/voice/status webhook (HMAC of full URL +
  sorted params with your Auth Token; use `validateRequest`/`validateRequestWithBody`). Reject otherwise.
- **A2P 10DLC (US):** register **Brand** (legal name, EIN ≥15 days old, address, live website) + a
  **Campaign** (use case, message samples, opt-in flow, **live Privacy Policy + Terms URLs**) via TCR
  *before* sending. Match the use case to actual content or carriers reject/suspend.
- **TCPA consent:** explicit, **un-bundled, no pre-checked boxes**; separate consent per use case
  (marketing vs transactional); store proof (when/where/how). Provide STOP + HELP in messages.
- **Quiet hours:** respect local-time sending windows for marketing (TCPA ~8am–9pm recipient local time).
- **PII:** phone numbers are PII — encrypt, restrict, retention; don't log full OTP codes.
- **OTP abuse:** rate-limit OTP requests per number/IP; short code TTL; consider Verify (built-in
  fraud controls) to avoid SMS-pumping toll fraud.

---

## 8. Scale & reliability

- **Idempotent send:** key by `(business_event, recipient)` in your outbox so retries don't double-text.
- **Idempotent inbound:** dedupe by `MessageSid` (provider redelivers).
- **Provider abstraction:** a `TelephonyProvider` interface (`sendSms`, `validate`, `parseInbound`)
  so Twilio↔Telnyx↔SNS is a config change; helps failover/least-cost routing.
- **Backpressure + retries:** queue with concurrency limiter; exponential backoff on `5xx`/`429`.
- **Reconcile** from status callbacks (delivered/undelivered/ErrorCode), not from `create()` success
  (that only means *accepted*).

---

## 9. Testing

- **Signature validation:** unit-test that a tampered body/URL fails and a valid one passes
  (`validateRequest` with the exact public URL incl. query string).
- **Opt-out flow:** STOP → opted out → next send is skipped/`21610`; START → re-subscribed.
- **Segmentation:** assert GSM-7 vs UCS-2 segment counts (Arabic/emoji → UCS-2/70).
- **IVR:** simulate DTMF + speech + no-input branches; assert human fallback path.
- Use **Twilio test credentials / magic numbers** and a tunneled local webhook; never test on a real list.

---

## 10. Observability

- **Delivery funnel:** sent → delivered rate, undelivered/failed by `ErrorCode` (30007 filtered,
  21610 opted-out, 30034 unregistered) — alert on delivered-rate drop.
- **A2P health:** campaign status/trust tier, throughput utilization vs cap.
- **OTP metrics:** request rate, delivery time, verification success, pumping-fraud anomalies.
- **Voice:** answer rate, IVR completion, transfer-to-human rate, call duration, ASR confidence.
- **Spend** per segment/country; flag UCS-2 cost spikes.

---

## 11. i18n / RTL (Arabic) & templates

- **Arabic SMS = UCS-2 (70 chars/segment)** — bodies are ~half as long and cost more; write tight,
  show segment count, consider WhatsApp for longer Arabic content.
- **Localized templates** per language; pick by recipient locale. Keep OTP codes LTR even in Arabic
  bodies (wrap in bidi isolate so the digits don't reorder).
- **Sender IDs:** Gulf carriers (UAE TDRA, KSA CITC) often require **pre-registered alphanumeric
  sender IDs** and block two-way long codes — plan sender provisioning per market.
- **IVR voice + language:** set `<Say language="ar-XA" voice="...">` / appropriate TTS; offer a
  language-selection menu first.

---

## 12. Anti-patterns

- **Sending US A2P on an unregistered long code** → silent carrier filtering (looks sent, never arrives).
- **No `X-Twilio-Signature` validation** → anyone can forge inbound/status webhooks.
- **Ignoring STOP / bundled or pre-checked consent** → TCPA violations, fines, campaign suspension.
- **SMS as the only MFA** for high-value accounts → SIM-swap takeover.
- **Looping one number for bulk** instead of a Messaging Service pool → throttling + spam flags.
- **Trusting `create()` success as "delivered"** → it only means accepted; reconcile via callbacks.
- **Long Arabic/emoji SMS** unaware of UCS-2 70-char segmentation → surprise cost + truncation.
- **Dead-end IVR** with no human path.

## 13. Agent checklist

```
- [ ] Provider abstraction (Twilio default); E.164 validation everywhere
- [ ] US: A2P 10DLC brand + campaign registered (live Privacy/Terms URLs); use case matches content
- [ ] Send via Messaging Service (sender pool + campaign); idempotent outbox; status callbacks
- [ ] Inbound + status webhooks validate X-Twilio-Signature; dedupe by MessageSid
- [ ] STOP/HELP/START handled (or Advanced Opt-Out); consent stored, un-bundled, no pre-check; quiet hours
- [ ] OTP: rate-limited, short TTL, anti-pumping (or use Verify); SMS not sole MFA
- [ ] Voice: TwiML IVR with DTMF+speech + human fallback; Media Streams for AI voice (barge-in, <700ms)
- [ ] Segmentation aware (GSM-7 160 / UCS-2 70 for Arabic/emoji); show segment count
- [ ] Metrics: delivered rate, ErrorCode breakdown, A2P trust tier, OTP success, spend
```

## 14. References (2026)
- Twilio Programmable Messaging: https://www.twilio.com/docs/messaging
- A2P 10DLC overview & registration: https://www.twilio.com/docs/messaging/compliance/a2p-10dlc
- Webhook signature validation (X-Twilio-Signature): https://www.twilio.com/docs/usage/webhooks/webhooks-security
- TwiML Voice: https://www.twilio.com/docs/voice/twiml · Media Streams: https://www.twilio.com/docs/voice/media-streams
- Twilio Verify (managed OTP): https://www.twilio.com/docs/verify
- TCPA (FCC): https://www.fcc.gov/general/telemarketing-and-robocalls · Amazon SNS SMS: https://docs.aws.amazon.com/sns/latest/dg/sns-mobile-phone-number-as-subscriber.html

## 15. Related
`whatsapp-business-integration`, `omnichannel-inbox-chatbot`, `support-helpdesk-system`,
`push-notifications-advanced`, `email-integration-advanced` · `backend-api-master` (auth/MFA,
integrations-pro webhooks), `ai-mcp-master` (voice bot brain).
