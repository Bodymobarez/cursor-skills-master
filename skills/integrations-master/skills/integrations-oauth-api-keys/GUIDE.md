---
name: integrations-oauth-api-keys
description: >-
  Staff-level OAuth 2.1 / OIDC and credential handling: authorization code + PKCE (S256, now
  mandatory), refresh-token rotation, client credentials, JWT-bearer (GitHub App, Salesforce),
  DPoP/mTLS sender-constraining, exact redirect matching, and a per-tenant KMS-wrapped token vault
  with envelope encryption, revocation, and proactive refresh.
---

# OAuth 2.1, API Keys & the Credential Vault

**Mandate: in 2026 you build to OAuth 2.1 defaults — PKCE on every authorization-code flow (even
confidential clients), exact redirect-URI matching, refresh-token rotation, and no tokens in URLs.**
The implicit and password (ROPC) grants are dead; if a vendor guide still shows them, ignore it.

> OAuth 2.1 (`draft-ietf-oauth-v2-1`, ~draft 15 in early 2026) is not yet a final RFC but its
> requirements are stable and already enforced by Okta, Entra ID, and Auth0. Build to it now.

## Decision — pick the grant by who acts

| Scenario | Grant / mechanism | Credential |
|----------|-------------------|------------|
| User connects their Google/Slack/Notion account | **Auth Code + PKCE (S256)** | per-user refresh token |
| Pure machine-to-machine, your own backend | **Client Credentials** | client_id + secret (or mTLS) |
| Installation-scoped at org level | **App + JWT → installation token** | GitHub App private key |
| Salesforce/Google service integration, no UI | **JWT-Bearer assertion** | RSA private key + cert |
| Dev script / personal automation | **PAT / API key** | scoped token (short-lived if possible) |
| First-party login (you are the IdP) | **OIDC** (`openid` scope, ID token) | — |

Rule of thumb: **prefer installation/app auth over per-user OAuth** when you act org-wide — fewer
tokens to refresh, survives the connecting user leaving, finer-grained permissions.

## Authorization Code + PKCE (the user-connect flow)

PKCE defeats code-interception: you commit to a secret (`code_verifier`) up front and reveal it only
at token exchange. S256 only — never `plain`.

```ts
import { createHash, randomBytes } from "crypto";

// 1. /connect/:provider — build the authorize URL
const codeVerifier = randomBytes(32).toString("base64url");          // 43–128 chars
const codeChallenge = createHash("sha256").update(codeVerifier).digest("base64url");
const state = randomBytes(16).toString("base64url");                 // CSRF + flow-pinning
await cache.set(`oauth:${state}`, { codeVerifier, tenantId, returnTo }, { ttl: 600 });

const url = new URL(provider.authorizeEndpoint);
url.search = new URLSearchParams({
  response_type: "code",
  client_id: provider.clientId,
  redirect_uri: provider.redirectUri,    // MUST match registered value byte-for-byte (exact match)
  scope: provider.scopes.join(" "),       // least privilege
  state,
  code_challenge: codeChallenge,
  code_challenge_method: "S256",
  access_type: "offline", prompt: "consent", // Google: required to receive a refresh_token
}).toString();
return redirect(url.toString());

// 2. /callback?code&state — exchange server-side
const ctx = await cache.getAndDelete(`oauth:${state}`);              // reject unknown/replayed state
if (!ctx) throw new Error("invalid_state");
const res = await fetch(provider.tokenEndpoint, {
  method: "POST",
  headers: { "Content-Type": "application/x-www-form-urlencoded" },
  body: new URLSearchParams({
    grant_type: "authorization_code",
    code, redirect_uri: provider.redirectUri,
    client_id: provider.clientId, client_secret: provider.clientSecret, // omit secret for public clients
    code_verifier: ctx.codeVerifier,
  }),
});
const tok = await res.json(); // { access_token, refresh_token, expires_in, scope, token_type }
await vault.store(ctx.tenantId, provider.id, tok);                   // encrypted (below)
```

## Refresh-token rotation (OAuth 2.1 requirement)

Each refresh **returns a new refresh token and invalidates the old one**. If you ever see the old
one used again, treat it as theft → revoke the whole grant.

```ts
async function getAccessToken(integrationId: string): Promise<string> {
  const c = await vault.load(integrationId);
  if (c.expiresAt > Date.now() + 60_000) return c.accessToken;       // 60s safety skew

  return mutex.run(integrationId, async () => {                      // serialize: avoid double-refresh race
    const fresh = await vault.load(integrationId);                   // re-read inside lock
    if (fresh.expiresAt > Date.now() + 60_000) return fresh.accessToken;
    const res = await fetch(provider.tokenEndpoint, { method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ grant_type: "refresh_token", refresh_token: fresh.refreshToken,
        client_id: provider.clientId, client_secret: provider.clientSecret }) });
    if (res.status === 400) { await vault.markNeedsReauth(integrationId); throw new Error("invalid_grant"); }
    const tok = await res.json();
    await vault.store(integrationId, provider.id, { ...tok,
      refresh_token: tok.refresh_token ?? fresh.refreshToken });     // some IdPs omit if unchanged
    return tok.access_token;
  });
}
```

Also run a **background job** that refreshes anything within ~5 min of expiry so the hot path never
pays the refresh latency. On `invalid_grant`, set `status=needs_reauth` and notify the user — a dead
refresh token is silent until a customer's data stops syncing.

## JWT-Bearer (server-to-server, no browser)

**GitHub App:** RS256 JWT, `iss` = **client id** (recommended) or app id, `exp` ≤ **10 min**, `iat`
back-dated 60s for clock skew → exchange for a 1-hour installation token. Let Octokit do it:

