---
name: cloudixia-integrations-ecosystem
description: >-
  Principal-level Cloudixia integrations ecosystem: 17 modules, Integration Marketplace (Cloudflare/
  Supabase/Vercel/Stripe tier), 100+ providers, certified partner apps, unified schema, backend services,
  APIs, UI, billing, RBAC. Databases, Storage, Deploy, Domains, API Studio, Email, Inbox, VoIP, Auth,
  Billing, Monitoring, AI Studio, Secrets, K8s, CDN, Search. Use for Cloudixia platform design or build.
---

# Cloudixia — Integrations Ecosystem (Complete)

**Mandate:** design Cloudixia as a **Cloud Developer Ecosystem** — not a single-product clone of Supabase or Neon.
Every module ships **native first-party capabilities** plus an **Integration Marketplace** with **Certified Apps**
(OAuth-reviewed, security-scanned, badge + SLA tier). Read `integrations-architecture-foundation` before implementing any connector.

**Catalog:** `data/integration-catalog.yaml` (100+ providers, priorities, certification tier).

**Pair with:** `integrations-oauth-api-keys`, `integrations-webhooks-events`, `integrations-ipaas-n8n-zapier`,
`payments-master`, `communications-master`, `systems-platforms-master`, `database-studio-complete`,
`marketplace-master` (multi-tenant billing), `elite-ui-ux-design-system`.

---

## Platform vision

| Dimension | Cloudixia position |
|-----------|-------------------|
| **Category** | Unified cloud control plane for builders: data, deploy, comms, APIs, domains |
| **North-star** | One org, one RBAC, one billing meter — many modules + marketplace extensions |
| **Compete with** | Supabase + Vercel + Resend + Twilio + Cloudflare (combined), not one of them only |
| **Enterprise wedge** | Certified integrations, audit logs, SSO/SAML, usage-based billing, data residency |

### Reference architectures to emulate

| Platform | Steal |
|----------|-------|
| **Cloudflare** | One-click integrations, dashboard tiles, audit, API tokens per integration |
| **Supabase** | Marketplace extensions, OAuth for third-party tools, project-scoped secrets |
| **Neon** | Branching hooks for CI, GitHub-native flows |
| **Vercel** | Git → deploy, env sync, integration install per project |
| **Twilio** | Subaccounts, usage records, webhook debugger |
| **Stripe** | Connect-style partner apps, certified partner program, metered billing |

---

## Module map (17 modules)

| # | Module ID | Native core | Marketplace focus |
|---|-----------|-------------|-------------------|
| 1 | `databases` | Postgres/MySQL/Mongo/Redis managed | ORM, BI, external DB attach |
| 2 | `object_storage` | R2-compatible buckets | S3, B2, media CDNs |
| 3 | `deploy` | Build + run from Git | Actions, Terraform, registries |
| 4 | `domains` | DNS + SSL automation | Registrars, Route53 |
| 5 | `api_studio` | OpenAPI design + mock + gateway | Postman, Kong |
| 6 | `email_api` | Transactional send + auth DNS | Resend, SES, SendGrid |
| 7 | `email_marketing` | Campaigns + segments | CRM + Mailchimp sync |
| 8 | `inbox` | Omnichannel inbox | WhatsApp, Zendesk, Intercom |
| 9 | `voip` | Cloudixia voice + SIP bridge | Twilio, Zoom, Teams |
| 10 | `auth_sso` | Cloudixia Auth + SAML | Google, Microsoft, LDAP |
| 11 | `billing` | Usage meters + invoices | Stripe, Paddle |
| 12 | `monitoring` | Metrics + logs baseline | Grafana, Datadog, Sentry |
| 13 | `ai_studio` | Prompt workflows + keys | OpenAI, Anthropic, Gemini |
| 14 | `secrets` | Encrypted secret store | Vault, AWS SM |
| 15 | `kubernetes` | Managed K8s attach | EKS, GKE, AKS |
| 16 | `cdn` | Edge cache + rules | Cloudflare, Bunny |
| 17 | `search` | Meilisearch managed | Elasticsearch, Typesense |

---

## Integration Marketplace architecture

