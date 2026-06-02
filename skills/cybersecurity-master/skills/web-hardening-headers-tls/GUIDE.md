---
name: web-hardening-headers-tls
description: >-
  Harden the HTTP/TLS edge at staff depth: strict CSP (per-request nonce + strict-dynamic, Report-Only
  rollout), HSTS+preload, Referrer-Policy, Permissions-Policy, frame-ancestors/X-Frame-Options,
  COOP/COEP, cookie flags (HttpOnly/Secure/SameSite + __Host-), CORS done right (never reflect-any),
  TLS 1.3 cipher config + OCSP stapling. Copy-paste header sets for Next.js and nginx.
---

# Web Hardening — Security Headers, Cookies & TLS

**Mandate:** the response headers and TLS config are a **free, high-leverage defense layer** that
turns "one XSS = total compromise" into "one XSS = blocked by CSP, can't steal the cookie, can't
frame the page." These are defense-in-depth: they don't replace fixing the bug, they contain the
blast radius when one slips through. Ship them by construction, verify them in CI.

## When to use / NOT
**Use** on every internet-facing app/API. **Don't** treat headers as a substitute for output
encoding/AuthZ (`appsec-owasp-top10`) — a strict CSP mitigates XSS impact but a missing `orgId`
filter is still an IDOR. Headers are the *last* line, applied *first*.

## Mental model: what each header stops

| Header | Stops (attacker view) | If missing |
|--------|----------------------|-----------|
| `Content-Security-Policy` | Injected/3p script execution (XSS) | XSS → full account takeover |
| `Strict-Transport-Security` | SSL-strip / downgrade MITM | First/again requests over http |
| `Set-Cookie` flags | Cookie theft via JS/MITM/CSRF | Session stolen by XSS or sent cross-site |
| CORS (`Access-Control-*`) | Cross-origin reads of authed responses | Any site reads your API as the user |
| `X-Frame-Options`/`frame-ancestors` | Clickjacking | UI redress overlay attacks |
| `Referrer-Policy` | URL/token leakage to 3p | Secrets in querystrings leak via Referer |
| `Permissions-Policy` | Abuse of camera/geo/etc by injected code | Powerful APIs available to XSS |
| `X-Content-Type-Options` | MIME sniffing → script from "image" | Polyglot upload executes |

---

## 1. Content-Security-Policy — the crown jewel (strict, nonce-based)

The 2026 consensus (web.dev, MDN, OWASP CSP Cheat Sheet): **a strict, nonce-based CSP with
`strict-dynamic`** — *not* a host allowlist (allowlists are bypassable via JSONP/CDNs and a nightmare
to maintain).

```
Content-Security-Policy:
  script-src 'nonce-{RANDOM}' 'strict-dynamic';
  object-src 'none';
  base-uri 'none';
  require-trusted-types-for 'script';
```

Why this shape:
- `'nonce-{RANDOM}'` — a fresh, ≥128-bit CSPRNG value **per response**; only your server-rendered
  scripts carry it, so injected `<script>` can't execute.
- `'strict-dynamic'` — scripts trusted by nonce may load their own scripts (so bundlers/3p widgets
  work) without you allowlisting hosts. Modern browsers ignore host allowlists when this is present —
  good, allowlists are the bypass.
- `object-src 'none'` + `base-uri 'none'` — kill Flash/`<object>` and `<base>`-tag injection.
- `require-trusted-types-for 'script'` — defuse DOM XSS sinks (`innerHTML`) where supported.

### Generate a nonce per request (Next.js middleware)

```ts
// middleware.ts (Next.js App Router) — nonce per request, strict CSP
import { NextResponse, type NextRequest } from "next/server";

export function middleware(req: NextRequest) {
  const nonce = Buffer.from(crypto.randomUUID()).toString("base64");
  const csp = [
    `default-src 'self'`,
    `script-src 'nonce-${nonce}' 'strict-dynamic' https: 'unsafe-inline'`, // https+unsafe-inline = fallback, IGNORED by modern browsers when nonce present
    `style-src 'self' 'nonce-${nonce}'`,
    `img-src 'self' data: blob:`,
    `font-src 'self'`,
    `object-src 'none'`,
    `base-uri 'none'`,
    `form-action 'self'`,
    `frame-ancestors 'none'`,
    `upgrade-insecure-requests`,
  ].join("; ");

  const reqHeaders = new Headers(req.headers);
  reqHeaders.set("x-nonce", nonce);                 // pass nonce to the app to tag scripts
  const res = NextResponse.next({ request: { headers: reqHeaders } });
  res.headers.set("Content-Security-Policy", csp);
  return res;
}
export const config = { matcher: "/((?!_next/static|_next/image|favicon.ico).*)" };
```