```ts
import { App } from "octokit";                                       // wraps @octokit/auth-app
const app = new App({ appId: APP_ID, privateKey: PRIVATE_KEY });
const octokit = await app.getInstallationOctokit(installationId);    // auto JWT + token refresh
```

**Salesforce JWT-Bearer:** sign an RS256 assertion and POST it; no client secret transmitted.

```ts
import jwt from "jsonwebtoken";
const assertion = jwt.sign(
  { iss: CONSUMER_KEY, sub: INTEGRATION_USERNAME,
    aud: isSandbox ? "https://test.salesforce.com" : "https://login.salesforce.com" },
  PRIVATE_KEY, { algorithm: "RS256", expiresIn: "3m" });             // exp ≤ ~5 min or SF rejects
const res = await fetch(`${loginUrl}/services/oauth2/token`, { method: "POST",
  headers: { "Content-Type": "application/x-www-form-urlencoded" },
  body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }) });
const { access_token, instance_url } = await res.json();             // use instance_url as API base
```

## Sender-constrained tokens (DPoP / mTLS)

For high-value B2B/fintech, bind the token to your client so a stolen bearer is useless: **DPoP**
(RFC 9449 — per-request signed proof header) or **mTLS** (RFC 8705 — client cert). OAuth 2.1 strongly
encourages these for public clients; required by some regulated APIs (open banking, UAE/EU fintech).

## The credential vault (per-tenant, envelope-encrypted)

Never store plaintext tokens. Envelope encryption = a KMS Customer Master Key wraps a per-row data
key; you decrypt the DEK via KMS at use time, then AES-256-GCM the token locally.

```ts
import { GenerateDataKeyCommand, DecryptCommand, KMSClient } from "@aws-sdk/client-kms";
import { createCipheriv, createDecipheriv, randomBytes } from "crypto";
const kms = new KMSClient({});

async function encryptToken(plaintext: string, tenantId: string) {
  const { Plaintext: dek, CiphertextBlob: wrapped } = await kms.send(new GenerateDataKeyCommand({
    KeyId: process.env.KMS_KEY_ARN!, KeySpec: "AES_256",
    EncryptionContext: { tenantId } }));                              // context binds key to tenant
  const iv = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", Buffer.from(dek!), iv);
  const ct = Buffer.concat([cipher.update(plaintext, "utf8"), cipher.final()]);
  return { dekWrapped: Buffer.from(wrapped!), iv, tag: cipher.getAuthTag(), ciphertext: ct };
}
```

Alternatives: HashiCorp Vault, GCP KMS, Azure Key Vault — same envelope pattern. Static vault
runner-up: app-level AES with the master key in a secret manager (rotate it).

## API keys & secret hygiene

- Per-environment keys (`sk_live_` vs `sk_test_`); never let test keys reach prod paths.
- Per-tenant keys for white-label B2B (revoke one tenant without touching others).
- **Rotation**: support two active keys during overlap; deprecate, then revoke. Build rotation in
  before you need it — emergency rotation under breach with one key is a multi-hour outage.
- Detect leaked keys: scan commits (gitleaks), and prefix keys so secret-scanners can match them.

## Edge cases & gotchas

- **Scope creep**: providers silently grant fewer scopes than requested — read the returned `scope`
  and gate features on what you actually got.
- **Clock skew** breaks JWT `exp`/`nbf` — back-date `iat` ~60s, run NTP.
- **Refresh races**: two requests refresh simultaneously, one rotation wins, the other 400s — hence
  the per-integration mutex above.
- **Google** only returns a refresh token on first consent unless `prompt=consent&access_type=offline`.
- **Token endpoint errors** are `application/json` with `{error, error_description}` — log
  `error`, never the body verbatim (may echo the assertion).

## Observability & testing

- Metrics: `token_refresh_total{result}`, `needs_reauth_total`, time-to-expiry histogram.
- Test the full PKCE round-trip against the provider's sandbox; assert state-mismatch and
  expired-code are rejected; unit-test rotation invalidates the prior refresh token.

## Anti-patterns

- PKCE only for "public" clients (2.1: PKCE for *all* auth-code clients).
- Storing refresh tokens in `localStorage`/SPA, or unencrypted in the DB.
- Wildcard/substring redirect URIs (exact match only).
- Long-lived PATs as the primary prod auth when an App/JWT flow exists.
- Refreshing on the hot request path with no lock (double-refresh invalidation storms).
- Requesting `full`/`*` scopes "to be safe."

## Agent checklist

```
- [ ] Auth code + PKCE S256, state stored server-side, exact redirect_uri
- [ ] Refresh rotation handled; reuse of old refresh → revoke grant
- [ ] Background proactive refresh (~5 min pre-expiry) + needs_reauth on invalid_grant
- [ ] Tokens envelope-encrypted (KMS DEK + AES-256-GCM), tenant in encryption context
- [ ] Least-privilege scopes; returned scope verified
- [ ] M2M uses client-credentials/JWT-bearer/App, not user OAuth
- [ ] Key rotation path exists (two active keys) before launch
```

## References

- OAuth 2.1 spec hub: https://oauth.net/2.1/ · Security BCP RFC 9700: https://www.rfc-editor.org/rfc/rfc9700
- PKCE RFC 7636: https://www.rfc-editor.org/rfc/rfc7636 · DPoP RFC 9449: https://www.rfc-editor.org/rfc/rfc9449
- GitHub App JWT: https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-json-web-token-jwt-for-a-github-app
- Salesforce JWT-bearer: https://help.salesforce.com/s/articleView?id=sf.remoteaccess_oauth_jwt_flow.htm

## Related

`integrations-architecture-foundation`, `integrations-github-gitlab-bitbucket`,
`integrations-google-microsoft`, `google-sign-in` (backend-api-master), `mfa-authenticator-security`
