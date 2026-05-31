---
name: white-label-platform
description: >-
  Make a product white-label / multi-tenant brandable. Use when the user wants
  white-labeling, reseller/agency multi-brand, per-tenant custom domains, theming,
  logos, and isolated data. Covers tenancy models, custom domains + TLS, dynamic
  theming/branding, per-tenant config, and billing.
---

# White-Label Platform

Let each customer (tenant/reseller) run your product under **their own brand, domain, and theme**
with isolated data.

## 1. Tenancy model (pick one)

| Model | Isolation | Best for |
|-------|-----------|----------|
| **Shared DB, `tenant_id` column** (row-level) | Logical | Most SaaS; cheapest to scale |
| **Schema-per-tenant** | Medium | Stronger isolation, moderate count |
| **DB-per-tenant** | Strong | Enterprise/compliance, few large tenants |

Default to **shared DB + `tenant_id`** with enforced row-level security. Resolve the tenant from
the **request host/domain** (or subdomain) early in middleware and scope every query.

## 2. Custom domains + TLS

```
tenant.yourapp.com         (subdomain — easy, wildcard cert *.yourapp.com)
app.clientbrand.com        (custom domain — client adds CNAME → your edge)
```
- Verify domain ownership (CNAME/TXT), then **auto-provision TLS** (Let's Encrypt / ACME, or
  platform like Vercel/Cloudflare for SaaS). Map host → tenant in a `domains` table.

## 3. Branding / theming (per tenant)

Store a `branding` record per tenant and inject at runtime:
```json
{
  "logo_url": "...", "favicon_url": "...",
  "colors": { "primary": "#...", "accent": "#...", "bg": "#...", "text": "#..." },
  "font": "Inter", "email_from": "noreply@clientbrand.com",
  "custom_css": null, "support_url": "..."
}
```
- Apply via **CSS custom properties** (`--color-primary`, etc.) set from tenant config — no
  rebuild per tenant. (Pair with `brand-identity-creator` to generate the brand kit, and
  `charts-and-dashboards` themes inherit the same tokens.)
- White-label **emails** (from-address, logo, footer), **PDF/docs**, and **auth pages**.

## Build checklist

```
- [ ] 1. Tenant model + `tenant_id` on every table + row-level enforcement
- [ ] 2. Host→tenant resolver middleware (subdomain + custom domain)
- [ ] 3. Custom domain onboarding (verify CNAME/TXT) + automatic TLS
- [ ] 4. Per-tenant branding config (logo, colors via CSS vars, fonts, favicon)
- [ ] 5. White-label emails, documents, auth screens, and error pages
- [ ] 6. Per-tenant feature flags / plan limits + settings
- [ ] 7. Reseller/agency layer (manage many sub-tenants) if needed
- [ ] 8. Billing per tenant (Stripe) + usage metering
- [ ] 9. Remove all hard-coded brand strings; centralize in config
```

## Anti-patterns
- Any query missing `tenant_id` (cross-tenant data leak — the #1 white-label bug).
- Hard-coded logo/brand/app name in components or emails.
- Rebuilding/redeploying per tenant for theming (use runtime CSS variables).
- Sharing caches/sessions across tenants without keying by tenant.
- Forgetting to white-label transactional emails and PDFs (common miss).
