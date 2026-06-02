---
name: appsec-owasp-top10
description: >-
  Secure-code the OWASP Top 10 (2025, with 2021 mapping) at staff depth — every category as a real
  vulnerable→fixed pair in TypeScript/SQL: broken access control + IDOR, security misconfiguration,
  software-supply-chain & integrity, cryptographic failures, injection (SQLi/NoSQLi/cmd), SSRF
  (allowlist), insecure design, auth failures, logging/alerting, and exceptional-condition handling.
---

# AppSec — OWASP Top 10 (2025) with Exploit→Fix

**Mandate:** the Top 10 is the *floor*, not the ceiling. You should be able to look at any handler
and name which Top 10 categories it touches and prove the control. This skill is exploit→fix in
**copy-paste TypeScript/SQL** — understand the vuln well enough to *kill the class*, not patch one
instance.

> Using the current list: **OWASP Top 10:2025** (released Nov 2025) supersedes 2021. Biggest moves:
> SSRF folded into **A01 Broken Access Control**; **A03 Software Supply Chain Failures** (was
> "Vulnerable & Outdated Components"); Security Misconfiguration up to **A02**; new **A10 Mishandling
> of Exceptional Conditions**. Where teams still cite 2021 IDs, the mapping is noted per section.

## When to use / NOT

**Use** for any code that handles untrusted input, authN/authZ, data access, serialization,
outbound requests, or rendering. **Don't** treat it as a substitute for threat modeling
(`cybersecurity-foundations`) — the Top 10 tells you *common* classes; your model finds *your*
specific ones (business-logic abuse the Top 10 never lists).

## The list at a glance (2025)

| 2025 | Category | Root-cause one-liner | 2021 equivalent |
|------|----------|----------------------|------------------|
| A01 | Broken Access Control (+SSRF) | Missing/again server-side authZ | A01 + A10 (SSRF) |
| A02 | Security Misconfiguration | Insecure defaults, verbose errors, open features | A05 |
| A03 | Software Supply Chain Failures | Trusting code/deps/build you didn't verify | A06 |
| A04 | Cryptographic Failures | Weak/missing crypto, secrets in transit/rest | A02 |
| A05 | Injection (incl. XSS) | Untrusted data hits an interpreter | A03 |
| A06 | Insecure Design | Missing security control by design | A04 |
| A07 | Authentication Failures | Weak identity proofing/session | A07 |
| A08 | Software or Data Integrity Failures | Unverified updates/deserialization | A08 |
| A09 | Security Logging & Alerting Failures | Can't see/respond to attacks | A09 |
| A10 | Mishandling of Exceptional Conditions | Fail-open, leaky errors, logic on error paths | (new) |

---

## A01 — Broken Access Control (#1, and it includes SSRF now)

The most common, highest-impact class. Two flavors: **IDOR** (object-level) and **function-level**
(privilege) — plus **SSRF** (server tricked into making requests).

### IDOR — vulnerable → fixed

```ts
// ❌ VULNERABLE: trusts the id in the URL, no ownership check (CWE-639)
app.get("/api/invoices/:id", requireAuth, async (req, res) => {
  const invoice = await db.invoice.findUnique({ where: { id: req.params.id } });
  res.json(invoice);                       // any logged-in user reads ANY invoice
});
```

```ts
// ✅ FIXED: complete mediation — scope every read to the caller's tenant + ownership
app.get("/api/invoices/:id", requireAuth, async (req, res) => {
  const invoice = await db.invoice.findFirst({
    where: { id: req.params.id, orgId: req.user.orgId },   // tenant scope
  });
  if (!invoice) return res.sendStatus(404);  // 404 not 403 — don't confirm existence
  if (!can(req.user, "invoice:read", invoice)) return res.sendStatus(403);
  res.json(invoice);
});
```

Senior rules: **never trust an identifier from the client to select rows you own** — always add the
`orgId`/`ownerId` predicate in the query (deny-by-default). Use **opaque/UUID** ids (not sequential
ints that enumerate). Centralize authZ in a policy layer (`can(user, action, resource)`), don't
scatter `if (user.role === 'admin')` across handlers.

### Function-level (vertical privesc) — fixed pattern

```ts
// ✅ deny-by-default policy; routes declare required permission, middleware enforces
const policy = { "admin": ["user:delete","billing:write"], "member": ["invoice:read"] } as const;
const authorize = (perm: string) => (req, res, next) =>
  policy[req.user.role]?.includes(perm) ? next() : res.sendStatus(403);
app.delete("/api/users/:id", requireAuth, authorize("user:delete"), handler);
```

### SSRF — vulnerable → fixed (now part of A01)

