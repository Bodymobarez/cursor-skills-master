# Acquire

Fetch a web page and return clean content for the notebook skill's acquire workflow.

## Core function

```js
import { acquirePage } from '../src/acquire.js';

const url = 'https://example.com/';
const doc = await acquirePage(url, { respectRobots: true });
console.log(doc?.title);
```

## Notebook skill integration

Call `acquirePage()` from the notebook acquire workflow when source type is `web`:

```js
// In notebook acquire.js
import { acquirePage } from '../skills/puppeteer/src/acquire.js';

const result = await acquirePage(url, { respectRobots: true });
if (result) {
  // Save to notebook/documents/{slug}.md
  await saveDocument(slug, result.text, {
    title: result.title,
    url,
    acquired: result.timestamp,
    type: 'web',
  });
}
```

## Batch acquisition

```js
import { acquirePages } from '../src/acquire.js';
const results = await acquirePages(urls, { delayMs: 5000, respectRobots: true });
```

> Delay between requests is essential for targeted personal scraping — 2s minimum, 5s+ for cautious operation.

## Output format

```js
{
  title: "Page title from document.title",
  text: "Clean extracted text content...",
  links: [{ text: "Link text", href: "https://..." }],
  url: "https://source.example.com/page",
  timestamp: "2026-02-22T10:30:00.000Z"
}
```
