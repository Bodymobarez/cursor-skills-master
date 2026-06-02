---
name: infra-cloud-network-security
description: >-
  Secure cloud + network infrastructure at staff depth: IAM least-privilege (deny-by-default policies,
  no wildcards, OIDC over keys), network segmentation/security groups, zero-trust + mTLS, encryption
  at rest/in transit, cloud-posture misconfigs (public buckets, IMDSv2, over-broad roles) for
  AWS/GCP/Azure, container image scanning, and Kubernetes hardening (RBAC, NetworkPolicy, Pod Security
  Standards). Real Terraform/YAML, vulnerable→fixed.
---

# Infra, Cloud & Network Security

**Mandate:** most cloud breaches are **misconfiguration**, not exotic exploits — a public S3 bucket,
an over-permissioned role, an open security group, an unpatched control plane. Your job is to make
the **secure config the default and the insecure config impossible to ship** (IaC scanning gates).
Least privilege and segmentation are the two levers that shrink blast radius the most.

## When to use / NOT
**Use** when provisioning or reviewing cloud accounts, IAM, networking, containers, or K8s. **Don't**
duplicate app-layer controls here (those are `appsec-owasp-top10`) — this is the substrate they run
on. Secret storage/KMS overlaps with `secrets-supply-chain-security`.

## Mental model: assume breach, limit blast radius

```
Identity (who)  ── least privilege ──►  Resource (what)
     │                                        │
  zero trust: verify every request        segmentation: even if reached, can't pivot
     │                                        │
  short-lived creds (OIDC/STS)            mTLS + NetworkPolicy between services
```

Two questions for every component: **"if this identity is stolen, what's the blast radius?"** and
**"if an attacker lands on this host/pod, where can they go?"** Drive both toward "almost nothing."

---

## 1. IAM least-privilege (the #1 cloud control)

```hcl
# ❌ VULNERABLE: the breach generator
resource "aws_iam_policy" "bad" {
  policy = jsonencode({ Statement = [{ Effect = "Allow", Action = "*", Resource = "*" }] })
}
```

```hcl
# ✅ FIXED: specific actions, scoped resources, conditions; deny-by-default everywhere else
resource "aws_iam_policy" "uploader" {
  name = "s3-uploader"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect   = "Allow",
      Action   = ["s3:PutObject", "s3:GetObject"],
      Resource = "arn:aws:s3:::app-uploads/${aws_iam... }/*",
      Condition = {                                   # extra guardrails
        Bool        = { "aws:SecureTransport" = "true" }     # TLS only
        StringEquals= { "s3:x-amz-server-side-encryption" = "aws:kms" }
      }
    }]
  })
}
```

Rules:
- **No `Action: "*"` / `Resource: "*"`** on real workloads. Grant the specific verbs on specific ARNs.
- **Roles, not users/keys.** Workloads assume roles (EC2 instance profile, EKS IRSA/Pod Identity,
  GCP Workload Identity, Azure Managed Identity). CI uses **OIDC federation** → STS, never stored
  access keys (see `secrets-supply-chain-security`).
- **Right-size from real usage**: AWS IAM Access Analyzer can generate a policy from CloudTrail.
  Start deny-all, add what's actually used. Review/prune quarterly.
- **Guardrails above identities**: SCPs (AWS Orgs) / Org Policies (GCP) / Azure Policy to *cap* what
  any account can do (e.g. deny public S3 org-wide, deny disabling CloudTrail, region pinning).
- **Separate roles for separate jobs** (deploy ≠ read-logs ≠ admin); **no standing admin** — use
  just-in-time elevation with approval + logging.

---

## 2. Cloud-posture misconfigs (find + prevent the classics)

| Misconfig | Impact | Fix | Org guardrail |
|-----------|--------|-----|---------------|
| Public S3/GCS/Blob | data leak (the canonical breach) | Block Public Access ON; bucket policies private | SCP/Org Policy deny public |
| IMDSv1 enabled | SSRF → steal instance creds | **require IMDSv2** (token) | enforce in launch template |
| Over-broad IAM role | privilege escalation | least-priv + Access Analyzer | SCP cap |
| Security group `0.0.0.0/0:22/3389` | exposed admin | SSM/bastion only, no public SSH/RDP | config rule auto-remediate |
| Unencrypted EBS/RDS/snapshots | data at rest exposure | KMS encryption default-on | SCP require encryption |
| CloudTrail/Config off or single-region | no audit trail | org-wide multi-region trail, log-file validation | SCP deny stop-logging |
| Public RDS/Elasticsearch | DB on the internet | private subnets only | guardrail |