```
┌──────────────────────────────────────────────────────────────────────────┐
│ Cloudixia Console — Integrations Hub (/org/integrations)                  │
├──────────────────────────────────────────────────────────────────────────┤
│ Browse: By Module | By Category | Certified Only | Installed | Updates   │
│ App detail: Install → OAuth/API key → Scopes → Webhook URL → Test → Enable│
└──────────────────────────────────────────────────────────────────────────┘
         │ install                    │ events
         ▼                            ▼
┌─────────────────┐    ┌──────────────────────┐    ┌─────────────────────┐
│ Integration     │    │ Connection Service    │    │ Provider Adapter     │
│ Registry (catalog)│───▶│ (OAuth, secrets KMS) │───▶│ (per vendor port)    │
└─────────────────┘    └──────────────────────┘    └─────────────────────┘
         │                            │
         ▼                            ▼
┌─────────────────┐    ┌──────────────────────┐
│ Certified App   │    │ Webhook Ingress +     │
│ Review Pipeline │    │ Outbound Delivery + DLQ│
└─────────────────┘    └──────────────────────┘
```

### Native vs marketplace vs certified

| Type | Who builds | Review | Badge | Billing |
|------|------------|--------|-------|---------|
| **native** | Cloudixia | Internal | Official | Included in module plan |
| **marketplace (certified_partner)** | Partner | Security + OAuth review | Certified | Revenue share or per-seat |
| **marketplace (partner)** | Partner | Automated scan | Verified | Listed |
| **marketplace (community)** | Anyone | Self-attestation | None | Free listing |

### Certified App program (سيرتفايد)

Partners submit an **Integration App Manifest** (`integration-app.yaml`):

```yaml
app_id: com.resend.cloudixia
name: Resend Email
module: email_api
certification_tier: certified_partner
oauth:
  authorization_url: https://api.resend.com/oauth/authorize
  token_url: https://api.resend.com/oauth/token
  scopes: [email.send, domains.read]
webhooks:
  events: [email.sent, email.bounced]
  signature_header: Resend-Signature
  algorithm: hmac-sha256
security:
  sast_report_url: ...
  privacy_policy_url: ...
  data_retention_days: 30
```

**Review gates:** (1) manifest schema valid, (2) OAuth redirect allowlist, (3) webhook signature test vectors,
(4) least-privilege scopes, (5) pen-test checklist for P0 partners, (6) SLA + support contact.

**Badges in UI:** Official (cloud logo), Certified (shield), Verified (check), Community (no badge).

---

## Unified database schema (marketplace + connections)

```sql
-- ─── Catalog (global, versioned) ───
CREATE TABLE integration_apps (
  id                text PRIMARY KEY,              -- 'resend'
  module_id         text NOT NULL,                 -- 'email_api'
  category          text NOT NULL,
  provider_name     text NOT NULL,
  type              text NOT NULL,                 -- native | marketplace
  certification     text NOT NULL,                 -- official | certified_partner | partner | community
  manifest          jsonb NOT NULL,
  priority_score    int NOT NULL DEFAULT 50,
  is_published      boolean DEFAULT false,
  created_at        timestamptz DEFAULT now()
);

CREATE TABLE integration_app_versions (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  app_id            text REFERENCES integration_apps(id),
  version           text NOT NULL,
  changelog         text,
  manifest_delta    jsonb,
  published_at      timestamptz
);

-- ─── Per org install ───
CREATE TABLE org_integration_installs (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id            uuid NOT NULL,
  project_id        uuid,                          -- null = org-wide
  app_id            text NOT NULL REFERENCES integration_apps(id),
  status            text NOT NULL,                   -- active | needs_reauth | suspended
  config            jsonb DEFAULT '{}',
  installed_by      uuid,
  installed_at      timestamptz DEFAULT now(),
  UNIQUE (org_id, project_id, app_id)
);

CREATE TABLE integration_connections (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  install_id        uuid NOT NULL REFERENCES org_integration_installs(id),
  auth_type         text NOT NULL,                 -- oauth2 | api_key | iam | none
  access_token_enc  bytea,
  refresh_token_enc bytea,
  api_key_enc       bytea,
  dek_wrapped       bytea,
  expires_at        timestamptz,
  scopes            text[],
  external_account_id text,
  metadata          jsonb,
  last_health_at    timestamptz,
  health_status     text DEFAULT 'unknown'
);

CREATE TABLE integration_webhook_subscriptions (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  install_id        uuid NOT NULL REFERENCES org_integration_installs(id),
  provider_event    text NOT NULL,
  target_url        text,                          -- Cloudixia ingress URL
  secret_enc        bytea,
  status            text DEFAULT 'active'
);

CREATE TABLE integration_usage_events (
  id                bigserial PRIMARY KEY,
  org_id            uuid NOT NULL,
  install_id        uuid,
  module_id         text NOT NULL,
  metric            text NOT NULL,                 -- emails.sent | db.storage.gb
  quantity          numeric NOT NULL,
  recorded_at       timestamptz DEFAULT now()
);

CREATE TABLE integration_audit_log (
  id                bigserial PRIMARY KEY,
  org_id            uuid NOT NULL,
  actor_id          uuid,
  action            text NOT NULL,                 -- install | uninstall | token_refresh | webhook_received
  app_id            text,
  payload_hash      text,
  created_at        timestamptz DEFAULT now()
);
```

