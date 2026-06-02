---
name: security-operations-ir-compliance
description: >-
  Run security operations at staff depth: a logging strategy + SIEM pipeline, detection engineering
  (rules/alerting mapped to MITRE ATT&CK), the incident-response lifecycle (NIST SP 800-61 — prep,
  detect/analyze, contain, eradicate, recover, lessons; r3/CSF 2.0 mapping), runbooks, evidence/
  forensics basics, and compliance (SOC 2, ISO 27001, PCI DSS 4.0, GDPR) mapped to real controls +
  breach-notification timelines.
---

# Security Operations, Incident Response & Compliance

**Mandate:** prevention fails eventually — your ability to **detect fast, respond calmly, and
recover cleanly** is what separates a near-miss from a headline. This skill is the *run-it-as-a-
program* layer: see everything (logging/SIEM), know when you're under attack (detection), have a
plan you've rehearsed (IR), and prove your controls work (compliance). Detection + response is the
backstop for every other skill in this master.

## When to use / NOT
**Use** to design logging/SIEM, write detections, build IR runbooks, run an incident, or prep for an
audit (SOC 2 / ISO 27001 / PCI / GDPR). **Don't** treat compliance as security — passing SOC 2 ≠
secure; it's evidence your controls *exist*, not that they *stop attackers*. Build security; map it
to compliance, not the reverse.

## Mental model: OODA at organizational scale

```
LOG everything → DETECT (rules/ML/anomaly) → ALERT (signal, not noise) → TRIAGE → RESPOND (IR) → RECOVER → LEARN
        └──────────────── feedback: every incident becomes a new detection + a control gap closed ──────────────┘
```

You can't respond to what you can't see, and you can't see without logs you actually *analyze*. The
loop must be **fast** (low MTTD/MTTR) and **improving** (each incident hardens the next).

---

## 1. Logging strategy (the foundation — OWASP A09)

Log the **security-relevant** events, structured, centralized, time-synced, tamper-evident:

| Source | Log | Why |
|--------|-----|-----|
| App | authN/authZ decisions, input-validation failures, admin actions, high-value txns | detect abuse, forensics |
| Identity | logins, MFA, password resets, privilege changes | ATO detection |
| Cloud | CloudTrail/Audit Logs (API calls, IAM, resource changes) | config tampering, privesc |
| Network/edge | WAF actions, rate-limit trips, flow logs | attack patterns |
| Host/container | process, file integrity, EDR telemetry | post-exploit detection |

```ts
// ✅ structured security event — correlatable, no secrets, machine-parseable
logger.info({
  event: "authz.denied", ts: new Date().toISOString(),
  actor: { userId: u.id, ip: req.ip, ua: req.get("user-agent") },
  target: { resource: "invoice", id, action: "read" },
  outcome: "denied", reqId: req.id, tenantId: u.tenantId,
});
```

Rules: **never log secrets/passwords/tokens/full PANs/excess PII** (a log leak becomes a data
breach — and over-logging PII violates GDPR data-minimization). Use **UTC + synchronized clocks
(NTP)** so timelines line up across systems. Ship to a **central, append-only/immutable** store with
retention meeting compliance (PCI: ≥1 year, 90 days hot). Logs nobody reads are just disk cost —
which is why the 2025 OWASP rename to "**Alerting**" matters.

---

## 2. SIEM + detection engineering

```yaml
# ✅ Detection-as-code: Sigma rule (vendor-neutral; compiles to Splunk/Elastic/Sentinel queries)
title: Credential Stuffing - many failed logins then success
logsource: { product: webapp, service: auth }
detection:
  failures: { event: "auth.login.failed" }
  success:  { event: "auth.login.success" }
  timeframe: 5m
  condition: failures | count() by actor.ip > 50 and success
level: high
falsepositives: ["shared NAT / corporate proxy"]
tags: [attack.credential_access, attack.t1110.004]   # MITRE ATT&CK: credential stuffing
```

Detection engineering principles:
- **Map coverage to MITRE ATT&CK** — which adversary techniques (initial access, persistence, privesc,
  exfil) can you actually detect? Find and fill the gaps deliberately.
- **Tune for signal.** An alert that fires 500×/day with 1 true positive trains analysts to ignore it
  (alert fatigue is how real incidents get missed). Track precision; suppress/aggregate noise.
- **Detection-as-code**: version-control rules (Sigma), test against known-attack telemetry, peer-
  review changes, CI-deploy to the SIEM. Treat detections like software.
- **High-value detections** (start here): impossible travel, MFA-fatigue, new-admin/role-binding,
  CloudTrail/Config disabled, public-resource creation, secret-manager mass read, anomalous egress,
  WAF attack-score surge, EDR process anomalies, refresh-token reuse.

Tooling: Splunk / Elastic Security / Microsoft Sentinel / Google Chronicle / Wazuh (OSS). Pipe in the
feeds from every other skill (CSP reports, WAF events, auth events, cloud audit, vuln findings).

