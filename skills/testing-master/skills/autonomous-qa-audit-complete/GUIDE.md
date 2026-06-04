---
name: autonomous-qa-audit-complete
description: >-
  Autonomous end-to-end QA audit: scan codebase, discover all routes/pages/APIs/flows, Playwright crawl
  (every page, button, form, modal, CRUD, auth), console/network monitoring, screenshots on failure,
  fix-retest loop until green. Deliver QA_AUDIT_REPORT.md, FIXES_APPLIED.md, TEST_COVERAGE.md.
  Zero dead buttons, zero broken routes goal. Use for full-app QA audit or pre-release hardening.
---

# Autonomous QA Audit — Complete (E2E until green)

**Mandate:** act as **Senior QA Engineer + Full Stack Developer + Product Tester**. Do not file a report and
stop — **discover → test → fix → retest → repeat** until success criteria pass or you document blocked
manual items with reproduction steps. Ship **`QA_AUDIT_REPORT.md`**, **`FIXES_APPLIED.md`**, **`TEST_COVERAGE.md`**
in the **target project root** (not the skills repo).

**Pair with:** `adding-e2e-tests`, `form-testing`, `api-smoke-testing`, `browser-automation-master`,
`code-quality-master` (a11y/perf), `elite-ui-ux-design-system` (UI consistency).

---

## When to use / when NOT

| Use | Don't |
|-----|-------|
| Pre-release full-app audit, "test everything", broken buttons/routes hunt | Unit-test-only task → `writing-tests` / `mattpocock-tdd` |
| Playwright crawl + fix loop on local/staging | **Production** without explicit user approval + read-only mode |
| Generate coverage + audit deliverables | Security pentest → `cybersecurity-master` |

**Safety:** default target = `http://localhost:*` or staging. Never DELETE real prod data. Use test accounts
and isolated DB (Docker seed). Destructive CRUD only on `*.test.local` or seeded fixtures.

---

## Success criteria (definition of done)

```
- [ ] Zero console errors on all discovered routes (warnings logged separately)
- [ ] Zero broken routes (no 404/500 on in-app navigation)
- [ ] Zero dead buttons (every [role=button], button, [data-testid*=btn] does something or is disabled-by-design)
- [ ] Zero failing forms (valid submits succeed; invalid show validation)
- [ ] Zero failing API calls during happy-path flows (4xx/5xx tracked)
- [ ] Zero unhandled exceptions (client + server logs clean during crawl)
- [ ] All pages render (no infinite spinners > 30s)
- [ ] Auth flows: login, logout, register, reset (if present) pass
- [ ] CRUD flows pass on test entities
- [ ] Responsive: smoke at 390px, 768px, 1280px without layout break
- [ ] Deliverables written and counts accurate
```

---

## Operating protocol (agent loop)

```
┌─────────────────────────────────────────────────────────────┐
│ LOOP until success criteria OR blocked manual list exhausted   │
├─────────────────────────────────────────────────────────────┤
│ 1. DISCOVER  — static scan: routes, APIs, components, flows │
│ 2. INVENTORY — write discovery.json + TEST_COVERAGE.md draft  │
│ 3. RUN       — Playwright crawl + API smoke + a11y spot-check │
│ 4. CAPTURE   — screenshots, traces, HAR on every failure    │
│ 5. TRIAGE    — classify: auto-fix | manual | env | flake    │
│ 6. FIX       — minimal code change; one issue cluster at a time│
│ 7. RETEST    — affected routes + regression smoke           │
│ 8. REPORT    — update QA_AUDIT_REPORT.md + FIXES_APPLIED.md │
└─────────────────────────────────────────────────────────────┘
```

**Rules:**
- Fix **before** expanding crawl scope when failures block navigation (auth broken → fix first).
- One logical fix per commit when user asked for commits; otherwise batch by area.
- After each fix: rerun **failed test + parent flow + 3 random smoke routes**.
- Max 3 retries on flaky tests; then mark `FLAKE` with mitigation.

---

## Phase 1 — Static discovery (entire codebase)

