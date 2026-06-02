---
name: integrations-github-gitlab-bitbucket
description: >-
  Staff-level GitHub/GitLab/Bitbucket integration: GitHub App (JWT → installation token, the
  production default), fine-grained scopes, X-Hub-Signature-256 webhooks, Checks API, secondary
  rate-limit handling, cursor pagination, GraphQL vs REST, GitLab X-Gitlab-Token, Bitbucket OAuth,
  and gh-CLI automation. Pick App over PAT for anything multi-repo or org-wide.
---

# GitHub, GitLab & Bitbucket

**Mandate: production GitHub integrations are GitHub *Apps*, not PATs.** A PAT is one human's blast
radius, no per-repo scoping, and dies when they leave. A GitHub App has its own identity,
fine-grained permissions, per-installation tokens, and a 15k req/hr ceiling that scales with installs.

## Decision — GitHub integration type

| Type | Identity | Rate limit | Use when |
|------|----------|-----------|----------|
| **GitHub App** | the app (per installation) | 15k/hr/installation | ✅ Production, multi-repo, org-wide, bots |
| **OAuth App (user-to-server)** | acting user | 5k/hr/user | "Connect GitHub" to act *as the user* |
| **Fine-grained PAT** | a user | 5k/hr | Personal scripts, short-lived automation |
| **`gh` CLI** | logged-in user/`GH_TOKEN` | inherits | Agent/CI triage → see `git-workflow-master` |

Need to act as the user (open PRs under their name)? App **+ user-to-server** token. Pure automation
(checks, comments, releases)? App **installation** token.

## GitHub App auth (let Octokit manage JWT + token rotation)

JWT is RS256, `iss`=client id (recommended), `exp` ≤ 10 min; installation token lives 1 hour. Don't
hand-roll it:

```ts
import { App } from "octokit";                                   // wraps @octokit/auth-app
const app = new App({
  appId: process.env.GH_APP_ID!,
  privateKey: process.env.GH_PRIVATE_KEY!,                       // PEM; \n auto-unescaped
  webhooks: { secret: process.env.GH_WEBHOOK_SECRET! },
  oauth: { clientId: process.env.GH_CLIENT_ID!, clientSecret: process.env.GH_CLIENT_SECRET! },
});

// store installation_id per org on the `installation.created` webhook, then:
const octokit = await app.getInstallationOctokit(installationId); // auto-refreshes the 1h token
await octokit.rest.checks.create({ owner, repo, name: "ci/policy", head_sha,
  status: "completed", conclusion: "success" });
```

Minimal permissions for a CI/review bot: `contents:read`, `pull_requests:write`, `checks:write`,
`issues:write`, `metadata:read`. Subscribe to events: `pull_request`, `push`, `check_suite`,
`installation`. Add `workflows:write` only if you dispatch workflows.

## Common tasks (REST + when to use GraphQL)

| Task | REST endpoint |
|------|---------------|
| List PRs | `GET /repos/{o}/{r}/pulls?state=open&per_page=100` |
| Create check run | `POST /repos/{o}/{r}/check-runs` |
| Comment on PR | `POST /repos/{o}/{r}/issues/{n}/comments` |
| Review comment (inline) | `POST /repos/{o}/{r}/pulls/{n}/comments` |
| Dispatch workflow | `POST /repos/{o}/{r}/actions/workflows/{id}/dispatches` |
| Create release | `POST /repos/{o}/{r}/releases` |
| Commit status | `POST /repos/{o}/{r}/statuses/{sha}` |

Use **GraphQL v4** when REST would N+1 (e.g. PRs + reviews + files + labels in one query, or
ProjectsV2 which is GraphQL-only). Use REST for simple CRUD and anything with an Octokit helper.

## Rate limits & pagination (the part people get wrong)

GitHub has **two** limits: the primary hourly budget (`x-ratelimit-remaining`/`reset`) and an
undocumented **secondary** limit on bursts/concurrency that returns 403/429 with `retry-after`.

```ts
// Honor BOTH; back off on secondary limits, don't hammer concurrently
octokit.hook.error("request", async (error, options) => {
  const h = (error as any).response?.headers ?? {};
  if (h["retry-after"]) { await sleep(Number(h["retry-after"]) * 1000); return octokit.request(options); }
  if (h["x-ratelimit-remaining"] === "0") {
    const waitMs = Number(h["x-ratelimit-reset"]) * 1000 - Date.now();
    await sleep(Math.max(waitMs, 0)); return octokit.request(options);
  }
  throw error;
});
// Cursor pagination — never page by guessing; follow Link/iterator
for await (const { data } of octokit.paginate.iterator(octokit.rest.pulls.list, { owner, repo, per_page: 100 }))
  for (const pr of data) { /* ... */ }
```

