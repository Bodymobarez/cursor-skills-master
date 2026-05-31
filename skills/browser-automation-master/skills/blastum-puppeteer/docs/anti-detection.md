# Anti-Detection

For personal, targeted page access. Not designed for bulk or commercial scraping.

## What's already handled by stealth plugin

`puppeteer-extra-plugin-stealth` patches these automatically:
- `navigator.webdriver` flag (fingerprint tell)
- Chrome runtime properties that reveal automation
- Plugin and language arrays (consistent with real browser)
- WebGL and canvas fingerprinting

No extra code needed once registered (see setup.md).

## User-agent

```js
// Set a realistic, current desktop UA
await page.setUserAgent(
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) ' +
  'AppleWebKit/537.36 (KHTML, like Gecko) ' +
  'Chrome/121.0.0.0 Safari/537.36'
);
```

Update the UA string as Chrome releases new major versions.

## Robots.txt

Check before every request — see `robotsAllows()` in `src/setup.js`.

| Situation | Approach |
|-----------|----------|
| Personal research, page allows | Proceed |
| Personal research, page disallows | Log and skip; find alternative source |
| CAPTCHAs on allowed page | See below |

## CAPTCHA handling

For simple CAPTCHAs on pages you're entitled to access:

```bash
npm install puppeteer-extra-plugin-recaptcha
```

```js
import RecaptchaPlugin from 'puppeteer-extra-plugin-recaptcha';

puppeteer.use(RecaptchaPlugin({
  provider: {
    id: '2captcha',
    token: process.env.CAPTCHA_API_KEY,
  },
  visualFeedback: false,
}));

// After navigation, solve any found CAPTCHAs
const { solved } = await page.solveRecaptchas();
```

> Requires a paid 2captcha account. Only worth it for occasional access to pages you have legitimate reason to visit.

## Manual (interactive) CAPTCHA solving

If you just want the page for personal research, the most reliable approach is running
in a visible browser and solving the challenge yourself (cookies persist via `userDataDir`):

```js
import { acquirePage } from "../src/acquire.js";

const doc = await acquirePage("https://example.com/", {
  respectRobots: true,
  interactive: true,
  launchOptions: { headless: false, userDataDir: "tmp/puppeteer-user-data" }
});
```

## Avoiding rate-limit detection

- Always use `delayMs` between requests in batch acquisition (see acquire.md)
- Don't parallelize requests to the same domain
- If blocked (403/429): back off, wait 5–10 minutes, retry once
- Don't retry repeatedly — respect the signal

## If site requires login

```js
// Manual: navigate to login, fill form, then continue
await page.goto('https://example.com/login');
await page.type('#username', process.env.SITE_USER);
await page.type('#password', process.env.SITE_PASS);
await page.click('button[type=submit]');
await page.waitForNavigation();
// Now navigate to target page — session persists in browser instance
```
