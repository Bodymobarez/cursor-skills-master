---
name: contracts-pro
description: >-
  Engineer professional contracts at staff depth: standard contract anatomy (parties,
  recitals, definitions, obligations, payment, term/termination, IP, confidentiality,
  liability/indemnity, governing law, dispute resolution, signatures, schedules), a clause
  library + templating (docxtemplater / structured JSON→DOCX/PDF) with variables and
  conditional clauses, versioning/redlines, e-signature integration (DocuSign / Dropbox Sign)
  with webhook + document integrity, and UAE/GCC bilingual Arabic/English + RTL notes. This is
  ENGINEERING guidance, not legal advice — always route final contracts to a qualified lawyer.
---

# Contracts Pro — Professional Contract Generation

**A contract is structured data that happens to render as prose.** Treat clauses as composable,
versioned, testable components — not a Word file someone copy-pastes and forgets to update. Your
job is the *generation pipeline and integrity*: correct anatomy, safe templating, clean redlines,
verifiable signatures. **It is never to invent the law.**

> ⚠️ **DISCLAIMER (read first, repeat to the user).** This skill is engineering guidance for
> *producing* contract documents. It is **not legal advice**, creates no attorney–client
> relationship, and must not be relied on for legal sufficiency. Laws vary by jurisdiction and
> change. **Always have a qualified lawyer in the relevant jurisdiction review and approve any
> contract before use.** Never fabricate statutes, article numbers, case law, or regulatory
> citations — if you don't have a verified source, say so and defer to counsel.

---

## 1. Mandate

Deliver a **generation system**: a clause library, a typed data model, a templating pipeline that
assembles correct documents, version control with reviewable redlines, and an e-signature flow
whose integrity you can prove. Make documents bilingual-ready (EN/AR, RTL) where the jurisdiction
demands it. Encode *structure and process*; leave *legal substance* to lawyers.

---

## 2. When to use / when NOT

**Use when:** generating NDAs, MSAs/SOWs, employment/contractor agreements, leases, sales orders,
or any templated agreement; building a clause library; wiring e-signature; producing bilingual
GCC contracts.

**Use a different tool / escalate when:**
- The user needs **legal interpretation, enforceability, or "is this clause valid in X?"** → that's a
  lawyer, not this skill. Provide structure; defer substance.
- It's plain **document mechanics** (just make a DOCX/PDF, no legal structure) → `anthropic-docx` / `pdf-pro-documents`.
- They want **e-signature on an arbitrary PDF** with no contract logic → `pdf-pro-documents` + the e-sign API directly.
- **Litigation / regulatory filings / notarization** → out of scope; human professionals.

---

## 3. Mental model — contract anatomy + generation architecture

**Standard anatomy (the skeleton every commercial agreement shares):**

```
1.  Title + parties        Legal names, entity type, registration no., address ("Party A"/"Party B")
2.  Recitals / "Whereas"   Background + intent (context, not operative obligations)
3.  Definitions            Defined Terms (Capitalized) used consistently throughout
4.  Obligations / scope    What each party must do (services, deliverables, SOW/Schedule ref)
5.  Payment / fees         Amounts, currency, schedule, invoicing, taxes, late interest
6.  Term & termination     Start/end, renewal, termination for cause/convenience, effects of term.
7.  IP / ownership         Background vs foreground IP, licenses, work-for-hire/assignment
8.  Confidentiality        Definition, carve-outs, duration, return/destruction
9.  Warranties             What each party promises is true
10. Liability & indemnity  Caps, exclusions (indirect/consequential), indemnities
11. Governing law          Which jurisdiction's law applies
12. Dispute resolution     Courts vs arbitration (seat, rules, language), escalation
13. Boilerplate            Notices, assignment, force majeure, entire agreement, severability, amendments, counterparts
14. Signatures             Authorized signatory, name, title, date (+ e-sign block)
15. Schedules / exhibits   SOW, pricing, SLAs, DPA, annexes
```

**Generation architecture — contract as data:**

```
clause library (versioned)  +  data model (parties, dates, fees, options)
        ↓ templating (variables + conditional clauses + loops)
   assembled document (DOCX or structured → PDF)
        ↓ review / redline (track changes or git diff)
   final PDF (archival PDF/A via pdf-pro-documents)
        ↓ e-signature (envelope)  →  webhook (verify + re-fetch status)
   executed PDF + SHA-256 + audit trail/certificate  →  immutable store
```

