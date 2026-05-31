# Setup

## Installation

```bash
npm install puppeteer puppeteer-extra
npm install puppeteer-extra-plugin-stealth
npm install @ghostery/adblocker-puppeteer
# Optional
npm install puppeteer-extra-plugin-recaptcha
```

> puppeteer downloads Chromium on install (~170MB). Pin the version if build reproducibility matters.

## Base configuration

```js
// Canonical implementation lives in src/.
import { openBrowser, newPage, robotsAllows } from '../src/setup.js';

const browser = await openBrowser();
const page = await newPage(browser, { adblock: true });
console.log(await robotsAllows('https://example.com/'));
```

See `src/setup.js` for the full implementations.

## Environment notes

- Node.js 18+ required
- macOS: no extra deps for Chromium
- Linux: may need `libnss3`, `libxss1`, `libasound2`
- CI/Docker: add `--no-sandbox` flag (included above)