Extend `integrations` table from `integrations-architecture-foundation` — **connections** are always
scoped to `org_id` + optional `project_id`.

---

## Backend services (microservice boundaries)

| Service | Responsibility |
|---------|----------------|
| **integration-registry** | CRUD catalog, manifest validation, certification workflow |
| **connection-service** | OAuth dance, token refresh, KMS encrypt, health checks |
| **webhook-ingress** | Verify signature, dedupe, enqueue |
| **webhook-worker** | Route event to module handlers, DLQ + replay |
| **adapter-runtime** | Load adapter plugins per `app_id` |
| **usage-metering** | Emit `integration_usage_events` → billing |
| **billing-bridge** | Stripe/Paddle metered items |
| **notification-bridge** | Alert on install failure, quota, cert expiry |

**Event bus topics:** `integration.installed`, `integration.connection.unhealthy`, `webhook.{app_id}.{event}`.

---

## Public APIs

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/v1/integrations/apps` | List catalog (filter module, certified) |
| GET | `/v1/integrations/apps/{appId}` | App detail + manifest |
| POST | `/v1/orgs/{orgId}/integrations/installs` | Install app |
| DELETE | `/v1/orgs/{orgId}/integrations/installs/{id}` | Uninstall |
| GET | `/v1/orgs/{orgId}/integrations/installs` | Installed apps |
| POST | `/v1/integrations/oauth/start` | Begin OAuth (returns authorize URL) |
| GET | `/v1/integrations/oauth/callback` | OAuth callback (server-only) |
| POST | `/v1/integrations/connections/{id}/test` | Health check |
| POST | `/v1/webhooks/ingress/{appId}` | Inbound provider webhooks |
| GET | `/v1/integrations/usage` | Usage for billing dashboard |
| POST | `/v1/partner/apps` | Submit certified app (partner portal) |
| GET | `/v1/partner/apps/{id}/certification-status` | Review state |

**Auth:** Cloudixia API keys + OAuth for console; partner portal uses separate client credentials.

---

## UI screens (Integrations Hub)

| Route | Screen |
|-------|--------|
| `/integrations` | Marketplace home — featured certified, by module |
| `/integrations/browse` | Filters: module, category, certified, search |
| `/integrations/apps/{appId}` | Detail: description, scopes, pricing, reviews, Install CTA |
| `/integrations/installed` | Org installs — status, reconnect, configure |
| `/integrations/installed/{id}` | Config: credentials, webhooks, logs, test button |
| `/integrations/installed/{id}/events` | Webhook delivery log (like Stripe/Twilio debugger) |
| `/integrations/oauth/callback` | Loading state → redirect back |
| `/partner/submit` | Partner: submit manifest for certification |
| `/partner/apps/{id}/review` | Admin: certification queue |
| Per-module shortcut | e.g. `/databases/integrations` → filtered browse |

**UX bar:** `elite-ui-ux-design-system` — Certified badge prominent; prod warning on broad scopes.

---

## Billing architecture

| Layer | Model |
|-------|-------|
| **Module base** | Per org plan: Pro / Enterprise includes N native integrations |
| **Marketplace install** | Free install; **usage pass-through** + Cloudixia fee (e.g. 15% on metered partner SKUs) |
| **Certified partner** | Partner sets price in manifest; Cloudixia rev-share 70/30 |
| **Native overage** | DB storage GB, email sends, VoIP minutes — unified meter |
| **Stripe Connect** | For partners billing end-customers (optional) |

```sql
CREATE TABLE billing_meters (
  id           text PRIMARY KEY,    -- 'email_api.sends'
  module_id    text NOT NULL,
  unit         text NOT NULL,
  stripe_price_id text
);