Separate **content** (clauses), **data** (the deal), **logic** (which clauses apply), and **render**
(DOCX/PDF). That separation is what makes contracts auditable and re-generatable.

---

## 4. DECISION MATRIX — generation pipeline + e-sign provider

**Which generation pipeline:**

| Scenario | Pipeline | Why |
|---|---|---|
| Business users edit the template in Word | **docxtemplater** (DOCX template + JSON) | Non-devs design layout; you inject data, loops, conditional clauses. |
| Fully programmatic, no Word template | `docx` (dolanmiu) builder → DOCX, or structured JSON → render | Code owns structure end-to-end; great for many small variants. |
| Contract-as-code, heavy versioning/redlines | **Markdown/Legal-Markdown + git** → DOCX/PDF (pandoc/WeasyPrint) | Plain-text diffs, PR review, CI; convert at the end. |
| Computable / smart clauses | **Accord Project (Cicero/Concerto)** | Machine-readable clause logic tied to natural language. |
| Final, archival, signature-ready | render to **PDF/A** via `pdf-pro-documents` | Long-term retention + accessibility. |

**Which e-signature provider** (verify current terms before committing):

| Criterion | DocuSign eSignature | Dropbox Sign (ex-HelloSign) | DocuSeal (OSS) |
|---|---|---|---|
| Best for | Enterprise, regulated | Clean dev API, embedded | Self-hosting / data residency |
| Developer experience | Powerful but complex | Simplest, well-documented | Good, open-source |
| Embedded signing | ✅ | ✅ (clean iframe) | ✅ |
| Webhook integrity | HMAC-SHA256 (Connect) | `event_hash` HMAC-SHA256 | configurable |
| Heavy compliance (FedRAMP, 21 CFR Part 11) | ✅ | ◑ limited | self-managed |
| Self-host | ❌ | ❌ | ✅ |

**E-signature assurance levels** (eIDAS terminology; confirm what your use case legally requires):

| Level | What it is | Typical use |
|---|---|---|
| **SES** Simple | basic e-sign (click/type) | low-risk everyday agreements |
| **AES** Advanced | uniquely linked to signer, tamper-detectable | higher-value B2B |
| **QES** Qualified | AES + qualified certificate; in EU ≈ handwritten | regulated/high-stakes |

---

## 5. Production code

### 5a. docxtemplater — clause assembly with variables, conditional clauses, loops

```js
// npm i docxtemplater pizzip
// IMPORTANT: the angular expression parser must be angular-expressions >= 1.5.2 (sandbox-escape fix)
import PizZip from "pizzip";
import Docxtemplater from "docxtemplater";
import expressionParser from "docxtemplater/expressions.js"; // bundled angular-expressions wrapper
import fs from "node:fs";

/*
 Template msa.docx (authored in Word) contains tags:
   {party_a.name} ({party_a.reg}) and {party_b.name}
   Effective Date: {effective_date}
   {#has_confidentiality} 8. CONFIDENTIALITY … {/has_confidentiality}   ← conditional clause
   {#fees}{desc}: {amount} {ccy}{/fees}                                  ← loop (pricing rows)
   Liability cap: {liability_cap_months} months' fees
   Governing law: the laws applicable in {governing_law}.
*/
export function generateMSA(data, templatePath = "templates/msa.docx") {
  const zip = new PizZip(fs.readFileSync(templatePath, "binary"));
  const doc = new Docxtemplater(zip, {
    paragraphLoop: true,   // clean paragraph-level loops/conditions (no empty lines)
    linebreaks: true,
    parser: expressionParser, // enables {#fees.length > 0}, ternaries, comparisons
    nullGetter: () => "",  // NEVER render the literal "undefined" into a contract
  });
  doc.render(data);
  return doc.getZip().generate({ type: "nodebuffer", compression: "DEFLATE" });
}

// Usage — data is the deal; logic flags pick which clauses appear:
const buf = generateMSA({
  party_a: { name: "Acme FZ-LLC", reg: "DMCC-12345" },
  party_b: { name: "Globex Ltd" },
  effective_date: "2026-06-01",
  fees: [
    { desc: "Implementation (one-off)", amount: "50,000", ccy: "AED" },
    { desc: "Annual support",           amount: "12,000", ccy: "AED" },
  ],
  has_confidentiality: true,        // toggles the whole clause block
  liability_cap_months: 12,
  governing_law: "the Dubai International Financial Centre (DIFC)",
});
fs.writeFileSync("out/msa-acme.docx", buf);
```

