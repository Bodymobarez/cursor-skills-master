# Testing

Run this when user says: **"test the skill"**.

## One command

From the skill root folder:

```bash
bash scripts/test-skill.sh
```

What it does:
- verifies `node` and `npm`
- installs dependencies if missing (`npm ci` when lockfile exists, else `npm install`)
- runs automated tests via `npm run test:skill`
- runs `npm audit --omit=dev` in non-blocking mode (set `SKIP_AUDIT=1` to skip)

## Test coverage

`scripts/run-tests.mjs` validates:
- dependency/module load (`puppeteer-extra`, stealth, `@ghostery/adblocker-puppeteer`)
- robots parsing and allow/disallow behavior
- browser launch + basic navigation smoke test
- optional live extraction-quality smoke test (off by default)

## Robots targets used

These are deterministic public test endpoints:

- robots file: `https://httpbin.org/robots.txt`
- allowed path: `https://httpbin.org/get`
- disallowed path: `https://httpbin.org/deny`

`httpbin` publishes:

```txt
User-agent: *
Disallow: /deny
```

So the test can assert both allowed and blocked outcomes.

## Expected output

On success:
- `PASS deps/plugins ...`
- `PASS robots ...`
- `PASS browser ...`
- `PASS live ...` (only if enabled)
- `PASS all tests (...)`

On failure:
- `FAIL: <reason>`
- non-zero exit code

## Optional live quality test (recommended when tuning extraction)

This hits a real site, so it's opt-in:

```bash
LIVE_TEST=1 bash scripts/test-skill.sh
```

Or specify your own URL:

```bash
LIVE_TEST_URL="https://example.com/some/page" LIVE_TEST=1 bash scripts/test-skill.sh
```

## Optional quick checks

If you only want robots behavior:

```bash
node -e "fetch('https://httpbin.org/robots.txt').then(r=>r.text()).then(console.log)"
```

If you only want browser launch:

```bash
node -e "import('puppeteer').then(async m=>{const b=await m.default.launch({headless:true,args:['--no-sandbox']});await b.close();console.log('ok')})"
```
