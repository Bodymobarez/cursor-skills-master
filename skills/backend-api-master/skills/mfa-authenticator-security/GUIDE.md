---
name: mfa-authenticator-security
description: >-
  Implement multi-factor authentication (MFA/2FA) and authenticator security.
  Use for TOTP authenticator apps (Google Authenticator, Authy, 1Password), QR
  enrollment, WebAuthn/passkeys, SMS/email OTP, push approval, backup/recovery
  codes, and step-up auth. Covers correct crypto, storage, rate-limiting, and UX.
---

# MFA / Authenticator Security

Add strong, correct multi-factor auth. Pick factors by threat model — **TOTP and WebAuthn are the
defaults; SMS is the weakest** (SIM-swap/phishing).

## Factor types (strongest → weakest)

| Factor | What | Notes |
|--------|------|-------|
| **WebAuthn / Passkeys** ⭐ | Hardware/platform keys (FIDO2) | Phishing-resistant, best UX; recommend as primary |
| **TOTP** ⭐ | Authenticator app codes (RFC 6238) | Google Authenticator/Authy/1Password; offline, no SMS cost |
| **Push approval** | Approve on a trusted device | Watch for "MFA fatigue" → use number-matching |
| **Email OTP** | One-time code via email | OK fallback; only as strong as the inbox |
| **SMS OTP** | Code via text | Last resort — SIM-swap/SS7 risk; never the only factor |
| **Backup codes** | One-time recovery codes | Always offer as recovery for the above |

## 1. TOTP (Google Authenticator-style) — the core flow

```
Enroll:  server generates a random secret (≥160-bit, base32)
         → build otpauth:// URI → render as QR (see qr-code-generation)
         → user scans → enters a code → server VERIFIES before enabling (proves sync)
Login:   user enters 6-digit code → server checks current 30s window ±1 step (clock drift)
```

`otpauth` URI format:
```
otpauth://totp/{Issuer}:{account}?secret={BASE32}&issuer={Issuer}&algorithm=SHA1&digits=6&period=30
```
> Keep defaults **SHA1 / 6 digits / 30s** — that's what authenticator apps expect. Don't get clever.

**Node (`otplib`):**
```js
import { authenticator } from "otplib";
const secret = authenticator.generateSecret();              // store ENCRYPTED at rest
const uri = authenticator.keyuri(user.email, "MyApp", secret);
// verify with drift tolerance:
authenticator.options = { window: 1 };                       // accept ±1 step (~30s)
const ok = authenticator.verify({ token, secret });
```
**Python:** `pyotp` — `pyotp.TOTP(secret).verify(token, valid_window=1)`.

### TOTP must-dos
- **Verify a code during enrollment** before turning MFA on (catches clock/scan errors).
- **Replay protection**: reject a code that was already used in its window (store last-used step).
- **Rate-limit** verification (e.g. 5 attempts → lockout/backoff) — brute force is 1-in-a-million per try.
- Encrypt the secret at rest (KMS/secret box), never log it, never return it after enrollment.

## 2. WebAuthn / Passkeys (phishing-resistant, recommend first)

Use a library — never hand-roll: **SimpleWebAuthn** (JS), `py_webauthn`, Spring Security WebAuthn.
```
Register: server → creationOptions (challenge, rp, user) → navigator.credentials.create()
          → verify attestation → store credential (id, publicKey, counter, transports)
Login:    server → requestOptions (challenge, allowCredentials) → navigator.credentials.get()
          → verify assertion (signature + counter increases) 
```
- Store `rpID` = your domain; bind challenges server-side (single-use, expiring).
- Verify the **signature** and that the **signCount increased** (clone detection).

## 3. Backup & recovery codes
- Generate 8–10 single-use codes; show **once**; store only **hashes** (bcrypt/argon2).
- Mark used; let users regenerate (invalidates old set). Required so users aren't locked out.

## 4. SMS / Email OTP (fallback only)
- 6 digits, short TTL (5–10 min), single-use, hashed at rest, strict rate limit + resend cooldown.
- Bind to the session/flow; never reveal whether the account exists.

## Build checklist
```
- [ ] Primary: WebAuthn/passkeys and/or TOTP; SMS only as fallback
- [ ] TOTP: random ≥160-bit secret, QR enroll, verify-before-enable, ±1 window, replay + rate limit
- [ ] Encrypt MFA secrets at rest (KMS); never log/return them
- [ ] Backup codes (hashed, single-use, regenerable)
- [ ] Lockout/backoff on repeated failures; alert on new factor enrolled
- [ ] Step-up auth for sensitive actions (re-prompt MFA), not just at login
- [ ] "Remember this device" with a signed, expiring, revocable device token
- [ ] Recovery flow that can't bypass MFA trivially (support/identity proof)
- [ ] Audit log: enroll, verify, disable, recovery used
```

## Step-up / adaptive auth
Require MFA again for high-risk actions (change email/password, payouts, admin) and on risk
signals (new device, new geo/IP, impossible travel). Pair with `adding-auth` for sessions and
`google-sign-in` for social login.

## Anti-patterns
- SMS as the only/strong factor; revealing account existence in OTP flows.
- Storing TOTP secrets/backup codes in plaintext; logging codes.
- No replay protection or rate limit (codes become brute-forceable).
- Enabling MFA without verifying a code first (locks users out).
- Hand-rolling WebAuthn crypto instead of a vetted library.
- Push prompts without number-matching (MFA-fatigue attacks).