CREATE TABLE org_subscription_items (
  org_id       uuid,
  meter_id     text,
  quantity     numeric,
  period_start timestamptz,
  period_end   timestamptz
);
```

**Enterprise:** committed use discounts; invoice line per module + per certified app.

---

## RBAC permissions (org + project)

| Permission | Scope | Description |
|------------|-------|-------------|
| `integrations:read` | org | View marketplace + installed |
| `integrations:install` | org/project | Install/uninstall apps |
| `integrations:configure` | project | Edit connection config |
| `integrations:secrets:read` | project | View masked credentials |
| `integrations:secrets:write` | project | Rotate API keys |
| `integrations:webhooks:replay` | org | Replay failed deliveries |
| `integrations:partner:submit` | partner org | Submit certified apps |
| `integrations:admin:certify` | platform | Approve certification |
| `module:{id}:admin` | project | Full control of that module |

**Roles:** Owner (all), Admin (install + configure), Developer (install dev/staging only), Billing (usage read), Viewer (read catalog only).

**Production guard:** `integrations:install` on production project requires MFA + Owner approval optional.

---

## Priority scoring (0–100)

```
score = (enterprise_demand * 0.35) + (revenue_potential * 0.25) + (implementation_ease * 0.20) + (strategic_fit * 0.20)
```

| Band | Score | Action |
|------|-------|--------|
| P0 | 80–100 | Native or certified launch |
| P1 | 60–79 | Marketplace Q1 |
| P2 | 40–59 | Partner-led |
| P3 | <40 | Community listing only |

---

## Module playbooks

### 1. Databases

**Competitors:** Supabase, Neon, PlanetScale, MongoDB Atlas, Redis Cloud, Aiven, Railway DB.

**Enterprise expects:** bring-your-own DB, IAM, private link, PITR backup, read replicas, query insights, SOC2.

**Native:** Postgres, MySQL, MongoDB, Redis clusters. **Marketplace:** Prisma/Drizzle sync, Metabase/Grafana BI, OpenAI SQL copilot.

| Provider | Category | Business Value | API | OAuth | Webhooks | Pricing | Priority |
|----------|----------|----------------|-----|-------|----------|---------|----------|
| PostgreSQL | Database | Default OLTP | SQL + mgmt API | No | Optional logical repl | Included | P0 95 |
| Prisma | ORM | Schema migrate from studio | Prisma CLI/API | Yes (GitHub) | Migrate hooks | Free connector | P0 88 |
| Metabase | BI | Exec dashboards on Cloudixia DB | REST | Yes | Sync | Partner rev-share | P1 72 |
| OpenAI | AI | Natural language → SQL | REST | API key | No | Usage + markup | P0 85 |

**Module APIs:** `POST /v1/databases`, `GET /v1/databases/{id}/connection-string`, `POST /v1/databases/{id}/integrations/prisma/link`.

**UI:** Database list → Studio → Integrations tab → “Connect Prisma” wizard.

---

### 2. Object Storage

**Competitors:** AWS S3, Cloudflare R2, MinIO, Backblaze, Wasabi.

**Enterprise expects:** S3 API compatibility, lifecycle, CORS, virus scan hook, CDN bind.

| Provider | Category | Business Value | API | OAuth | Webhooks | Pricing | Priority |
|----------|----------|----------------|-----|-------|----------|---------|----------|
| Cloudflare R2 | S3 | Zero egress to Cloudixia CDN | S3 API | API token | Object events | Per GB | P0 92 |
| AWS S3 | S3 | Enterprise existing buckets | S3 + IAM | IAM/STS | SNS→ingress | Pass-through + fee | P0 90 |
| Cloudinary | Media | Transform + optimize | REST | Yes | Upload done | Partner | P1 70 |

---

### 3. Deploy

**Competitors:** Vercel, Netlify, Railway, Fly.io, Render.

**Enterprise expects:** GitOps, OIDC to CI, signed builds, environment promotion, rollback.

| Provider | Category | Business Value | API | OAuth | Webhooks | Pricing | Priority |
|----------|----------|----------------|-----|-------|----------|---------|----------|
| GitHub | Git | Push-to-deploy | REST+App | Yes | push, PR, release | Free | P0 98 |
| GitHub Actions | CI/CD | Build pipeline | Actions API | Yes | workflow_run | Minutes meter | P0 95 |
| Terraform | IaC | Declarative infra | TF Cloud API | API token | Run complete | Seat | P0 85 |

**UI:** Project → Deploy → Git connect → Pipeline graph.

---

### 4. Domains

**Competitors:** Cloudflare Registrar/DNS, Namecheap, Route53, Vercel Domains.

| Provider | Category | Business Value | API | OAuth | Webhooks | Pricing | Priority |
|----------|----------|----------------|-----|-------|----------|---------|----------|
| Cloudflare DNS | DNS | Fast propagation | CF API | Yes | DNS events | Included | P0 94 |
| Let's Encrypt | SSL | Auto TLS | ACME | No | No | Free | P0 96 |
| Namecheap | Registrar | Buy domain in-console | API | Yes | Transfer status | At cost + fee | P1 65 |

---

### 5. API Studio

**Competitors:** Postman, Kong Konnect, Stoplight, SwaggerHub.

| Provider | Category | Business Value | API | OAuth | Webhooks | Pricing | Priority |
|----------|----------|----------------|-----|-------|----------|---------|----------|
| OpenAPI | Docs | Standard spec import | File | No | No | Free | P0 97 |
| Postman | Testing | Sync collections | Postman API | Yes | Collection updates | Partner | P0 82 |
| Kong | Gateway | Enterprise API mgmt | Admin API | Yes | Yes | Enterprise | P2 55 |

---

### 6. Email API

**Competitors:** Resend, SendGrid, Postmark, SES, Mailgun.

**Enterprise expects:** dedicated IP, DMARC alignment, bounce/complaint webhooks, templates.

| Provider | Category | Business Value | API | OAuth | Webhooks | Pricing | Priority |
|----------|----------|----------------|-----|-------|----------|---------|----------|
| Resend | Provider | Dev-first DX | REST | API key | sent, bounced | Per 1k | P0 90 |
| SES | Provider | AWS cost at scale | AWS API | IAM | SNS | Pass-through | P0 88 |
| SPF/DKIM/DMARC | Auth | Deliverability | DNS API | No | No | Included | P0 95 |

---

### 7. Email Marketing

**Competitors:** Mailchimp, Brevo, HubSpot Marketing, ActiveCampaign.

| Provider | Category | Business Value | API | OAuth | Webhooks | Pricing | Priority |
|----------|----------|----------------|-----|-------|----------|---------|----------|
| HubSpot | CRM | Two-way contacts | CRM API | Yes | contact.* | Partner | P0 86 |
| Mailchimp | Automation | Campaigns | REST | Yes | subscribe | Partner | P0 84 |

---

### 8. Inbox

**Competitors:** Zendesk, Intercom, Freshdesk, Respond.io, Front.

| Provider | Category | Business Value | API | OAuth | Webhooks | Priority |
|----------|----------|----------------|-----|-------|----------|----------|
| WhatsApp Business | Chat | MENA + global reach | Cloud API | Meta OAuth | messages | P0 96 |
| Zendesk | Help Desk | Ticket sync | REST | Yes | ticket.* | P0 80 |
| Intercom | Help Desk | Product tours + inbox | REST | Yes | conversation | P1 75 |

---

### 9. VoIP

**Competitors:** Twilio, Vonage, Telnyx, Zoom, Teams.

| Provider | Category | Business Value | API | OAuth | Webhooks | Priority |
|----------|----------|----------------|-----|-------|----------|----------|
| Twilio | Telephony | PSTN + SIP | REST | API key | call status | P0 94 |
| Zoom | Meetings | Click-to-meet | OAuth | Yes | meeting.end | P0 88 |
| Microsoft Teams | Meetings | Enterprise cal | Graph | Yes | Yes | P0 87 |

---

### 10. Authentication & SSO (new module)

**Competitors:** Auth0, Clerk, Supabase Auth, WorkOS.

**Native:** Cloudixia Auth, SAML SP. **Marketplace:** social + LDAP.

| Provider | Category | Business Value | OAuth | Priority |
|----------|----------|----------------|-------|----------|
| Google | Social | Login | OIDC | P0 98 |
| Microsoft | Social | Enterprise login | OIDC | P0 97 |
| SAML | Enterprise | IdP federation | SAML metadata | P0 95 |
| LDAP | Enterprise | On-prem directory | Bind creds | P1 70 |

---

### 11. Billing (new module)

**Competitors:** Stripe Billing, Paddle, Chargebee.

| Provider | Business Value | Webhooks | Priority |
|----------|----------------|----------|----------|
| Stripe | Subscriptions + meters | invoice.*, customer.* | P0 99 |
| Paddle | MoR EU VAT | subscription.* | P1 75 |

---

### 12. Monitoring (new module)

**Competitors:** Datadog, Grafana Cloud, New Relic, Sentry.

| Provider | Business Value | Priority |
|----------|----------------|----------|
| Sentry | Error tracking | P0 92 |
| Grafana | Dashboards + alerts | P0 88 |
| Datadog | Full observability | P1 78 |

---

### 13. AI Studio (new module)

**Competitors:** OpenAI Playground, Anthropic Console, Vercel AI SDK hosting.

| Provider | Business Value | Priority |
|----------|----------------|----------|
| OpenAI | GPT models | P0 96 |
| Anthropic | Claude | P0 94 |
| Gemini | Google multimodal | P0 90 |
| DeepSeek | Cost-efficient | P1 72 |

---

### 14. Secrets (new module)

**Competitors:** HashiCorp Vault, Doppler, AWS Secrets Manager.

| Provider | Priority |
|----------|----------|
| AWS Secrets Manager | P0 88 |
| HashiCorp Vault | P1 75 |

---

### 15. Kubernetes (new module)

**Competitors:** EKS, GKE, AKS, Rancher.

| Provider | Priority |
|----------|----------|
| EKS | P1 80 |
| GKE | P1 78 |

---

### 16. CDN (new module)

**Competitors:** Cloudflare, Fastly, BunnyCDN.

| Provider | Priority |
|----------|----------|
| Cloudflare | P0 95 |
| BunnyCDN | P1 68 |

---

### 17. Search (new module)

**Competitors:** Algolia, Meilisearch Cloud, Typesense.

| Provider | Priority |
|----------|----------|
| Meilisearch | P0 90 (native) |
| Typesense | P1 72 |
| Elasticsearch | P1 70 |

---

## Full catalog export format

For **each** row in `integration-catalog.yaml`, expand to this table in docs/PRDs:

| Field | Description |
|-------|-------------|
| **Integration Category** | e.g. S3 Compatible, CRM, Telephony |
| **Provider** | Vendor name |
| **Module** | Cloudixia module id |
| **Type** | native / marketplace |
| **Certification** | official / certified_partner / partner / community |
| **Business Value** | 1-line enterprise value prop |
| **API Requirements** | REST/GraphQL/S3, rate limits, ids |
| **OAuth Requirements** | scopes, PKCE, offline access |
| **Webhook Requirements** | events, signature algo, retry policy |
| **Pricing Strategy** | included / pass-through / rev-share / per-seat |
| **Priority Score** | 0–100 + P0–P3 |

**Script to render markdown from YAML:**

```bash
node -e "
const fs=require('fs');const yaml=require('yaml');
const c=yaml.parse(fs.readFileSync('data/integration-catalog.yaml','utf8'));
c.integrations.forEach(i=>{
  console.log('|',i.provider,'|',i.category,'|',i.module,'|',i.type,'|',i.priority,'|',i.oauth,'|',i.webhooks,'|',i.certified,'|');
});
"
```

---

## Implementation roadmap

| Quarter | Deliverables |
|---------|----------------|
| **Q1** | Registry + Connection service + OAuth; P0 GitHub, Stripe, Postgres, Resend, WhatsApp, Google auth |
| **Q2** | Webhook debugger UI; Certified pipeline; 30 certified_partner apps |
| **Q3** | Partner portal + rev-share billing; module-specific integration tabs |
| **Q4** | Community marketplace; iPaaS export (Zapier/n8n triggers per install) |

---

## Agent checklist

```
- [ ] Read integration-catalog.yaml for provider list
- [ ] integrations-architecture-foundation patterns applied (KMS, webhooks, idempotency)
- [ ] Schema: integration_apps + org_integration_installs + connections
- [ ] APIs + UI routes for marketplace defined
- [ ] RBAC permissions mapped to roles
- [ ] Billing meters per module + partner rev-share
- [ ] Per-module competitor + enterprise table in PRD
- [ ] Certified app manifest + review gates documented
- [ ] P0 integrations have adapter port interface stub
```

---

## Related

`integrations-platform-index`, `integrations-ipaas-n8n-zapier`, `integrations-cicd-devops`,
`integrations-cloud-aws-gcp-azure`, `communications-master`, `payments-master`, `marketplace-master`.
