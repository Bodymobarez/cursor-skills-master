---
name: google-sign-in
description: >-
  Implement Google Sign-In / Google Identity Services (OAuth 2.0 + OIDC). Use for
  "Sign in with Google", Google OAuth, social login, ID token verification, or
  Google API authorization. Covers GIS web button, OAuth code flow + PKCE, ID
  token verification, refresh tokens, and security pitfalls.
---

# Google Sign-In (Google Identity Services)

Add "Sign in with Google" correctly and securely. Two needs:
- **Authentication** (who is the user) → ID token (OIDC).
- **Authorization** (call Google APIs) → access/refresh tokens (OAuth scopes).

## Setup (once)

1. Google Cloud Console → **OAuth consent screen** → configure.
2. **Credentials → OAuth Client ID** → Web application.
3. Add **Authorized JavaScript origins** and **redirect URIs** (exact match, incl. localhost for dev).
4. Store `CLIENT_ID` (public) and `CLIENT_SECRET` (server-only, for code exchange).

## Web sign-in (GIS) — frontend

```html
<script src="https://accounts.google.com/gsi/client" async></script>
<div id="g_id_onload"
     data-client_id="CLIENT_ID"
     data-callback="onSignIn"></div>
<div class="g_id_signin" data-type="standard"></div>
<script>
function onSignIn(resp) {
  // resp.credential is a JWT ID token — send to your backend over HTTPS
  fetch("/auth/google", { method: "POST", headers: {"Content-Type":"application/json"},
    body: JSON.stringify({ credential: resp.credential }) });
}
</script>
```

## Verify the ID token — backend (CRITICAL)

Never trust a token from the client without verifying it server-side.

```js
import { OAuth2Client } from "google-auth-library";
const client = new OAuth2Client(CLIENT_ID);
const ticket = await client.verifyIdToken({ idToken: credential, audience: CLIENT_ID });
const p = ticket.getPayload();
// MUST check: p.aud === CLIENT_ID, p.iss ∈ {accounts.google.com, https://accounts.google.com},
// p.exp not expired, and (for apps) p.email_verified === true
const user = { googleId: p.sub, email: p.email, name: p.name, picture: p.picture };
// upsert by p.sub (stable id), then issue YOUR session/JWT
```

## Authorization code flow + PKCE (to call Google APIs)

Use when you need offline access / Google API scopes:
1. Redirect to Google authorize URL with `scope`, `access_type=offline`, `code_challenge` (PKCE),
   `state` (CSRF).
2. Google redirects back with `code` → exchange server-side (with `CLIENT_SECRET`) for
   `access_token` + `refresh_token`.
3. Store the **refresh token** encrypted; use it to mint access tokens. Handle revocation.

## Using a framework? Prefer a library
- Next.js → **Auth.js/NextAuth** Google provider (handles flow, tokens, sessions).
- See `adding-auth` (in this master) for full session/protected-route patterns.

## Checklist
```
- [ ] OAuth client + exact origins/redirect URIs configured
- [ ] Frontend GIS button returns ID token to backend over HTTPS
- [ ] Backend verifies aud + iss + exp + email_verified
- [ ] User upserted by `sub` (not email); your own session issued
- [ ] PKCE + state if using the code flow; refresh tokens stored encrypted
- [ ] Logout + token revocation handled
```

## Anti-patterns
- Trusting the client-side token without server verification.
- Keying users by email (changes/reassigns) instead of `sub`.
- `CLIENT_SECRET` in frontend code.
- Skipping `state`/PKCE (CSRF / interception risk).
- Requesting broad scopes you don't need.
