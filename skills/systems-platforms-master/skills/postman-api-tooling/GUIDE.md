---
name: postman-api-tooling
description: >-
  Professional Postman + Newman at staff depth (2026): collections as version-controlled API contracts,
  environment/variable scopes, pre-request & test scripts (pm.* API), auth helpers, mock servers,
  monitors, OpenAPI import, and Newman in CI with real GitHub Actions YAML (junit + htmlextra, --bail).
  Use to build a maintainable API test suite that runs in the pipeline, not just in the GUI.
---

# Postman + Newman — API Tooling (collections that gate your CI)

**Mandate:** A Postman collection is **executable API documentation and a regression suite** — author it with
variables (never hardcoded URLs/tokens), assert real `pm.test` checks, chain requests via collection
variables, then run it headless with **Newman in CI** so a contract break fails the build. If it only runs
when a human clicks "Send", it's a toy.

## When to use / when NOT to use
- **Use** to design/test/document REST & GraphQL APIs, build smoke + contract + e2e API suites, mock
  endpoints before the backend exists, monitor prod uptime/correctness, and gate merges on API tests in CI.
- **NOT** as your unit-test framework (keep logic tests in Jest/Vitest/pytest), for heavy load testing (use
  k6/Gatling/Artillery), or for browser/UI flows (→ `testing-master`/Playwright). Postman tests the **API
  contract**, not internal units.

## Mental model
Hierarchy of variable **scopes**, narrowest wins: **Local (data file)** → **Data (iteration)** → **Environment**
→ **Collection** → **Global**. URLs, tokens, and IDs are **variables**; the same collection runs against
local/staging/prod by swapping the **environment**. Requests chain by writing variables in one request's test
script and reading them in the next (`{{authToken}}`, `{{userId}}`). The collection is a JSON file you
**commit to git** and run with Newman anywhere.

---

## 1. Structure: collection + environments (commit them)

```
api-tests/
  collection.json            # exported collection (folders = features, requests = endpoints)
  env.local.json             # baseUrl=http://localhost:3000 ...
  env.staging.json           # baseUrl=https://staging.api.example.com ...
  env.production.json        # baseUrl=https://api.example.com (read-only smoke only)
  data/users.csv             # iteration data for data-driven runs
```

```jsonc
// env.staging.json — secrets stay OUT of git; inject at run time via --env-var or CI secrets
{
  "name": "staging",
  "values": [
    { "key": "baseUrl", "value": "https://staging.api.example.com", "enabled": true },
    { "key": "authToken", "value": "", "enabled": true }      // filled by the login request at runtime
  ]
}
```
Reference everywhere with `{{baseUrl}}/v1/users`. **Never** bake a token or host into a request URL — that's
the difference between a reusable suite and a throwaway.

---

## 2. The `pm.*` API — pre-request & test scripts (where the power is)

```js
// PRE-REQUEST SCRIPT on a folder/collection: get a token ONCE and reuse it (auth chaining)
const tokenExpired = !pm.collectionVariables.get("authToken")
  || Date.now() > Number(pm.collectionVariables.get("authTokenExp") || 0);

if (tokenExpired) {
  pm.sendRequest({
    url: `${pm.environment.get("baseUrl")}/v1/auth/login`,
    method: "POST",
    header: { "Content-Type": "application/json" },
    body: { mode: "raw", raw: JSON.stringify({
      email: pm.environment.get("testEmail"), password: pm.environment.get("testPassword") }) },
  }, (err, res) => {
    if (err) throw err;
    const json = res.json();
    pm.collectionVariables.set("authToken", json.access_token);
    pm.collectionVariables.set("authTokenExp", Date.now() + json.expires_in * 1000);
  });
}
```

```js
// TEST SCRIPT on a "Create user" request: assert the contract + capture the id for later requests
pm.test("status is 201", () => pm.response.to.have.status(201));
pm.test("responds < 800ms", () => pm.expect(pm.response.responseTime).to.be.below(800));
pm.test("content-type json", () =>
  pm.expect(pm.response.headers.get("Content-Type")).to.include("application/json"));

const body = pm.response.json();
pm.test("body shape", () => {
  pm.expect(body).to.have.property("id").that.is.a("string");
  pm.expect(body.email).to.eql(pm.iterationData.get("email") ?? pm.environment.get("testEmail"));
});

// JSON Schema validation = real contract testing (ajv is built into the sandbox)
const schema = {
  type: "object",
  required: ["id", "email", "createdAt"],
  properties: { id: { type: "string" }, email: { type: "string", format: "email" },
    createdAt: { type: "string" } },
};
pm.test("matches schema", () => pm.response.to.have.jsonSchema(schema));

pm.collectionVariables.set("userId", body.id);   // chain into GET/PATCH/DELETE /users/{{userId}}
```

