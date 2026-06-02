---
name: einvoicing-compliance
description: >-
  Build tax-compliant invoicing and e-invoicing at principal depth: one VAT engine (rates by
  jurisdiction/date, inclusive/exclusive, reverse charge, zero-rated vs exempt), and the 2026
  mandates — Saudi ZATCA Phase 2 (clearance/reporting, UBL 2.1, CSID, PIH hash chain, TLV QR),
  UAE Peppol/PINT AE (DCTCE via ASP), EU ViDA/EN 16931, plus Arabic/RTL invoices. Verify locally.
---

# E-Invoicing & VAT Compliance

**Tax is a regulated data contract, not a `* 1.05`.** A non-compliant invoice isn't a UI bug — in Saudi
Arabia it can't be legally issued (ZATCA must clear B2B invoices *before* the buyer sees them), and from
2027 a UAE B2B invoice must travel the Peppol network through an accredited provider. Build **one tax
engine** and treat e-invoicing as a pipeline: *compute → format (XML) → sign/stamp → clear/report →
deliver → archive*. This is the canonical tax/compliance home that `accounting-finance` and `erp-builder`
call into.

> **Regulation moves fast and varies by country.** Treat the dates/thresholds here as a 2026 snapshot,
> verify against the tax authority before shipping, and integrate a certified provider rather than
> building crypto/clearance yourself where one exists.

---

## 1. Mandate
1. **One VAT engine** owns every tax decision (rate, base, inclusive/exclusive, reverse charge, exemption).
2. **Tax point = time of supply**, not invoice creation — use the legally correct date/rate.
3. **Compliant structured format** where mandated (UBL 2.1 / EN 16931 / PINT AE), not just a PDF.
4. **Integrity is cryptographic** where required: signatures, **hash chains (PIH)**, and **QR**.
5. **Clearance vs reporting** is a per-jurisdiction flow — model both; clear *before* delivery when required.
6. **Immutable archive** of issued invoices (years, per local law) + gapless numbering (see `erp-builder`).

## 2. When to use / when NOT
**Use** for any invoicing that must satisfy VAT/GST/e-invoicing law (GCC, EU, LATAM, India GST, etc.).
**Don't** build the ZATCA cryptographic stack or a Peppol Access Point from scratch — onboard a
**certified ASP / clearance provider** (ClearTax, Wafeq, Avalara, Pagero, Sovos, Fatora-certified ERPs).
Your job is correct invoice *data*, the engine, and the integration. **Always** recommend a tax advisor
for the user's jurisdiction.

## 3. The VAT engine (do this once, correctly)

```ts
type TaxTreatment = "standard" | "zero_rated" | "exempt" | "reverse_charge" | "out_of_scope";
type TaxLine = { base: bigint; rate: number; amount: bigint; treatment: TaxTreatment };

/** Resolve rate by jurisdiction + supply date (rates change: KSA 5%→15% in 2020). */
function rateFor(jurisdiction: string, supplyDate: string): number {
  // lookup from a versioned tax_rate table: (jurisdiction, kind, valid_from, valid_to, percent)
  return lookupRate(jurisdiction, supplyDate);             // e.g. AE→5, SA→15, BH→10, OM→5
}

/** Compute tax per line. Exclusive: tax on top of net. Inclusive: tax extracted from gross.
 *  Work in basis points (15% → 1500 bp) so fractional rates stay exact in integer math. */
function computeTax(base: bigint, rate: number, inclusive: boolean, t: TaxTreatment): TaxLine {
  if (t !== "standard") return { base, rate: 0, amount: 0n, treatment: t };  // charged tax = 0
  const bp = BigInt(Math.round(rate * 100));            // 15% → 1500, 5% → 500, 7.5% → 750
  const amount = inclusive
    ? base - (base * 10000n) / (10000n + bp)            // inclusive: tax = gross − net
    : (base * bp) / 10000n;                             // exclusive: tax = net × rate
  return { base, rate, amount, treatment: "standard" };
}
```

**Distinctions that matter (and trip people up):**
- **Zero-rated ≠ exempt.** Zero-rated = 0% but **taxable** (input VAT recoverable, reported); exempt =
  outside VAT (no input recovery). Reporting and recoverability differ — don't collapse them.
- **Reverse charge**: buyer accounts for VAT (cross-border B2B/imported services); supplier charges 0
  but the invoice must state reverse charge. Post a notional Dr/Cr VAT (see `accounting-finance`).
- **Rounding**: per-line vs per-invoice must match local rule; document it once (see `accounting-finance` §7).
- **GCC standard rates (2026):** KSA **15%**, UAE **5%**, Bahrain **10%**, Oman **5%**; Qatar & Kuwait: **no VAT yet**.

## 4. E-invoicing model — decision matrix

