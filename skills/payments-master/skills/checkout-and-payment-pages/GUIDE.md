---
name: checkout-and-payment-pages
description: >-
  Build payment pages that convert and stay PCI SAQ-A at production depth — hosted vs embedded
  (Stripe Payment Element / Adyen Drop-in) vs full-API, server-created intents, 3DS2/SCA
  requires_action handling, tokenization/saved cards, per-market method selection, and the
  PCI DSS v4.0.1 SAQ-A script-security rules for iframes. Conversion + trust UX, localized methods,
  pending/voucher states. Always behind your adapter layer.
---

# Checkout & Payment Pages

**The card field belongs to the PSP, never to your DOM.** Use hosted fields/redirect so PAN/CVV
never touch your servers (PCI SAQ-A); create the intent server-side; confirm on the webhook, not the
redirect. Then optimize relentlessly for conversion — checkout is where researched demand turns into
revenue or abandonment. Always sits on your `payments-architecture` layer.

## When to use / when NOT

- **Use** to build the actual pay page/flow: method selection, card entry, 3DS2, saved cards,
  success/pending/failure states.
- **NOT** for gateway integration internals (`global-`/`africa-payment-gateways`), wallet/mobile-money
  rails (`ewallets-and-mobile-money`), or routing/fraud (`payment-orchestration-and-security`).

## DECISION MATRIX — integration style (PCI scope drops as you go up)

| Style | PCI scope | UX control | When | v4.0.1 script duty |
|-------|-----------|-----------|------|--------------------|
| **Redirect / hosted page** | **SAQ-A (lowest)** | low | fastest/safest; most African PSPs default here | **exempt** from the script criterion |
| **Embedded hosted fields** (Stripe Payment Element, Adyen Drop-in, iframes) | **SAQ-A** | high | default for most products | **must** confirm page not script-attackable (see §Security) |
| **Drop-in / prebuilt widget** | low | medium | multi-method, little custom UI | as above (iframe) |
| **Full API / raw card in your inputs** | **SAQ-D (highest)** | total | avoid — pen tests, ASV scans, ~300 controls | full 6.4.3 + 11.6.1 apply |

> Default to the **Payment Element / Drop-in** (one widget, many methods, tokenized) or a **hosted
> page**. Rendering your own `<input>` for the card number drags you to SAQ-D — almost never worth it.

## Reference flow — Stripe Payment Element (server + client)

```ts
// SERVER: create the intent. Amount comes from your DB, never the request body.
app.post("/api/checkout", async (req, res) => {
  const order = await getOrder(req.body.orderId, req.user.id);    // authoritative amount + currency
  const pi = await stripe.paymentIntents.create(
    { amount: order.totalMinor, currency: order.currency.toLowerCase(),
      automatic_payment_methods: { enabled: true },               // cards + wallets + local per locale
      metadata: { reference: order.id } },
    { idempotencyKey: `order:${order.id}:attempt:${order.attempt}` },
  );
  res.json({ clientSecret: pi.client_secret });                   // publishable key only on the client
});
```

```tsx
// CLIENT: mount the Element, confirm, handle 3DS2 via the redirect/automatic next-action.
import { loadStripe } from "@stripe/stripe-js";
import { Elements, PaymentElement, useStripe, useElements } from "@stripe/react-stripe-js";

const stripePromise = loadStripe(process.env.NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY!); // pk_…, safe on client

function PayForm() {
  const stripe = useStripe(); const elements = useElements();
  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    const { error } = await stripe!.confirmPayment({
      elements: elements!,
      confirmParams: { return_url: `${location.origin}/checkout/return` }, // 3DS2/redirect lands here
      // redirect: "if_required" keeps frictionless flows inline; only challenges navigate away.
    });
    if (error) showInlineError(error.message);   // e.g. card_declined — keep entered data, offer retry
    // SUCCESS IS NOT CONFIRMED HERE. The webhook (payment_intent.succeeded) fulfils the order.
  }
  return <form onSubmit={onSubmit}><PaymentElement /><button>Pay</button></form>;
}
export default ({ clientSecret }: { clientSecret: string }) => (
  <Elements stripe={stripePromise} options={{ clientSecret, appearance: { theme: "stripe" } }}><PayForm /></Elements>
);
```

> The return page reads the PaymentIntent status to show success/pending/failed, but **fulfilment is
> driven by the webhook** — a user can close the tab mid-redirect. Show "pending" if status is unknown.

## 3DS2 / SCA on the page

- Let the PSP run the challenge: a `requires_action` PaymentIntent triggers the 3DS2 flow automatically
  (Stripe handles the iframe/redirect). Don't build your own 3DS UI.
- **Frictionless-first**: the Element sends device/browser data so the issuer can grant a frictionless
  pass or an exemption (TRA, low-value); only a real challenge interrupts the user.
- On failure, surface the specific decline (`card_declined`, `insufficient_funds`,
  `authentication_required`) and offer a one-tap retry — don't show a generic "payment failed".

## Tokenization & saved cards

- Save the **provider token** (`SetupIntent` → `payment_method` + `customer`), never the PAN.
- Show saved methods as brand + last4 + expiry; allow add/remove/set-default.
- Re-auth per risk: a returning low-risk customer may be frictionless; step up to 3DS2 on risk signals.
- Off-session future charges (subscriptions) are **MITs** — authenticate at save-time + store a mandate
  (`payment-orchestration-and-security`).

## i18n / localized methods (the biggest abroad lever)

