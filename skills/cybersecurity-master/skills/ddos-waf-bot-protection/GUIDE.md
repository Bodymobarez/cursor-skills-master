---
name: ddos-waf-bot-protection
description: >-
  Defend the edge at staff depth: DDoS mitigation (L3/4 volumetric vs L7 application), Cloudflare/CDN
  posture, WAF (Cloudflare Managed Ruleset + Attack Score vs OWASP CRS, custom rules), rate-limiting
  algorithms (token bucket vs sliding window), bot management, Cloudflare Turnstile/CAPTCHA with
  accessibility, credential-stuffing/scraping defense, and edge caching as a DDoS control.
---

# DDoS, WAF & Bot Protection — Edge Defense

**Mandate:** the edge (CDN/WAF/rate-limiter/bot-manager) absorbs volume and obvious attacks so your
origin only handles legitimate, shaped traffic. It is **defense in depth, not a substitute** for
fixing the app — a WAF "virtual patch" buys time; the code fix is the real remediation. The goal:
keep the service **available** and make automated abuse uneconomical.

## When to use / NOT
**Use** for any internet-facing app/API: configuring CDN/WAF, rate limits, bot/CAPTCHA, or responding
to a flood/scraping/credential-stuffing wave. **Don't** rely on the WAF to "cover" SQLi/XSS — it
reduces exposure but is bypassable; fix the root cause (`appsec-owasp-top10`).

## Mental model: layered funnel

```
Internet → [Anycast network: L3/4 DDoS absorb] → [WAF: signatures + attack score]
        → [Rate limiting: per-IP/user/key] → [Bot management + Turnstile challenge]
        → [Cache: serve static at edge] → ORIGIN (only clean, shaped traffic)
```

Each layer drops a class of traffic so the next sees less. Order matters: cheap/coarse filters
(volumetric, IP reputation) first; expensive/precise checks (bot ML, challenges) later.

---

## 1. DDoS types + mitigation

| Layer | Attack | Example | Mitigation |
|-------|--------|---------|-----------|
| **L3/4 (volumetric)** | saturate bandwidth/state | SYN/UDP/DNS amplification flood | Anycast scrubbing network (Cloudflare/AWS Shield/Akamai) — **must** be upstream of origin |
| **L7 (application)** | exhaust app resources cheaply | HTTP flood, "low & slow" (Slowloris), expensive-query flood | WAF + rate limiting + challenges + caching; per-endpoint cost awareness |
| **App logic** | abuse expensive operations | unauth'd search/report/export spam | auth-gate, rate-limit, queue, cache, async |

Senior reality: **you cannot absorb a modern multi-Tbps volumetric attack at your origin** — you need
an Anycast provider in front whose capacity dwarfs the attack. **Never expose origin IPs** (attackers
bypass the CDN by hitting the IP directly): lock origin firewall to the CDN's IP ranges + a shared
secret header (Authenticated Origin Pull / mTLS). L7 is where *your* config matters most — that's the
rest of this skill.

---

## 2. WAF — managed first, custom for your app, CRS with care

```
# Cloudflare WAF layering (2026), in execution order:
#  1. HTTP DDoS managed (ddos_l7)        → auto
#  2. Custom Rules (http_request_firewall_custom)
#  3. Rate Limiting (http_ratelimit)
#  4. Managed Rules (http_request_firewall_managed): Cloudflare Managed Ruleset + Attack Score
```

| Ruleset | What | Use |
|---------|------|-----|
| **Cloudflare Managed Ruleset** | curated signatures, low false-positive | ✅ enable first |
| **WAF Attack Score** (Biz/Ent) | ML likelihood a request is an attack | ✅ great catch-all custom rule |
| **OWASP Core Rule Set** (CRS 3.3.0) | cumulative anomaly scoring | ⚠️ false-positive prone; Cloudflare itself says marginal on top of the above — enable only for compliance, **Log mode first**, tune for weeks |
| **Custom rules** | your app's specifics | ✅ block known-bad paths, geo/ASN, header anomalies |
| **Leaked Credential Detection** | flags known-breached creds at login | ✅ pair with auth defense |

```js
// ✅ custom rule expressions (Cloudflare WAF) — examples
// block the Next.js middleware-bypass header at the edge (defense in depth for CVE-2025-29927)
(http.request.headers["x-middleware-subrequest"][0] ne "")
// challenge high-attack-score requests to sensitive paths
(cf.waf.score lt 20 and http.request.uri.path contains "/api/")
```

