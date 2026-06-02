---
name: integrations-cicd-devops
description: >-
  Staff-level CI/CD integration: OIDC federation to cloud (zero long-lived keys), GitHub Actions /
  GitLab CI / Jenkins / CircleCI / Azure DevOps triggers + status/Checks APIs, deploy gates,
  artifact/provenance (SLSA, signed images), pipeline webhooks, and secret-free runners. Default to
  OIDC + reusable workflows; never paste cloud keys into CI.
---

# CI/CD & DevOps Integrations

**Mandate: CI must hold zero long-lived cloud credentials — use OIDC federation to mint short-lived,
audience-scoped tokens at job time.** A static `AWS_ACCESS_KEY_ID` in CI secrets is the single most
common cloud breach vector. If your pipeline has a permanent cloud key, that's the bug.

## When to integrate CI vs. let CI call you

| Pattern | Direction | Use when |
|---------|-----------|----------|
| **App triggers CI** | you → CI | Self-serve deploy, tenant provisioning, rebuild-on-content |
| **CI reports to you** | CI → you | Status dashboards, deploy gates, audit/compliance log |
| **CI → cloud via OIDC** | CI → cloud | Deploy/artifact push without stored keys |
| **CI → chat** | CI → Slack | Notify on deploy/fail (see slack skill) |

## OIDC federation (do this first)

The CI provider issues a signed OIDC JWT describing the run (`repo`, `ref`, `environment`); the cloud
trust policy validates issuer + `sub` claim and returns a scoped, minutes-long credential.

```yaml
# GitHub Actions → AWS, no stored keys
permissions: { id-token: write, contents: read }   # id-token REQUIRED to request the OIDC JWT
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::123456789012:role/GitHubDeploy
          aws-region: me-central-1
```

Lock the cloud trust policy to **exact** claims — never wildcard the repo/branch:

```jsonc
// IAM trust: only this repo's main branch may assume the role
"Condition": {
  "StringEquals":  { "token.actions.githubusercontent.com:aud": "sts.amazonaws.com" },
  "StringLike":    { "token.actions.githubusercontent.com:sub": "repo:acme/app:ref:refs/heads/main" }
}
```

GitLab (`CI_JOB_JWT_V2` / ID tokens), CircleCI, and Azure DevOps all federate the same way to AWS/
GCP/Azure. Bind GCP via Workload Identity Federation, Azure via federated credentials on an app reg.

## GitHub Actions

```bash
gh workflow run deploy.yml --ref main -f tenant_id=acme -f version=1.4.2   # trigger from your app/CI
```

- Receive results: `workflow_run` (and `check_suite`) webhooks → post back via **Checks API** for
  rich PR annotations, or the simpler commit **status API**.
- **Reusable/callable workflows** (`workflow_call`) + composite actions = DRY across repos; pin
  third-party actions to a **full commit SHA**, never a moving `@v3` tag (supply-chain).
- Use `environment:` with required reviewers for deploy gates.

## GitLab CI / Jenkins / CircleCI / Azure DevOps

| Platform | Trigger in | Results out |
|----------|-----------|-------------|
| **GitLab CI** | `POST /projects/:id/trigger/pipeline` (trigger token) or pipeline schedules | Pipeline/job webhooks; commit status API |
| **Jenkins** | `POST /job/{name}/build` + crumb + API token (or generic webhook trigger) | Notification plugin → your endpoint |
| **CircleCI** | API v2 `POST /project/{slug}/pipeline` | Webhooks: `workflow-completed`, `job-completed` |
| **Azure DevOps** | REST `runs`/`pipelines` (PAT/Entra) | Service Hooks → HTTPS endpoint |

Verify pipeline webhooks' shared secret/signature like any inbound webhook (raw body), dedupe by run
id, ACK fast.

## Deploy-gate pattern (CI waits on your approval)

```
CI job → POST /deploys {sha, env}  →  your API returns deploy_id + "pending"
CI polls GET /deploys/{id}  (or you call back via repository_dispatch / pipeline trigger)
human/policy approves → status "approved" → CI proceeds; "rejected" → CI fails the job
```

Idempotency: key the deploy by `(sha, env)` so retried jobs don't double-create. Timeout the gate and
default to **reject**, not approve.

## Artifacts, provenance & supply chain (2026 baseline)

- Push artifacts to cloud via **OIDC** (S3/GCS/Blob), not stored keys.
- **Sign images** with cosign (keyless, OIDC-backed) and generate **SLSA provenance**; verify
  signatures at deploy admission. Attach an **SBOM** (`syft`) per build.
- Scan dependencies + IaC in-pipeline (block on criticals); store scan results with the build record.

## Security

- No long-lived cloud keys, registry creds, or PATs in CI variables — OIDC or short-lived tokens.
- Mark secrets masked + "protected" (only on protected branches); never `echo` them.
- Pin actions/orbs/images by digest; restrict who can edit pipeline YAML (CODEOWNERS on `.github/`).
- Separate roles per environment (dev role can't touch prod).

## Observability & testing

- Emit deploy markers to your APM (Datadog/Sentry release) keyed by `sha` for change-correlated
  alerting; track DORA metrics (lead time, deploy freq, CFR, MTTR).
- Test pipeline logic locally: `act` (Actions), `gitlab-runner exec`, Jenkinsfile replay.
- Contract-test your trigger/callback API with recorded CI payloads.

## Anti-patterns

- Static cloud keys in CI secrets (use OIDC).
- `uses: some/action@v3` (mutable tag) → pin to a SHA.
- Deploy gate that defaults to approve on timeout/error.
- Re-deploying non-idempotently on job retry (no `(sha,env)` key).
- Building prod artifacts on every PR push instead of path-filtered/needs-based jobs.

## Agent checklist

```
- [ ] OIDC federation set up; zero long-lived cloud keys in CI
- [ ] Cloud trust policy pinned to exact repo:ref/environment (no wildcards)
- [ ] Third-party actions/orbs pinned to commit SHA/digest
- [ ] Results posted via Checks/status API; pipeline webhooks verified + deduped
- [ ] Deploy gate idempotent by (sha,env), fails-closed on timeout
- [ ] Images signed (cosign) + SBOM + provenance; scans block on critical
```

## References

- GitHub OIDC: https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect
- Reusable workflows: https://docs.github.com/en/actions/using-workflows/reusing-workflows
- GitLab ID tokens/OIDC: https://docs.gitlab.com/ee/ci/secrets/id_token_authentication.html
- SLSA: https://slsa.dev · cosign/sigstore: https://docs.sigstore.dev

## Related

`integrations-github-gitlab-bitbucket`, `integrations-cloud-aws-gcp-azure`, `integrations-slack-discord-teams`,
`devops-master`