Key `pm.*` surface: `pm.response` (`.status/.code/.json()/.responseTime/.headers`), `pm.expect` (Chai),
`pm.test(name, fn)`, `pm.environment`/`pm.collectionVariables`/`pm.globals`/`pm.iterationData`/`pm.variables`
(get/set/unset), `pm.sendRequest()` (helper calls), `pm.execution.setNextRequest("name")` (control flow in
the runner). Set the request's **Authorization** to Bearer `{{authToken}}` so the token flows automatically.

---

## 3. Auth helpers
- Use the **Authorization tab** (collection-level, inherited by requests): Bearer Token `{{authToken}}`,
  Basic, API Key, **OAuth 2.0** (Postman can run the auth-code/client-credentials flow and store the token).
- For machine flows, the pre-request login pattern above is the most portable (works identically in Newman).
- Keep credentials in **environment variables / CI secrets**, never in the committed collection.

## 4. Mock servers (build the client before the backend)
- Create a mock from the collection; saved **example responses** become the mock's responses (match by
  path + optional `x-mock-response-name`/status). Front-end and contract tests run against
  `https://<mock-id>.mock.pstmn.io` while the real API is still being built.
- Drive different scenarios by selecting examples (200/404/500) — great for testing client error handling.

## 5. Monitors (scheduled prod checks)
- A **monitor** runs a collection on a schedule (e.g. every 5 min) from Postman's cloud, against an
  environment, with alerting on failures. Use it for uptime + correctness smoke tests on production. For
  CI-owned scheduling, prefer Newman on a cron in your pipeline (you control secrets + artifacts).

## 6. OpenAPI import (spec ↔ collection)
- **Import** an OpenAPI 3.x / Swagger spec → Postman generates a collection (and can keep them in sync via
  an **API definition**). This bootstraps tests from the contract and catches drift between spec and reality.
- Reverse: generate/maintain the collection from the spec so docs, mocks, and tests share one source.

---

## 7. Newman in CI — the part that actually gates merges

```bash
npm i -g newman newman-reporter-htmlextra
# Reporters: comma-separated, NO SPACES. cli stays on only if you list it explicitly alongside others.
newman run collection.json \
  -e env.staging.json \
  --env-var "authToken=$STAGING_TOKEN" \        # inject secrets at runtime, not from the file
  -d data/users.csv -n 3 \                        # data-driven: 3 iterations over the CSV
  -r cli,junit,htmlextra \
  --reporter-junit-export reports/junit.xml \
  --reporter-htmlextra-export reports/report.html \
  --bail \                                        # stop at first failure (fail fast in CI)
  --timeout-request 10000
# Newman exits non-zero on any failed assertion → the CI step fails. That's the point.
```

```yaml
# .github/workflows/api-tests.yml — real, copy-paste pipeline gate
name: API Tests
on:
  pull_request:
  push: { branches: [main] }
  schedule: [ { cron: "0 6 * * *" } ]   # daily prod smoke
jobs:
  newman:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: "20" }
      - run: npm i -g newman newman-reporter-htmlextra
      - run: mkdir -p reports
      - name: Run Newman
        run: |
          newman run api-tests/collection.json \
            -e api-tests/env.${{ github.ref_name == 'main' && 'production' || 'staging' }}.json \
            --env-var "authToken=${{ secrets.API_TOKEN }}" \
            -r cli,junit,htmlextra \
            --reporter-junit-export reports/junit.xml \
            --reporter-htmlextra-export reports/report.html \
            --bail
      - name: Upload report
        if: always()                              # publish artifacts even when tests fail
        uses: actions/upload-artifact@v4
        with: { name: newman-report, path: reports/ }
      - name: Publish JUnit
        if: always()
        uses: dorny/test-reporter@v1
        with: { name: API Tests, path: reports/junit.xml, reporter: java-junit }
```

```js
// Programmatic Newman (custom orchestration / monorepo runner)
const newman = require("newman");
newman.run({
  collection: require("./collection.json"),
  environment: require("./env.staging.json"),
  reporters: ["cli", "junit"],
  reporter: { junit: { export: "reports/junit.xml" } },
  bail: true,
}, (err, summary) => {
  if (err || summary.run.failures.length) process.exit(1);  // make CI fail on assertion failures
});
```

Built-in reporters: `cli`, `json`, `junit`, `progress`, `emojitrain` (+ community `htmlextra`). Use **junit**
for CI test panels, **htmlextra** for human-readable artifacts. Keep collections in git and run Newman on
every PR (smoke against staging) and on a schedule (against prod).

---

