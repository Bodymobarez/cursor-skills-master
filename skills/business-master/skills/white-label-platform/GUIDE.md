---
name: white-label-platform
description: >-
  Ship one codebase that runs as N brands at principal depth: host→tenant resolution, custom
  domains with automated ACME TLS, runtime theming via CSS variables (no per-tenant rebuild),
  white-labeled emails/PDFs/auth pages, per-tenant feature flags & plan limits, a reseller/agency
  layer, and per-tenant billing. Builds on multi-tenant-isolation + tailwind-design-tokens.
---

# White-Label Platform — One Codebase, N Brands

**White-label = the same deploy, themed and isolated per tenant at runtime.** If theming a new brand
requires a build, a redeploy, or a code change, you've failed the assignment — onboarding a reseller
should be a row in a table and a DNS record, not a release. Two hard parts: **never leak data across
tenants** (data layer) and **never leak brand** (every pixel, email, and PDF). This skill is the brand/
domain/runtime layer; the **data isolation** layer lives in **`multi-tenant-isolation`**.

---

## 1. Mandate
1. **Zero hard-coded brand** — name, logo, colors, from-address, support URL all come from tenant config.
2. **Theming is runtime CSS variables**, never a per-tenant build or redeploy.
3. **Tenant resolved from the request host** early in middleware; every downstream query is scoped.
4. **Custom domains get automated TLS** (ACME) after verified ownership.
5. **Emails, PDFs, and auth pages are white-labeled too** — the most-missed surfaces.
6. **Data isolation is structural** (RLS + `FORCE`) — delegated to **`multi-tenant-isolation`**.