---

## 3. Incident Response lifecycle (NIST SP 800-61)

The classic **r2 lifecycle** (the phases everyone references) — and how **r3 (Apr 2025)** reframes it
to CSF 2.0:

| Phase (r2) | Do | CSF 2.0 (r3) |
|------------|-----|--------------|
| **Preparation** | runbooks, roles/on-call, tooling, comms plan, retainers, tabletop drills | Govern, Identify, Protect |
| **Detection & Analysis** | triage alert → confirm incident → scope + severity | Detect |
| **Containment** | stop the spread (isolate host, revoke creds/keys, block IPs) — short + long term | Respond |
| **Eradication** | remove the cause (patch, rebuild, rotate, close the hole) | Respond |
| **Recovery** | restore from clean state, monitor for recurrence, validate | Recover |
| **Post-Incident (Lessons Learned)** | blameless retro → new detections + control fixes | Govern (improve) |

> NIST 800-61r3 (Apr 2025) **supersedes r2** and maps incident response across all six CSF 2.0
> Functions — **Govern, Identify, Protect, Detect, Respond, Recover** — emphasizing IR as continuous
> risk management, not a one-off four-phase ritual. The phase *activities* above still apply; r3 just
> embeds them in the broader program. Cite r3 in 2026.

### Severity → response (define before you need it)

| Sev | Example | Response |
|-----|---------|----------|
| SEV-1 | active data exfil, ransomware, prod-wide outage | war room, exec + legal + comms, all-hands |
| SEV-2 | confirmed compromise, contained | IR lead + on-call, hourly updates |
| SEV-3 | suspicious activity, single account | analyst investigates, standard SLA |

### Containment do's/don'ts
- **Preserve evidence before you wipe** (snapshot disk/memory) — but life-of-the-business comes first;
  contain to stop active harm.
- **Revoke + rotate**: kill sessions, rotate the leaked credential/key, disable the compromised
  identity — don't just block one IP.
- **Don't tip off** a sophisticated attacker prematurely (sudden changes can trigger destruction) —
  balance with stopping active exfil. This is a judgment call for the IR lead.

---

## 4. Runbooks (rehearsed, specific, owned)

```md
# Runbook: Leaked Credential / Key in Public Repo
1. CONFIRM   — validate the secret is real + live (don't assume).
2. CONTAIN   — revoke/rotate the credential NOW; invalidate sessions/tokens issued from it.
3. ASSESS    — query logs (SIEM): was it used? from where? what did it touch? (blast radius)
4. ERADICATE — remove from history is NOT enough — rotation is the fix; close the leak path (gitleaks gate).
5. RECOVER   — confirm new creds work; monitor for use of the old one (alert).
6. NOTIFY    — if data was accessed: trigger breach-assessment + legal (see §6).
7. LEARN     — why did it leak? add/strengthen the pre-commit + CI secret-scan gate.
```

Keep runbooks for the incidents you'll actually face: account takeover, leaked secret, ransomware,
DDoS, data exfil, vuln-being-exploited (e.g. a KEV match), insider, third-party/supply-chain
compromise. **Tabletop them quarterly** — an untested plan fails under pressure. Maintain an
out-of-band comms channel (attackers may be reading your Slack/email).

---

## 5. Forensics & evidence basics
- **Order of volatility**: capture memory/network state before disk before archived logs (volatile
  data vanishes on reboot).
- **Chain of custody**: who collected what, when, hashes (SHA-256) of every image; store read-only.
  This matters if it goes legal/law-enforcement.
- **Work on copies**, never the original. Don't "poke around" a live compromised box and destroy
  evidence. Cloud: snapshot volumes, export logs to an isolated account before remediation.
- Know when to call in **professional IR/DFIR** (retainer) and **law enforcement** — for serious
  incidents, don't go it alone.

---

## 6. Compliance — mapped to controls (security first, then evidence)

| Framework | Scope | You must (selected) | Notable timeline |
|-----------|-------|---------------------|------------------|
| **SOC 2** (AICPA TSC) | service orgs; trust criteria (security, availability, confidentiality…) | access control, change mgmt, monitoring, IR, vendor mgmt — **evidence over a period** (Type II) | continuous evidence |
| **ISO 27001:2022** | ISMS | risk assessment, Statement of Applicability, Annex A controls, mgmt review, internal audit | 3-yr cert + surveillance |
| **PCI DSS 4.0(.1)** | cardholder data | network segmentation, no default creds, encrypt PAN, MFA, log ≥1yr, quarterly ASV scans, annual pentest | (4.0 mandatory since Mar 2025) |
| **GDPR** | EU personal data | lawful basis, data minimization, DPIA, processor contracts, security (Art. 32) | **breach notify supervisory authority ≤72h** |