### 1.1 Routes & pages

| Framework | Discovery command / pattern |
|-----------|----------------------------|
| **Next.js App Router** | Glob `app/**/page.tsx`, `app/**/route.ts`; read `middleware.ts` |
| **Next.js Pages** | `pages/**/*.{tsx,jsx}` minus `_app`, `_document` |
| **React Router** | `createBrowserRouter`, `<Route path=`, `routes.ts` |
| **Remix** | `app/routes/**` |
| **Vue/Nuxt** | `pages/**`, `router/index` |

```bash
# Example inventory (run in project root)
find app -name 'page.tsx' -o -name 'page.jsx' 2>/dev/null | sort
rg -l "export (async )?function (GET|POST|PUT|PATCH|DELETE)" app api src/pages/api
rg "<Link |href=|router\.push|navigate\(" --glob "*.{tsx,jsx,vue}" -c
```

Output → `qa-audit/discovery.json`:

```json
{
  "routes": [{ "path": "/dashboard", "file": "app/dashboard/page.tsx", "auth": true }],
  "apiRoutes": [{ "method": "GET", "path": "/api/users", "file": "app/api/users/route.ts" }],
  "layouts": ["app/layout.tsx", "app/(dashboard)/layout.tsx"],
  "modals": [{ "component": "CreateUserDialog", "file": "components/CreateUserDialog.tsx" }]
}
```

### 1.2 Components, buttons, forms

```bash
rg "<form|FormProvider|useForm" --glob "*.{tsx,jsx}" -l
rg "<button|Button |role=\"button\"|type=\"submit\"" --glob "*.{tsx,jsx}" -c
rg "data-testid=" --glob "*.{tsx,jsx}"
```

Count: pages, components (unique files), buttons (approximate), forms (unique).

### 1.3 User flows (map manually + from product)

| Flow ID | Steps | Priority |
|---------|-------|----------|
| `auth-login` | /login → fill → submit → /dashboard | P0 |
| `auth-register` | /register → … | P0 |
| `auth-logout` | menu → logout → /login | P0 |
| `auth-reset` | /forgot-password → … | P1 |
| `crud-*` | list → create → read → update → delete | P0 per entity |
| `settings` | profile save | P1 |
| `checkout` | cart → pay (mock) | P0 if e-commerce |

### 1.4 APIs

Use `api-smoke-testing` patterns: enumerate routes, seed auth cookie/header, hit each with valid + invalid body.

---

## Phase 2 — Playwright autonomous crawl

### 2.1 Setup (if missing)

Follow `adding-e2e-tests`. Add QA-specific config:

```bash
npm install -D @playwright/test @axe-core/playwright
npx playwright install chromium
mkdir -p qa-audit/{specs,screenshots,traces,reports}
```

Copy from this skill's `scripts/` into project:
- `scripts/qa-audit/playwright.config.ts`
- `scripts/qa-audit/discover-routes.mjs`
- `scripts/qa-audit/crawl.spec.ts`
- `scripts/qa-audit/flows.auth.spec.ts`
- `scripts/qa-audit/flows.crud.spec.ts`

```json
// package.json
{
  "scripts": {
    "qa:discover": "node scripts/qa-audit/discover-routes.mjs",
    "qa:audit": "playwright test -c scripts/qa-audit/playwright.config.ts",
    "qa:audit:ui": "playwright test -c scripts/qa-audit/playwright.config.ts --ui"
  }
}
```

### 2.2 Crawl behavior (every page, every click)

The crawler (`crawl.spec.ts`) must:

