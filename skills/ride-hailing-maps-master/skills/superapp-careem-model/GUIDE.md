---
name: superapp-careem-model
description: >-
  Staff-level super-app architecture (the Careem/Grab/Gojek model): rides + food/delivery +
  payments/wallet under one identity/SSO, clean service boundaries, shared platform services
  (location, maps, notifications, identity, wallet), mini-apps / module federation for
  verticals, and an honest "when NOT to build a super-app" section. Real identity/token and
  module-federation code, MENA (Careem) context.
---

# The Super-App Model — One Identity, Many Verticals, Shared Rails

**A super-app is not "many apps in one binary" — it's one identity + one wallet + a set of shared platform rails (location, maps, notifications, payments) that independent vertical teams build mini-apps on.** Careem went rides → food → delivery → Careem Pay; Grab and Gojek did the same. The principal insight: the moat is the **shared account and wallet**, not the feature count. Get identity, wallet, and the platform-vs-vertical boundary right, and you can add verticals cheaply. Get them wrong and you've shipped a slow monolith that can't ship anything.

---

## 1. Mandate

- **One identity, one wallet, shared rails.** Single account/SSO and a single wallet across every vertical; location/maps/notifications/payments are platform services, not per-vertical reinventions.
- **Verticals are independent; the platform is shared.** Rides, food, delivery teams own their domain + UI behind clean APIs; they consume platform services, they don't fork them.
- **Mini-apps for breadth, native for the core.** Core verticals are first-class; long-tail services arrive as mini-apps (module federation / web containers) without a full release.
- **Don't build a super-app prematurely.** Earn the second vertical with a loved first one and a real shared-account advantage; otherwise you've added complexity for nothing.

## 2. When to use / when NOT

**Use when:** you have a successful core vertical (e.g., rides) and a strategic reason to add adjacent on-demand verticals sharing the *same users, wallet, and location rails* (food, delivery, payments). Defines how the verticals from the rest of this master compose.

**Skip / explicitly do NOT build a super-app when:** you haven't nailed one vertical yet; the second vertical doesn't share users/wallet/location (no synergy → just a worse standalone app); you lack the org structure for platform-vs-vertical ownership; or regulatory/payments licensing for a wallet isn't realistic in your market. **A super-app is an organizational bet as much as a technical one.**

## 3. Mental model — platform rails vs vertical mini-apps

```
        ┌──────────────────────── ONE SUPER-APP SHELL (identity + wallet + home) ────────────────────────┐
        │   Rides mini-app     Food mini-app     Delivery mini-app     Pay/Wallet     3P mini-apps        │
        │        │                  │                  │                   │              │               │
        └────────┼──────────────────┼──────────────────┼───────────────────┼──────────────┼──────────────┘
                 ▼                  ▼                  ▼                   ▼              ▼
        ┌───────────────────────── SHARED PLATFORM SERVICES (the moat) ─────────────────────────┐
        │  Identity/SSO   Wallet/Payments   Location/Maps   Notifications   Trust&Safety   Profile │
        └────────────────────────────────────────────────────────────────────────────────────────┘
```

| Layer | Owns | Examples |
|-------|------|----------|
| **Shell** | navigation, home, deep-links, mini-app hosting | super-app container, tab bar, universal search |
| **Vertical mini-apps** | domain logic + UI | rides (this master), food/delivery (`marketplace-master`) |
| **Platform services** ⭐ | the shared moat | identity/SSO, wallet, location/maps, notifications, profile, T&S |

## 4. DECISION MATRIX — vertical delivery mechanism

