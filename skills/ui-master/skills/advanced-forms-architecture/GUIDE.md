---
name: advanced-forms-architecture
description: >-
  Architect advanced forms end-to-end. Use as the foundation for any form — registration,
  login, checkout, surveys, admin, booking. Covers form state, validation (client +
  server), schema libraries (Zod/Yup), React Hook Form/Formik, accessibility (WCAG),
  error UX, security, and the server-action/API boundary. Read first, then form-patterns
  or multi-step-dynamic-forms.
---

# Advanced Forms Architecture

The foundation for every professional form. Read this first, then the pattern-specific skill.

## Layers (never skip one)

```
1. SCHEMA     — single source of truth (Zod/Yup/Valibot) → types + client + server rules
2. CLIENT     — controlled state (RHF/Formik/native), inline validation, a11y, UX
3. SERVER     — re-validate EVERYTHING; never trust the client; rate-limit; CSRF
4. PERSIST    — DB/API; idempotent submit; audit log for sensitive forms
```

> **Rule**: schema defines validation once; client mirrors it for UX; server enforces it for security.

## Recommended stack (2026)

| Layer | Choice |
|-------|--------|
| Schema | **Zod** (TypeScript-first) or Valibot (lighter) |
| React state | **React Hook Form** + `@hookform/resolvers/zod` |
| Vue | VeeValidate + Zod |
| Svelte | Superforms + Zod |
| Server (Next.js) | Server Actions + `safeParse` on the same Zod schema |
| UI primitives | Radix/shadcn `Form`, `FormField`, `FormMessage` — wired to RHF |

```ts
const schema = z.object({
  email: z.string().email(),
  password: z.string().min(8).regex(/[A-Z]/, "Need uppercase"),
});
type FormData = z.infer<typeof schema>;
// client: useForm({ resolver: zodResolver(schema) })
// server: const r = schema.safeParse(await request.json()); if (!r.success) return 400
```

## Field anatomy (every field)

```
Label (linked via htmlFor) → Input → Description (optional) → Error message
```
- `aria-invalid`, `aria-describedby` linking error + hint.
- Errors appear **on blur** or **on submit** (pick one per form; be consistent).
- Show errors **inline next to the field**, not only a toast at the top.
- Preserve user input on server error — never wipe the form.

## Validation timing

| Strategy | Use |
|----------|-----|
| `onBlur` | Most fields (don't nag while typing email) |
| `onChange` (debounced) | Username availability, password strength |
| `onSubmit` | Final gate; show all errors at once if invalid |
| Async server | Email/username taken, tax ID lookup — debounce 300–500ms |

## Security essentials
- **Server re-validation** always; sanitize; never echo raw input into HTML (XSS).
- **CSRF** token on cookie-session forms; SameSite cookies.
- **Rate-limit** submissions (registration, login, contact) per IP/email.
- **Honeypot** + optional CAPTCHA/Turnstile on public forms (spam).
- Passwords: hash server-side (argon2/bcrypt); never log; strength meter is UX only.
- File uploads: type/size limits, virus scan, store outside web root, signed URLs.

## Accessibility (forms fail here most)
- Every input has a visible `<label>` (not placeholder-only).
- Logical tab order; `fieldset` + `legend` for radio/checkbox groups.
- `autocomplete` attributes (`email`, `current-password`, `name`, `tel`, `address-line1`…).
- Error summary at top **with links** to fields (`aria-live="polite"` on submit fail).
- Don't disable submit until valid unless necessary — show errors instead (disabled buttons confuse screen readers).
- Touch targets ≥ 44px; sufficient contrast on error states.

## UX patterns that feel "advanced"
- **Progress**: saving indicator, disable double-submit, optimistic only when safe.
- **Smart defaults**: country from geo/IP, phone country code, prefill from OAuth profile.
- **Inline help** vs error: help is neutral gray; error is red + icon — never mix.
- **Success**: clear next step (check email, go to dashboard), not a dead end.
- **Mobile**: appropriate `inputMode`, `type`, one-column layout, sticky submit on long forms.

## Anti-patterns
- Validation only on client (trivially bypassed).
- Placeholder as label; no error messages; wiping form on failed submit.
- Different rules client vs server (drift → confusion and bugs).
- `alert()` for errors; only red border with no text.
- Giant single-page registration with 30 fields (use steps — see multi-step skill).