Keep concurrency low (≈ single-digit parallel requests/installation), prefer conditional requests
(`If-None-Match` ETag → 304s don't count against quota).

## Webhooks

Verify `X-Hub-Signature-256` (HMAC-SHA256 hex, `sha256=` prefix) on the **raw body**; dedupe by
`X-GitHub-Delivery`. Octokit's `app.webhooks.verifyAndReceive({ id, name, signature, payload })` does
both. Handle: `pull_request`, `push`, `release`, `workflow_run`, `check_run`, `installation`,
`installation_repositories`. See `integrations-webhooks-events` for the verifier.

## GitLab

- Auth: **Project/Group access tokens** (preferred over personal), or OAuth 2.0 for user context.
- API base `https://gitlab.com/api/v4/` (or self-hosted host); pagination via `Link` headers +
  `X-Next-Page`. Keyset pagination for large lists.
- Webhooks authenticate with a **shared secret in `X-Gitlab-Token`** — compare constant-time (it's a
  static token, not an HMAC). Merge Requests ≡ PRs; Pipelines ≡ CI status.

```ts
const ok = timingSafeEqual(Buffer.from(req.headers["x-gitlab-token"] ?? ""), Buffer.from(SECRET));
```

## Bitbucket

- **OAuth 2.0** (app passwords are deprecated — migrate). Cloud REST API 2.0 base
  `https://api.bitbucket.org/2.0/`; pagination via `next` URL in the response.
- Webhooks on `repo:push`, `pullrequest:created` etc.; secure with the configured secret + HTTPS.

## Use cases

- AI review bot on `pull_request.opened` → Checks API annotations (`check_runs` with `annotations`).
- Deploy on `release.published` (tag-gated) → CI dispatch.
- Auto-link PR ↔ ticket (Jira/Linear) via branch name `feature/ENG-123-…`.
- Developer-portal repo sync (poll + webhook reconcile).

## Security & multi-tenant

- One installation token per org; never share across tenants. Cache tokens (they're 1h) keyed by
  `installation_id`, refresh on 401.
- Private key in a secret manager/KMS, not the repo. Rotate via App settings → new key, dual-run.
- Least-privilege fine-grained permissions; review the App's permission diff on every change (it
  forces re-consent).

## Testing & observability

- Record fixtures of `pull_request`/`check_run` payloads; signature test the verifier.
- Sandbox: a throwaway org + test repo; `act` for local Actions; smee.io to tunnel webhooks.
- Metrics: `gh_ratelimit_remaining`, `secondary_limit_hits`, `installation_token_refresh_total`,
  per-event handler latency.

## Anti-patterns

- A PAT in CI/prod for anything multi-repo (use an App or OIDC).
- Ignoring secondary rate limits (concurrent floods → 403 storms → throttled app).
- Page-number pagination assumptions / fetching all pages eagerly when you need the first match.
- Re-deriving JWTs by hand instead of Octokit (clock-skew + exp bugs).
- Treating `X-Gitlab-Token` like an HMAC signature (it's a plain shared secret).

## Agent checklist

```
- [ ] GitHub App (not PAT) for multi-repo/org/prod; installation token cached + auto-refreshed
- [ ] Fine-grained least-priv permissions; events subscribed minimally
- [ ] X-Hub-Signature-256 verified on raw body; dedupe X-GitHub-Delivery
- [ ] Primary AND secondary rate limits handled; cursor pagination + ETags
- [ ] GitLab uses X-Gitlab-Token (constant-time); Bitbucket OAuth (not app passwords)
- [ ] Private key in KMS/secret manager with a rotation plan
```

## References

- GitHub Apps: https://docs.github.com/en/apps · REST: https://docs.github.com/en/rest · GraphQL: https://docs.github.com/en/graphql
- Rate limits: https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api
- GitLab API: https://docs.gitlab.com/ee/api/ · Bitbucket Cloud: https://developer.atlassian.com/cloud/bitbucket/rest/

## Related

`integrations-cicd-devops`, `integrations-webhooks-events`, `integrations-oauth-api-keys`,
`git-workflow-master` (gh CLI, PR/CI triage)