| Mechanism | Ship speed | Native feel | Best for | Cost |
|-----------|-----------|-------------|----------|------|
| **Native module (in-app)** ⭐ | release-bound | ⭐ best | core verticals (rides, food) | high (in the app team's release train) |
| **Module federation / micro-frontend** | independent | good | mid-tier verticals, frequent change | medium (shared runtime contracts) |
| **Web container mini-app (RN WebView / mini-app SDK)** | instant | adequate | long-tail / 3rd-party services | low (no app release) |
| **Deep-link to separate app** | n/a | broken (leaves the app) | rare / regulatory carve-outs | low but kills the super-app promise |

**Verdict:** native for the 2–3 core verticals (the experience must be flawless), **module federation or a mini-app SDK for the long tail** so partners/teams ship without your release train. Reserve deep-links out as a last resort — every hop out of the shell erodes the "one app" value.

## 5. One identity / SSO (the foundation)

```ts
// Single account; verticals get scoped tokens from ONE identity service. OAuth2/OIDC under the hood.
// Access token carries the user + the vertical scopes; verticals never see raw credentials.
interface SuperAppClaims {
  sub: string;                 // the ONE user id across rides/food/delivery/pay
  scopes: string[];            // e.g., ["rides:book","food:order","wallet:read"]
  wallet_id: string;           // single wallet ref, shared
  city_id: number;             // shared geo context
  kyc_level: "none" | "basic" | "full";  // gates wallet/cash-out per market regulation
}

// A vertical exchanges the shell session for a vertical-scoped token (token exchange / RFC 8693).
async function mintVerticalToken(shellToken: string, vertical: "rides" | "food" | "delivery") {
  const res = await fetch(`${IDENTITY}/oauth2/token`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:token-exchange",
      subject_token: shellToken,
      subject_token_type: "urn:ietf:params:oauth:token-type:access_token",
      scope: SCOPES[vertical].join(" "),
    }),
  });
  if (!res.ok) throw new Error(`token-exchange ${res.status}`);
  return (await res.json()).access_token;   // short-lived, vertical-scoped — least privilege
}
```

**One `sub`, one `wallet_id`, scoped tokens per vertical.** A rider in the rides mini-app and a diner in the food mini-app are the *same account* with the *same payment methods and wallet balance* — that's the whole point. KYC level is a shared claim because the wallet/cash-out is shared and regulated per market.

## 6. The shared wallet (the real moat)

```ts
// ONE wallet, many verticals debit/credit it. The ledger is double-entry (payments-master owns it).
// Each vertical calls the SAME wallet service with an idempotency key; never its own balance store.
async function chargeWallet(p: {
  walletId: string; amountMinor: bigint; currency: string;
  vertical: "rides" | "food" | "delivery"; refId: string;   // tripId / orderId
}) {
  return wallet.debit({
    walletId: p.walletId,
    amount: p.amountMinor, currency: p.currency,
    idemKey: `${p.vertical}:${p.refId}`,                     // idempotent per vertical-ref
    memo: `${p.vertical} ${p.refId}`,
  });
  // Top-ups, cash-out, promotions, and the double-entry ledger live in payments-master.
}
```

Cross-vertical wallet = a ride refund lands as wallet credit that pays for dinner; loyalty points span verticals; one top-up funds everything. **This is why users stay.** All money mechanics (top-up rails, ledger, payouts, COD, refunds, PSP/3DS) defer to **`payments-master`** — verticals never keep their own balances.

## 7. Shared platform services (build once, consume everywhere)

- **Location/Maps** — one location service + one map SDK config + one geocoding stack (the rest of this master). Food delivery and rides share driver/courier presence patterns; don't run two map integrations.
- **Notifications** — one push/SMS/in-app service with per-vertical templates and a shared preference center (`communications-master`).
- **Profile & saved places** — Home/Work set once, used by rides *and* food delivery (`geocoding-places-addressing`).
- **Trust & Safety** — shared identity/device/fraud signals across verticals (a banned user is banned everywhere); collusion/abuse detection pools signal.
- **Support** — one support entry that routes to the right vertical with shared context.

The anti-pattern is each vertical re-integrating maps, re-storing addresses, re-building push — duplicated cost, inconsistent UX, fragmented fraud signal.

## 8. Mini-apps via module federation (independent shipping)

```ts
// Shell hosts verticals as remotes (Webpack/Rspack Module Federation or RN equivalents).
// rsbuild/rspack module-federation config (shell):
export default {
  plugins: [
    moduleFederation({
      name: "shell",
      remotes: {
        rides: "rides@https://cdn.superapp.com/rides/remoteEntry.js",
        food:  "food@https://cdn.superapp.com/food/remoteEntry.js",
      },
      shared: {                                   // share ONE copy of platform SDKs (contract-versioned)
        react: { singleton: true, requiredVersion: "^18.0.0" },
        "@superapp/identity": { singleton: true },
        "@superapp/wallet": { singleton: true },
        "@superapp/maps": { singleton: true },
      },
    }),
  ],
};
// Verticals deploy their remoteEntry independently; the shell loads the latest at runtime.
// Contract tests on @superapp/* shared packages prevent a vertical from breaking the shell.
```

The contract (shared identity/wallet/maps SDKs, versioned) is what lets teams ship independently *without* breaking each other. **Module federation without contract tests is a runtime time-bomb** — pin and test the shared surface.

## 9. Edge cases & gotchas

- **Version skew across mini-apps** → shell on v2 of the wallet SDK, a vertical built against v1. Singleton + semver contracts + contract tests; fail fast at load, not in production.
- **Cross-vertical deep links** → "order food, then book a ride home" must preserve session, city, and wallet context across the hop.
- **One vertical's outage** must not down the shell → mini-apps are isolated; a failed remote shows a graceful fallback, not a white screen.
- **Wallet consistency** → two verticals debit concurrently → the single wallet service serializes with idempotency; no vertical-local balances.
- **KYC gating** → a market requires full KYC for wallet cash-out but not for rides → shared `kyc_level` claim gates per-vertical features.
- **Notification storms** → multiple verticals pinging the same user → shared preference center + rate limiting + per-vertical caps.
- **Account ban propagation** → T&S ban must apply across all verticals atomically (it's one identity).

## 10. Performance & scale

- **App startup budget** is the super-app's tax: lazy-load verticals (don't initialize food's SDK on a rides-only session); the shell stays lean.
- **Shared SDKs loaded once** (singletons) — duplicated React/maps copies bloat the bundle and memory.
- **Platform services scale independently** of verticals; identity and wallet are hot, must be HA and low-latency (every vertical calls them).
- **Per-vertical, per-city sharding** continues from `ride-hailing-architecture` — the super-app doesn't centralize what should stay local.

## 11. Security & reliability

- **Least-privilege scoped tokens** per vertical (§5); a compromised food mini-app can't book rides or drain the wallet beyond its scope.
- **The wallet is the crown jewel** — strongest auth, full audit, double-entry ledger (`payments-master`), per-vertical idempotency, fraud monitoring.
- **Mini-app sandboxing** — 3rd-party mini-apps run with constrained capabilities and reviewed permissions; never give a partner raw wallet/identity access.
- **Shared T&S** — device/identity/payment fraud signals pooled across verticals (a fraud ring hitting food is flagged in rides).
- **Blast-radius isolation** — a vertical's failure degrades that tab, not the shell/identity/wallet.

## 12. Testing

- **Contract tests** on every shared SDK (`@superapp/identity|wallet|maps`) — a vertical's build fails if it violates the shell contract.
- **Cross-vertical journeys** — book ride → pay from wallet → order food with the refund credit, as an end-to-end test.
- **Isolation/chaos** — kill a remote mini-app, assert the shell + other verticals survive with a graceful fallback.
- **Token-scope tests** — assert a food token cannot call rides/wallet-write endpoints.
- **Startup budget test** — assert cold-start time stays under budget as verticals are added (lazy-load enforced).

## 13. Observability

- **Cross-sell / synergy metrics** — % users in 2+ verticals (the super-app's reason to exist), wallet adoption, cross-vertical retention vs single-vertical.
- **Per-vertical health** — independent dashboards; shell crash-free rate separate from any vertical.
- **Shared-service SLOs** — identity & wallet latency/error (every vertical depends on them), notification deliverability.
- **Mini-app load** — remote load success/latency, version-skew rejections, fallback rate.

## 14. Accessibility & i18n / RTL (MENA — the Careem reality)

- **One RTL/Arabic system** across the shell and all verticals — consistent bidi, Arabic numerals, localized copy (don't let each vertical re-solve RTL).
- **Careem's actual model:** rides + Careem Food + delivery + **Careem Pay** wallet + bill payments under one Careem ID, MENA + Pakistan; **COD and cash are first-class** across verticals (`payments-master`).
- **Shared saved places & landmarks** (Makani/National Address) used by rides and delivery alike (`geocoding-places-addressing`).
- **Locale-aware everything** — Ramadan demand, prayer-time patterns, market-by-market regulation (wallet licensing, surge caps) as shared config.
- **Accessibility once** — screen-reader, contrast, reduced-motion solved at the shell + shared-component level, inherited by verticals (`ui-master`).

## 15. Anti-patterns

- **Building a super-app before nailing one vertical** → complexity with no moat. Earn it.
- **Per-vertical identity/wallet/maps** → no synergy, duplicated cost, fragmented fraud. Shared rails are the point.
- **Monolith "many features one binary"** → can't ship; everything couples. Platform + independent verticals.
- **Module federation without contract tests** → runtime breakage when a vertical drifts. Versioned, tested shared SDKs.
- **A vertical outage downing the shell** → no isolation. Sandboxed mini-apps + graceful fallback.
- **Over-broad tokens** → a mini-app compromise drains the wallet. Least-privilege scopes.
- **Each vertical re-solving RTL/a11y/notifications** → inconsistent UX. Solve once at the platform.
- **Deep-linking out to separate apps** for core verticals → breaks the one-app promise.

## 16. Agent checklist

```
- [ ] ONE identity/SSO; verticals get short-lived, least-privilege scoped tokens (token exchange)
- [ ] ONE shared wallet (single balance, double-entry ledger in payments-master); per-vertical idempotent charges
- [ ] Shared platform services: location/maps, notifications, profile/saved-places, T&S, support — built once
- [ ] Core verticals native; long-tail via module federation / mini-app SDK with versioned shared contracts
- [ ] Contract tests on shared SDKs; mini-app isolation + graceful fallback (vertical outage ≠ shell down)
- [ ] Cross-vertical journeys work (refund→wallet→other vertical); session/city/wallet context preserved on deep-links
- [ ] KYC level shared claim gates wallet/cash-out per market regulation
- [ ] Startup budget: lazy-load verticals, singleton shared SDKs
- [ ] Cross-sell/synergy + per-vertical + shared-service-SLO observability
- [ ] MENA: one RTL/Arabic+a11y system, COD/cash first-class across verticals, shared Makani/landmark places
- [ ] Honest check: do we have a loved core vertical + real shared-account synergy? If not, DON'T build a super-app
```

## 17. References (verify current — 2026)

- OAuth 2.0 Token Exchange (RFC 8693): https://datatracker.ietf.org/doc/html/rfc8693 · OIDC: https://openid.net/specs/openid-connect-core-1_0.html
- Module Federation (Rspack/Webpack): https://module-federation.io · https://rspack.dev/guide/features/module-federation
- Careem (Uber-owned, MENA super-app — rides/food/delivery/pay): https://www.careem.com
- Grab / Gojek super-app engineering (reference architectures): https://engineering.grab.com · https://www.gojek.io/blog
- Mini-app platform patterns (WeChat-style): https://developers.weixin.qq.com/miniprogram/en/dev/

## 18. Related

`ride-hailing-architecture` (the rides vertical + per-city sharding the super-app inherits) · cross-master: `payments-master` (the shared wallet, ledger, COD, payouts — money lives here), `marketplace-master` (food/delivery verticals + dispatch), `cross-platform-apps-master` (the app shell, mini-app hosting, native modules), `communications-master` (shared notifications), `backend-api-master` (identity/SSO, API gateway), `business-master` (multi-tenant/white-label if offering the platform to others)
