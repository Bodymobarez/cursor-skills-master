---
name: integrations-cloud-aws-gcp-azure
description: >-
  Staff-level cloud integration: workload identity over static keys (IAM roles / GCP WIF / Azure
  Managed Identity), presigned uploads with constraints, SQS/PubSub/Service Bus as webhook buffers
  with DLQ + redrive, SNS/EventBridge fan-out, SES/email, KMS envelope encryption, idempotency
  stores, and data-residency/regional pinning. Never ship a long-lived access key.
---

# Cloud: AWS, GCP & Azure

**Mandate: identity comes from the runtime, not from a pasted key.** Use IAM roles (ECS/EKS/Lambda),
GCP Workload Identity, or Azure Managed Identity. A static `AWS_ACCESS_KEY_ID`/service-account JSON in
env is acceptable only on a laptop, never in prod. Queues — not your HTTP handler — absorb spikes.

## When the cloud is the integration layer

Cloud primitives are the *plumbing* behind most integrations: a queue buffers inbound webhooks, a
bucket holds user uploads, a topic fans an event out to N consumers, KMS guards tenant tokens. Reach
for them whenever you need durability, fan-out, or async between you and a third party.

## AWS (the common set)

| Service | Integration role | Gotcha |
|---------|------------------|--------|
| **S3** | File storage, presigned direct uploads | Constrain content-type/size; block public ACLs |
| **SQS** | Webhook buffer, async jobs, **DLQ** | At-least-once → idempotent consumers; visibility timeout > job time |
| **SNS / EventBridge** | Fan-out / event bus / partner events | EventBridge for routing+schema; SNS for simple pub/sub |
| **Lambda** | Serverless webhook workers | 6 MB sync payload cap; cold starts on bursty webhooks |
| **SES** | Transactional email | Sandbox until verified; sign with DKIM |
| **DynamoDB** | Idempotency ledger / event store | Conditional `PutItem` = atomic dedupe |
| **Secrets Manager / KMS** | Integration creds + envelope encryption | Rotate; scope key policy per service |

```ts
// Presigned upload — client PUTs straight to S3, server never proxies bytes
import { S3Client, PutObjectCommand } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
const url = await getSignedUrl(new S3Client({}),                  // creds from the role, not env
  new PutObjectCommand({ Bucket: BUCKET, Key: `${tenantId}/${uuid}`,
    ContentType: "image/png" }),                                  // pin type
  { expiresIn: 300 });                                            // short-lived; enforce size via policy/CORS
```

```ts
// DynamoDB atomic idempotency — first writer wins, dupes throw
try {
  await ddb.send(new PutItemCommand({ TableName: "processed_events",
    Item: { pk: { S: `${provider}#${eventId}` } },
    ConditionExpression: "attribute_not_exists(pk)" }));
} catch (e) { if (e.name === "ConditionalCheckFailedException") return; /* duplicate */ throw e; }
```

**Auth:** task/execution **IAM role** (ECS/EKS IRSA/Lambda). Locally, SSO/`aws sso login`. CI → OIDC
(see cicd skill). Never embed keys.

## Google Cloud

| Service | Use |
|---------|-----|
| **Cloud Storage** | Files (≈S3); signed URLs (V4) for direct upload |
| **Pub/Sub** | Event bus; push *or* pull subscriptions; built-in DLQ + ordering keys |
| **Cloud Run / Functions** | Webhook workers (scale to zero) |
| **BigQuery** | Analytics/event export sink |

Auth: **Workload Identity Federation** (no key files) on GKE/Cloud Run; for cross-account, federate
the external identity. Pub/Sub **push** subscriptions can attach an OIDC token — verify it server-side
instead of a shared secret.

## Microsoft Azure

| Service | Use |
|---------|-----|
| **Blob Storage** | Files; SAS tokens for scoped direct upload |
| **Service Bus** | Queues/topics + sessions (ordering) + DLQ |
| **Functions / Container Apps** | Webhook workers |
| **Key Vault** | Secrets + keys; Managed Identity to read |

Auth: **Managed Identity** for Azure-hosted apps (`DefaultAzureCredential`); federated credentials for
external/CI. Avoid client-secret app registrations where MI is possible.

## Cross-cloud patterns

```
inbound webhook → verify+ACK → SQS/PubSub/ServiceBus → worker (idempotent) → DLQ on exhaustion → redrive
```

- **Queue as shock absorber**: never process a third-party webhook inline; enqueue and ACK.
- **DLQ + redrive**: configure a dead-letter queue with `maxReceiveCount`; expose a redrive/replay.
- **Fan-out**: one event → many consumers via SNS/EventBridge/PubSub, each with its own DLQ.
- **Visibility/lease > max job time**, else you double-process; make consumers idempotent regardless.

## Performance & cost

- Batch (`SendMessageBatch`, S3 multipart, BigQuery load jobs) — per-request overhead dominates.
- Presign/SAS for uploads so bytes never traverse your app tier.
- Right-size Lambda memory (CPU scales with it); reuse SDK clients across invocations.
- Egress and cross-region traffic cost real money — co-locate the queue, worker, and store.

## Security

- **Least-privilege IAM**: per-service roles; deny `*` resources. Bucket: block public access,
  enforce TLS + SSE-KMS, per-tenant key prefixes.
- **KMS envelope encryption** for tenant tokens with `EncryptionContext` = tenant id (see oauth skill).
- **SSRF**: if users supply URLs/regions, validate against an allowlist; block the metadata endpoint.
- Tag resources by `tenant_id` for cost/audit; enable CloudTrail/Cloud Audit Logs/Azure Monitor.

## Data residency / multi-region

Pin per-tenant region (UAE `me-central-1`, EU, etc.) for compliance; store the chosen region on the
tenant and route to regional endpoints/buckets. Don't replicate PII across regions implicitly.

## Testing & observability

- LocalStack (AWS), Pub/Sub & Service Bus emulators for local dev; moto for unit tests.
- Metrics: queue `ApproximateAgeOfOldestMessage`, `dlq_depth`, consumer error rate, upload failures.
- Alert on DLQ depth > 0 and oldest-message age (silent backlog = silent outage).

## Anti-patterns

- Long-lived access keys / SA JSON in env or CI.
- Processing webhooks synchronously instead of enqueueing.
- Public S3 buckets / unconstrained presigned PUTs (any type, any size, long TTL).
- No DLQ → poison messages infinitely redeliver and wedge the consumer.
- One global IAM role with `*` used by every service.

## Agent checklist

```
- [ ] Runtime identity (IAM role / WIF / Managed Identity); zero static keys
- [ ] Inbound third-party traffic buffered through a queue, ACK fast
- [ ] Idempotent consumers; visibility/lease > job time; DLQ + redrive configured
- [ ] Presigned/SAS uploads with type+size+TTL constraints; buckets private + SSE-KMS
- [ ] Tenant tokens KMS envelope-encrypted; per-service least-priv policies
- [ ] Region pinned per tenant for residency; resources tagged tenant_id
```

## References

- AWS IAM roles / IRSA: https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html
- S3 presigned URLs: https://docs.aws.amazon.com/AmazonS3/latest/userguide/PresignedUrlUploadObject.html
- GCP Workload Identity Federation: https://cloud.google.com/iam/docs/workload-identity-federation
- Azure Managed Identity: https://learn.microsoft.com/en-us/entra/identity/managed-identities-azure-resources/overview

## Related

`integrations-cicd-devops`, `integrations-architecture-foundation`, `integrations-resilience-rate-limits`,
`devops-master`
