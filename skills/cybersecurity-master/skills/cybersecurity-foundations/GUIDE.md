---
name: cybersecurity-foundations
description: >-
  Threat-model and reason about risk like a staff security engineer: STRIDE (worked example),
  attack trees, the core principles (least privilege, defense in depth, fail secure, complete
  mediation, secure defaults), attack-surface mapping, trust boundaries, risk scoring (DREAD vs
  likelihood×impact), and a secure SDLC that gates ship. Start here before any hardening task.
---

# Cybersecurity Foundations — Think Like an Attacker, Build Like a Defender

**Mandate:** security is a *design property*, not a feature you bolt on at the end. Before you write
a line of hardening code, you model **what can go wrong**, **who would do it**, and **what it costs
you**. A control with no threat behind it is cargo-cult; a threat with no control is an open
incident. This skill is the lens every other skill in `cybersecurity-master` plugs into.

> Ethics: threat modeling and attack trees here are to find and fix *your own* weaknesses. Offensive
> framing ("how would I break in") is mandatory for good defense — but only ever applied to systems
> you own or are authorized in writing to test.

## When to use / when NOT to

**Use when:** starting a new service or feature, a design review, onboarding a security program,
prioritizing a backlog of findings, scoping a pentest, or after an incident (model what was missed).

**Don't bother when:** you're patching a single known CVE (go straight to remediation) or the change
has no trust-boundary impact (pure CSS, copy edits). Threat modeling a typo fix is theater.

---

## 1. Mental model: attacker view vs defender view

| Question | Attacker asks | Defender must answer |
|----------|---------------|----------------------|
| Entry | Where's the cheapest way in? | What is my full attack surface? |
| Value | What's worth stealing/breaking? | What are my crown-jewel assets + data classes? |
| Trust | What does the system *assume*? | Where are my trust boundaries (and are they enforced)? |
| Cost | What's the effort/skill needed? | Have I raised cost above the attacker's payoff? |
| Detection | Will anyone notice? | Will I detect + respond before impact? |

Security ROI = **raise attacker cost** and **lower your detection/response time** until the expected
value of an attack goes negative. You will never reach "unhackable"; you reach "not worth it, and
caught fast if tried."

---

## 2. The principles that actually drive decisions

These are not posters; each one is a concrete design test.

- **Least privilege** — every identity (user, service, token, CI job) gets the *minimum* rights for
  the *minimum* time. Test: "if this credential leaks, what's the blast radius?" If the answer is
  "everything," you failed.
- **Defense in depth** — no single control is load-bearing. WAF *and* parameterized queries *and*
  least-priv DB user. Test: "remove any one control — am I breached?" If yes, that layer was a SPOF.
- **Fail secure (fail closed)** — on error/ambiguity, *deny*. An auth check that throws must result
  in 403, never "continue." Most real breaches are *fail-open* bugs (see CVE-2025-29927: Next.js
  middleware bypass — a request that skipped middleware was allowed through).
- **Complete mediation** — check authorization on *every* access, server-side, every time. Never
  cache "this user is allowed" in a way the client can replay or that skips re-validation. IDOR is a
  complete-mediation failure.
- **Secure defaults** — the out-of-the-box config is the locked-down one; opening up is an explicit,
  logged decision. Buckets private by default, ports closed by default, registration disabled by
  default.
- **Separation of duties** — the person who writes the deploy can't also approve + merge + release
  unreviewed. Kills both insider risk and single-account-compromise blast radius.
- **Economy of mechanism / KISS** — complexity is the enemy of security. Less code, fewer flags,
  smaller trust base = smaller attack surface.
- **Open design (Kerckhoffs)** — security must not depend on secrecy of the *design*, only of the
  *keys*. "No one knows this endpoint exists" is not a control.
- **Psychological acceptability** — if the secure path is painful, users route around it. Make the
  secure way the easy way (passkeys > forced 90-day password rotation).

---

## 3. STRIDE — the threat taxonomy (worked example)

STRIDE (Microsoft) maps each threat class to the security property it violates:

| STRIDE threat | Violates | Example | Primary control |
|---------------|----------|---------|-----------------|
| **S**poofing | Authentication | Forged JWT, stolen session | Strong auth, MFA, signed tokens |
| **T**ampering | Integrity | Modify price in request, poison cache | Input validation, signing, integrity checks |
| **R**epudiation | Non-repudiation | "I didn't make that transfer" | Audit logs, signed events, append-only |
| **I**nformation disclosure | Confidentiality | IDOR, verbose errors, S3 leak | AuthZ, encryption, output filtering |
| **D**enial of service | Availability | L7 flood, ReDoS, resource exhaustion | Rate limits, quotas, autoscale, WAF |
| **E**levation of privilege | Authorization | Horizontal/vertical privesc, RCE | Least priv, sandboxing, AuthZ checks |

### Worked example: "money transfer" endpoint

System: `POST /api/transfer { fromAccount, toAccount, amount }`, JWT in cookie, Postgres ledger.

**Step 1 — draw the Data Flow Diagram (DFD)** and mark **trust boundaries** (where data crosses a
privilege level — these are where threats live):

```
[Browser] --TLS--> (TB1: internet→edge) [CDN/WAF] --> (TB2: edge→app) [API]
   [API] --(TB3: app→data)--> [Postgres]    [API] --(TB4: app→3p)--> [Payments API]
```

**Step 2 — enumerate per element with STRIDE.** A subset:

| # | Element / flow | STRIDE | Threat | Control | Residual risk |
|---|----------------|--------|--------|---------|---------------|
| 1 | Browser→API (TB2) | S | Replay stolen session cookie | `__Host-` cookie, HttpOnly+Secure+SameSite, short TTL, rotate on auth | Low |
| 2 | transfer payload | T | Tamper `amount`/`fromAccount` to debit another user | Server derives `fromAccount` from session, never trusts client; AuthZ on ownership | Low |
| 3 | transfer | E | IDOR: set `fromAccount` to victim's | Complete mediation: `where account.owner = session.userId` | Low |
| 4 | transfer | R | User denies transfer | Append-only signed audit log w/ request id, IP, ts | Low |
| 5 | API→Postgres (TB3) | T/I | SQLi → read/modify ledger | Parameterized queries, least-priv DB role | Low |
| 6 | endpoint | D | Automated abuse drains rate/locks rows | Rate limit per user+IP, idempotency key | Medium |
| 7 | API→Payments (TB4) | S | SSRF pivots to internal metadata | Egress allowlist, no user-controlled URL | Low |

**Step 3 — rank + decide.** Each row gets risk = likelihood × impact (see §6). Tampering/IDOR on a
money flow is critical → must-fix before ship. The DoS row is medium → ship with rate limit, monitor.

This table *is* the security backlog. It's reviewable, testable, and traceable to controls.

> Alternatives to STRIDE: **LINDDUN** for privacy threat modeling, **PASTA** for risk-centric/
> attacker-simulation programs, **MITRE ATT&CK** for mapping real adversary TTPs to detections.
> STRIDE is the best default for per-feature design review. Use ATT&CK to drive your detection
> coverage (§ security-operations-ir-compliance).

---

## 4. Attack trees (decompose a goal into paths)

An attack tree puts the **attacker's goal at the root** and decomposes into AND/OR sub-goals. It
finds the *cheapest leaf* — which is where you spend defense budget.

```
GOAL: Exfiltrate customer PII database
├── OR  Compromise an app credential
│   ├── OR  Phish an engineer  (cost: low, MFA-resistant phishing kit)  ← cheapest leaf
│   ├── OR  Find secret in git history          (cost: low)            ← cheap leaf
│   └── OR  Steal long-lived CI token            (cost: med)
├── OR  Exploit the application
│   ├── AND SQL injection + DB user can read PII (cost: med)
│   └── OR  SSRF → cloud metadata → IAM creds     (cost: med)
└── OR  Attack the infrastructure
    ├── OR  Public S3 bucket / snapshot           (cost: low)          ← cheap leaf
    └── OR  Over-permissioned IAM role assumed     (cost: med)
```