How to do compliance without theater: **build the security control, then map it to the clause** and
**automate the evidence** (Drata/Vanta/Secureframe collect config + access reviews + logs
continuously). The controls overlap massively across frameworks — implement once (least-priv, MFA,
logging, encryption, IR, vuln mgmt, change control), evidence many. Don't invert it (writing policies
you don't follow to pass an audit = expensive paper that stops zero attackers).

### Data-breach notification (know your clocks)
- **GDPR**: notify the supervisory authority **within 72 hours** of awareness (if risk to
  individuals); notify affected individuals "without undue delay" if high risk.
- **US**: state laws (all 50) + sector rules; **SEC** requires public companies to disclose material
  incidents on Form 8-K (Item 1.05) generally within **4 business days** of materiality determination.
  HIPAA, GLBA, and others add their own.
- Pre-build the decision tree (is it a reportable breach? which regulators/customers? what's the
  clock?) **with legal, before** an incident — you won't have time to figure it out at hour zero.

---

## 7. Performance / cost
- Logging volume = cost (ingest + storage + SIEM licensing). Tier it: hot (90d, queryable) → warm →
  cold/archive. Sample high-volume low-value logs; **never** sample security-critical events.
- Detections run continuously — budget SIEM compute; optimize noisy queries. The cost of *no*
  detection is measured in dwell time (industry mean is weeks–months) and breach blast radius.

## 8. Scale / multi-tenant
- Tenant-tag every log + alert so incidents scope to a tenant and detections roll up org-wide.
  A per-tenant compromise must be detectable and containable **without** touching other tenants.
- Centralize SIEM across services/regions; normalize schemas (OCSF/ECS) so cross-source correlation
  works. Federated logging for data-residency (keep EU logs in EU) while preserving central detection.

## 9. Testing & verification
- **Purple-team / breach-and-attack simulation** (Atomic Red Team, Caldera): run known ATT&CK
  techniques *in your own environment* and confirm the detection fires + the alert lands. A detection
  you've never tested is a hope.
- **Tabletop + live-fire IR drills**; measure MTTD/MTTR. Test log pipeline end-to-end (does an event
  actually reach the SIEM and alert?). Test backups restore (ransomware recovery).

## 10. Observability of the program itself
KPIs: MTTD, MTTR, dwell time, % ATT&CK coverage, alert precision/false-positive rate, # incidents by
severity, SLA adherence, log-source coverage (are all assets logging?), control-evidence freshness.
Report these to leadership — security operations is a measurable program, not vibes.

## Anti-patterns
- Logging everything including secrets/PII (becomes a breach + GDPR violation), or logging nothing useful.
- Alerts no one tunes → fatigue → real incidents missed.
- No IR plan / never rehearsed → chaos, evidence destroyed, regulators notified late.
- Wiping/rebuilding a compromised host before preserving evidence (when feasible to preserve).
- Compliance theater: policies you don't follow, controls that exist only for the auditor.
- Treating a SOC 2 report as proof of security.
- Discovering the 72-hour GDPR clock *during* the breach.

## Agent checklist
```
- [ ] Security events logged structured (no secrets/PII), UTC-synced, centralized + immutable, retained per compliance
- [ ] SIEM ingests app/identity/cloud/edge/host; detections as code (Sigma) mapped to MITRE ATT&CK
- [ ] Alerts tuned for precision; high-value detections live (ATO, privesc, exfil, audit-tampering)
- [ ] IR plan per NIST 800-61(r3): runbooks, roles, severity matrix, OOB comms — tabletop quarterly
- [ ] Containment = revoke+rotate+isolate; evidence preserved (order of volatility, chain of custody)
- [ ] Compliance controls built then mapped (SOC2/ISO/PCI/GDPR); evidence automated
- [ ] Breach-notification decision tree pre-built with legal (GDPR 72h, SEC 4 biz days, etc.)
- [ ] Detections + backups + IR drills tested (purple team / BAS); MTTD/MTTR tracked
```

## References
- NIST SP 800-61r3 (Incident Response, CSF 2.0): https://csrc.nist.gov/pubs/sp/800/61/r3/final
- NIST CSF 2.0: https://www.nist.gov/cyberframework · MITRE ATT&CK: https://attack.mitre.org/
- OWASP Logging Cheat Sheet: https://cheatsheetseries.owasp.org/cheatsheets/Logging_Cheat_Sheet.html · Sigma: https://sigmahq.io/
- PCI DSS 4.0: https://www.pcisecuritystandards.org/ · ISO 27001: https://www.iso.org/standard/27001 · GDPR Art. 33/34: https://gdpr-info.eu/
- SOC 2 (AICPA): https://www.aicpa-cima.com/topic/audit-assurance/audit-and-assurance-greater-than-soc-2

## Related
`cybersecurity-foundations` (risk/SDLC), `pentesting-vuln-management` (findings→SLA, KEV),
`auth-session-account-security` (auth telemetry), `ddos-waf-bot-protection` (edge events),
`infra-cloud-network-security` (audit logs), `secrets-supply-chain-security` (leaked-secret IR).
