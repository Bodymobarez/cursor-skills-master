---
name: auth-session-account-security
description: >-
  Build authentication that survives real attacks at staff depth: argon2id password hashing (OWASP
  params), session vs JWT (and JWT's footguns — alg=none, weak secret, no exp, storage), session
  fixation/rotation, MFA (TOTP/WebAuthn-passkeys), OAuth2/OIDC security (PKCE, state, redirect
  validation), and account-takeover defense (credential stuffing, lockout, breached-password checks,
  secure password reset). Maps to OWASP A07.
---

# Auth, Session & Account Security

**Mandate:** auth is the single highest-value target in your app — own it. The rule for 2026: **don't
hand-roll auth.** Use a vetted library/IdP (Auth.js, Lucia, Ory, Keycloak, WorkOS, Clerk, Cognito,
Entra ID) and configure it correctly. This skill is what "correctly" means: the parameters,
pitfalls, and ATO defenses that vetted libraries still let you get wrong.

> Frame: every technique here defends *your* users' accounts. Attacker mindset ("how would I take
> over this account?") is how you find the gaps — applied only to systems you're authorized on.

## When to use / NOT
**Use** for any login, session, token, SSO, MFA, or password flow. **Don't** reimplement primitives
(crypto, OAuth state machines) — wire up audited libraries. If you're writing your own JWT verify
loop or password hasher, stop.

## Mental model: the account-takeover kill chain

```
credential theft (phish / breach reuse / keylogger)  ─┐
brute force / credential stuffing  ───────────────────┤→ valid creds → [MFA?] → session → [rotation?] → persistence
session hijack (XSS / fixation / token leak)  ────────┘
```

Each arrow is a control point: strong hashing + breach checks (theft), rate-limit + lockout
(brute/stuffing), **phishing-resistant MFA** (the big one), HttpOnly cookies + CSP (hijack), session
rotation + short TTL (persistence). Defense in depth — no single control is enough.

---

## 1. Password storage — argon2id, current OWASP params

```ts
import argon2 from "argon2";                                   // npm i argon2 (node-argon2)

// ✅ OWASP-recommended minimum (2026): m=19456 KiB (19 MiB), t=2, p=1
const HASH_OPTS = { type: argon2.argon2id, memoryCost: 19456, timeCost: 2, parallelism: 1 };

export const hashPassword = (pw: string) => argon2.hash(pw, HASH_OPTS);
export const verifyPassword = async (hash: string, pw: string) => {
  const ok = await argon2.verify(hash, pw);                    // constant-time, parses params from hash
  if (ok && argon2.needsRehash(hash, HASH_OPTS)) {/* schedule rehash on next login */}
  return ok;
};
```

OWASP Password Storage Cheat Sheet (current) — pick the profile that fits your latency budget; all
are equivalent security:

| Algo | Params | When |
|------|--------|------|
| **argon2id** ✅ | `m=19456, t=2, p=1` (min) — or `m=47104, t=1, p=1` / `m=64MB, t=3, p=1` (higher) | default for all new apps |
| scrypt | `N=2^17, r=8, p=1` | argon2 unavailable |
| **bcrypt** | work factor ≥10 (12 in 2026), **enforce 72-byte max** | legacy only; migrate on login |
| PBKDF2-HMAC-SHA256 | ≥600,000 iters | FIPS-140 compliance only |

Rules: salt is automatic + per-hash (in the encoded string). **Never** MD5/SHA-1/SHA-256 alone for
passwords (GPU-crackable at billions/sec). bcrypt's 72-byte limit is a real footgun — long
passphrases silently truncate; pre-hash with SHA-256→base64 if you must exceed it, or use argon2id.
Consider a **pepper** (app-level secret in KMS, separate from the DB) as defense-in-depth. Benchmark
on prod hardware: target ~50–250ms/verify.

---

## 2. Sessions vs JWT — choose deliberately

| | Server sessions (stateful) | JWT / stateless |
|---|---|---|
| Revocation | ✅ instant (delete row) | ❌ hard — valid until exp (need denylist = stateful anyway) |
| Logout/ban | ✅ trivial | ❌ token still works until expiry |
| Scale | needs shared store (Redis) | ✅ no lookup |
| Best for | web app sessions (default!) | service-to-service, short-lived access tokens |

**Senior default: server-side sessions for browser auth** (opaque random id in a `__Host-` cookie,
state in Redis/DB). Reach for JWT for *stateless service auth* or short-lived access tokens paired
with rotating refresh tokens. Don't use long-lived JWTs as your session — you can't revoke them.

### Session hardening

```ts
// ✅ rotate session id on EVERY privilege change (login, MFA, role elevation) → kills fixation
app.post("/login", async (req, res) => {
  const user = await authenticate(req.body);
  await req.session.regenerate();                 // NEW id; old fixed id is now useless
  req.session.userId = user.id;
  req.session.createdAt = Date.now();
  // cookie: __Host-, HttpOnly, Secure, SameSite=Lax, short idle + absolute TTL
});
```

- **Session fixation**: always *regenerate* the session id after authentication, never accept a
  pre-login id as authenticated.
- **Idle + absolute timeouts**: e.g. 30-min idle, 8–12h absolute. Re-auth (step-up) for sensitive
  actions.
- **Bind + monitor**: log IP/UA; alert on impossible travel / device change; offer "log out all
  sessions."

### JWT footguns (verify you avoid every one)

```ts
import jwt from "jsonwebtoken";
// ✅ pin algorithm, require exp/iss/aud, strong secret/asymmetric key
const payload = jwt.verify(token, PUBLIC_KEY, {
  algorithms: ["RS256"],          // ❌ NEVER allow "none"; ❌ don't accept HS256 if you issue RS256 (key-confusion)
  issuer: "https://auth.example.com",
  audience: "api.example.com",
  maxAge: "15m",
});
```

| Pitfall | Attack | Fix |
|---------|--------|-----|
| `alg: none` accepted | unsigned forged token | pin `algorithms:["RS256"]` allowlist |
| HS/RS confusion | sign with public key as HMAC secret | never accept HS when expecting RS |
| weak HMAC secret | offline crack → forge | ≥256-bit random secret, or asymmetric keys |
| no `exp` | token valid forever | require + short `exp` (5–15m access) |
| stored in localStorage | XSS steals it | HttpOnly cookie, or in-memory + refresh |
| no `aud`/`iss` check | token reuse across services | validate both |
| sensitive data in claims | base64 = plaintext, readable | never put secrets/PII in JWT |

Pattern: **short access token + rotating refresh token** (refresh stored HttpOnly, single-use,
rotation detection → reuse means theft → revoke family).

---

## 3. MFA — phishing-resistant first

| Factor | Phishing-resistant? | UX | Use |
|--------|--------------------|----|-----|
| **WebAuthn / passkeys** ✅ | **Yes** (origin-bound) | excellent | default; the 2026 gold standard |
| TOTP (authenticator app) | No (code is phishable) | good | solid second choice |
| Push w/ number-matching | Partly | good | enterprise |
| **SMS OTP** | No (SIM-swap, phishable) | familiar | last resort / not for high value |

```ts
// ✅ TOTP (RFC 6238) with otplib — but prefer WebAuthn
import { authenticator } from "otplib";
const secret = authenticator.generateSecret();                 // store encrypted (KMS), per user
const uri = authenticator.keyuri(user.email, "Example", secret); // → QR
const valid = authenticator.verify({ token: req.body.code, secret });
// window=1 tolerance; RATE-LIMIT verification (6-digit = 1M space, brute-forceable); single-use codes
```

```ts
// ✅ WebAuthn / passkeys with @simplewebauthn/server — origin + RP-ID bound = phishing-resistant
import { generateRegistrationOptions, verifyRegistrationResponse } from "@simplewebauthn/server";
const options = await generateRegistrationOptions({
  rpName: "Example", rpID: "example.com", userName: user.email,
  authenticatorSelection: { residentKey: "preferred", userVerification: "preferred" },
});
// store credential public key + counter; on auth, verify signature, origin, and counter increment
```

Passkeys win because the credential is **cryptographically bound to your origin** — a phishing site
on `examp1e.com` literally cannot use it. Push passkeys hard; keep TOTP as fallback; treat SMS as
break-glass only. Always issue **single-use recovery codes** (hashed) and rate-limit MFA entry.

---

## 4. OAuth2 / OIDC security (don't reinvent the dance)

```ts
// ✅ Authorization Code + PKCE + state + nonce (the only flow you should use in 2026)
// 1. client makes a per-request code_verifier (CSPRNG) → code_challenge = S256(verifier)
// 2. redirect with: response_type=code, code_challenge, code_challenge_method=S256,
//    state=<CSRF token>, nonce=<replay token>, exact redirect_uri
// 3. on callback: verify state matches, exchange code+verifier, validate id_token (iss/aud/exp/nonce/sig)
```

| Control | Stops | Note |
|---------|-------|------|
| **PKCE (S256)** | auth-code interception | mandatory for *all* clients now (incl. confidential), per OAuth 2.1 |
| **`state`** | CSRF on the callback | bind to session, single-use |
| **`nonce`** (OIDC) | id_token replay | echo + verify in id_token |
| **Exact redirect_uri match** | open-redirect token theft | no wildcards/substring; pre-register exact URIs |
| validate id_token sig + `iss`/`aud`/`exp` | forged/borrowed tokens | use the IdP's JWKS |

The classic breaches: **open redirect_uri** (attacker registers `https://app.example.com.evil.com` or
exploits a loose matcher → steals the code) and **missing state** (login CSRF). Never implement the
token exchange or signature validation yourself — use a certified OIDC client lib. Implicit flow is
**dead**; use Authorization Code + PKCE everywhere (SPA, mobile, server).

---

## 5. Account-takeover defenses

### Credential stuffing + brute force

```ts
// ✅ layered: per-account + per-IP rate limit, exponential backoff, lockout w/ alerting
//   (do the heavy lifting at the edge too — see ddos-waf-bot-protection)
const key = `login:fail:${userId}`;
const fails = await redis.incr(key); await redis.expire(key, 900);
if (fails > 5) { logger.warn({event:"auth.lockout", userId, ip}); throw new TooManyRequests(); }
// success → reset counter; ALWAYS return a generic error (don't reveal which of user/pass was wrong)
```

- Rate-limit by **account AND IP AND device** (stuffing rotates IPs; single-account spikes are
  brute force).
- Lockout/backoff after N failures — but beware lockout-as-DoS; prefer exponential backoff +
  step-up challenge (CAPTCHA/Turnstile) over hard permanent lock.
- Add a **bot/CAPTCHA challenge** on suspicious patterns (`ddos-waf-bot-protection`).

### Breached-password check (k-anonymity)

```ts
// ✅ Have I Been Pwned range API — send only first 5 chars of SHA-1, never the password
import crypto from "node:crypto";
async function isBreached(pw: string) {
  const sha1 = crypto.createHash("sha1").update(pw).digest("hex").toUpperCase();
  const res = await fetch(`https://api.pwnedpasswords.com/range/${sha1.slice(0,5)}`,
    { headers: { "Add-Padding": "true" } });
  return (await res.text()).split("\n").some(l => l.startsWith(sha1.slice(5)));
}
// reject/flag known-breached passwords at signup + reset. Follow NIST 800-63B: screen against
// breach corpora, allow long passphrases, NO forced periodic rotation, NO composition rules.
```

### Secure password reset

```ts
// ✅ single-use, short-TTL, hashed token; uniform response; rotate sessions on reset
const raw = crypto.randomBytes(32).toString("base64url");
await db.resetToken.create({ data: {
  userId: user.id, tokenHash: sha256(raw), expiresAt: Date.now()+15*60_000 }});