1. **Visit every route** in `discovery.json` (respect auth: `storageState` from setup project).
2. **Wait for settle:** `networkidle` or `domcontentloaded` + no pending skeleton > 30s.
3. **Collect clickables:** `button, [role=button], a[href], [data-testid*=btn], summary, [tabindex="0"]`.
4. **Click safely:** skip `target=_blank` external URLs unless allowlisted; skip `mailto:` / `tel:`.
5. **Detect dead buttons:** click → no URL change, no modal, no network activity within 2s → flag `DEAD_BUTTON`.
6. **Open modals:** click triggers with `aria-haspopup`, `data-testid*=modal`, Dialog patterns; close with Escape.
7. **Forms:** run `form-testing` 3-pass (empty / invalid / valid) per discovered form.
8. **Links:** every internal `<a href>` returns < 400 and no crash.
9. **Console:** fail on `error` (filter known benign: favicon, extension).
10. **Network:** fail on 5xx during crawl; log 4xx for triage.
11. **Screenshot:** `qa-audit/screenshots/{route}-{issue}.png` on failure.
12. **Trace:** retain on first retry failure.

### 2.3 Viewports (responsive)

```typescript
const viewports = [
  { name: "mobile", width: 390, height: 844 },
  { name: "tablet", width: 768, height: 1024 },
  { name: "desktop", width: 1280, height: 800 },
];
```

For each **P0 route**, screenshot at 3 sizes; flag horizontal overflow (`document.documentElement.scrollWidth > innerWidth`).

### 2.4 Auth project (Playwright)

```typescript
// scripts/qa-audit/auth.setup.ts
import { test as setup, expect } from "@playwright/test";

setup("authenticate", async ({ page }) => {
  await page.goto("/login");
  await page.getByTestId("email").fill(process.env.QA_USER_EMAIL!);
  await page.getByTestId("password").fill(process.env.QA_USER_PASSWORD!);
  await page.getByRole("button", { name: /sign in/i }).click();
  await expect(page).toHaveURL(/dashboard/);
  await page.context().storageState({ path: "qa-audit/.auth/user.json" });
});
```

### 2.5 CRUD template

```typescript
test("crud: users", async ({ page }) => {
  await page.goto("/users");
  await page.getByRole("button", { name: /create|add/i }).click();
  await page.getByLabel(/name/i).fill(`QA User ${Date.now()}`);
  await page.getByRole("button", { name: /save/i }).click();
  await expect(page.getByText(/created|success/i)).toBeVisible();
  // READ — row visible
  // UPDATE — edit → save
  // DELETE — confirm dialog → row gone
});
```

### 2.6 Role permissions

| Role | Tests |
|------|-------|
| `admin` | Access /admin, destructive actions |
| `user` | Denied /admin → 403 or redirect |
| `guest` | Protected routes → /login |

Run separate `storageState` per role.

---

## Phase 3 — API & database verification

### API (requirement 9)

```typescript
test("api: users CRUD", async ({ request }) => {
  const create = await request.post("/api/users", { data: { name: "QA" } });
  expect(create.status()).toBe(201);
  const id = (await create.json()).id;
  expect((await request.get(`/api/users/${id}`)).status()).toBe(200);
  expect((await request.delete(`/api/users/${id}`)).status()).toBe(204);
});
```

- Validate error shapes: 400 returns `{ message | error }`.
- Idempotency: double POST with same key (if supported).

### Database (requirement 10)

After UI create: verify row via API or test DB query (Prisma/Drizzle):

```typescript
const row = await prisma.user.findFirst({ where: { email: testEmail } });
expect(row).not.toBeNull();
```

After delete: assert `findFirst` null.

### Server logs (requirement 12)

During crawl tail dev server output:

```bash
# If using npm run dev in background, capture log file
npm run dev 2>&1 | tee qa-audit/server.log
rg -i "error|exception|unhandled" qa-audit/server.log
```

---

## Phase 4 — Issue taxonomy & auto-fix playbook

