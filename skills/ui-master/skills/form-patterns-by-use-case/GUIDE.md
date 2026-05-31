---
name: form-patterns-by-use-case
description: >-
  Build advanced forms by use case with production-ready patterns. Use for registration,
  login, password reset, onboarding, profile/settings, contact, checkout, surveys,
  applications, booking, and admin CRUD forms. Each pattern includes fields, validation,
  security, UX flow, and server integration. Builds on advanced-forms-architecture.
---

# Form Patterns by Use Case

Copy-adapt these patterns for each form type. Pair with `advanced-forms-architecture` for stack/a11y
and `multi-step-dynamic-forms` for wizards.

## Registration (sign-up) — advanced

```
Fields: email, password (+ confirm), name (first/last or full), optional phone,
        terms checkbox (required), marketing opt-in (optional), country/locale
Flow:   validate → create user (pending) → send verification email → "check your inbox"
        (don't auto-login until verified, unless product allows)
```
- **Password**: min 8–12, complexity rules in schema; strength meter (zxcvbn); show/hide toggle.
- **Email**: format + async "already registered" check (debounced); normalize lowercase.
- **Confirm password**: `z.refine` match; validate on blur of confirm field.
- **Terms**: required checkbox with link to terms; store consent timestamp + version.
- **Security**: rate-limit; CAPTCHA on abuse; no user enumeration ("if email exists" → same
  generic message: "If an account exists, we sent instructions").
- **OAuth alternative**: "Continue with Google" above or beside email form (`google-sign-in`).
- **Post-submit**: verification email with expiring token; resend with cooldown.

## Login (sign-in)

```
Fields: email/username, password, remember-me (optional)
Flow:   validate → session/JWT → redirect to returnUrl
```
- Generic error: "Invalid email or password" (don't reveal which failed).
- **Brute-force**: rate-limit + lockout/backoff; optional CAPTCHA after N fails.
- **Remember me**: long-lived refresh token in httpOnly cookie vs session-only.
- Links: forgot password, sign up.
- **MFA step**: if enrolled, redirect to TOTP/WebAuthn step (`mfa-authenticator-security`).

## Password reset

```
Request: email only → always show "If account exists, email sent"
Reset:   new password + confirm + token from URL (single-use, expiring)
```
- Token in URL: short TTL (1h), one-time use, invalidate on password change.
- Invalidate all sessions on reset.

## Onboarding (post-signup)

```
Multi-step wizard: role → company details → preferences → invite team → done
Progress bar; back allowed; save draft per step (optional)
Skip optional steps; celebrate completion
```
- Pre-fill from registration/OAuth; minimal required fields per step.
- See `multi-step-dynamic-forms`.

## Profile / account settings

```
Tabs or sections: Personal | Security | Notifications | Billing | Danger zone
Each section = separate form + separate save (don't one giant submit)
```
- **Security**: change email (re-verify), change password (current password required), MFA enroll.
- **Danger zone**: delete account — type email to confirm + password; soft-delete grace period.
- Optimistic UI only for low-risk fields (display name); pessimistic for email/password.

## Contact / support

```
Fields: name, email, subject/category, message, optional attachment
```
- Honeypot + Turnstile; rate-limit; auto-create ticket (`support-helpdesk-system`).
- Category drives routing; max message length; sanitize HTML in message.

## Checkout / payment

```
Sections: contact → shipping → payment → review
```
- Address autocomplete (Google Places); validate shipping zones.
- Amount/totals computed **server-side** only (`payments-master`, `checkout-and-payment-pages`).
- Don't collect card in your inputs — hosted fields only.

## Survey / feedback / NPS

```
One question per screen OR scrollable; progress; required vs optional per question
Types: single choice, multi, scale 1–10, text, ranking
```
- Allow save & resume (token in URL); thank-you screen; analytics on drop-off per step.

## Application / intake (jobs, KYC, vendor)

```
Long multi-step; document uploads; conditional sections by applicant type
Status: draft → submitted → under review; editable until submitted
```
- File uploads with progress; virus scan; PII encryption at rest.
- Audit trail of who changed what.

## Booking / reservation

```
Date/time picker (timezone-aware), guests, special requests, payment hold
```
- Real-time availability check; hold slot 10–15 min during checkout.
- Pair with `travel-tech` / marketplace patterns as needed.

## Admin CRUD (create/edit entity)

```
Mode: create vs edit (prefill on edit); inline vs modal vs full page
Fields: match DB schema; relation pickers (searchable select); slug auto from title
```
- Optimistic locking (`version` field) on concurrent edit.
- Destructive actions: confirm modal + typed confirmation.

## Quick reference: validation snippets (Zod)

```ts
// registration
z.object({
  email: z.string().email().toLowerCase(),
  password: z.string().min(8).max(128),
  confirmPassword: z.string(),
  acceptTerms: z.literal(true, { errorMap: () => ({ message: "Required" }) }),
}).refine(d => d.password === d.confirmPassword, { path: ["confirmPassword"] })

// phone (E.164 friendly)
phone: z.string().regex(/^\+?[1-9]\d{6,14}$/)
```

## Checklist (any form)
```
- [ ] Zod schema shared client + server
- [ ] Correct pattern for use case (above)
- [ ] Security: rate-limit, no enumeration, CSRF, server re-validate
- [ ] a11y: labels, errors, autocomplete, error summary
- [ ] Success/failure UX with clear next step; no wipe on error
```

## Anti-patterns
- Registration that auto-logs in without verification when email verification is required.
- "Email already exists" on login form (enumeration).
- One 40-field page instead of stepped onboarding.
- Checkout totals from client JavaScript.
- Admin delete without confirmation.
