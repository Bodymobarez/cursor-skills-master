---
name: integrations-platform-index
description: >-
  Routing index for 90+ platforms → the right integrations-master skill, the auth type to use, and
  the current (2026) official API docs URL. Use to look up any named SaaS/tool before building, and
  follow the "unknown platform protocol" when a platform isn't listed.
---

# Platform Integration Index

**How to use:** find the platform → note its **auth type** → open the **docs** → read the linked
**skill** for the implementation pattern. Auth type tells you which credential flow from
`integrations-oauth-api-keys` and which webhook scheme from `integrations-webhooks-events` applies.

> This index routes; it does not implement. Every build still follows
> `integrations-architecture-foundation` (adapter, idempotency, retries, DLQ).

---

## Dev & source control → `integrations-github-gitlab-bitbucket`

| Platform | Auth | Docs |
|----------|------|------|
| GitHub | **App (JWT→installation)** / OAuth / fine-grained PAT | https://docs.github.com/en/rest |
| GitLab | Project/Group token / OAuth; webhook `X-Gitlab-Token` | https://docs.gitlab.com/ee/api/ |
| Bitbucket | OAuth 2.0 (app passwords deprecated) | https://developer.atlassian.com/cloud/bitbucket/rest/ |
| Azure Repos | PAT / Entra ID | https://learn.microsoft.com/en-us/rest/api/azure/devops/git/ |
| Gitea / Forgejo | token | self-hosted `/api/v1` |

## CI/CD → `integrations-cicd-devops`

| Platform | Auth | Docs |
|----------|------|------|
| GitHub Actions | **OIDC** to cloud / `GITHUB_TOKEN` | https://docs.github.com/en/actions |
| GitLab CI | trigger token / OIDC ID tokens | https://docs.gitlab.com/ee/ci/ |
| Jenkins | API token + crumb | https://www.jenkins.io/doc/book/using/remote-access-api/ |
| CircleCI | API v2 token / OIDC | https://circleci.com/docs/api/v2/ |
| Azure DevOps Pipelines | PAT / Entra; service hooks | https://learn.microsoft.com/en-us/rest/api/azure/devops/pipelines/ |
| Buildkite | API token + webhooks | https://buildkite.com/docs/apis |

## Cloud → `integrations-cloud-aws-gcp-azure`

| Platform | Auth | Docs |
|----------|------|------|
| AWS | **IAM role / OIDC** (keys only in dev) | https://docs.aws.amazon.com |
| Google Cloud | **Workload Identity Federation** / SA | https://cloud.google.com/apis/docs/overview |
| Azure | **Managed Identity** / Entra app | https://learn.microsoft.com/en-us/rest/api/azure/ |
| Cloudflare | API token (scoped) | https://developers.cloudflare.com/api/ |
| DigitalOcean | PAT / OAuth | https://docs.digitalocean.com/reference/api/ |
| Vercel / Netlify | token / OAuth; deploy hooks | https://vercel.com/docs/rest-api · https://docs.netlify.com/api/get-started/ |

## Google & Microsoft → `integrations-google-microsoft`

| Platform | Auth | Docs |
|----------|------|------|
| Gmail/Drive/Calendar/Sheets | **OAuth 2.1** (+ SA/DWD for Workspace) | https://developers.google.com/workspace |
| Microsoft 365 / Outlook / OneDrive / Teams | **Entra ID OAuth** (Graph) | https://learn.microsoft.com/en-us/graph/ |
| Entra ID (Azure AD) | OAuth / OIDC | https://learn.microsoft.com/en-us/entra/identity-platform/ |
| Dropbox | OAuth 2.0 | https://www.dropbox.com/developers/documentation/http/overview |
| Box | OAuth 2.0 / JWT app | https://developer.box.com/reference/ |

## Chat & collaboration → `integrations-slack-discord-teams`

| Platform | Auth | Webhook verify | Docs |
|----------|------|----------------|------|
| Slack | OAuth (bot `xoxb-`) | **v0 HMAC** (`X-Slack-Signature`) | https://docs.slack.dev |
| Discord | bot token / OAuth | **Ed25519** (`X-Signature-Ed25519`) | https://discord.com/developers/docs |
| Microsoft Teams | Entra (Graph) / Bot Framework | Graph subscription | https://learn.microsoft.com/en-us/microsoftteams/platform/ |
| Telegram | bot token | secret token header | https://core.telegram.org/bots/api |
| Mattermost | token / webhooks | token | https://developers.mattermost.com/api-documentation/ |
| Zoom | **Server-to-Server OAuth** | HMAC-SHA256 (`x-zm-signature`) | https://developers.zoom.us/docs/api/ |

## PM & docs → `integrations-pm-notion-linear-jira`