Read it like an attacker: the **cheapest leaves** (phishing, secret in git, public bucket) are your
top priorities — not the exotic exploit. This is why **secrets scanning, MFA/passkeys, and cloud
posture** beat fancy controls for most orgs. Annotate leaves with cost/skill/detectability to
prioritize objectively.

---

## 5. Attack-surface mapping (you can't defend what you can't see)

Inventory every place untrusted input or an attacker can touch your system:

- **Network:** open ports, public IPs, load balancers, exposed admin panels, debug endpoints.
- **App:** every route/param, file upload, webhook receiver, GraphQL resolver, deserialization sink,
  template render, redirect, SSRF-capable fetch.
- **Identity:** every auth flow, OAuth callback, password reset, SSO, API key, service account.
- **Supply chain:** dependencies, base images, CI/CD, build secrets (see `secrets-supply-chain`).
- **Data:** PII/PCI/PHI stores, backups, logs, caches, third-party shares.
- **Human:** support social-engineering, admin accounts, contractors.

```bash
# Cheap external attack-surface recon on YOUR OWN domains (authorized only):
subfinder -d example.com -silent | httpx -silent -title -tech-detect -status-code
nuclei -l live-hosts.txt -t http/exposures/ -severity high,critical   # exposed panels/secrets
```

Rule: **every item on this list maps to a control + an owner + a detection.** Unowned surface is
where breaches start. Re-run discovery continuously — surface grows with every deploy.

---

## 6. Risk scoring — pick a model and be consistent

Don't argue vibes; score. Two pragmatic models:

| Model | Formula | Best for | Watch out |
|-------|---------|----------|-----------|
| **Likelihood × Impact** | qualitative 1–5 × 1–5 grid → heat map | product/feature triage | subjective; calibrate with examples |
| **CVSS 4.0** | Base (AV/AC/AT/PR/UI + VC/VI/VA + SC/SI/SA) + Threat + Env | scoring a specific vuln/CVE | base score ≠ *your* risk — apply Environmental |
| **DREAD** | Damage+Reproducibility+Exploitability+Affected+Discoverability | quick relative ranking | math is fuzzy; many orgs dropped it |

Senior take: use **likelihood×impact** for design/feature risk, and **CVSS 4.0** (current standard,
FIRST, Nov 2023) for *concrete vulnerabilities* — but always re-score with **Environmental metrics**
for *your* deployment. A CVSS 9.8 on a service that isn't internet-reachable and holds no data may be
*your* medium; a 6.1 reflected XSS on your admin SSO portal may be *your* critical. Context wins.
(Triage workflow lives in `pentesting-vuln-management`.)

---

## 7. Secure SDLC — bake controls into the pipeline (shift left, gate right)

| Phase | Activity | Gate / tooling |
|-------|----------|----------------|
| Design | Threat model (STRIDE), abuse cases | Review sign-off on high-risk features |
| Code | Secure coding, peer review | Pre-commit secret scan (gitleaks), linters |
| Build | SCA, SAST, SBOM | CI **fails** on new high/critical (semgrep/CodeQL, Snyk, CycloneDX SBOM) |
| Test | DAST, auth/AuthZ tests, fuzzing | DAST (ZAP) against staging; AuthZ test suite |
| Release | Signing, provenance | cosign sign + SLSA provenance; protected branches |
| Deploy | IaC scan, config review | tfsec/checkov; no public-by-default |
| Operate | Logging, detection, patching | SIEM alerts, SLA-bound vuln mgmt, IR runbooks |

The non-negotiable: **at least one automated security gate that can block the merge/deploy.** A
program with no gate is a wishlist. Start with secret-scanning + SCA (highest ROI, lowest friction),
then add SAST, then DAST. (Full pipeline configs in `secrets-supply-chain-security` and
`pentesting-vuln-management`.)

---

## 8. Performance & friction impact (be honest)

Security controls cost something; ignoring it gets them ripped out:

- Threat modeling: ~1–4h per significant feature. Skipping it costs 10–100× in incident response.
- SAST/DAST in CI: minutes added to pipeline → cache results, run full scans nightly + diff on PR.
- Argon2id, TLS handshakes, WAF inspection: real CPU/latency — quantified in the relevant skills.
- The biggest "perf" cost is *developer friction*: a noisy gate with 90% false positives gets
  disabled. Tune signal-to-noise relentlessly or you lose the gate.