```tsx
// app/layout.tsx — read the nonce and apply to scripts; Next propagates it to its own scripts
import { headers } from "next/headers";
export default async function RootLayout({ children }) {
  const nonce = (await headers()).get("x-nonce") ?? "";
  return (<html><body>{children}<script nonce={nonce} src="/analytics.js" /></body></html>);
}
```

### Rollout without breaking prod (mandatory process)

1. Ship **`Content-Security-Policy-Report-Only`** with the target policy + a reporting endpoint.
2. Collect **≥2 weeks** of real-user reports (one full release cycle + weekly crons + long-tail
   browsers/extensions).
3. Triage: *legit-but-missed* → fix the loading to use nonce; *inline* → move to nonce/hash;
   *extension noise* → ignore; *real attack* → alert.
4. Promote to enforcing `Content-Security-Policy`, **keep Report-Only running** with the next
   iteration. Both headers can run simultaneously.

```
# Report-Only + Reporting API endpoint
Reporting-Endpoints: csp="https://example.com/csp-reports"
Content-Security-Policy-Report-Only: script-src 'nonce-{RANDOM}' 'strict-dynamic'; object-src 'none'; base-uri 'none'; report-to csp
```

> **Never** build middleware that regex-injects `nonce=` into every `<script>` — attacker-injected
> tags would get the nonce too. Use a real templating engine / framework nonce propagation.

---

## 2. The full production header set

### Next.js (`next.config.js`) — static headers (CSP via middleware as above)

```js
const securityHeaders = [
  { key: "Strict-Transport-Security", value: "max-age=63072000; includeSubDomains; preload" },
  { key: "X-Content-Type-Options", value: "nosniff" },
  { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
  { key: "X-Frame-Options", value: "DENY" },                      // legacy backstop for frame-ancestors
  { key: "Permissions-Policy", value: "camera=(), microphone=(), geolocation=(), browsing-topics=()" },
  { key: "Cross-Origin-Opener-Policy", value: "same-origin" },    // process isolation (Spectre)
  { key: "Cross-Origin-Resource-Policy", value: "same-origin" },
];
module.exports = {
  poweredByHeader: false,                                          // drop X-Powered-By fingerprint
  async headers() { return [{ source: "/:path*", headers: securityHeaders }]; },
};
```

### nginx — server block

```nginx
# --- TLS 1.3 (and 1.2 floor) — Mozilla "Intermediate" 2026 ---
ssl_protocols TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers off;                                    # let TLS1.3 client pick (all are safe)
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
ssl_ecdh_curve X25519:prime256v1:secp384r1;
ssl_session_timeout 1d;
ssl_session_cache shared:MozSSL:10m;                              # ~40k sessions
ssl_session_tickets off;                                          # forward secrecy hygiene
ssl_stapling on;                                                  # OCSP stapling (faster + private)
ssl_stapling_verify on;
resolver 1.1.1.1 8.8.8.8 valid=300s;

# --- Security headers (add_header applies; use 'always' so they're set on errors too) ---
add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
add_header X-Content-Type-Options "nosniff" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
add_header X-Frame-Options "DENY" always;
add_header Permissions-Policy "camera=(), microphone=(), geolocation=()" always;
add_header Content-Security-Policy "default-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'" always;
```

---

## 3. HSTS + preload (don't preload until you're sure)

```
Strict-Transport-Security: max-age=63072000; includeSubDomains; preload
```

- `max-age` 2 years (63072000s) is the preload-list requirement.
- `includeSubDomains` — **every** subdomain must be HTTPS-capable forever, or you brick them.
- `preload` — submit at https://hstspreload.org. This is **baked into browsers and hard to undo**
  (removal takes months). Only preload when you're certain all subdomains are HTTPS, possibly for
  years. Start without `preload`, prove it, then submit.

---

## 4. Cookies — the session lives or dies here