| Platform | Auth | API / webhook | Docs |
|----------|------|---------------|------|
| Linear | OAuth / API key | GraphQL; `Linear-Signature` HMAC | https://linear.app/developers |
| Jira | 3LO OAuth / Connect JWT / token | REST v3 | https://developer.atlassian.com/cloud/jira/platform/rest/v3/ |
| Notion | integration token / OAuth | REST; **`X-Notion-Signature`** (2026) | https://developers.notion.com |
| Asana | OAuth / PAT | REST; `X-Hook-Secret` handshake | https://developers.asana.com |
| Monday.com | OAuth / token | GraphQL | https://developer.monday.com/api-reference |
| ClickUp | OAuth / token | REST; signed webhooks | https://developer.clickup.com |
| Trello | OAuth / API key+token | REST | https://developer.atlassian.com/cloud/trello/rest/ |
| Airtable | OAuth / PAT | REST + webhooks | https://airtable.com/developers/web/api/introduction |
| Confluence | OAuth / Connect | REST | https://developer.atlassian.com/cloud/confluence/rest/v2/ |

## CRM & sales → `integrations-crm-salesforce-hubspot`

| Platform | Auth | Bulk / events | Docs |
|----------|------|---------------|------|
| Salesforce | **JWT-bearer** / Client Credentials / OAuth | Bulk 2.0; Pub/Sub API (CDC) | https://developer.salesforce.com/docs |
| HubSpot | private-app token / OAuth | batch upsert; `X-HubSpot-Signature-v3` | https://developers.hubspot.com/docs/api/overview |
| Pipedrive | OAuth / API token | REST + webhooks | https://developers.pipedrive.com |
| Zoho CRM | OAuth | REST | https://www.zoho.com/crm/developer/docs/ |
| Dynamics 365 | Entra (Dataverse OData) | `$batch`; change tracking | https://learn.microsoft.com/en-us/power-apps/developer/data-platform/webapi/overview |

## Support & comms → `communications-master` + `integrations-webhooks-events`

| Platform | Auth | Docs |
|----------|------|------|
| Zendesk | OAuth / API token | https://developer.zendesk.com/api-reference/ |
| Intercom | OAuth / token | https://developers.intercom.com/docs |
| Freshdesk | API key | https://developers.freshdesk.com/api/ |
| Twilio | API key/SID; `X-Twilio-Signature` | https://www.twilio.com/docs/usage/api |
| SendGrid / Mailgun / SES | API key; signed event webhooks | https://www.twilio.com/docs/sendgrid · https://documentation.mailgun.com |
| WhatsApp Business | Meta OAuth / system token | https://developers.facebook.com/docs/whatsapp |

## Commerce → `integrations-commerce-shopify-woocommerce`

| Platform | Auth | Webhook verify | Docs |
|----------|------|----------------|------|
| Shopify | OAuth / admin token | **`X-Shopify-Hmac-SHA256`** (base64) | https://shopify.dev/docs/api |
| WooCommerce | consumer key/secret | `X-WC-Webhook-Signature` (base64) | https://woocommerce.github.io/woocommerce-rest-api-docs/ |
| BigCommerce | OAuth (store-hash) | signed webhooks | https://developer.bigcommerce.com |
| Magento (Adobe) | OAuth / integration token | — | https://developer.adobe.com/commerce/webapi/ |
| Amazon SP-API | LWA OAuth + AWS SigV4 → `marketplace-master` | https://developer-docs.amazon.com/sp-api/ |
| eBay / Etsy | OAuth 2.0 | https://developer.ebay.com · https://developers.etsy.com |

## Payments → `payments-master` (not duplicated here)

Stripe (`Stripe-Signature`), Adyen, PayPal, Checkout.com, Razorpay, Paystack, Flutterwave, Fawry,
Paymob, M-Pesa, Ozow, Yoco. Auth + signature schemes live in `payments-master`.

## HR & accounting → `business-master`

| Platform | Auth | Docs |
|----------|------|------|
| QuickBooks Online | OAuth 2.0 | https://developer.intuit.com |
| Xero | OAuth 2.0 | https://developer.xero.com/documentation/ |
| BambooHR / Workday | API key / OAuth | https://documentation.bamboohr.com/docs |
| Deel / Rippling | OAuth / token | https://developer.deel.com · https://developer.rippling.com |

## Marketing & analytics → `integrations-marketing-analytics` + `analytics-master`

| Platform | Auth | Docs |
|----------|------|------|
| Segment / RudderStack | write key | https://segment.com/docs · https://www.rudderstack.com/docs/ |
| Mixpanel / Amplitude | project token / API key | https://developer.mixpanel.com · https://amplitude.com/docs/apis |
| PostHog | project API key | https://posthog.com/docs/api |
| GA4 | Measurement Protocol secret | https://developers.google.com/analytics/devguides/collection/protocol/ga4 |
| Meta / Google / LinkedIn Ads | OAuth + system token | https://developers.facebook.com/docs/marketing-apis · https://developers.google.com/google-ads/api |
| Klaviyo / Mailchimp / Customer.io | API key / OAuth | https://developers.klaviyo.com · https://mailchimp.com/developer/ |