| Model | Who | Flow | Build implication |
|-------|-----|------|-------------------|
| **Clearance (CTC)** | KSA ZATCA B2B/B2G | Submit → authority validates & **stamps** → *then* deliver to buyer | Real-time call in the issue path; block delivery until cleared |
| **Reporting (post / near-real-time)** | KSA B2C (24h), EU ViDA DRR (at issuance) | Issue to buyer → report data to authority | Async report job derived from the invoice |
| **Interoperability (Peppol 4/5-corner)** | UAE DCTCE, EU | Exchange via Access Points; authority gets data (UAE: 5-corner) | Integrate an **ASP**; you can't connect directly |
| **Post-audit (legacy)** | many EU pre-ViDA | Issue freely; authority audits later | Keep compliant archive |

## 5. Saudi Arabia — ZATCA Phase 2 (Fatoorah)

Phase 2 (Integration, live in waves since Jan 2023; **Wave 24 > SAR 375k by 30 Jun 2026** — effectively all
VAT-registered businesses). Requirements:

- **Format**: ZATCA-modified **UBL 2.1 XML** (or PDF/A-3 with embedded XML), aligned to EN 16931.
- **B2B/B2G = clearance**: POST to ZATCA, receive cryptographic stamp + cleared XML, *then* send to buyer.
- **B2C (simplified) = reporting**: stamp locally, give buyer the invoice, report to Fatoora **within 24h**.
- **Crypto**: onboard to get a **CSID** (Cryptographic Stamp Identifier); sign with **ECDSA secp256k1**,
  **SHA-256**, X.509 certs from ZATCA's PKI.
- **Per-invoice**: a **UUID**, a **QR (TLV, base64)**, and a **PIH hash chain** so invoices can't be altered.

```ts
import { createHash } from "node:crypto";

/** PIH chain: each invoice embeds the hash of the previous one → tamper-evident sequence.
 *  Hash the canonicalized invoice XML (ZATCA specifies the canonicalization); chain with prev hash. */
export function invoiceHash(canonicalXml: string, previousInvoiceHash: string): string {
  return createHash("sha256")
    .update(previousInvoiceHash + canonicalXml, "utf8")   // genesis prevHash = base64(sha256("0"))
    .digest("base64");
}

/** ZATCA QR is TLV (tag‑length‑value), base64-encoded. Phase 1 tags 1–5; Phase 2 adds 6–9 (hash, sig, key). */
export function zatcaTlvQr(f: {
  sellerName: string; vatNumber: string; timestampIso: string;  // ISO 8601
  invoiceTotalWithVat: string; vatTotal: string;                // decimal strings
}): string {
  const tlv = (tag: number, val: string) => {
    const v = Buffer.from(val, "utf8");
    return Buffer.concat([Buffer.from([tag, v.length]), v]);
  };
  return Buffer.concat([
    tlv(1, f.sellerName), tlv(2, f.vatNumber), tlv(3, f.timestampIso),
    tlv(4, f.invoiceTotalWithVat), tlv(5, f.vatTotal),
    // Phase 2 standard invoices also append: tlv(6, xmlHash), tlv(7, ecdsaSignature), tlv(8, publicKey), tlv(9, certSignature)
  ]).toString("base64");
}
```

> Integrate a ZATCA-certified solution for the actual CSID onboarding, signing, and clearance API
> (`.../e-invoicing/core/invoices/clearance/single`); don't hand-roll PKI in production.

## 6. UAE — FTA e-invoicing (Peppol, DCTCE)

UAE uses a **Decentralised CTC & Exchange (DCTCE)** model — a **Peppol-based 5-corner** system. Invoices
in **PINT AE** (XML) flow between businesses via **FTA-Accredited Service Providers (ASPs)**, and tax data
reaches the FTA in near real time (the FTA does **not** pre-clear). Legal basis: Ministerial Decisions
**243 & 244 of 2025**. Timeline (verify — it has shifted):

| Group | Appoint ASP by | Mandatory go-live |
|-------|----------------|-------------------|
| Pilot (FTA-invited) | — | 1 Jul 2026 (voluntary) |
| Revenue ≥ AED 50M | 30 Oct 2026 | **1 Jan 2027** |
| Revenue < AED 50M | 31 Mar 2027 | 1 Jul 2027 |
| Government entities | 31 Mar 2027 | 1 Oct 2027 |

**Build implication:** you **cannot** connect to the network directly — integrate an accredited ASP for
PINT AE conversion, validation, exchange, and FTA reporting. Your system produces clean invoice data and
talks to the ASP's API.

## 7. EU — ViDA / EN 16931

ViDA (adopted Mar 2025, in force 14 Apr 2025) phases through 2035. Key dates: from **1 Jul 2030**,
intra-EU **B2B** transactions require **structured e-invoices (EN 16931)** + near-real-time **Digital
Reporting Requirements (DRR)** (invoice within 10 days of the chargeable event; report at issuance; EC
Sales Lists abolished); by **1 Jan 2035** national systems align. Member States may already mandate
**domestic** e-invoicing (Italy SdI, France, Germany, Poland KSeF, etc.). Build to **EN 16931** (UBL /
CII) and route via **Peppol** where applicable.