```ts
// ❌ VULNERABLE: fetches a user-supplied URL → hits cloud metadata / internal services (CWE-918)
app.post("/fetch-preview", async (req, res) => {
  const r = await fetch(req.body.url);     // attacker: http://169.254.169.254/latest/meta-data/
  res.send(await r.text());
});
```

```ts
// ✅ FIXED: allowlist host, resolve+pin IP, block private ranges, no redirects to internal
import dns from "node:dns/promises";
import ipaddr from "ipaddr.js";

const ALLOWED_HOSTS = new Set(["images.example.com", "cdn.partner.com"]);

async function safeFetch(rawUrl: string) {
  const u = new URL(rawUrl);
  if (u.protocol !== "https:") throw new Error("https only");
  if (!ALLOWED_HOSTS.has(u.hostname)) throw new Error("host not allowed");
  const { address } = await dns.lookup(u.hostname);          // resolve
  const ip = ipaddr.parse(address);
  const range = ip.range();                                   // block SSRF pivots
  if (["private","loopback","linkLocal","uniqueLocal","carrierGradeNat","reserved"].includes(range))
    throw new Error("blocked internal address");
  return fetch(u, { redirect: "error", signal: AbortSignal.timeout(5000) }); // no redirect, timeout
}
```

For cloud: also enforce **IMDSv2** (token-required metadata) so even an SSRF can't trivially read
instance creds (see `infra-cloud-network-security`). Best of all: don't let users supply URLs — pass
an enum/id that maps to a server-known URL.

---

## A02 — Security Misconfiguration (#2)

```ts
// ❌ VULNERABLE
app.use(errorHandler({ stack: true }));    // leaks stack traces, paths, versions (CWE-209)
app.disable("etag"); // ...and X-Powered-By: Express advertised, CORS '*', debug routes live
```

```ts
// ✅ FIXED: secure defaults, generic errors, no fingerprinting
import helmet from "helmet";
app.disable("x-powered-by");
app.use(helmet());                         // sane security-header defaults
app.use((err, req, res, _next) => {
  logger.error({ err, reqId: req.id });    // full detail to logs (not the client)
  res.status(500).json({ error: "internal_error", requestId: req.id });  // generic to user
});
```

Checklist: disable debug/admin endpoints in prod, remove default creds/sample apps, deny-by-default
CORS (see `web-hardening-headers-tls`), set security headers, patch the stack, scan IaC. Misconfig is
a *config* bug — gate it with tfsec/checkov + a hardened base image, not manual review.

---

## A03 — Software Supply Chain Failures (#3, big expansion)

Now covers the whole dependency + build ecosystem, not just "outdated components."

```jsonc
// ✅ minimum bar in CI (full treatment in secrets-supply-chain-security)
// - lockfile committed + integrity-verified (npm ci, not npm install)
// - SCA gate: fail on new high/critical
// - pin GitHub Actions to commit SHA, not @v4
// - npm publish --provenance (OIDC), verify with `npm audit signatures`
```

2026 reality check: valid SLSA provenance proves *where/how* a package built — **not that it's
safe**. The May 2026 TanStack npm compromise shipped malware with *legitimate* provenance (pipeline
hijack). Combine provenance with SCA, minimum-release-age policies, and `--ignore-scripts`. Deep dive
in `secrets-supply-chain-security`.

---

## A04 — Cryptographic Failures (#4)

```ts
// ❌ VULNERABLE: MD5 "hash", ECB, hardcoded key, math.random token (CWE-327/328/338)
const token = Math.random().toString(36);                 // predictable
const hash = crypto.createHash("md5").update(pw).digest("hex");  // broken for passwords
```

```ts
// ✅ FIXED: CSPRNG tokens; argon2id for passwords; AES-256-GCM (AEAD) for data; KMS-managed key
import crypto from "node:crypto";
const token = crypto.randomBytes(32).toString("base64url");        // 256-bit CSPRNG

function encrypt(plaintext: string, key: Buffer) {                 // key from KMS/Vault, never code
  const iv = crypto.randomBytes(12);                               // 96-bit nonce for GCM
  const c = crypto.createCipheriv("aes-256-gcm", key, iv);
  const ct = Buffer.concat([c.update(plaintext, "utf8"), c.final()]);
  return { iv, ct, tag: c.getAuthTag() };                          // AEAD: integrity + confidentiality
}
```

Rules: passwords → argon2id (never a fast hash — see `auth-session-account-security`); data → AEAD
(AES-GCM / ChaCha20-Poly1305); tokens/IDs → `crypto.randomBytes`; TLS 1.2+ in transit; keys in
KMS/Vault with rotation; never roll your own crypto. Classify data first — you can't protect what you
haven't labeled (PII/PCI/PHI).

