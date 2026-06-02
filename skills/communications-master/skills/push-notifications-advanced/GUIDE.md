---
name: push-notifications-advanced
description: >-
  Cross-platform push + in-app notifications at staff depth: Web Push (VAPID, service worker),
  FCM HTTP v1 (legacy retired 2024), APNs token-based auth (.p8 JWT over HTTP/2), token lifecycle
  & pruning, a channel-orchestration layer (push/in-app/email/SMS fallback) with user preferences,
  quiet hours, batching/digest, dedupe, and delivery analytics. Use for transactional + lifecycle
  notifications across iOS/Android/web, with consent and preference management.
---

# Push & In-App Notifications (advanced)

**Push is a permission-gated, best-effort firehose — engineer it as an orchestration problem, not an
API call.** Three truths: (1) the **legacy FCM HTTP/XMPP APIs were removed in 2024 → you MUST use
FCM HTTP v1 (OAuth2)**; (2) device tokens **rot constantly** (reinstalls, expiry) so unregister on
`410/NotRegistered` or you burn quota on ghosts; (3) the hard part is **not delivery, it's
restraint** — preferences, quiet hours, dedupe, and cross-channel fallback so you reach users
without becoming the app they mute. Always pair a notification with a **fallback channel** and a
**preference the user controls**.

---

## 1. When to use / when NOT

**Use** for: transactional nudges (order shipped, mention, payment), lifecycle/re-engagement, and
**in-app notification centers**. Push is the cheap, instant tap-through layer; it complements
`email-integration-advanced` (durable, rich), `voice-sms-telephony` (any phone, urgent), and
`realtime-chat-messaging` (live, in-session).

**Do NOT** use push for content that must be guaranteed-delivered or legally recorded (push is
best-effort; back critical messages with email/SMS). Don't push without **explicit opt-in** (iOS/web
require a permission prompt — ask *in context*, never on first launch). Don't blast marketing push to
users who only consented to transactional. For live in-session updates, use the chat socket, not push.

---

## 2. Architecture

```
event ─► Notification Orchestrator ──────────────────────────────────────────────┐
          ├─ resolve user PREFERENCES (per category) + QUIET HOURS (user TZ)      │
          ├─ DEDUPE (collapse key) + BATCH/DIGEST (coalesce bursts)               │
          ├─ pick channels by priority: in-app ▸ push ▸ email/SMS fallback        │
          └─ render per-locale ──► providers:                                      │
                 Web Push (VAPID)   ─► browser push services (FCM/Mozilla/WNS)     │
                 FCM HTTP v1        ─► Android (+ can proxy APNs/webpush)          │
                 APNs (.p8 JWT/HTTP2)─► iOS                                        │
          delivery receipts + 410/NotRegistered ─► prune dead tokens, analytics  ◄┘
```

- The **orchestrator** is the product. Providers are interchangeable transports behind it.

---

## 3. Decision matrices

**Platform → transport**

| Target | Transport | Auth |
|--------|-----------|------|
| **iOS / macOS** | **APNs** (direct) or via FCM | **token-based .p8 JWT (ES256)** over HTTP/2 ⭐ (not legacy .p12 certs) |
| **Android** | **FCM HTTP v1** | OAuth2 service-account Bearer ⭐ (legacy server key retired 2024) |
| **Web** (Chrome/Edge/Firefox/Safari16.4+) | **Web Push (VAPID)** | VAPID keys; browser routes to its push service |
| **In-app center** | your DB + realtime | your auth |

**Build vs buy the orchestration layer**

| Option | Best for |
|--------|----------|
| **Build** (this guide) ⭐ | full control, data ownership, custom fallback/digest logic |
| **Knock / Courier / Novu / OneSignal / Braze** | fast multi-channel + preference center + templates out of the box |
| **Firebase Cloud Messaging only** | Android+web+iOS *delivery* (you still build preferences/digest) |

**Priority / collapse**

| Type | Priority | Collapse/dedupe |
|------|----------|-----------------|
| OTP / time-critical | high (APNs `10`, FCM `high`) | never collapse |
| Chat message | high, but coalesce per chat | collapse by `thread_id` |
| Social (likes) | normal, **digest** | collapse + batch hourly |
| Marketing | normal, quiet-hours + freq cap | heavy throttling |

---

## 4. Production code

### 4a. Web Push — service worker subscribe + server send (VAPID)