| Code | Detection | Auto-fix strategy |
|------|-----------|-------------------|
| `ROUTE_404` | Navigation 404 | Add route file, fix Link `href`, redirect |
| `ROUTE_500` | Server error | Fix API handler, null guard, env var |
| `DEAD_BUTTON` | No op on click | Wire `onClick`, `href`, or `disabled` + `aria-disabled` |
| `MISSING_HANDLER` | ESLint + no onClick | Implement handler |
| `FORM_VALIDATION` | Invalid pass / valid fail | Fix zod/schema, error display |
| `FORM_SUBMIT` | 4xx/5xx on submit | Fix API + form action |
| `API_ERROR` | Network 5xx | Handler, DB connection, try/catch |
| `CONSOLE_ERROR` | `page.on("console")` | Fix undefined, missing key, hydration |
| `HYDRATION` | React #418/#423 | Client-only wrapper, suppress mismatch source |
| `INFINITE_LOAD` | Spinner > 30s | Fix loading state, error branch, missing await |
| `EMPTY_PAGE` | Main blank | Data fetch, auth guard, suspense fallback |
| `A11Y` | axe critical | Labels, roles, focus trap in modals |
| `PERF` | LCP > 4s on 3G | Lazy load, image size, bundle split |
| `FLAKE` | Intermittent | `expect.poll`, `waitFor`, increase timeout |

**Do not auto-fix without understanding:** payment, prod migrations, security policy — mark `MANUAL`.

---

## Phase 5 — Deliverables (required files)

Generate in **project root** (update after each fix loop):

### `QA_AUDIT_REPORT.md`

Use template: `templates/QA_AUDIT_REPORT.md` in this skill folder.

Must include:
- Executive summary (pass/fail)
- Counts: pages, components, buttons, forms, APIs
- Issues found / fixed / manual / warnings
- Per-issue: severity, route, screenshot path, steps, status
- Performance & a11y recommendations
- Remaining warnings (non-blocking)

### `FIXES_APPLIED.md`

Chronological log:

```markdown
## Fix 001 — DEAD_BUTTON on /settings
- **File:** components/SettingsForm.tsx
- **Change:** Added onSubmit handler wired to PATCH /api/settings
- **Retest:** crawl /settings, form-testing pass 3 — PASS
```

### `TEST_COVERAGE.md`

Matrix:

| Route / Flow | Desktop | Mobile | Auth | CRUD | Forms | APIs | Status |
|--------------|---------|--------|------|------|-------|------|--------|
| /dashboard | ✅ | ✅ | user | — | — | ✅ | PASS |

Include **% coverage** = tested routes / discovered routes.

---

## Phase 6 — Browser MCP fallback (no Playwright yet)

If Playwright not installed, use **cursor-ide-browser** MCP with same checklist:

1. `browser_navigate` each route
2. `browser_snapshot` → inventory clickables
3. `browser_click` / `browser_fill` per `form-testing`
4. `browser_console_messages` + network from CDP
5. `browser_take_screenshot` on failure

Then **install Playwright** and codify as repeatable `qa:audit` script.

---

## Playwright config essentials

```typescript
// scripts/qa-audit/playwright.config.ts
import { defineConfig, devices } from "@playwright/test";

export default defineConfig({
  testDir: "./scripts/qa-audit",
  fullyParallel: false, // crawl order-sensitive
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 1,
  workers: 1,
  reporter: [
    ["list"],
    ["html", { outputFolder: "qa-audit/reports/html" }],
    ["json", { outputFile: "qa-audit/reports/results.json" }],
  ],
  use: {
    baseURL: process.env.QA_BASE_URL ?? "http://localhost:3000",
    trace: "on-first-retry",
    screenshot: "only-on-failure",
    video: "retain-on-failure",
  },
  projects: [
    { name: "setup", testMatch: /auth\.setup\.ts/ },
    {
      name: "crawl",
      dependencies: ["setup"],
      use: { ...devices["Desktop Chrome"], storageState: "qa-audit/.auth/user.json" },
    },
    { name: "api", testMatch: /api\./ },
    { name: "mobile", use: { ...devices["iPhone 13"] }, dependencies: ["setup"] },
  ],
  webServer: {
    command: "npm run dev",
    url: process.env.QA_BASE_URL ?? "http://localhost:3000",
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
  },
});
```

---

## Crawler core (click every safe element)

