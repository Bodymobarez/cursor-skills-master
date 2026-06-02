---
name: secrets-supply-chain-security
description: >-
  Secure secrets and the software supply chain at staff depth: secret managers (Vault/AWS Secrets
  Manager/KMS), keep secrets out of git (gitleaks/detect-secrets + pre-commit), .env hygiene, SCA
  (npm audit/Snyk/Dependabot/OSV), CycloneDX SBOM, signing & provenance (cosign keyless + SLSA),
  lockfile integrity, dependency confusion/typosquatting defense, and CI/CD hardening (OIDC,
  least-priv tokens, pinned actions). Maps to OWASP A03/A08.
---

# Secrets & Software-Supply-Chain Security

**Mandate:** in 2026 the cheapest way into most companies is a **leaked secret** or a **poisoned
dependency** — not an app exploit (revisit the attack tree in `cybersecurity-foundations`: the
cheapest leaves are secrets-in-git and a malicious npm package). Secrets belong in a manager, never
in code; every dependency and build artifact must be **verified, pinned, and attributed**. This is
OWASP A03 (Software Supply Chain Failures) + A08 (Integrity Failures) made operational.

## When to use / NOT
**Use** on every repo/pipeline: setting up secret management, wiring CI security gates, responding to
a leaked credential, or hardening a build. **Don't** confuse this with runtime cloud IAM
(`infra-cloud-network-security`) — though they meet at OIDC + KMS.

## Mental model: the supply chain is a trust graph

```
your source → deps (npm/pip/...) → transitive deps → build (CI) → artifact → registry → deploy
     ▲ secrets leak here    ▲ confusion/typosquat   ▲ pipeline hijack   ▲ unsigned = swappable
```

Every edge is an attacker target. Defense: **verify what enters** (SCA, lockfile, signatures),
**harden where it's built** (CI least-priv, OIDC, pinned actions), **attest what leaves** (SBOM +
provenance + signing), and **keep secrets out of the graph entirely** (managers + short-lived creds).

---

## 1. Secrets: never in code, never long-lived

### Decision matrix — where does a secret live?

| Need | Use | Why |
|------|-----|-----|
| App runtime config (DB pass, API keys) | **AWS Secrets Manager / GCP Secret Manager / Vault** | central, audited, rotatable, IAM-scoped |
| Encryption keys (never leave HSM) | **KMS** (envelope encryption) | key never exposed; crypto ops via API |
| Dynamic, short-lived DB/cloud creds | **Vault dynamic secrets** | per-session creds, auto-expire — no standing secret |
| CI → cloud auth | **OIDC federation** (no stored key) | zero long-lived CI secrets |
| Local dev | `.env` (gitignored) + dev-only values | never prod secrets on laptops |

```ts
// ✅ fetch + cache at boot from a manager; app never holds a static secret in code/env-baked-into-image
import { SecretsManagerClient, GetSecretValueCommand } from "@aws-sdk/client-secrets-manager";
const sm = new SecretsManagerClient({});
async function getSecret(id: string) {
  const { SecretString } = await sm.send(new GetSecretValueCommand({ SecretId: id }));
  return JSON.parse(SecretString!);   // creds delivered via instance/pod IAM role — no key in code
}
```

```ts
// ✅ envelope encryption with KMS — data key is encrypted at rest, plaintext key never persisted
// generateDataKey → use plaintext key in memory for AES-256-GCM → store only the encrypted key
```