### 5b. Clause library as data (compose, don't copy-paste)

```ts
// A clause is versioned content + applicability logic. The engine selects; humans approve wording.
type Clause = {
  id: string; version: string; title: string;
  bodyEn: string; bodyAr?: string;          // bilingual-ready
  appliesIf?: (deal: Deal) => boolean;       // conditional inclusion
  requiresReview?: boolean;                  // force lawyer sign-off when non-standard
};

const clauses: Clause[] = [
  { id: "confidentiality", version: "2026-01", title: "Confidentiality",
    bodyEn: "Each party shall keep the other's Confidential Information secret …",
    bodyAr: "يلتزم كل طرف بالحفاظ على سرية المعلومات السرية للطرف الآخر …",
    appliesIf: (d) => d.exchangesConfidentialInfo },
  { id: "ip-assignment", version: "2026-01", title: "Intellectual Property",
    bodyEn: "All Foreground IP created under this Agreement is assigned to the Client …",
    appliesIf: (d) => d.type === "services", requiresReview: true },
];

export function selectClauses(deal: Deal) {
  const chosen = clauses.filter((c) => !c.appliesIf || c.appliesIf(deal));
  return {
    clauses: chosen,
    needsLawyer: chosen.some((c) => c.requiresReview), // surface this to the user, loudly
  };
}
```

### 5c. E-signature integrity — verify the webhook, then trust the API (not the payload)

```js
import crypto from "node:crypto";

// DocuSign Connect: HMAC-SHA256 of the RAW body with your Connect key, base64, in X-DocuSign-Signature-1.
export function verifyDocuSign(rawBody, headerSig, secret) {
  const expected = crypto.createHmac("sha256", secret).update(rawBody, "utf8").digest("base64");
  const a = Buffer.from(expected), b = Buffer.from(headerSig || "");
  return a.length === b.length && crypto.timingSafeEqual(a, b); // constant-time compare
}

// Dropbox Sign: event_hash = HMAC-SHA256(event_time + event_type) keyed by your API key (hex).
export function verifyDropboxSign(event, apiKey) {
  const expected = crypto.createHmac("sha256", apiKey)
    .update(event.event.event_time + event.event.event_type).digest("hex");
  return expected === event.event.event_hash;
}

// Webhooks are at-least-once and UNORDERED. After verifying, re-fetch the authoritative status
// from the API (idempotent) instead of trusting the event payload.
async function onEnvelopeEvent(rawBody, headerSig) {
  if (!verifyDocuSign(rawBody, headerSig, process.env.DS_CONNECT_KEY)) throw new Error("bad signature");
  const evt = JSON.parse(rawBody);
  const envelope = await docusign.getEnvelope(accountId, evt.envelopeId); // source of truth
  if (envelope.status === "completed") await archiveExecuted(evt.envelopeId);
}
```

### 5d. Document integrity — tamper-evidence on the executed file

```js
import crypto from "node:crypto";
// Hash the final executed PDF and store it with the envelope id + completion certificate.
// Any later byte change → different digest → tampering is provable.
export function sealRecord(pdfBytes, envelopeId, certificateBytes) {
  return {
    envelopeId,
    sha256: crypto.createHash("sha256").update(pdfBytes).digest("hex"),
    certificateSha256: crypto.createHash("sha256").update(certificateBytes).digest("hex"),
    sealedAt: new Date().toISOString(),
  };
}
// Note: providers also apply their own tamper-evident digital seal (PAdES/PKI) + audit trail.
// Store the executed PDF + certificate of completion immutably (WORM/object-lock).
```

---

## 6. Edge cases & gotchas

- **Defined-term drift**: a term defined once but used with different casing/wording elsewhere creates
  ambiguity. Lint that every Capitalized Defined Term is actually defined and used consistently.
- **Dangling cross-references**: "as set out in Section 7.3" after clauses are reordered. Use
  auto-numbered references, not hard-coded numbers.
- **Empty conditional blocks** leaving orphan headings/numbering when a clause is excluded — use
  `paragraphLoop`/paragraph-placeholder so the heading disappears with the clause.
- **`nullGetter`**: without it, missing data renders "undefined" into a binding document — unacceptable.
- **Currency/number/date locale**: "1,500" vs "1.500"; date formats (DD/MM vs MM/DD) cause real disputes — normalize and spell out where high-stakes.
- **Signatory authority**: the named signer must be authorized to bind the entity; capture name + title.
- **Counterparts & e-sign**: include a counterparts/electronic-signature clause so separately-signed copies form one agreement.
- **Schedules out of sync** with the main body after edits — generate them from the same data model.