sendEmail(user.email, `${BASE}/reset?token=${raw}`);   // store HASH, email the RAW
res.json({ message: "If that account exists, a reset link was sent." }); // uniform → no enumeration
// on use: constant-time compare hash, check expiry+unused, mark used, set new pw, invalidate ALL sessions
```

Reset rules: tokens are CSPRNG, **stored hashed**, single-use, short TTL (≤15–30m); responses are
**uniform** (no "no such email" → no account enumeration); **invalidate all sessions** on reset; rate-
limit requests; never email the new password. Same uniformity on login + signup + "forgot username."

---

## 6. Performance impact
- argon2id ~50–250ms/verify *by design* (it's the cost that stops cracking) — run it off the request
  hot path if needed and rate-limit login so it's not a DoS vector.
- WebAuthn/TOTP verify: sub-ms (one signature/HMAC).
- Session store lookup: a Redis round-trip (~0.1–1ms) — cheap; the revocation it buys is worth it.

## 7. Scale / multi-tenant
- Session store must be shared (Redis cluster) across app instances; key by tenant where relevant.
- Per-tenant IdP/SSO (enterprise SaaS): support SAML/OIDC per tenant, isolate signing keys, validate
  the tenant's `iss`. Never let tenant A's IdP mint tokens accepted for tenant B.
- Rate-limit + lockout counters must be cluster-wide (centralized store), or attackers shard around
  per-node limits.

## 8. Testing & verification
- Unit: alg=none rejected, expired token rejected, wrong-issuer rejected, session id changes on login.
- AuthZ/authN integration: brute-force hits lockout; reset token is single-use + expires; reused
  refresh token revokes the family.
- DAST/pentest: test for user enumeration (timing + response diffs), session fixation, JWT tampering
  (use jwt_tool/Burp), open redirect on OAuth callback. (`pentesting-vuln-management`.)

## 9. Observability / detection
Emit structured events: `auth.login.success/failed`, `auth.mfa.challenge/failed`, `auth.lockout`,
`auth.password.reset`, `auth.token.reuse_detected`. SIEM rules: failure spikes per account/IP
(stuffing), impossible travel, new-device logins, MFA-fatigue (repeated push), refresh-token reuse.

## 10. Accessibility / i18n
- MFA must have **accessible** flows: TOTP needs copy-paste-able secrets + readable QR alt; passkeys
  inherit platform a11y; offer recovery codes for users who can't use a given factor.
- SMS OTP as the *only* factor excludes users without reliable mobile service — provide alternatives.
- Localize all auth/error emails and keep error messages uniform across locales (no enumeration leak
  via translated strings).

## Anti-patterns
- Rolling your own auth, crypto, or OAuth state machine.
- Fast hashes (MD5/SHA-x) or unsalted hashes for passwords.
- JWT as a long-lived session you can't revoke; JWT in localStorage.
- Accepting `alg:none` or not pinning the algorithm allowlist.
- SMS as primary/only MFA for high-value accounts.
- Password composition rules + forced 90-day rotation (NIST says don't).
- Reset tokens stored in plaintext, reusable, or non-expiring; enumerable responses.
- Implicit OAuth flow; wildcard/substring redirect_uri matching; missing PKCE/state.
- Hard permanent lockout with no recovery (DoS-by-design).

## Agent checklist
```
- [ ] argon2id at current OWASP params (m=19456,t=2,p=1+) ; bcrypt only legacy w/ 72-byte cap
- [ ] Server sessions for browser auth; session id regenerated on login/elevation; idle+absolute TTL
- [ ] JWTs (if used): pinned alg, exp/iss/aud required, HttpOnly cookie, short-lived + rotating refresh
- [ ] MFA offered, passkeys/WebAuthn pushed as default; TOTP fallback; SMS only break-glass
- [ ] OAuth: Authorization Code + PKCE(S256) + state + nonce + EXACT redirect_uri
- [ ] Login rate-limited per account+IP; lockout/backoff + challenge; generic errors (no enumeration)
- [ ] Breached-password screening (HIBP k-anonymity) at signup + reset; NIST 800-63B rules
- [ ] Reset tokens: CSPRNG, hashed-at-rest, single-use, ≤30m, invalidate all sessions, uniform response
- [ ] Auth events logged + SIEM detections (stuffing, impossible travel, token reuse)
```

## References
- OWASP Authentication / Session Mgmt / Password Storage Cheat Sheets: https://cheatsheetseries.owasp.org/
- NIST SP 800-63B Digital Identity Guidelines: https://pages.nist.gov/800-63-3/sp800-63b.html
- OAuth 2.1 draft + Security BCP (RFC 9700): https://oauth.net/2.1/ · WebAuthn: https://www.w3.org/TR/webauthn-3/
- Have I Been Pwned API: https://haveibeenpwned.com/API/v3 · OpenID Connect: https://openid.net/developers/how-connect-works/

## Related
`web-hardening-headers-tls` (cookies/CSRF/CSP), `appsec-owasp-top10` (A07), `ddos-waf-bot-protection`
(stuffing/CAPTCHA at edge), `secrets-supply-chain-security` (key/pepper storage), `backend-api-master`.
