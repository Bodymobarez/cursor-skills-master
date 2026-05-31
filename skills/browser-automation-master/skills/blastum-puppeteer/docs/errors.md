# Errors

## Common failures and responses

| Error | Likely cause | Response |
|-------|-------------|----------|
| `TimeoutError` | Page slow/hung | Increase timeout or try `domcontentloaded` waitUntil |
| `net::ERR_NAME_NOT_RESOLVED` | Bad URL or DNS | Validate URL before launch |
| `net::ERR_CONNECTION_REFUSED` | Site down | Skip, log, don't retry |
| HTTP 403/429 | Rate limited or blocked | Back off, don't retry immediately |
| `detached Frame` | Page navigated mid-extract | Wrap extraction in try/catch |
| Blank `page.evaluate()` result | DOM not ready | Add explicit `waitForSelector` |

## Retry wrapper

```js
import { withRetry } from '../src/errors.js';
```

Usage:

```js
const result = await withRetry(() => acquirePage(url), { maxAttempts: 3 });
```

## Fallback to basic HTTP fetch

When puppeteer fails entirely and content doesn't require JS rendering:

```js
import { fallbackFetch } from '../src/errors.js';
```

## Cleanup on failure

Always close the browser in a `finally` block to avoid orphaned Chromium processes:

```js
const browser = await openBrowser();
try {
  // ... work
} catch (err) {
  console.error(`Failed: ${url}`, err.message);
  return null;   // return null, don't re-throw, let caller decide
} finally {
  await browser.close();
}
```

## Logging format

```js
function logResult(url, status, detail = '') {
  const ts = new Date().toISOString().slice(0, 19);
  console.log(`[${ts}] ${status.padEnd(7)} ${url}${detail ? ' — ' + detail : ''}`);
}

// Usage
logResult(url, 'OK', `${content.text.length} chars`);
logResult(url, 'SKIP', 'robots.txt disallow');
logResult(url, 'FAIL', err.message);
```