---

## A05 — Injection (incl. XSS) (#5)

Untrusted data interpreted as code/query. SQLi, NoSQLi, command, LDAP, and **XSS** all live here.

### SQL injection — vulnerable → fixed

```ts
// ❌ VULNERABLE: string concatenation (CWE-89)
const rows = await db.query(`SELECT * FROM users WHERE email = '${req.body.email}'`);
//  email = "' OR '1'='1" → dumps all users; "'; DROP TABLE users;--" → destruction
```

```sql
-- ✅ FIXED: parameterized query — data can never become SQL
SELECT * FROM users WHERE email = $1;
```

```ts
const rows = await db.query("SELECT * FROM users WHERE email = $1", [req.body.email]); // pg
// or ORM: db.user.findUnique({ where: { email } })  — uses bind params under the hood
// allowlist any dynamic identifiers (column/sort) — params don't cover table/column names:
const SORT = { name: "name", created: "created_at" } as const;
const col = SORT[req.query.sort as keyof typeof SORT] ?? "created_at";
```

### NoSQL injection (Mongo) — fix

```ts
// ❌ { email: req.body.email, password: req.body.password }  → attacker sends {"$gt":""} → bypass
// ✅ coerce types + reject objects:
const email = String(req.body.email);
const password = String(req.body.password);
const user = await coll.findOne({ email });   // then verify password hash in app, not in query
```

### Command injection — fix

```ts
// ❌ exec(`convert ${req.body.file} out.png`)  → "; rm -rf /" (CWE-78)
import { execFile } from "node:child_process";
execFile("convert", [userFile, "out.png"]);    // ✅ argv array, no shell, validate userFile path
```

### XSS — output-encode + CSP (defense in depth)

```tsx
// ❌ VULNERABLE: raw HTML injection (CWE-79)
<div dangerouslySetInnerHTML={{ __html: comment.body }} />   // stored XSS
```

```tsx
// ✅ FIXED: contextual output encoding (React auto-escapes); sanitize only when HTML is required
import DOMPurify from "isomorphic-dompurify";
<div>{comment.body}</div>                                    // auto-escaped — preferred
// if you MUST render HTML (rich text): sanitize with an allowlist
<div dangerouslySetInnerHTML={{ __html: DOMPurify.sanitize(comment.body) }} />
```

Layer a **strict CSP (nonce + strict-dynamic)** so an injection that slips through still can't
execute (`web-hardening-headers-tls`). Encoding is context-specific: HTML body, HTML attribute, JS,
URL, and CSS each need different encoding — use a framework that does it, never hand-roll.

---

## A06 — Insecure Design (#6)

A control that's *missing by design* — no code bug, the spec is wrong. Examples: password reset with
no rate limit (enables enumeration/brute force), "buy" flow with no server-side price/stock check,
coupon with no per-user cap. Fix is **threat modeling + abuse cases + secure design patterns**
(`cybersecurity-foundations`), not a one-line patch.

```ts
// ❌ INSECURE DESIGN: trust client-sent price
const order = { item, price: req.body.price, qty: req.body.qty };  // attacker sets price: 0
// ✅ SECURE DESIGN: server is source of truth; validate invariants
const product = await db.product.findFirstOrThrow({ where: { id: item, active: true } });
if (req.body.qty < 1 || req.body.qty > product.maxPerOrder) throw new BadRequest();
const order = { item, price: product.price, qty: req.body.qty };   // price from DB, not client
```

---

## A07 — Authentication Failures (#7)

Weak credentials, no MFA, session fixation, JWT pitfalls, credential stuffing. Full treatment +
argon2id, WebAuthn, OAuth/OIDC, lockout in `auth-session-account-security`. The one-liner: **don't
build auth from scratch in 2026** — use a vetted library/IdP, enforce MFA/passkeys, check passwords
against breach corpora, rate-limit + lock out.

---

## A08 — Software or Data Integrity Failures (#8)

Trusting code/data whose integrity you didn't verify — insecure deserialization, unsigned
auto-updates, CI/CD tampering.

```ts
// ❌ VULNERABLE: deserialize attacker data into live objects (CWE-502)
const obj = deserialize(req.body);          // e.g. node-serialize → RCE gadget chains
// ✅ FIXED: parse to plain data + validate a schema; never instantiate types from input
import { z } from "zod";
const Schema = z.object({ name: z.string().max(100), qty: z.number().int().positive() });
const data = Schema.parse(JSON.parse(req.body));   // JSON only; no code path from input
```

Also: verify signatures on anything you execute/update (cosign), pin + verify dependencies, sign your
own artifacts. See `secrets-supply-chain-security`.

---

## A09 — Security Logging & Alerting Failures (#9)