Process: **monitor (Log) → tune → enforce.** Deploy rules in log-only, watch real traffic for false
positives, then promote to Block/Managed Challenge. A WAF that blocks real users gets disabled — and
then you have no WAF.

---

## 3. Rate limiting — pick the right algorithm

| Algorithm | Behavior | Best for | Trade-off |
|-----------|----------|----------|-----------|
| **Fixed window** | N per calendar window | simplest | boundary bursts (2N across the edge) |
| **Sliding window** | smoothed over rolling window | general API limits | slightly more state |
| **Token bucket** | refill rate + burst capacity | allow bursts, cap sustained | tune burst vs rate |
| **Leaky bucket** | constant drain | smooth/queue outbound | adds latency |

```ts
// ✅ token bucket at the app (defense in depth behind edge limits) — Redis, atomic via Lua
// key by the most specific identity you have: user > API key > IP (IPs are shared/spoofable)
// edge does coarse per-IP; app does precise per-account/key/endpoint
```

```
# ✅ Cloudflare rate limiting rule (edge) — protect login from credential stuffing
#   match: http.request.uri.path eq "/api/auth/login"  and method POST
#   characteristics: ip.src  (+ a header/cookie if available)
#   rate: 10 requests / 1 min  → action: Managed Challenge (then Block on repeat)
```

Rules: rate-limit by **identity, not just IP** (stuffing rotates IPs; IPs are shared by NAT/CGNAT —
blocking an IP can take out a whole office). Per-endpoint limits (login + password-reset + search +
export are tighter than reads). Return `429` with `Retry-After`. Do coarse limiting at the edge,
precise limiting at the app. Watch for **distributed low-and-slow** that stays under any single
threshold — that's where bot ML + behavioral signals earn their keep.

---

## 4. Bot management + Turnstile/CAPTCHA

Good bots (search crawlers, monitors) vs bad bots (scrapers, stuffers, scalpers, spam). Distinguish
with: TLS/HTTP fingerprinting (JA3/JA4), behavioral ML, IP reputation, and **proof-of-work / managed
challenges** rather than legacy image CAPTCHAs.

```html
<!-- ✅ Cloudflare Turnstile — privacy-friendly, mostly invisible, accessible alternative to reCAPTCHA -->
<div class="cf-turnstile" data-sitekey="0xYOURSITEKEY" data-action="login" data-theme="auto"></div>
<script src="https://challenges.cloudflare.com/turnstile/v0/api.js" async defer></script>
```

```ts
// ✅ ALWAYS verify the token server-side — never trust the client widget alone
async function verifyTurnstile(token: string, ip: string) {
  const r = await fetch("https://challenges.cloudflare.com/turnstile/v0/siteverify", {
    method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ secret: process.env.TURNSTILE_SECRET!, response: token, remoteip: ip }),
  });
  const data = await r.json();
  return data.success === true;        // also check action/hostname/cdata if you set them
}
```

Senior take: deploy challenges **adaptively** (only on risk signals — new device, high attack score,
rate-limit trip), not on every pageview (kills conversion + UX). Turnstile/managed challenges beat
image CAPTCHAs on both UX and accessibility. **Verify the token on the server** every time. For
scraping defense, combine bot scoring + rate limits + (for APIs) authenticated keys with quotas.

### Accessibility & i18n (don't lock out real users)

- **Never** an image/audio CAPTCHA as the *only* path — it fails screen-reader and low-vision/deaf
  users (WCAG 1.1.1). Prefer Turnstile/proof-of-work (non-interactive) or hCaptcha's accessibility
  cookie. If you must use a visual challenge, provide an accessible alternative (audio + a non-visual
  fallback) and don't time-box so tightly that assistive-tech users fail.
- Localize challenge UI + error/`429` messaging; `data-theme="auto"` respects dark mode; ensure the
  widget is keyboard-focusable and announces state to AT.
- Avoid blanket geo/ASN blocks that wall off legitimate regions; prefer behavioral signals.

---

## 5. Edge caching as a DDoS control
A cache hit never touches your origin — so **cacheable content is implicitly DDoS-resistant**. Cache
static assets aggressively (immutable + long max-age + hashed filenames) and cache anonymous,
non-personalized HTML/API responses at the edge. Under an L7 flood, a high cache-hit ratio means the
origin barely notices. **Never** cache authenticated/personalized responses without a per-user key
(cache poisoning / data leak). Set an "under attack" mode (Cloudflare) that challenges all new
visitors during an active incident.