## 2. When to use / when NOT
**Use** for reseller/agency/multi-brand products, embedded/OEM offerings, and "powered-by-you" platforms.
**Don't** white-label what should stay first-party (your own marketing site), and don't promise *custom
code* per tenant — that's bespoke software, not white-label. Per-tenant **config and theme**: yes.
Per-tenant **forks**: never (you'll drown maintaining them).

## 3. Tenancy & host resolution

Default to **shared DB + `tenant_id` + RLS** (trade-offs, sharding, residency → **`multi-tenant-isolation`**).
The white-label-specific job is mapping an incoming **host** to a tenant:

```
acme.yourapp.com         subdomain     → wildcard cert *.yourapp.com (instant onboarding)
app.clientbrand.com      custom domain → client adds CNAME; you provision a cert
```

```ts
// Edge/middleware: resolve tenant from host, set context, then let RLS scope everything.
export async function resolveTenant(req: Request): Promise<TenantContext> {
  const host = req.headers.get("host")!.toLowerCase().split(":")[0];
  const row = await lookupDomain(host);            // domains table: host → tenant_id, status
  if (!row || row.status !== "active") throw new UnknownTenantError(host);
  return { tenantId: row.tenantId, branding: await getBranding(row.tenantId) };
}
// Then run the request inside withTenant(pool, ctx.tenantId, ...) — see multi-tenant-isolation.
```

Cache `host → tenant` (and branding) at the edge with a short TTL + explicit bust on change; this lookup
is on every request's critical path. **Never** trust an `X-Tenant` header or a path param from the client.

## 4. Custom domains + automated TLS

| Step | What | How |
|------|------|-----|
| 1. Add domain | tenant enters `app.clientbrand.com` | row in `domains` (status `pending`) |
| 2. Prove ownership | CNAME → your edge, or TXT challenge | poll DNS until it resolves to you |
| 3. Issue cert | automated, no human | **ACME** (Let's Encrypt/ZeroSSL) HTTP-01/DNS-01, or platform "SSL for SaaS" (Cloudflare) / Vercel Domains API |
| 4. Renew | automatic before expiry | ACME client / platform handles it; monitor expiry |
| 5. Activate | flip to `active` | route + cert live |

Don't build a cert manager by hand unless you must — **Cloudflare SSL for SaaS** (custom hostnames) or
**Vercel** issue and renew per-tenant certs via API and are the pragmatic 2026 choice. If self-hosting,
use **Caddy** (on-demand TLS) or an ACME library; store certs in a secret store, never in the repo.

## 5. Runtime theming (the core trick)

Store branding per tenant; inject as **CSS custom properties** at the document root — the entire UI
re-themes with **zero rebuild**. This is exactly the multi-brand pattern in **`tailwind-design-tokens`**
(reference it for the OKLCH/semantic-token architecture):

```ts
// branding config (validated; colors in OKLCH/hex, validated for WCAG contrast at save time)
type Branding = {
  logoUrl: string; faviconUrl: string;
  colors: { primary: string; accent: string; bg: string; fg: string };
  fontFamily: string; emailFrom: string; supportUrl: string; customCss?: string | null;
};
```

```tsx
// Server-render the tenant's tokens into <head>; components reference semantic vars, never raw colors.
export function BrandStyle({ b }: { b: Branding }) {
  return (
    <style>{`:root{
      --color-primary:${b.colors.primary}; --color-accent:${b.colors.accent};
      --color-background:${b.colors.bg};   --color-foreground:${b.colors.fg};
      --font-sans:${JSON.stringify(b.fontFamily)};
    }`}</style>
  );
}
```

**Validate brand colors against WCAG contrast at save time** (reject an unreadable primary-on-bg) so a
reseller can't theme themselves into an inaccessible UI. Treat raw `customCss` as untrusted — sanitize/scope
it or you've opened CSS-injection across the shared app. (Generate brand kits with `brand-identity-creator`;
palette/contrast math in `color-design-master`.)

## 6. White-label EVERY surface (the audit checklist)
- **Emails**: from-address/domain (per-tenant SPF/DKIM/DMARC), logo, footer, reply-to, links to the
  tenant's domain. A `noreply@yourapp.com` email on a "client brand" account breaks the illusion instantly.
- **PDFs/invoices**: logo, colors, company/legal details, support info (and tax/e-invoicing identity →
  **`einvoicing-compliance`**).
- **Auth pages**: login/signup/reset, OAuth consent screens, and 2FA emails carry tenant brand.
- **Error/empty/loading pages, favicons, OG/meta tags, transactional SMS.**
- **Outbound webhooks/API**: docs and signatures referencing the tenant brand where exposed.

## 7. Feature flags, plans & reseller hierarchy
- **Per-tenant flags + plan limits** (seats, storage, API calls): resolve effective config = plan
  defaults ⊕ tenant overrides; enforce limits server-side, not just hide UI.
- **Reseller/agency layer**: a parent tenant manages many sub-tenants (set branding/plans, see usage),
  with role scoping so a reseller sees only *their* sub-tenants. Model `parent_tenant_id`; keep data
  isolation between sibling sub-tenants absolute.

## 8. Per-tenant billing
- **You bill the reseller** (who bills their own customers), or you bill each tenant directly — decide and
  model it. **Stripe** customer/subscription per billing entity; meter usage (seats/API) and report.
- Reseller economics: wholesale price to reseller, they set retail; your invoices to them are
  white-labeled too. Pair with **`payments-master`** / `accounting-finance` for the money side.

## 9. Performance, security & scale
- **Brand/domain lookups are per-request** — cache aggressively (edge KV), bust on change.
- **Don't leak across tenants in shared infra**: namespace **cache keys, queues, rate limits, search
  indexes, and file storage paths by `tenant_id`** (a shared Redis key without the tenant prefix is a
  cross-tenant data bug just like a missing SQL filter).
- **Per-tenant secrets** (their SMTP/OAuth/webhook keys) in a secret manager, encrypted, access-audited.
- **Noisy neighbor & residency** → `multi-tenant-isolation` (cells, region pinning for EU/GCC data laws).

## 10. Testing & observability
- **Brand-leak test**: render emails/PDFs/auth for tenant A → assert no default brand strings, correct
  from-domain, correct logo. Snapshot per tenant.
- **Domain lifecycle test**: pending→verified→cert-issued→active; expired cert alerts.
- **Cache-namespacing test**: tenant A's cached value never served to tenant B.
- **Observe**: per-tenant cert expiry, DNS verification failures, theme-render errors, per-tenant error/latency
  (so one reseller's outage is visible), email deliverability per sending domain.

## 11. i18n / RTL
Per-tenant default locale + RTL (Arabic) theming; localized emails/PDFs/auth in the tenant's language;
tenant-configurable currency/date formats. Mirror layout for `dir="rtl"` using the same semantic tokens.

## 12. Anti-patterns
- **Any query/cache/queue key without `tenant_id`** → cross-tenant leak (the #1 white-label bug).
- **Hard-coded logo/app-name/brand** in components, emails, or PDFs.
- **Rebuild/redeploy per tenant** for theming → use runtime CSS variables.
- **Forgetting to white-label emails/PDFs/auth** → brand leak that kills trust.
- **Unsanitized per-tenant `customCss`/HTML** → CSS/script injection across the shared app.
- **Shared sessions/JWTs not scoped to tenant** → auth bleed.
- **Per-tenant code forks** → unmaintainable; keep it config + theme.
- **Manual cert management** → expired certs take a brand down; automate ACME.

## 13. Agent checklist
```
- [ ] Host→tenant resolver in middleware; tenant from host only, never client input
- [ ] Shared DB + RLS + FORCE (multi-tenant-isolation); cache/queue/storage keyed by tenant
- [ ] Custom domains: verify CNAME/TXT → automated ACME TLS → auto-renew + expiry alerts
- [ ] Runtime theming via CSS vars (tailwind-design-tokens); WCAG-validate brand colors at save
- [ ] Emails (per-tenant DKIM/SPF), PDFs, auth pages, favicons all white-labeled — no default strings
- [ ] Per-tenant flags/plan limits enforced server-side; reseller hierarchy with scoped access
- [ ] Per-tenant billing (Stripe) + usage metering
- [ ] Brand-leak + cache-namespacing tests in CI; per-tenant cert/deliverability monitoring
```

## 14. References (2026-current)
- Cloudflare SSL for SaaS (custom hostnames): https://developers.cloudflare.com/cloudflare-for-platforms/cloudflare-for-saas/
- Vercel Domains API / multi-tenant: https://vercel.com/docs/multi-tenant
- Caddy on-demand TLS / ACME: https://caddyserver.com/docs/automatic-https · https://datatracker.ietf.org/doc/html/rfc8555
- CSS custom properties (runtime theming): https://developer.mozilla.org/en-US/docs/Web/CSS/--*

## Related
`multi-tenant-isolation`, `tailwind-design-tokens` (tailwind-master), `brand-identity-creator` & `color-design-master`,
`einvoicing-compliance`, `payments-master`, `accounting-finance`