You can't respond to what you can't see. "Alerting" (2025 rename) is the point — logs nobody acts on
are worthless.

```ts
// ✅ log security events as structured data, no secrets, with correlation id + actor + outcome
logger.warn({
  event: "auth.login.failed", userId: u?.id ?? null, ip: req.ip,
  reqId: req.id, reason: "bad_password", attemptCount,
});  // → SIEM rule: alert on N failures/min/account or /IP (credential stuffing)
```

Log authN/authZ decisions, input-validation failures, admin actions, and high-value transactions —
**never** log passwords, tokens, full PANs, or secrets. Ship to a tamper-evident store with alerting.
Full detection engineering in `security-operations-ir-compliance`.

---

## A10 — Mishandling of Exceptional Conditions (#10, new in 2025)

Bugs on error/abnormal paths: **failing open**, leaking detail in errors, logic errors under load,
unhandled rejections that bypass checks.

```ts
// ❌ VULNERABLE: fail-OPEN on error → auth check throws, request proceeds (CWE-636/703)
async function isAllowed(user, res, next) {
  try { return await authz.check(user); }
  catch { return next(); }                 // 💥 error → allowed!
}
```

```ts
// ✅ FIXED: fail-CLOSED, generic error to client, full detail to logs
async function isAllowed(req, res, next) {
  try {
    if (await authz.check(req.user)) return next();
    return res.sendStatus(403);
  } catch (err) {
    logger.error({ err, reqId: req.id, event: "authz.error" });
    return res.sendStatus(403);            // deny on ambiguity (fail secure)
  }
}
```

This is the principle "fail secure" made into a category. Audit every `catch`, default branch, and
timeout path on a security control: does it deny? CVE-2025-29927 (Next.js middleware bypass) was
exactly this — a path that skipped the check was allowed.

---

## Performance impact
Most controls are negligible: parameterized queries are *faster* (plan caching); output encoding is
microseconds; Zod validation is sub-ms. The real costs are crypto (argon2id ~50–250ms by design — a
*feature*) and DOM sanitization on huge payloads (sanitize server-side, cache). Don't trade
correctness for these.

## Testing & verification
- **SAST**: semgrep / CodeQL rules for each class (taint from `req` to `db.query`/`exec`/`innerHTML`).
- **DAST**: OWASP ZAP / Burp active scan against staging for injection, XSS, SSRF.
- **AuthZ tests**: a matrix test — every role × every endpoint, assert 403 where expected (catches
  IDOR/function-level regressions). This is the single highest-ROI test suite you can own.
- Map your suite to **OWASP ASVS** for coverage. (Tooling: `pentesting-vuln-management`.)

## Anti-patterns
- Blocklist "sanitization" of SQL/HTML (`replace("'", "")`) instead of parameterization/encoding.
- Client-side-only validation/authZ.
- Sequential integer IDs with no ownership check (IDOR generator).
- `dangerouslySetInnerHTML` / `eval` / `child_process.exec` with any user data.
- Verbose stack traces / framework versions in prod responses.
- Building bespoke auth/crypto instead of vetted libraries.
- One catch-all `catch {}` that swallows + continues on a security path.

## Agent checklist
```
- [ ] Every data-access query is tenant/owner-scoped (no IDOR) + uses bind params (no injection)
- [ ] AuthZ is server-side, deny-by-default, centralized; route-level perms enforced
- [ ] User-supplied URLs blocked or allowlisted + private-range-blocked (SSRF)
- [ ] Output contextually encoded; HTML sanitized w/ allowlist; strict CSP layered on
- [ ] Passwords argon2id; data AES-GCM; tokens CSPRNG; keys in KMS
- [ ] No deserialization of untrusted data into objects; schema-validate instead
- [ ] Security events logged (no secrets) + alerted; errors fail closed + generic
- [ ] SAST + DAST + role×endpoint authZ matrix in CI
```

## References
- OWASP Top 10:2025: https://owasp.org/Top10/2025/en/ · Project: https://owasp.org/www-project-top-ten/
- OWASP Cheat Sheet Series: https://cheatsheetseries.owasp.org/
- OWASP ASVS: https://owasp.org/www-project-application-security-verification-standard/
- CWE Top 25: https://cwe.mitre.org/top25/ · SSRF: https://cheatsheetseries.owasp.org/cheatsheets/Server_Side_Request_Forgery_Prevention_Cheat_Sheet.html

## Related
`cybersecurity-foundations` (find your specific threats), `web-hardening-headers-tls` (CSP/cookies),
`auth-session-account-security` (A07), `secrets-supply-chain-security` (A03/A08),
`pentesting-vuln-management` (verify), `code-quality-master` (secure review).