---

## 7. Performance (bulk / large)

- **Bulk send** (onboarding 5,000 contractors): generate from one template + a dataset, then use the
  provider's **bulk send** / batch envelope API; queue + idempotency key per recipient.
- **Reuse the parsed template**: cache the compiled docxtemplater zip; don't re-read the `.docx` per render.
- **Render DOCX→PDF in a pool** (see `pdf-pro-documents` §9) — converting thousands of contracts means a browser/WeasyPrint pool, not one process per file.
- **Long contracts (100+ pages)**: prefer a typesetting/print pipeline (Typst/WeasyPrint) for reliable pagination, TOC, and cross-refs.

---

## 8. Security

- **Template injection / sandbox escape**: docxtemplater's angular parser evaluates expressions.
  **Never** let untrusted users upload templates you then render with the angular parser, and pin
  **angular-expressions ≥ 1.5.2** (older versions had sandbox-escape CVEs). Treat templates as code.
- **PII everywhere**: contracts contain names, IDs, salaries, bank details. Encrypt at rest, restrict
  access (need-to-know), redact in logs, and honor data-retention/erasure obligations. Pair with
  jurisdiction privacy rules (GDPR / UAE PDPL — verify specifics with counsel).
- **Webhook authenticity**: always HMAC-verify the **raw** body (constant-time), reject on mismatch,
  and re-fetch status from the API. Make the handler idempotent (dedupe by envelope/event id).
- **Document integrity**: store the executed PDF + completion certificate immutably (object-lock/WORM);
  keep the SHA-256; rely on the provider's tamper-evident seal + audit trail as primary evidence.
- **Access control on envelopes**: signing links are bearer tokens — scope, expire, and bind them to
  authenticated recipients where possible (embedded signing with your own auth).
- **Secrets**: API keys/Connect keys in a secret manager, never in templates or the repo.

---

## 9. Scale / automation / batch

- **Contract lifecycle (CLM) pipeline**: request → generate → review/approve → sign → store → renew.
  Automate generation + signature; keep human approval gates for non-standard clauses
  (`requiresReview`).
- **Versioned clause library** in git with semantic versions; a contract records which clause
  versions it used (reproducibility + audit).
- **Renewals/expiry**: schedule jobs off `term`/`renewal` dates to trigger reminders/auto-renew drafts.
- **Integrations**: push executed contracts to the system of record (CRM/ERP/DMS). Pair with
  `integrations-master` (DocuSign/CRM connectors) and `business-master` (CLM/CRM/ERP).

---

## 10. Testing & validation

- **Golden-file rendering**: for a fixed dataset, assert the generated DOCX/PDF text contains the
  expected clauses and omits excluded ones (conditional logic correctness).
- **No-undefined test**: scan output for `undefined`/empty placeholders/unresolved `{tags}`.
- **Defined-term + cross-ref lint**: every Capitalized term defined; every "Section X" reference resolves.
- **Schema-validate the deal data** (parties, dates, amounts, currency) before generation — fail loud.
- **E-sign in sandbox**: DocuSign demo / Dropbox Sign test mode; verify webhook signature
  verification, idempotency, and out-of-order delivery handling with replayed events.
- **Integrity test**: tamper one byte of the executed PDF → confirm the stored SHA-256 no longer matches.

---

## 11. Accessibility & i18n / RTL Arabic (UAE / GCC bilingual)

- **Bilingual contracts (Arabic/English)** are standard in the UAE/GCC. Common layouts: two parallel
  columns (AR right, EN left) or two sequential versions. **Specify the controlling language** in a
  clause — in UAE/GCC court proceedings the working language is Arabic, and where versions conflict
  the **Arabic text typically prevails** unless the parties (and the forum) accept otherwise. *Confirm
  the exact effect with local counsel.*
- **RTL rendering**: lay out the Arabic column/version RTL (`dir="rtl"`, `lang="ar"`); embed an
  Arabic-shaping font; keep amounts/dates/IDs readable inside RTL text (BiDi marks). Generate the
  final bilingual PDF via `pdf-pro-documents` (HTML→PDF handles BiDi cleanly).