## 8. Mandatory invoice content (the universal core)
Seller & buyer legal name + address + **VAT/tax registration numbers**, unique **sequential number**
(gapless — `erp-builder` §6), **issue date** + **supply/tax-point date**, line items (description, qty,
unit price), **tax rate + tax amount per rate**, **totals** (net, tax, gross), currency (+ FX rate if
foreign), and any **reverse-charge / zero-rate / exemption** statement. **Credit notes must reference the
original invoice** (never edit an issued invoice — issue a credit note; mirrors the immutable-ledger rule).

## 9. Architecture, performance, reliability
- **Pipeline with states**: `computed → formatted → signed → cleared/reported → delivered → archived`,
  each transition persisted and idempotent (replay-safe on retry).
- **Clearance is on the critical path** (KSA B2B): handle authority latency/outages with a queue,
  timeouts, retries, and a clear UX for "pending clearance." Never deliver an uncleared B2B invoice.
- **Reporting is async** (KSA B2C 24h, EU DRR): a durable job derives the report from the stored invoice.
- **Idempotency**: one clearance/report attempt per invoice UUID; store the authority's response/stamp.
- **Hash chain is sequential** per device/branch — serialize issuance so PIH ordering is correct.

## 10. Security & multi-tenant
- **Signing keys / CSIDs are top-secret per tenant** — HSM or secret manager, never in code/DB plaintext;
  rotate and audit. In white-label/multi-tenant setups, each tenant has its own tax identity & keys
  (see `multi-tenant-isolation`, `white-label-platform`).
- **Archive integrity**: invoices are legal records — WORM/immutable storage, retention per law, tamper-evident.
- **PII**: buyer tax IDs and addresses are personal data — protect and minimize.

## 11. Testing & observability
- **Use the sandbox**: ZATCA Fatoora **simulation** environment and ASP test endpoints before production.
- **Golden invoices**: known inputs → exact XML/QR/hash outputs; validate against the official **XSD/Schematron**.
- **Chain test**: PIH of invoice N+1 equals hash of N; reordering breaks the chain (as intended).
- **Tax-engine property tests**: inclusive vs exclusive reconcile; rounding sums to the total; reverse-charge nets to zero.
- **Observe**: clearance success/latency, rejected-invoice reasons, reporting-SLA breaches (24h!), cert expiry, queue depth.

## 12. i18n / Arabic invoices
- **KSA requires Arabic** on tax invoices (bilingual Arabic/English is standard). Render **RTL**, Arabic
  labels, and optionally Arabic-Indic numerals; keep machine-readable amounts in standard digits in the XML.
- Print the **QR** prominently; show cleared-stamp status. Format money with `Intl.NumberFormat('ar-SA',
  {style:'currency', currency:'SAR'})`; mirror layout for `dir="rtl"` (pair with `ui-master` RTL skills).

## 13. Anti-patterns
- **A PDF where the law requires structured XML** (UBL/EN 16931/PINT AE) → non-compliant.
- **Tax math scattered across the codebase** instead of one versioned engine.
- **Hardcoded rate** (`* 1.15`) → breaks on rate changes and across jurisdictions; look up by date.
- **Conflating zero-rated and exempt**, or ignoring reverse charge → wrong VAT returns.
- **Delivering a B2B invoice before ZATCA clearance** → illegal in KSA.
- **Breaking the PIH chain** (parallel issuance, gaps) → integrity failure.
- **Editing an issued invoice** → issue a credit note instead.
- **Hand-rolling PKI / a Peppol AP** when a certified provider exists → years of avoidable risk.
- **Keys/CSIDs in the repo or plaintext DB.**

## 14. Agent checklist
```
- [ ] One VAT engine: rate by jurisdiction+date, inclusive/exclusive, reverse charge, zero-rated vs exempt
- [ ] Correct format per jurisdiction (UBL 2.1 / EN 16931 / PINT AE), validated against XSD/Schematron
- [ ] KSA: CSID onboarding via certified provider; UUID + TLV QR + PIH hash chain; clearance(B2B)/report(B2C 24h)
- [ ] UAE: integrate an accredited ASP (PINT AE, Peppol) — no direct connection
- [ ] EU: EN 16931 + Peppol where mandated; ViDA DRR roadmap noted
- [ ] Mandatory fields + gapless number + supply-date tax point; credit notes reference original
- [ ] Idempotent clearance/report pipeline with states; sandbox-tested; archive immutable
- [ ] Keys/CSIDs in HSM/secret manager per tenant; Arabic/RTL invoice rendering
- [ ] Recommend a local tax advisor; verify current thresholds/dates
```

## 15. References (2026-current)
- ZATCA e-invoicing (Fatoora) developer portal & specs: https://zatca.gov.sa/en/E-Invoicing/
- UAE Ministry of Finance e-invoicing (Peppol/PINT AE, ASP): https://mof.gov.ae/e-invoicing/
- EU ViDA: https://taxation-customs.ec.europa.eu/taxation/vat/vat-digital-age-vida_en · EN 16931 / Peppol BIS: https://peppol.org
- OpenPeppol specs: https://docs.peppol.eu

## Related
`accounting-finance`, `erp-builder`, `multi-tenant-isolation`, `white-label-platform`,
`payments-master`, `tailwind-rtl-arabic` (tailwind-master)