```
Set-Cookie: __Host-session=<value>; Max-Age=3600; Path=/; Secure; HttpOnly; SameSite=Lax
```

| Flag | Does | Why |
|------|------|-----|
| `HttpOnly` | JS can't read it | XSS can't exfiltrate the session |
| `Secure` | HTTPS only | No cleartext leak / SSL-strip |
| `SameSite=Lax` | Not sent on cross-site subrequests | CSRF defense (use `Strict` for admin) |
| `__Host-` prefix | Requires Secure + Path=/ + **no Domain** | Locks cookie to exact origin; can't be set by a subdomain attacker |

```ts
// express / @fastify/cookie
res.cookie("__Host-session", token, {
  httpOnly: true, secure: true, sameSite: "lax", path: "/", maxAge: 3_600_000,
});
```

Senior notes: `SameSite=Lax` is a strong CSRF baseline but **not complete** — pair state-changing
endpoints with anti-CSRF tokens (double-submit or synchronizer) or require a custom header +
SameSite. Use `SameSite=None; Secure` *only* for genuinely cross-site cookies (and then you need CSRF
tokens). Never put a session token in `localStorage` — it's readable by any XSS.

---

## 5. CORS — the most-misconfigured header (do NOT reflect any origin)

```ts
// ❌ CATASTROPHIC: reflect Origin + allow credentials → every site reads your authed API
res.setHeader("Access-Control-Allow-Origin", req.headers.origin);   // reflect-any
res.setHeader("Access-Control-Allow-Credentials", "true");
```

```ts
// ✅ FIXED: strict allowlist; only echo a vetted origin; never '*' with credentials
const ALLOWED = new Set(["https://app.example.com", "https://admin.example.com"]);
function cors(req, res, next) {
  const origin = req.headers.origin;
  if (origin && ALLOWED.has(origin)) {
    res.setHeader("Access-Control-Allow-Origin", origin);    // echo only if allowlisted
    res.setHeader("Vary", "Origin");                          // cache correctness
    res.setHeader("Access-Control-Allow-Credentials", "true");
    res.setHeader("Access-Control-Allow-Methods", "GET,POST,PUT,DELETE,OPTIONS");
    res.setHeader("Access-Control-Allow-Headers", "Content-Type,Authorization");
    res.setHeader("Access-Control-Max-Age", "600");
  }
  if (req.method === "OPTIONS") return res.sendStatus(204);    // preflight
  next();
}
```

Hard rules: **`Access-Control-Allow-Origin: *` and `Allow-Credentials: true` are mutually exclusive**
(browser rejects), and reflecting `Origin` *is* effectively `*` for attackers. Don't trust CORS as
authZ — it only governs *browser* cross-origin reads; your server still must authenticate every
request. Watch for `null` origin and suffix-match bugs (`evil-example.com` matching `example.com`).

---

## 6. Clickjacking — frame-ancestors (CSP) is authoritative

```
Content-Security-Policy: frame-ancestors 'none';     # or 'self' / explicit allowlist
X-Frame-Options: DENY                                 # legacy backstop for old browsers
```

`frame-ancestors` (CSP3) supersedes `X-Frame-Options` and supports multiple origins; keep XFO as a
backstop. For payment/admin flows use `'none'`.

---

## 7. TLS 1.3 specifics
- **Prefer TLS 1.3**: 1-RTT handshakes, only AEAD ciphers, forward secrecy by default, encrypted
  handshake. Keep TLS 1.2 as floor; **disable TLS 1.0/1.1/SSLv3** (PCI-banned, broken).
- 1.3 cipher suites are fixed/safe: `TLS_AES_128_GCM_SHA256`, `TLS_AES_256_GCM_SHA384`,
  `TLS_CHACHA20_POLY1305_SHA256` — don't fiddle. Only the 1.2 list needs curation (ECDHE + AEAD).
- **OCSP stapling** (`ssl_stapling on`) — server fetches revocation status and staples it, so clients
  don't leak browsing to the CA and pages load faster. Consider **OCSP Must-Staple** on the cert.
- **0-RTT (early data)** is replayable — only enable for idempotent GETs, never state-changing
  requests.
- Automate certs (ACME / cert-manager); short-lived + auto-renew. Test config at SSL Labs (target A+).

---