- Surface methods **by country + currency**: cards + Apple/Google Pay everywhere; **iDEAL** (NL),
  **PIX** (BR), **UPI** (IN), **Alipay/WeChat** (CN); in Africa **mobile money + bank transfer + Fawry
  voucher**. `automatic_payment_methods` / Adyen `/paymentMethods` do this per locale.
- Localize language, **currency presentment**, number/RTL formatting (Arabic), and method ordering.
  Put express wallets first (one-tap), then the locale's dominant method, then cards.
- Price/format money from your `Money` module; display major units with the right decimals per currency.

## Conversion & trust UX

```
- [ ] Express wallets (Apple/Google Pay) one-tap at the very top
- [ ] Guest checkout; minimal fields; address autocomplete; auto-detect country/currency
- [ ] Show total + currency + taxes + fees BEFORE pay; zero surprise costs
- [ ] Trust signals: lock, accepted-method logos, refund/returns policy, support
- [ ] Inline real-time validation; specific, actionable decline messages
- [ ] Mobile-first; no full-page reloads; disabled/loading state on submit (prevents double-submit)
- [ ] One-tap retry on soft declines; preserve entered data
- [ ] Pending state for MoMo ("approve on your phone") / voucher / bank transfer
- [ ] Post-payment: clear success, receipt/email, order status; localized throughout
```

## Security — PCI SAQ-A under PCI DSS v4.0.1 (effective 2025; current 2026)

- **PAN/CVV never hit your server**; publishable/public keys only on the client; secret keys server-side.
- **Embedded iframe (Element/Drop-in) merchants** must now satisfy the SAQ-A **script-security
  eligibility criterion**: confirm the page is **not susceptible to script attacks**, by either
  (a) applying the techniques of **Req 6.4.3** (authorize/integrity-check every script) **and 11.6.1**
  (tamper/change detection on the payment page), or (b) obtaining written confirmation from your
  PSP/TPSP that their embedded solution protects the page. (Req 6.4.3 & 11.6.1 were **removed from the
  SAQ-A questionnaire** itself, but this eligibility confirmation replaces them.)
- **Pure redirect / hosted-page merchants are exempt** from that script criterion — a strong reason to
  prefer redirect when you don't need inline UX.
- Practical controls: strict **CSP** (allowlist only the PSP's script origins), **Subresource Integrity**
  on third-party scripts, no analytics/tag-manager on the pay route, never log card data.
- Idempotency key per attempt (prevents double-charge on double-submit); confirm via webhook;
  rate-limit + bot protection on the create-intent endpoint (`payment-orchestration-and-security`).

## Performance

- Lazy-load the PSP SDK; create the PaymentIntent on intent-to-pay (or page load with caching), not on
  every keystroke. Cache the `clientSecret` for the attempt so re-renders don't mint new intents.
- Keep the pay route script-light (CSP also helps here): fewer third-party scripts = faster + safer + SAQ-A.

## Testing

- Stripe test cards: `4242 4242 4242 4242` (success), `4000 0027 6000 3184` (3DS2 challenge),
  `4000 0000 0000 9995` (insufficient funds), `4000 0000 0000 0002` (declined).
- Assert: double-submit yields one charge; closing the tab after redirect still fulfils via webhook;
  saved-card re-use works off-session; localized method set renders per country.
- Visual-regression the success/pending/failure/3DS states; Lighthouse the mobile pay route.

## Pages to build

Checkout (method select + pay) · 3DS/redirect return · success/receipt · failure/retry ·
**pending** (MoMo/voucher/bank ref) · saved-methods management · subscription manage/upgrade.

## Anti-patterns

- Rolling your own raw card `<input>` (SAQ-D) instead of hosted fields/Element.
- Marking success on the client redirect before the webhook confirms.
- Hiding taxes/fees until the last step → abandonment; forcing account creation → lost mobile conversions.
- Generic "payment failed" with no reason or retry path.
- Same method set for every country; cards-only where momo/iDEAL/PIX dominate.
- Loading analytics/tag-manager/3rd-party scripts on the embedded-iframe pay page (breaks SAQ-A script criterion).

## Agent checklist

```
- [ ] Integration style chosen for SAQ-A (hosted page or embedded Element/Drop-in); no raw card inputs
- [ ] Intent created SERVER-side (amount from DB) + idempotency key per attempt
- [ ] 3DS2/SCA via requires_action; frictionless-first; specific decline + retry UX
- [ ] Saved cards as provider tokens; off-session = MIT + mandate
- [ ] Localized methods/currency/language per market; express wallets on top
- [ ] Success driven by WEBHOOK; pending state for async (MoMo/voucher/transfer)
- [ ] PCI v4.0.1 SAQ-A: CSP + SRI + PSP confirmation (iframe) OR redirect (exempt); no card logging
```

## References (current 2026)

- Stripe Payment Element & Elements: https://docs.stripe.com/payments/payment-element · 3DS/SCA: https://docs.stripe.com/strong-customer-authentication
- Adyen Drop-in/Components: https://docs.adyen.com/online-payments/build-your-integration/
- PCI DSS v4.0.1 SAQ-A eligibility (script criterion): https://blog.pcisecuritystandards.org/faq-clarifies-new-saq-a-eligibility-criteria-for-e-commerce-merchants
- Stripe test cards: https://docs.stripe.com/testing

## Related

`payments-architecture`, `global-payment-gateways`, `africa-payment-gateways`,
`ewallets-and-mobile-money`, `payment-orchestration-and-security`, `payment-webhooks-and-idempotency`;
`ui-master`, `tailwind-master` (checkout UI).