```ts
// client: register SW and subscribe. Ask permission IN CONTEXT, not on load.
export async function subscribePush() {
  const reg = await navigator.serviceWorker.register("/sw.js");
  if ((await Notification.requestPermission()) !== "granted") return null;
  const sub = await reg.pushManager.subscribe({
    userVisibleOnly: true,                                  // required by browsers
    applicationServerKey: urlBase64ToUint8Array(process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY!),
  });
  await fetch("/api/push/subscribe", { method: "POST", body: JSON.stringify(sub) }); // store endpoint+keys
  return sub;
}
```

```js
// sw.js — the service worker shows the notification (and handles clicks).
self.addEventListener("push", (e) => {
  const d = e.data?.json() ?? {};
  e.waitUntil(self.registration.showNotification(d.title, {
    body: d.body, icon: d.icon, badge: d.badge, tag: d.collapseKey, // tag = collapse on device
    data: { url: d.url }, dir: "auto", lang: d.lang,
  }));
});
self.addEventListener("notificationclick", (e) => {
  e.notification.close();
  e.waitUntil(clients.openWindow(e.notification.data.url));
});
```

```ts
// server: send with the `web-push` library (handles VAPID + RFC 8291 encryption).
import webpush from "web-push";
webpush.setVapidDetails("mailto:push@acme.com", process.env.VAPID_PUBLIC_KEY!, process.env.VAPID_PRIVATE_KEY!);

export async function sendWebPush(sub: webpush.PushSubscription, payload: object) {
  try {
    await webpush.sendNotification(sub, JSON.stringify(payload), { TTL: 3600, urgency: "high" });
  } catch (err: any) {
    if (err.statusCode === 404 || err.statusCode === 410) await pruneSubscription(sub.endpoint); // dead → remove
    else throw err;
  }
}
```

### 4b. FCM HTTP v1 (Android + cross-platform) — OAuth2, not legacy server key

```ts
// fcm.ts — legacy FCM HTTP/XMPP was REMOVED in 2024. Use HTTP v1 with a service-account token.
import { GoogleAuth } from "google-auth-library";
const auth = new GoogleAuth({ scopes: ["https://www.googleapis.com/auth/firebase.messaging"] });
const PROJECT = process.env.FCM_PROJECT_ID!;

export async function sendFcm(token: string, n: { title: string; body: string; data?: Record<string, string> }) {
  const client = await auth.getClient();                   // ADC or GOOGLE_APPLICATION_CREDENTIALS
  const url = `https://fcm.googleapis.com/v1/projects/${PROJECT}/messages:send`;
  const message = {
    message: {
      token,
      notification: { title: n.title, body: n.body },
      data: n.data,                                        // string values only
      android: { priority: "high", notification: { channel_id: "transactional" } },
      apns: { headers: { "apns-priority": "10", "apns-push-type": "alert" },
              payload: { aps: { sound: "default", "thread-id": n.data?.threadId } } },
      webpush: { headers: { Urgency: "high" }, fcm_options: { link: n.data?.url } },
    },
  };
  const res = await client.request({ url, method: "POST", data: message });
  return res.data;                                         // on UNREGISTERED/NOT_FOUND → prune token (see 4d)
}
```

### 4c. APNs direct — token-based auth (.p8 JWT, ES256) over HTTP/2

```ts
// apns.ts — token auth beats cert auth: one .p8 key for all your apps, no yearly cert rotation.
import { SignJWT, importPKCS8 } from "jose";
import http2 from "node:http2";

async function apnsJwt() {
  const key = await importPKCS8(process.env.APNS_P8!, "ES256");
  return new SignJWT({}).setProtectedHeader({ alg: "ES256", kid: process.env.APNS_KEY_ID! })
    .setIssuer(process.env.APNS_TEAM_ID!).setIssuedAt().sign(key);  // reuse up to ~1h, refresh <60min
}