```hcl
# ✅ S3: lock it down by construction
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.app.id
  block_public_acls = true; block_public_policy = true
  ignore_public_acls = true; restrict_public_buckets = true
}
# ✅ EC2: force IMDSv2 so an app SSRF can't read instance credentials
resource "aws_instance" "app" {
  metadata_options { http_tokens = "required"; http_endpoint = "enabled"; http_put_response_hop_limit = 1 }
}
```

Run a **CSPM** continuously: Prowler, ScoutSuite, Steampipe, or native (AWS Security Hub, GCP SCC,
Microsoft Defender for Cloud) mapped to CIS Benchmarks. Gate **IaC pre-deploy** with tfsec/Checkov/
Trivy so the public bucket never merges.

---

## 3. Network segmentation + zero trust

```hcl
# ✅ tiered VPC: public ALB only; app + db in private subnets; SGs reference SGs, not CIDRs
resource "aws_security_group_rule" "app_from_alb" {
  type = "ingress"; from_port = 443; to_port = 443; protocol = "tcp"
  security_group_id        = aws_security_group.app.id
  source_security_group_id = aws_security_group.alb.id     # ✅ only the ALB SG, not 0.0.0.0/0
}
resource "aws_security_group_rule" "db_from_app" {
  type = "ingress"; from_port = 5432; to_port = 5432; protocol = "tcp"
  security_group_id        = aws_security_group.db.id
  source_security_group_id = aws_security_group.app.id     # DB reachable ONLY from app tier
}
```

**Zero-trust** replaces "inside the network = trusted." Principles: authenticate + authorize **every**
request (no implicit trust by network location), least-privilege per workload identity, encrypt all
internal traffic, microsegment so a foothold can't move laterally. Concretely: per-service identity +
**mTLS** (service mesh: Istio/Linkerd), egress allowlists (block the data-exfil + SSRF pivot),
private service endpoints (no internet path to data stores), and SSM/Tailscale/IAP for admin instead
of public SSH.

---

## 4. mTLS + encryption everywhere

```yaml
# ✅ Istio: mesh-wide STRICT mutual TLS — every service-to-service call is authenticated + encrypted
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata: { name: default, namespace: istio-system }
spec: { mtls: { mode: STRICT } }
```

- **In transit:** TLS 1.2+/1.3 externally (`web-hardening-headers-tls`); **mTLS internally** so
  services prove identity to each other (not just "I'm on the network").
- **At rest:** KMS-backed encryption default-on for disks, DBs, object storage, backups, queues.
  Envelope encryption for app data; per-tenant keys for isolation.
- **Key management:** keys in KMS/HSM, never in code/config; rotation enabled; separate keys per
  environment + data class; tightly scope `kms:Decrypt`. Key access is itself a least-priv decision.

---

## 5. Container image security

```dockerfile
# ✅ minimal, non-root, pinned base → small attack surface
FROM node:22-bookworm-slim@sha256:<digest>     # pin by digest, slim base
RUN useradd -r -u 10001 app
USER 10001                                      # ✅ never run as root
COPY --chown=10001 . /app
# distroless/chainguard for prod runtime = no shell, no package manager for an attacker to use
```

```bash
trivy image --severity HIGH,CRITICAL --exit-code 1 registry/app:tag   # scan in CI, fail build
grype registry/app:tag                                                # alt scanner
cosign verify registry/app@sha256:<digest> ...                        # only deploy signed images
```

Rules: minimal/distroless base, **non-root user**, read-only root filesystem, drop Linux capabilities,
no secrets in layers, pin base by digest, scan every image + block on critical, only run signed images
(admission policy). Rebuild regularly so base-image CVEs get patched.

---

## 6. Kubernetes hardening

### RBAC — least privilege (no cluster-admin for apps)

```yaml
# ✅ namespaced Role: read configmaps in one namespace, nothing else
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: { namespace: app, name: config-reader }
rules: [{ apiGroups: [""], resources: ["configmaps"], verbs: ["get","list"] }]
# ❌ NEVER: bind a workload ServiceAccount to cluster-admin or use verbs:["*"] resources:["*"]
```

### NetworkPolicy — default-deny, then allow

```yaml
# ✅ default-deny all ingress in a namespace (NetworkPolicies are additive allows)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: default-deny-ingress, namespace: app }
spec: { podSelector: {}, policyTypes: ["Ingress"] }
# then add explicit allows (e.g. ingress to api pods from the gateway namespace only)
```

### Pod Security Standards — enforce "restricted"

```yaml
# ✅ namespace label enforces the restricted PSS (no privileged/root/hostPath/hostNetwork)
apiVersion: v1
kind: Namespace
metadata:
  name: app
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: latest
```

```yaml
# ✅ secure pod spec
securityContext:
  runAsNonRoot: true
  readOnlyRootFilesystem: true
  allowPrivilegeEscalation: false
  capabilities: { drop: ["ALL"] }
  seccompProfile: { type: RuntimeDefault }
```