Rules: rotate on a schedule + on suspicion; scope each secret to least privilege; audit every access;
**prefer short-lived/dynamic creds over any standing secret.** Envelope-encrypt large data with KMS
data keys (don't ship plaintext data to KMS).

### .env hygiene

```gitignore
# .gitignore — and commit a .env.example with KEYS ONLY, no values
.env
.env.*
!.env.example
```

`.env` is for **local dev only** — never the channel for prod secrets (those come from the manager at
runtime). Never bake secrets into Docker images (`docker history` reveals `ENV`/`ARG`) — inject at
runtime. Don't log `process.env`.

---

## 2. Keep secrets out of git (detect before push, scan history)

```yaml
# .pre-commit-config.yaml — block secrets at commit time (gitleaks)
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.21.2
    hooks: [{ id: gitleaks }]
```

```bash
gitleaks detect --source . --redact          # scan full history (CI + ad hoc)
detect-secrets scan > .secrets.baseline      # Yelp detect-secrets: baseline + audit workflow
# CI gate: fail the build (and PR check) on any new finding
```

Critical: a secret committed to git is **compromised the moment it's pushed**, even if you delete the
file — it lives in history and any clone/fork. **Rotate it, don't just `git rm`.** Use server-side
push protection (GitHub Secret Scanning / GitLab) as a backstop. Rewriting history (`git filter-repo`)
removes the file but does **not** un-leak the value — rotation is mandatory.

---

## 3. SCA — know and gate your dependencies

```bash
npm audit --audit-level=high          # quick, but noisy/incomplete — not your only gate
osv-scanner -r .                      # Google OSV: multi-ecosystem, accurate advisory matching
snyk test --severity-threshold=high   # or Snyk/Trivy for richer remediation + reachability
```

```yaml
# .github/dependabot.yml — automated dependency + security PRs
version: 2
updates:
  - package-ecosystem: "npm"
    directory: "/"
    schedule: { interval: "weekly" }
    open-pull-requests-limit: 10
    groups: { minor-patch: { update-types: ["minor","patch"] } }   # batch low-risk
```

Senior take: run SCA in CI and **fail on new high/critical** (allow time-boxed, ticketed exceptions
for unreachable/no-fix cases — score with CVSS Environmental, see `pentesting-vuln-management`).
Prefer tools that do **reachability analysis** (is the vulnerable function actually called?) to cut
false positives. Enable Dependabot/Renovate for a steady patch cadence so you're never 200 versions
behind when a Log4Shell-class CVE drops.

---

## 4. Lockfile integrity + dependency confusion + typosquatting

```bash
npm ci          # ✅ installs EXACTLY the lockfile, fails on drift. NEVER `npm install` in CI.
npm ci --ignore-scripts   # ✅ block install-time lifecycle scripts (a common malware vector)
```

```jsonc
// .npmrc / .lockfile-lintrc.json — pin registries, allowlist scopes, defeat confusion
// lockfile-lint: every resolved URL must be a trusted registry (catches a swapped source)
{ "allowedHosts": ["registry.npmjs.org"], "allowedUrls": ["https://registry.npmjs.org"] }
```

| Threat | Mechanism | Defense |
|--------|-----------|---------|
| **Dependency confusion** | public pkg with your *internal* name + higher version → installed | scope internal pkgs (`@yourco/`), pin private registry, never publish internal names publicly |
| **Typosquatting** | `expres`, `lodahs`, `colour-string` | allowlist deps, review additions, use scopes, OSV/Socket checks |
| **Malicious version / pipeline hijack** | legit pkg, compromised maintainer or CI | `--ignore-scripts`, **minimum release age** (don't auto-adopt <7–14 day-old versions), commit lockfile, review diffs |
| **Lockfile tampering** | PR swaps resolved URL/hash | `npm ci`, lockfile-lint, require review on lockfile changes |

2026 reality: the **TanStack npm compromise (May 2026)** shipped malware that carried *valid* SLSA
provenance (attacker hijacked the pipeline mid-run); the **Bitwarden** incident abused OIDC publishing
after modifying the publish workflow. Lesson: **provenance ≠ safety** — combine it with branch
protection on workflow files, minimum-release-age, `--ignore-scripts`, and behavioral scanning
(Socket). Pin to integrity hashes; never blindly auto-merge dependency PRs without the gate.

---

## 5. SBOM — a bill of materials you can query

```bash
# CycloneDX (the de-facto SBOM standard) — generate per build, store as a release artifact
npm sbom --sbom-format cyclonedx > sbom.cdx.json     # native npm
syft dir:. -o cyclonedx-json=sbom.cdx.json           # Syft: any ecosystem/container
grype sbom:sbom.cdx.json                              # scan the SBOM for known vulns
```

Why: when the next Log4Shell drops, an SBOM lets you answer **"are we affected, and where?"** in
minutes instead of days. Generate at build time (most accurate), attach to the release, and feed it
to your vuln scanner continuously (new CVEs land against old artifacts). SPDX is the alternative
format; CycloneDX is the common default for security tooling.

---

## 6. Signing + provenance (prove what you ship)

```bash
# ✅ cosign keyless signing (Sigstore: Fulcio short-lived cert + Rekor transparency log) — no key to leak
cosign sign --yes registry.example.com/app@sha256:<digest>
cosign verify registry.example.com/app@sha256:<digest> \
  --certificate-identity-regexp '^https://github.com/yourorg/.+' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
cosign attest --predicate sbom.cdx.json --type cyclonedx ...   # bind SBOM as an attestation
```

**SLSA build levels** (Supply-chain Levels for Software Artifacts, v1.0):

| Level | Guarantee | How |
|-------|-----------|-----|
| L1 | provenance exists | emit provenance (≈ documentation) |
| L2 | provenance signed | signed by build platform → detects distribution tampering |
| L3 | tamper-resistant builder | isolated, ephemeral build (e.g. GitHub reusable workflow) generates provenance |

```yaml
# npm publish with provenance via OIDC (no NPM_TOKEN stored)
permissions: { contents: read, id-token: write }   # id-token = OIDC
# - run: npm ci --ignore-scripts
# - run: npm publish --provenance --access public    # links pkg → exact repo+commit+workflow
# consumers: `npm audit signatures`  to verify
```

Verify provenance on consume (`slsa-verifier`, `npm audit signatures`). Remember the 2026 caveat:
provenance proves *origin/process*, not *intent* — it's necessary, not sufficient. Layer it.

---

## 7. CI/CD hardening (the build is production)

```yaml
# ✅ least-privilege, OIDC (no long-lived cloud key), SHA-pinned actions
permissions:
  contents: read          # default deny everything else; grant per-job only what's needed
jobs:
  deploy:
    permissions: { id-token: write, contents: read }   # OIDC to assume a scoped AWS/GCP role
    steps:
      - uses: actions/checkout@b4ffde65f46336ab88eb53be808477a3936bae11   # v4.x PINNED TO SHA, not @v4
      - uses: aws-actions/configure-aws-credentials@<sha>   # role-to-assume via OIDC, no secrets
```

CI hardening rules:
- **Pin third-party actions to a full commit SHA** (tags are mutable → supply-chain hijack vector).
- **OIDC federation** to clouds/registries → kill long-lived `AWS_*`/`NPM_TOKEN` secrets.
- **`permissions: contents: read`** at top, grant up per-job (default GITHUB_TOKEN is too broad).
- Protect `main` + **require review on workflow file changes** (the Bitwarden lesson).
- Isolate build (ephemeral runner), separate the signing step from the build step, restrict who can
  trigger deploy workflows; treat secrets in CI as prod secrets.

---

## 8. Performance impact
- Pre-commit secret scan: ~seconds; cache + scan diffs only.
- SCA/SBOM/sign in CI: tens of seconds to a couple minutes — run on PR (diff) + nightly (full); cache
  advisory DBs. Worth every second vs. an incident.
- Vault dynamic secrets: a fetch + lease — sub-second; cache within lease TTL.

## 9. Scale / multi-tenant
- Centralize secret management; scope by team/tenant/environment with separate paths + IAM policies.
  Per-tenant encryption keys (KMS) so one tenant's key compromise can't decrypt another's data.
- One SBOM + provenance per service per release; index them centrally so a single CVE query covers
  the whole fleet. Org-wide policy: no deploy without a passing SCA gate + signed artifact.

## 10. Testing & verification
- CI must **actually fail** on: new high/critical dep vuln, a detected secret, an unpinned action, a
  lockfile registry mismatch, an unsigned/unverifiable artifact. Test the gate by injecting a known
  bad (e.g. add a deliberately vulnerable dev dep in a throwaway branch) and confirm it blocks.
- Periodically run `gitleaks` over full history and `cosign verify` in a canary deploy.

## 11. Observability
- Alert on: secret-manager access anomalies (new principal, off-hours, mass reads), failed signature
  verifications at deploy, new dependency with install scripts, CI workflow file edits. Route to SIEM
  (`security-operations-ir-compliance`).

## Anti-patterns
- Secrets in code, `.env` committed, or baked into Docker `ENV`/`ARG`.
- "We deleted the committed key" without rotating it.
- `npm install` (not `ci`) in pipelines; auto-running install scripts; auto-merging dep PRs.
- Actions pinned to `@v4`/`@main` (mutable) instead of SHA.
- Long-lived cloud/registry tokens in CI when OIDC is available.
- Treating SLSA provenance as proof of safety.
- No SBOM → can't answer "are we vulnerable to X?" during an incident.
- Internal package names that could be claimed on the public registry (confusion).

## Agent checklist
```
- [ ] No secrets in code/git; manager (Vault/Secrets Manager) + KMS for keys; .env gitignored
- [ ] gitleaks/detect-secrets pre-commit + CI; push protection on; leaked secrets ROTATED
- [ ] SCA (osv-scanner/Snyk) in CI, fails on new high/critical; Dependabot/Renovate enabled
- [ ] `npm ci --ignore-scripts`; lockfile committed + lockfile-lint; min-release-age policy
- [ ] Internal pkgs scoped + private registry (dependency-confusion safe)
- [ ] CycloneDX SBOM generated per build + scanned continuously
- [ ] Artifacts signed (cosign keyless) + SLSA provenance; verified on consume
- [ ] CI: contents:read default, OIDC (no long-lived tokens), actions pinned to SHA, workflow edits reviewed
```

## References
- OWASP A03:2025 Software Supply Chain Failures: https://owasp.org/Top10/2025/en/
- SLSA v1.0: https://slsa.dev/spec/v1.0/ · Sigstore/cosign: https://docs.sigstore.dev/
- CycloneDX SBOM: https://cyclonedx.org/ · OSV: https://osv.dev/ · gitleaks: https://github.com/gitleaks/gitleaks
- OWASP Secrets Management Cheat Sheet: https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html
- GitHub OIDC: https://docs.github.com/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect

## Related
`infra-cloud-network-security` (IAM/KMS/OIDC), `appsec-owasp-top10` (A03/A08), `pentesting-vuln-management`
(triage/SLA), `devops-master` (CI/CD), `git-workflow-master`.