## 8. Performance impact
- Headers: **~zero** cost (a few hundred bytes/response; gzip handles it).
- TLS 1.3: *faster* than 1.2 (1-RTT, 0-RTT for repeat) — modern AES-NI makes symmetric crypto free.
- OCSP stapling: removes a client-side CA round-trip → faster first paint.
- CSP nonce generation: one `randomUUID()`/request — negligible. The real cost is *engineering time*
  to roll out strict CSP cleanly — pay it once.

## 9. Scale / multi-tenant
- Per-tenant custom domains: each needs its own cert (ACME automation), HSTS decision, and CSP that
  accounts for tenant-specific script sources (prefer nonce so you don't maintain N allowlists).
- Set headers at the **edge/CDN** for consistency, but the **CSP nonce must be per-response from the
  origin** — don't cache a page with a fixed nonce (it defeats the control). Mark nonce'd HTML
  `Cache-Control: no-store` or use edge-computed nonces.

## 10. Testing & verification
```bash
# header audit
curl -sI https://example.com | grep -iE 'content-security|strict-transport|x-frame|referrer|permissions'
# automated graders (CI-friendly)
#   - Mozilla Observatory  (https://developer.mozilla.org/observatory)
#   - securityheaders.com
#   - SSL Labs (TLS): https://www.ssllabs.com/ssltest/
nuclei -u https://example.com -t http/misconfiguration/   # missing-headers templates
```
- CI gate: assert presence + value of each header in an integration test; fail the build if CSP
  weakens (e.g. `'unsafe-eval'` sneaks in).
- Use `report-to`/Reporting API to monitor CSP violations continuously (it doubles as XSS-attempt
  detection).

## 11. Observability
CSP reports are a **detection feed** — a spike of `script-src` violations on one route can be a live
XSS attempt. Pipe `report-to` into your SIEM (`security-operations-ir-compliance`).

## 12. Accessibility / i18n
- `Permissions-Policy` denials can silently break assistive features that legitimately use
  microphone/camera — allowlist those origins rather than blanket-deny if you ship a11y voice tools.
- Header-driven HTTPS redirects must preserve locale path prefixes (`/fr/…`) — test i18n routes.

## Anti-patterns
- CSP with `'unsafe-inline'`/`'unsafe-eval'` in `script-src` and no nonce → no XSS protection at all.
- Host-allowlist CSP instead of nonce + strict-dynamic (bypassable, unmaintainable).
- Reflecting `Origin` in `Access-Control-Allow-Origin` (with credentials) = open API.
- Session token in `localStorage`/non-HttpOnly cookie (XSS-stealable).
- `includeSubDomains; preload` shipped before every subdomain is HTTPS (you brick them).
- TLS 1.0/1.1 still enabled; cipher lists copy-pasted from a 2015 blog.
- Caching a page that carries a per-request CSP nonce.

## Agent checklist
```
- [ ] Strict CSP: nonce + strict-dynamic, object-src/base-uri 'none', frame-ancestors set
- [ ] CSP rolled out via Report-Only first (≥2 weeks) + reporting endpoint, then enforced
- [ ] HSTS max-age≥1yr + includeSubDomains; preload only after subdomain audit
- [ ] Cookies: __Host- prefix, HttpOnly, Secure, SameSite (+ CSRF tokens for state change)
- [ ] CORS allowlist (no Origin reflection); credentials never with '*'
- [ ] X-Content-Type-Options nosniff; Referrer-Policy strict-origin-when-cross-origin; Permissions-Policy locked
- [ ] TLS 1.3 + 1.2 floor; 1.0/1.1 disabled; OCSP stapling; SSL Labs A+
- [ ] Header presence/values asserted in CI; Observatory/securityheaders graded
```

## References
- web.dev Strict CSP: https://web.dev/articles/strict-csp · MDN CSP: https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/CSP
- OWASP Secure Headers Project: https://owasp.org/www-project-secure-headers/
- Mozilla SSL Config Generator: https://ssl-config.mozilla.org/ · HSTS preload: https://hstspreload.org/
- OWASP CSP / CORS Cheat Sheets: https://cheatsheetseries.owasp.org/

## Related
`appsec-owasp-top10` (XSS/A05, A02), `auth-session-account-security` (cookies/CSRF/sessions),
`ddos-waf-bot-protection` (edge), `security-operations-ir-compliance` (CSP report monitoring).