## Edge cases & war stories
- **Spaces in `-r`.** `-r cli, json` silently misbehaves; it must be `-r cli,json,junit` (no spaces).
- **`pm.execution.skipRequest()` differs in Newman.** Some newer GUI-only helpers aren't fully implemented in
  Newman → the runner errors. Gate behavior on an env var (`runner=newman`) instead of GUI-only APIs.
- **CLI output disappears** when you add reporters. Enabling other reporters drops the default `cli` output —
  list `cli` explicitly to keep it.
- **Token expiry mid-run.** Long runs fail late when the captured token expires. Refresh on a collection
  pre-request with an expiry check (pattern above), not once at the start.
- **Order-dependent collections.** A request that needs `{{userId}}` runs before the request that sets it.
  Order folders/requests deliberately; the runner executes top-to-bottom (or use `setNextRequest`).
- **Secrets committed in the environment file.** Export strips current values for secret-type vars, but
  people paste tokens in. Keep tokens out of git; inject via `--env-var`/CI secrets.
- **Flaky timeouts** in CI. Set `--timeout-request`; assert `responseTime` so latency regressions are caught,
  not just hard failures.

## Performance
- Reuse one token (pre-request refresh) instead of logging in per request. Use `-n`/`-d` for data-driven
  coverage without duplicating requests. Run independent collections in parallel CI jobs. Keep assertions
  focused (status + schema + key fields) rather than asserting every byte.

## Security
- No secrets in committed collections/environments; inject via `--env-var` or CI secrets. Use a dedicated
  **test account** with least privilege, never a prod admin. Scope prod monitors/smoke to **read-only**
  endpoints. Rotate the test token. Redact tokens from logs/reports (don't log `pm.response` wholesale).

## Scale & reliability
- Split a giant collection into per-feature collections + a smoke suite; gate PRs on smoke, run the full
  suite nightly. Tag/organize by folder. Use Postman **API definitions** to keep spec ↔ tests in sync at scale.

## Testing (meta)
- The collection *is* the test. Cover happy path + each documented error (400/401/403/404/409/422). Validate
  **JSON schema** (real contract test), not just status codes. Assert pagination, idempotency, and rate-limit
  headers where the API defines them.

## Observability
- junit → CI test reporter; htmlextra → artifact. Monitors/Newman-cron alert to Slack/email on failure.
  Track pass rate and p95 `responseTime` trend across runs to catch slow regressions.

## Cost notes
- Newman is free/OSS — run it anywhere. Postman cloud **mock servers + monitors** consume plan quotas
  (calls/runs per month); for heavy automation, prefer Newman in your own CI (free) and reserve cloud
  monitors for prod uptime.

## Anti-patterns
- Hardcoded URLs/tokens instead of `{{variables}}` + environments.
- Tests that only check `status 200` and never validate the body/schema.
- Running only in the GUI; no Newman in CI (so contract breaks reach prod).
- Secrets committed in the collection/environment JSON.
- One mega-collection with hidden ordering dependencies and no folders.
- Logging full responses/tokens into CI artifacts.

## Agent checklist
```
- [ ] Collection + per-env files committed to git; all URLs/tokens are {{variables}}
- [ ] Auth via collection Authorization (Bearer {{authToken}}) + pre-request refresh w/ expiry check
- [ ] Tests assert status + responseTime + JSON schema + key fields (real contract checks)
- [ ] Request chaining via pm.collectionVariables (set id → reuse downstream)
- [ ] Newman in CI: -r cli,junit,htmlextra (no spaces), --bail, secrets via --env-var/CI secrets
- [ ] junit published to CI test panel; htmlextra uploaded as artifact (if: always())
- [ ] PR runs smoke vs staging; scheduled run vs prod (read-only)
- [ ] Dedicated least-privilege test account; tokens rotated; not in git
- [ ] Error cases (4xx/409/422) covered, not just happy path
```

## References (2026-current)
- Newman (CLI + reporters): https://github.com/postmanlabs/newman
- Scripting / `pm.*` reference: https://learning.postman.com/docs/tests-and-scripts/write-scripts/postman-sandbox-api-reference/
- Variables & scopes: https://learning.postman.com/docs/sending-requests/variables/
- Mock servers: https://learning.postman.com/docs/design-apis/mock-apis/overview/ · Monitors: https://learning.postman.com/docs/monitoring-your-api/intro-monitors/
- OpenAPI import: https://learning.postman.com/docs/integrations/available-integrations/working-with-openAPI/

## Related
`systems-platforms-foundation` (this hub) · `backend-api-master` (API/auth design), `testing-master`
(test strategy), `git-workflow-master` (CI), `integrations-master` (webhooks/3rd-party APIs).