```typescript
// scripts/qa-audit/crawl.spec.ts — simplified pattern
import { test, expect } from "@playwright/test";
import discovery from "../../qa-audit/discovery.json";

for (const route of discovery.routes) {
  test(`crawl: ${route.path}`, async ({ page }) => {
    const errors: string[] = [];
    page.on("console", (msg) => {
      if (msg.type() === "error") errors.push(msg.text());
    });
    page.on("response", (res) => {
      if (res.status() >= 500) errors.push(`5xx ${res.url()} ${res.status()}`);
    });

    await page.goto(route.path, { waitUntil: "domcontentloaded" });
    await expect(page.locator("body")).toBeVisible({ timeout: 30_000 });

    const clickables = page.locator(
      'button:visible, [role="button"]:visible, a[href^="/"]:visible'
    );
    const count = await clickables.count();
    for (let i = 0; i < Math.min(count, 50); i++) {
      const el = clickables.nth(i);
      const label = (await el.innerText().catch(() => "")) || (await el.getAttribute("aria-label")) || `#${i}`;
      if (/delete|remove|drop/i.test(label) && process.env.QA_ALLOW_DESTRUCTIVE !== "1") continue;
      const before = page.url();
      await el.click({ timeout: 5000 }).catch(() => {});
      await page.waitForTimeout(500);
      if (page.url() === before && !(await page.locator("[role=dialog]").isVisible().catch(() => false))) {
        // potential dead button — verify network
      }
    }
    expect(errors, `Console/network errors on ${route.path}`).toEqual([]);
  });
}
```

---

## Environment variables

| Var | Purpose |
|-----|---------|
| `QA_BASE_URL` | Target app URL |
| `QA_USER_EMAIL` / `QA_USER_PASSWORD` | Test user |
| `QA_ADMIN_EMAIL` / `QA_ADMIN_PASSWORD` | Admin role tests |
| `QA_ALLOW_DESTRUCTIVE` | `1` to allow delete clicks in crawl |
| `DATABASE_URL` | Test DB for persistence checks |

---

## CI integration

```yaml
# .github/workflows/qa-audit.yml
name: QA Audit
on: workflow_dispatch
jobs:
  audit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
      - run: npm ci && npx playwright install --with-deps chromium
      - run: npm run qa:discover && npm run qa:audit
        env:
          QA_USER_EMAIL: ${{ secrets.QA_USER_EMAIL }}
          QA_USER_PASSWORD: ${{ secrets.QA_USER_PASSWORD }}
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: qa-audit
          path: |
            qa-audit/reports/
            qa-audit/screenshots/
            QA_AUDIT_REPORT.md
```

---

## Anti-patterns

- Report-only audit with no fixes
- Clicking "Delete production" on real prod
- Treating 3rd-party script console noise as app bugs without filtering
- Infinite crawl on public internet links
- Skipping auth setup → false "all routes 404"
- One giant 2-hour test with no sharding
- Ignoring flakes → marking PASS without retry policy

---

## Agent checklist

```
- [ ] discovery.json created with routes, APIs, flows
- [ ] Playwright qa:audit runs (or MCP fallback documented)
- [ ] Every P0 route crawled; forms 3-pass; auth + CRUD verified
- [ ] Console 0 errors; network 0 5xx on happy paths
- [ ] Screenshots for all failures
- [ ] Fixes applied with retest notes
- [ ] QA_AUDIT_REPORT.md + FIXES_APPLIED.md + TEST_COVERAGE.md committed
- [ ] Success criteria re-evaluated — pass or explicit MANUAL list
```

---

## Related skills

| Skill | Role |
|-------|------|
| `adding-e2e-tests` | Initial Playwright setup |
| `form-testing` | Form 3-pass methodology |
| `api-smoke-testing` | API route discovery + smoke |
| `anthropic-webapp-testing` | Browser scripting patterns |
| `browser-automation-master` | Visual QA, network audit |
| `parallel-test-fixing` | Many failing spec files |
| `code-quality-master` | a11y/perf deep dives |

## References

- Playwright: https://playwright.dev/docs/intro
- @axe-core/playwright: https://github.com/dequelabs/axe-core-npm
- Testing best practices: `cursor-skills-testing`
