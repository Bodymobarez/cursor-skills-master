# Extraction

Pull clean, readable content from a loaded Puppeteer page.

## Core extraction function

```js
import { extractContent } from '../src/extraction.js';

const { title, h1, h2s, text } = await extractContent(page);
console.log(title, h1, h2s.slice(0, 3), text.slice(0, 200));
```

Canonical implementation: `src/extraction.js` (used by both acquire and tests).

## Waiting for dynamic content

JavaScript-rendered pages need explicit waits before extraction:

```js
// Wait for a specific element to appear
await page.waitForSelector('article.main-content', { timeout: 10_000 });

// Wait for network to settle (for SPAs)
await page.waitForNetworkIdle({ idleTime: 1000 });

// Wait for arbitrary condition
await page.waitForFunction(
  () => document.querySelector('.results')?.children.length > 0,
  { timeout: 15_000 }
);
```

## Targeted extraction (specific pages)

When you know the site's structure:

```js
export async function extractArticle(page, selectors = {}) {
  const {
    title = 'h1',
    body = 'article, main, .content, .post-body',
    date = 'time, .date, .published',
  } = selectors;

  return page.evaluate(({ title, body, date }) => {
    const get = (sel) => document.querySelector(sel)?.innerText?.trim() ?? '';
    const getAttr = (sel, attr) => document.querySelector(sel)?.getAttribute(attr) ?? '';

    return {
      title: get(title),
      text: get(body),
      date: getAttr(date, 'datetime') || get(date),
    };
  }, { title, body, date });
}
```

## PDF snapshot

```js
// Save full-page PDF for archival alongside extracted text
export async function savePdf(page, outputPath) {
  await page.pdf({
    path: outputPath,
    format: 'A4',
    printBackground: true,
  });
}
```

## Screenshot

```js
export async function saveScreenshot(page, outputPath) {
  await page.screenshot({ path: outputPath, fullPage: true });
}
```

## Cleaning extracted text for notebook documents

```js
import { cleanText } from '../src/extraction.js';
```