## Auth & identity → `backend-api-master`

| Platform | Auth | Docs |
|----------|------|------|
| Auth0 / Clerk / Supabase Auth | OAuth / OIDC | https://auth0.com/docs · https://clerk.com/docs |
| Okta | OIDC / SAML (enterprise SSO) | https://developer.okta.com |
| Google / Apple Sign-In | OIDC | https://developers.google.com/identity · https://developer.apple.com/sign-in-with-apple/ |

## Data, queues & search

| Platform | Auth / pattern | Docs |
|----------|----------------|------|
| PostgreSQL / MySQL | connection + **CDC (Debezium/logical)** → `integrations-sync-engine-cdc` | https://debezium.io/documentation/ |
| MongoDB | change streams | https://www.mongodb.com/docs/manual/changeStreams/ |
| Kafka / RabbitMQ / SQS | SASL/IAM; consumer groups | https://kafka.apache.org/documentation/ |
| Snowflake / BigQuery | key-pair / OAuth; ETL sink | https://docs.snowflake.com · https://cloud.google.com/bigquery/docs |
| Elasticsearch / OpenSearch | API key / basic | https://www.elastic.co/guide/ |

## iPaaS → `integrations-ipaas-n8n-zapier`

| Platform | Auth | Docs |
|----------|------|------|
| Zapier | OAuth/API key connector (REST Hooks) | https://docs.zapier.com/platform |
| Make | OAuth/connection app | https://developers.make.com |
| n8n | self-host; node creds | https://docs.n8n.io |
| Workato / Tray.io / Pipedream | connector SDK / OAuth | https://docs.workato.com · https://pipedream.com/docs |

## AI & media → `ai-mcp-master` / `video-ai-master`

| Platform | Auth | Docs |
|----------|------|------|
| OpenAI / Anthropic / Gemini | API key (server-side) | https://platform.openai.com/docs · https://docs.anthropic.com · https://ai.google.dev |
| **MCP servers** (tool exposure) | per-server (OAuth emerging) | https://modelcontextprotocol.io |
| fal.ai / Replicate | API key | https://fal.ai/docs · https://replicate.com/docs |
| ElevenLabs | API key | https://elevenlabs.io/docs |

## Social

| Platform | Auth | Docs |
|----------|------|------|
| X (Twitter) | OAuth 2.0 (API v2) | https://developer.x.com/en/docs |
| LinkedIn | OAuth 2.0 | https://learn.microsoft.com/en-us/linkedin/ |
| Instagram / Facebook | Meta Graph OAuth | https://developers.facebook.com/docs/graph-api |
| TikTok | OAuth (Marketing/Content) | https://developers.tiktok.com |
| YouTube | OAuth (Data API v3) | https://developers.google.com/youtube/v3 |

## Travel / maps / gov → specialized masters

| Platform | Master | Notes |
|----------|--------|-------|
| Amadeus / Sabre / NDC | `travel-tech-master` | GDS/NDC auth varies |
| Mapbox / Google Maps | `ui-master` (gis) / backend | API key (restrict by referrer/IP) |
| UAE Pass | backend + gov docs | OIDC; sandbox→prod onboarding |

---

## Unknown platform — agent protocol

When a platform isn't listed, classify it, then apply the foundation. Do **not** invent endpoints —
find the official docs first.

```
1. FIND official docs: search "<platform> REST API docs", prefer developer.<platform>.com /
   <platform>.com/docs/api. Confirm it's current (check the changelog/version).
2. CLASSIFY auth: API key (header/Basic) | OAuth 2.1 + PKCE | OAuth client-credentials |
   JWT-bearer (cert) | App/installation | mTLS. → use the matching flow in integrations-oauth-api-keys.
3. CLASSIFY transport: REST | GraphQL | gRPC | SOAP(legacy) | SDK-only. Note pagination style
   (cursor vs offset vs Link header) and rate-limit headers (Retry-After / X-RateLimit-*).
4. CLASSIFY change feed: webhooks (find the SIGNATURE scheme + header + encoding) | polling +
   cursor | CDC/change stream | none. → integrations-webhooks-events or integrations-sync-engine-cdc.
5. VERIFY the webhook signature scheme exactly (algorithm, hex vs base64, what's signed, replay
   window). Never assume — providers differ (see the webhooks skill matrix).
6. IMPLEMENT via integrations-architecture-foundation: adapter behind a port, idempotency key,
   retries w/ jittered backoff, DLQ, token-bucket rate limit, encrypted per-tenant creds, correlation ids.
7. TEST against the sandbox; add fixtures + a signature test; wire metrics.
8. If recurring across tenants, add a row to this index (auth + docs). One-off → keep it in the
   tenant's integration config; don't fork the index for a single use.
```

## Related

All category skills in `integrations-master`; start at `integrations-architecture-foundation`.