export async function sendApns(deviceToken: string, payload: object, opts: { pushType?: string; topic: string }) {
  const jwt = await apnsJwt();
  const host = process.env.APNS_ENV === "prod" ? "https://api.push.apple.com" : "https://api.sandbox.push.apple.com";
  const session = http2.connect(host);
  const req = session.request({
    ":method": "POST", ":path": `/3/device/${deviceToken}`,
    authorization: `bearer ${jwt}`,
    "apns-topic": opts.topic,                              // your bundle id
    "apns-push-type": opts.pushType ?? "alert",           // alert|background|voip|liveactivity…
    "apns-priority": "10",
  });
  req.end(JSON.stringify({ aps: { alert: payload } }));
  return new Promise((resolve, reject) => {
    let status = 0; let body = "";
    req.on("response", (h) => (status = Number(h[":status"])));
    req.on("data", (c) => (body += c)); req.on("end", () => { session.close();
      if (status === 410 || (status === 400 && body.includes("BadDeviceToken"))) pruneToken(deviceToken); // dead
      status === 200 ? resolve(true) : reject(new Error(`APNs ${status} ${body}`)); });
  });
}
```

### 4d. Orchestrator — preferences, quiet hours, dedupe, fallback

```ts
// notify.ts — the brain: decide IF, WHICH channel, and WHEN before any provider call.
export async function notify(userId: string, ev: { category: string; collapseKey?: string;
  title: string; body: string; url?: string; critical?: boolean }) {
  const prefs = await getPrefs(userId);                    // per-category channel opt-ins
  if (!prefs.allows(ev.category) && !ev.critical) return;  // respect opt-out (critical OTP bypasses)

  // Dedupe: collapse repeats within a short window (e.g. 3 "new message" → 1).
  if (ev.collapseKey && (await recentlySent(userId, ev.collapseKey))) return upgradeToDigest(userId, ev);

  // Quiet hours in the USER'S timezone → defer to next allowed window (criticals bypass).
  if (!ev.critical && inQuietHours(prefs, userId)) return scheduleAfterQuietHours(userId, ev);

  await writeInApp(userId, ev);                            // in-app center is the durable record
  const devices = await activeDevices(userId);            // {platform, token/subscription}
  const localized = localize(ev, prefs.locale);

  let delivered = false;
  for (const d of devices) {
    try {
      if (d.platform === "web")     await sendWebPush(d.sub, { ...localized, collapseKey: ev.collapseKey, url: ev.url });
      if (d.platform === "android") await sendFcm(d.token, { ...localized, data: flat(ev) });
      if (d.platform === "ios")     await sendApns(d.token, localized, { topic: process.env.IOS_BUNDLE!, pushType: "alert" });
      delivered = true;
    } catch { /* prune handled inside providers; keep trying other devices */ }
  }
  // Fallback: if push reached nothing and it matters, fall through to email/SMS.
  if (!delivered && ev.critical) await fallbackChannel(userId, ev);  // email-integration-advanced / voice-sms-telephony
}
```

---

## 5. Edge cases

- **Token rot is constant:** prune on APNs `410`/`BadDeviceToken`, FCM `UNREGISTERED`/`NOT_FOUND`,
  Web Push `404`/`410`. Re-register tokens on app launch; treat one device = one token (dedupe).
- **iOS background vs alert:** `apns-push-type` must match (`background` pushes need
  `content-available:1`, `apns-priority:5`, and are throttled — don't use for visible alerts).
- **Web Push payload limit ~4KB**; keep it tiny, hydrate details on click.
- **Collapsing:** FCM `collapse_key` / APNs `apns-collapse-id` / Web `tag` replace the prior
  notification on-device — great for "3 unread" → one, dangerous for OTPs (don't collapse those).
- **Quiet hours across DST / travel:** compute in the user's *current* tz; a deferred notification
  shouldn't fire at 3am because you stored a UTC offset.
- **Duplicate across channels:** if the user is *active in-app*, suppress the push (they already saw it).
- **Permission revoked:** the OS stops delivering silently — track engagement and re-prompt in context.
- **Localization at send time** (not subscribe time) — the user may have switched language.

---

## 6. Performance & scale

- **Batch/multicast:** FCM v1 supports per-token sends; use concurrency-limited workers + HTTP/2
  connection reuse (APNs especially — one long-lived `http2` session, many requests). Don't open a
  socket per push.
- **Fan-out from a queue** (BullMQ/SQS) with rate limits per provider; shard by user.
- **Digest/coalesce** high-frequency categories server-side to cut volume and user annoyance.
- **Prune aggressively** — sending to dead tokens wastes quota and skews delivery metrics.
- **Token store** indexed by user; keep `last_seen`/`platform`/`locale` for targeting.

---

## 7. Security & privacy

- **Secrets:** APNs `.p8`, FCM service-account JSON, and VAPID private key are server-only secrets —
  encrypt, rotate, never ship to clients (the VAPID *public* key and FCM *web* config are public).
- **Explicit, in-context consent**; store per-category opt-in + timestamp; honor revocation.
- **Minimize PII in payloads** — push transits third-party services (APNs/FCM/browser push); put
  identifiers, not sensitive content; hydrate after auth on tap.
- **Don't leak on lock screen:** sensitive categories use generic alert text ("New message") and
  reveal detail only after unlock.
- **Validate device-token ownership** (bind token→authenticated user) to prevent cross-user push.

---

## 8. Scale & reliability

- **Idempotent notifications:** dedupe by `(user, event_id)` so a retried job doesn't double-buzz.
- **Provider abstraction** (`PushProvider`: `send`, `prune`) → swap/fallback FCM↔APNs↔WebPush↔managed.
- **In-app center is the durable source of truth**; push is best-effort delivery of it.
- **Outbox** so notifications are transactional with the triggering event.
- **Graceful degradation:** provider down → queue + retry, and fall back to email/SMS for criticals.

---

## 9. Testing

- **Token lifecycle:** simulate `410`/`UNREGISTERED` → token pruned, not retried forever.
- **Preferences/quiet hours:** opted-out category → no push; quiet hours → deferred to correct local time;
  `critical` → bypasses both.
- **Dedupe/collapse:** 5 rapid same-collapseKey events → 1 device notification (+ digest), OTP never collapsed.
- **Fallback:** all devices fail + critical → email/SMS fires.
- **Platform payloads:** APNs sandbox + FCM test token + a real browser subscription end-to-end.

---

## 10. Observability

- **Funnel:** sent → accepted (provider 2xx) → (where available) delivered → opened/clicked, per platform/category.
- **Token health:** active vs pruned, prune rate (spike = bad token handling or mass uninstall).
- **Suppression reasons:** opted-out / quiet-hours-deferred / deduped / no-active-device.
- **Opt-out & mute rate per category** (the real signal you're over-notifying).
- **Provider errors** (APNs status, FCM error codes) and latency; fallback invocation rate.

---

## 11. i18n / RTL (Arabic)

- **Localize at send time** to the user's current locale; render title/body `dir="auto"` (Web
  `showNotification({ dir: "auto", lang })`); OS notification UIs mirror RTL automatically on
  Arabic-locale devices.
- **Per-locale templates** with ICU pluralization (Arabic has 6 plural forms — `Intl.PluralRules`),
  not string concatenation.
- Keep LTR tokens (codes, amounts) inside bidi isolates; format numbers/dates with `Intl`.
- Test truncation in Arabic (longer strings) on lock-screen previews.

---

## 12. Anti-patterns

- **Using legacy FCM server keys / HTTP legacy API** → removed in 2024; use HTTP v1 (OAuth2).
- **APNs `.p12` cert auth** with yearly rotation pain → use token-based `.p8` (ES256) over HTTP/2.
- **Never pruning dead tokens** → wasted quota, garbage delivery metrics.
- **Permission prompt on first launch** → instant deny; ask in context after showing value.
- **No preferences / no quiet hours / no fallback** → users mute the app; criticals get lost.
- **Sensitive content in payloads / lock screen** → privacy leak through third-party push services.
- **Collapsing OTPs** or treating push as guaranteed delivery for critical messages.
- **String-concatenated, un-localized copy** → broken Arabic plurals and RTL.

## 13. Agent checklist

```
- [ ] Web Push (VAPID + SW), FCM HTTP v1 (OAuth2), APNs token (.p8 ES256, HTTP/2) — secrets server-only
- [ ] Device-token store bound to authed user; prune on 410/UNREGISTERED/404; re-register on launch
- [ ] Orchestrator: per-category preferences + quiet hours (user TZ) + critical bypass
- [ ] Dedupe/collapse (tag/collapse_key/apns-collapse-id); digest high-frequency categories (never OTP)
- [ ] Channel priority in-app ▸ push ▸ email/SMS fallback for criticals; in-app center is durable record
- [ ] In-context permission prompt; explicit per-category consent stored + revocable
- [ ] Minimal PII in payloads; generic lock-screen text for sensitive categories
- [ ] Idempotent (user,event_id); outbox; provider abstraction + retries
- [ ] Localize at send time; dir=auto; ICU plurals (Arabic 6 forms); Intl number/date
- [ ] Metrics: funnel, token prune rate, opt-out/mute per category, fallback rate
```

## 14. References (2026)
- FCM HTTP v1 send: https://firebase.google.com/docs/cloud-messaging/send-message · Migration: https://firebase.google.com/docs/cloud-messaging/migrate-v1
- APNs token-based auth: https://developer.apple.com/documentation/usernotifications/establishing-a-token-based-connection-to-apns
- APNs payload: https://developer.apple.com/documentation/usernotifications/setting-up-a-remote-notification-server
- Web Push API (MDN): https://developer.mozilla.org/en-US/docs/Web/API/Push_API · VAPID (RFC 8292): https://www.rfc-editor.org/rfc/rfc8292
- `web-push` library: https://github.com/web-push-libs/web-push
- Orchestration: https://docs.knock.app · https://www.courier.com/docs · https://docs.novu.co

## 15. Related
`realtime-chat-messaging`, `email-integration-advanced`, `voice-sms-telephony`,
`omnichannel-inbox-chatbot`, `whatsapp-business-integration` · `analytics-master` (engagement),
`backend-api-master` (auth, integrations-pro).