---

## 6. Performance impact
- CDN/edge typically *improves* performance (cache + Anycast proximity) while adding protection.
- WAF inspection: sub-millisecond per request at the edge; negligible.
- Challenges add user-visible friction → use adaptively. Turnstile is mostly invisible (near-zero
  friction for legit users).
- App-layer rate limiting: one Redis round-trip — cheap; do the bulk at the edge to keep origin load
  low during attacks.

## 7. Scale / multi-tenant
- Per-tenant custom domains all behind one edge config; per-tenant rate-limit + bot policies (a noisy
  tenant shouldn't trip another's limits). Tenant-aware cache keys to prevent cross-tenant leakage.
- Anycast scales horizontally by design; your **origin** is the bottleneck — keep it private,
  autoscaled, and shielded so only shaped traffic arrives.

## 8. Testing & verification
- Load/stress test your *own* infra (k6, Locust) in a controlled window to validate rate limits +
  autoscale (this is capacity testing, **not** an attack on anyone else).
- Verify WAF rules in Log mode against real + simulated malicious traffic before enforcing; confirm
  origin is **not** reachable by direct IP (the #1 DDoS-protection bypass).
- Test Turnstile server-side verification rejects missing/replayed/invalid tokens; test the
  accessible challenge path with a screen reader.

## 9. Observability
- Dashboards: requests by WAF action, attack-score distribution, rate-limit trips, bot vs human,
  cache-hit ratio, origin RPS/latency, `429`/`403` rates. Alert on traffic spikes, attack-score
  surges, and origin saturation **before** users feel it. Feed sustained attacks into IR
  (`security-operations-ir-compliance`); credential-stuffing signals into auth defense.

## Anti-patterns
- Exposing origin IPs / not locking origin to CDN ranges (lets attackers bypass all edge protection).
- Treating the WAF as a fix for app bugs (it's a time-buying virtual patch, bypassable).
- Enabling OWASP CRS at full strength in Block mode day one (false-positive storm → users blocked).
- Rate-limiting by IP only (NAT collateral damage; stuffing rotates IPs anyway).
- CAPTCHA on every pageview (conversion + a11y disaster); image-only CAPTCHA with no accessible path.
- Caching personalized/authenticated responses without per-user keys (leak/poisoning).
- No "under attack" runbook — scrambling to configure mid-incident.

## Agent checklist
```
- [ ] Anycast/CDN in front for L3/4; origin private + locked to CDN IPs + Authenticated Origin Pull
- [ ] WAF: Managed Ruleset + Attack Score enabled; custom rules for app; CRS only if needed (Log first)
- [ ] Rate limits by identity (user/key) + IP; tighter on login/reset/search/export; 429 + Retry-After
- [ ] Adaptive bot challenge (Turnstile) on risk signals; token verified SERVER-SIDE
- [ ] CAPTCHA has accessible/non-visual path; UI localized; no blanket geo blocks
- [ ] Aggressive edge caching for static/anonymous; never cache personalized w/o per-user key
- [ ] Dashboards + alerts (attack score, rate trips, origin saturation); "under attack" runbook ready
- [ ] WAF rules validated in Log mode before enforce; rate limits load-tested
```

## References
- Cloudflare WAF Managed Rules: https://developers.cloudflare.com/waf/managed-rules/
- Cloudflare Rate Limiting: https://developers.cloudflare.com/waf/rate-limiting-rules/ · Turnstile: https://developers.cloudflare.com/turnstile/
- OWASP DoS Cheat Sheet: https://cheatsheetseries.owasp.org/cheatsheets/Denial_of_Service_Cheat_Sheet.html
- OWASP Core Rule Set: https://coreruleset.org/ · AWS Shield/WAF: https://docs.aws.amazon.com/waf/
- WCAG CAPTCHA guidance: https://www.w3.org/TR/turingtest/

## Related
`auth-session-account-security` (credential stuffing/lockout), `web-hardening-headers-tls` (edge),
`appsec-owasp-top10` (fix the root cause behind virtual patches), `security-operations-ir-compliance`
(attack → IR), `infra-cloud-network-security` (origin shielding).