- **Accessible final PDF**: produce **PDF/UA** (tagged) + **PDF/A** (archival) so the executed
  contract is screen-reader accessible and retainable long-term.
- **Governing law / jurisdiction (engineering notes, not legal advice — verify with counsel):**
  - **US**: the **ESIGN Act (2000)** + **UETA** generally make e-signatures valid for most contracts
    (with carve-outs, e.g. wills, certain notices).
  - **EU**: **eIDAS (Regulation (EU) No 910/2014)** defines SES/AES/QES; **QES** has legal effect
    equivalent to a handwritten signature.
  - **UAE**: electronic transactions/e-signatures are recognized under UAE federal law on electronic
    transactions and trust services. Onshore vs DIFC/ADGM (common-law free zones) differ — pick the
    forum deliberately.
  - **NEVER fabricate** article numbers, statutes, or case citations. State the framework name,
    flag uncertainty, and defer specifics to a qualified lawyer.

---

## 12. Anti-patterns

- **Giving legal advice / asserting enforceability** instead of deferring to a lawyer.
- **Fabricating statutes, articles, or case law** to sound authoritative. Catastrophic — never do it.
- **Copy-paste clause sprawl** instead of a versioned clause library → silent inconsistencies.
- **Trusting webhook payloads** without HMAC verification + status re-fetch.
- **Rendering untrusted templates** with the angular parser / unpinned angular-expressions.
- **"undefined" or unresolved `{tags}`** in a binding document.
- **Hard-coded section numbers and dates** that rot when clauses are reordered.
- **No controlling-language clause** in a bilingual GCC contract.
- **Storing executed contracts mutably** with no hash/audit trail → no tamper evidence.

---

## 13. Agent checklist

```
- [ ] Stated the DISCLAIMER; recommended qualified-lawyer review; did NOT give legal advice
- [ ] No fabricated statutes/articles/cases — frameworks named, uncertainty flagged
- [ ] Anatomy complete (parties→signatures→schedules); defined terms consistent; cross-refs resolve
- [ ] Clauses from a versioned library; conditional inclusion logic correct; non-standard flagged for review
- [ ] Templating safe: angular-expressions ≥ 1.5.2; no untrusted templates; nullGetter set (no "undefined")
- [ ] Data schema-validated (parties, dates, amounts, currency); locale-correct formats
- [ ] Final rendered to PDF/A + PDF/UA via pdf-pro-documents
- [ ] E-sign: provider chosen; webhook HMAC-verified (raw body, constant-time) + status re-fetch + idempotent
- [ ] Executed PDF hashed (SHA-256) + certificate stored immutably (WORM)
- [ ] Bilingual AR/EN with RTL + controlling-language clause where jurisdiction requires
- [ ] PII encrypted/access-controlled; secrets in a manager; logs redacted
```

---

## 14. References (2026)

- docxtemplater 3.68.x — https://docxtemplater.com/docs/ · tag types https://docxtemplater.com/docs/tag-types/ · angular parser (≥1.5.2) https://docxtemplater.com/docs/angular-parse/
- `docx` (dolanmiu) programmatic DOCX — https://docx.js.org
- Accord Project (Cicero / Concerto) computable contracts — https://accordproject.org
- DocuSign eSignature API + Connect (HMAC) — https://developers.docusign.com · webhook security https://developers.docusign.com/platform/webhooks/connect/hmac/
- Dropbox Sign API (event_hash) — https://developers.hellosign.com / https://www.hellosign.com/api · DocuSeal (OSS) https://www.docuseal.com
- eIDAS Regulation (EU) 910/2014 — https://eur-lex.europa.eu/eli/reg/2014/910/oj · US ESIGN Act — https://www.fdic.gov/regulations/compliance/manual/10/x-3.1.pdf
- PAdES (PDF Advanced Electronic Signatures, ETSI) — https://www.etsi.org · WORM/object-lock concept (AWS S3 Object Lock) https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lock.html

---

## 15. Related

`anthropic-docx` / `blastum-docx` (DOCX mechanics, tracked changes), `pdf-pro-documents` (render
executed contracts to PDF/A + PDF/UA, watermark, encrypt), `excel-pro-spreadsheets` (pricing
schedules), `documentation-pro` (policy/handbook docs). Cross-master: `business-master`
(CLM/CRM/ERP, billing, VAT/e-invoicing), `integrations-master` (DocuSign/CRM/storage connectors),
`payments-master` (payment terms wiring). **Always pair with a qualified lawyer.**