K8s rules: enforce **restricted** Pod Security Standards (PSA replaced PSP); **default-deny**
NetworkPolicies + explicit allows; least-priv RBAC (audit with `kubectl-who-can`/`rbac-tool`); mount
secrets via CSI from a manager (not plain `Secret` objects when avoidable, and never in env if you
can mount); patch the control plane; restrict the API server; use admission control (OPA Gatekeeper/
Kyverno) to enforce "signed images only, no `:latest`, resource limits set." Don't expose the
dashboard or kubelet read-only port publicly.

---

## 7. Performance impact
- mTLS: a small per-connection handshake + CPU for encryption — service meshes amortize via
  connection reuse; usually single-digit % CPU. The lateral-movement protection is worth it.
- NetworkPolicy: enforced in the CNI (eBPF/iptables) — negligible at steady state.
- Image scanning / IaC scanning: CI-time only (seconds–minutes); zero runtime cost.
- Least-priv IAM: zero runtime cost — it's just policy.

## 8. Scale / multi-tenant
- **Account/project-per-tenant or per-environment** is the strongest isolation; namespace-per-tenant
  in K8s is weaker (shared kernel/control plane) — add NetworkPolicy + RBAC + resource quotas + PSS,
  and consider per-tenant node pools / sandboxed runtimes (gVisor/Kata) for hostile multi-tenancy.
- Centralize guardrails (SCP/Org Policy) so every new account inherits the secure baseline. Per-tenant
  KMS keys; per-tenant network isolation. Landing-zone automation (Control Tower/Terraform) so secure
  defaults scale without manual setup.

## 9. Testing & verification
- IaC scan in CI (tfsec/Checkov/Trivy) — **fail on misconfig**; CSPM (Prowler/SCC) continuously vs CIS.
- `kube-bench` (CIS K8s), `kube-hunter`/`kubescape` for cluster posture; `kubectl auth can-i` to prove
  RBAC denies what it should.
- Validate NetworkPolicy with actual connection tests (a pod that *should* be blocked is blocked).
- Authorized pentest of cloud config + lateral movement (`pentesting-vuln-management`).

## 10. Observability
- Enable + protect audit trails: **CloudTrail (org, multi-region, log validation)**, GCP Audit Logs,
  Azure Activity/Monitor, K8s API audit log. Alert on: IAM policy changes, new admin/role binding,
  public-resource creation, security-group opens, CloudTrail/Config tampering, root/break-glass use,
  anomalous `AssumeRole`. Ship to SIEM (`security-operations-ir-compliance`).

## Anti-patterns
- `*:*` IAM policies; long-lived access keys; standing admin; shared roles.
- Public buckets / public databases / `0.0.0.0/0` SSH/RDP.
- IMDSv1 left enabled (turns any SSRF into credential theft).
- Containers as root, `:latest` tags, unscanned/unsigned images, secrets in layers.
- K8s workloads bound to cluster-admin; no NetworkPolicy (flat pod network); PSP/PSS disabled.
- Trusting the private network ("it's internal") instead of authenticating every call.
- CloudTrail/audit logging off or single-region; no org guardrails.

## Agent checklist
```
- [ ] IAM: no wildcards, scoped ARNs+conditions, roles not keys, CI via OIDC, SCP/Org guardrails
- [ ] Buckets/DBs private; Block Public Access on; encryption at rest (KMS) default
- [ ] IMDSv2 required; no public SSH/RDP (SSM/bastion); SGs reference SGs not 0.0.0.0/0
- [ ] Zero-trust: per-service identity + mTLS internal; egress allowlists; private endpoints
- [ ] Images: minimal base pinned by digest, non-root, scanned (fail on critical), signed-only deploy
- [ ] K8s: restricted PSS enforced, default-deny NetworkPolicy, least-priv RBAC, admission policy
- [ ] IaC scanned in CI (fail on misconfig) + continuous CSPM vs CIS
- [ ] Audit logging org-wide/multi-region + protected; alerts on IAM/network/public changes
```

## References
- AWS/GCP/Azure CIS Benchmarks: https://www.cisecurity.org/cis-benchmarks
- AWS Well-Architected Security Pillar: https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/
- NIST SP 800-207 Zero Trust Architecture: https://csrc.nist.gov/pubs/sp/800/207/final
- Kubernetes Security: https://kubernetes.io/docs/concepts/security/ · Pod Security Standards: https://kubernetes.io/docs/concepts/security/pod-security-standards/
- Prowler: https://github.com/prowler-cloud/prowler · Trivy: https://trivy.dev/

## Related
`secrets-supply-chain-security` (KMS/OIDC/image signing), `appsec-owasp-top10` (SSRF/IMDS),
`web-hardening-headers-tls` (TLS), `ddos-waf-bot-protection` (edge), `devops-master` (Terraform/K8s).