---

## 9. Scale & multi-tenant foundations

- **Tenant isolation is a trust boundary** — model it explicitly. Every query, cache key, file path,
  and log line must be tenant-scoped. The classic SaaS breach is a missing `tenant_id` filter (an
  IDOR at tenant granularity). Enforce with row-level security / scoped data-access layer, not hope.
- **Blast-radius thinking:** one tenant's compromise must not reach another's data or keys. Per-
  tenant encryption keys, per-tenant rate limits, noisy-neighbor quotas.
- **Threat model the control plane separately** from the data plane — admin tooling is the juiciest
  target and often the least hardened.

---

## 10. Testing & verifying your model

A threat model is a hypothesis; verify it:

- Each control row → a **test** (unit AuthZ test, DAST check, pentest case). "Control exists" ≠
  "control works."
- **Purple-team** the attack tree's cheapest leaves: can you actually phish? Is there a secret in git
  history (`gitleaks detect`)? Is any bucket public?
- Track **coverage**: % of high-risk features with a current threat model; % of model controls with
  an automated test. These are real program KPIs.

---

## 11. Observability — model your detections too

For every high/critical threat, ask "**how would I know this is happening?**" and create a detection:

- IDOR/privesc → alert on cross-tenant access patterns, 403 spikes, sensitive-object access by new
  principals.
- Credential abuse → impossible-travel, new-device, auth-failure spikes.
- Exfil → anomalous egress volume/destinations.

A threat with a control but no detection is a silent failure waiting to happen. (Detection
engineering: `security-operations-ir-compliance`.)

---

## 12. Anti-patterns (kill these)

- **Security as a final-stage review** ("the pentest will catch it") instead of design-time modeling.
- **Checklist theater** — running a tool, ignoring output, claiming "we do SAST."
- **Trusting the client** — client-side validation/AuthZ, hidden form fields, `disabled` buttons as
  "controls." All client controls are UX, not security.
- **One giant admin role / one shared service account** — least privilege violated, blast radius = ∞.
- **Fail-open error handling** — `catch { /* allow */ }` on an auth path.
- **Obscurity as security** — unguessable URLs, "internal only" with no network control.
- **Unowned attack surface** — a debug endpoint or forgotten subdomain no one is responsible for.
- **Scoring by vibes** — "feels low risk" with no model behind it.

---

## Agent checklist
```
- [ ] Crown-jewel assets + data classifications identified (what are we protecting?)
- [ ] DFD drawn with trust boundaries marked
- [ ] STRIDE applied per element; threats → controls table produced
- [ ] Attack tree built; cheapest leaves prioritized (often: secrets, MFA, cloud posture)
- [ ] Attack surface inventoried; every item has an owner + control + detection
- [ ] Risks scored consistently (likelihood×impact for design, CVSS 4.0 + Env for vulns)
- [ ] High/critical threats are fail-secure, least-priv, completely mediated
- [ ] Each control has a test; each high threat has a detection
- [ ] ≥1 automated security gate can block merge/deploy
- [ ] Multi-tenant isolation modeled as an explicit trust boundary
```

## References
- OWASP Threat Modeling: https://owasp.org/www-community/Threat_Modeling
- Microsoft STRIDE: https://learn.microsoft.com/en-us/azure/security/develop/threat-modeling-tool-threats
- OWASP Application Security Verification Standard (ASVS): https://owasp.org/www-project-application-security-verification-standard/
- NIST Secure Software Development Framework (SSDF) SP 800-218: https://csrc.nist.gov/pubs/sp/800/218/final
- CVSS 4.0 (FIRST): https://www.first.org/cvss/
- LINDDUN (privacy): https://linddun.org · MITRE ATT&CK: https://attack.mitre.org

## Related
`appsec-owasp-top10` (the threats, concretely), `pentesting-vuln-management` (verify + score),
`security-operations-ir-compliance` (detect + respond), `infra-cloud-network-security` (least-priv),
`code-quality-master` (secure code review).
