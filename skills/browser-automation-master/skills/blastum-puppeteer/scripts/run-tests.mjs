import { PuppeteerBlocker } from "@ghostery/adblocker-puppeteer";
import { acquirePage } from "../src/acquire.js";
import { extractContent } from "../src/extraction.js";
import { openBrowser, newPage, robotsAllows } from "../src/setup.js";

const TEST_URLS = {
  smoke: "https://example.com/",
  robotsFile: "https://httpbin.org/robots.txt",
  robotsAllowed: "https://httpbin.org/get",
  robotsDisallowed: "https://httpbin.org/deny",
  liveDefault: "https://www.americancruiselines.com/cruises/mississippi-river-cruises/highlights-of-the-mississippi-cruise"
};

function ok(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

async function testDependenciesAndPlugins() {
  ok(typeof PuppeteerBlocker.fromPrebuiltAdsAndTracking === "function", "Ghostery blocker API missing");
  ok(typeof openBrowser === "function", "openBrowser missing");
  ok(typeof newPage === "function", "newPage missing");
  ok(typeof robotsAllows === "function", "robotsAllows missing");
  ok(typeof extractContent === "function", "extractContent missing");
  ok(typeof acquirePage === "function", "acquirePage missing");
  console.log("PASS deps/modules: src + ghostery adblock loaded");
}

async function testBrowserLaunchAndNavigation() {
  const browser = await openBrowser();

  try {
    const page = await newPage(browser, { adblock: true });
    await page.goto(TEST_URLS.smoke, { waitUntil: "domcontentloaded", timeout: 30000 });
    const title = await page.title();
    ok(title.toLowerCase().includes("example"), "Expected example.com title");
    console.log("PASS browser: launch + navigation smoke test");
  } finally {
    await browser.close();
  }
}

async function testRobotsRules() {
  // Validate our robots helper using deterministic httpbin rules.
  const allowed = await robotsAllows(TEST_URLS.robotsAllowed, { userAgent: "puppeteer-skill-test" });
  const disallowed = await robotsAllows(TEST_URLS.robotsDisallowed, { userAgent: "puppeteer-skill-test" });
  ok(allowed === true, "Expected /get to be allowed by httpbin robots.txt");
  ok(disallowed === false, "Expected /deny to be disallowed by httpbin robots.txt");
  console.log("PASS robots: allow/disallow behavior validated");
}

async function testLiveExtractionQuality() {
  const liveEnabled = process.env.LIVE_TEST === "1" || Boolean(process.env.LIVE_TEST_URL);
  if (!liveEnabled) {
    console.log("SKIP live: set LIVE_TEST=1 (or LIVE_TEST_URL=...) to enable");
    return;
  }

  const target = process.env.LIVE_TEST_URL || TEST_URLS.liveDefault;
  const isAllowed = await robotsAllows(target, { userAgent: "puppeteer-skill-test" });

  if (!isAllowed) {
    console.log(`SKIP live: robots.txt disallows ${target}`);
    return;
  }

  const browser = await openBrowser();

  try {
    const page = await newPage(browser, { adblock: true });

    await page.goto(target, { waitUntil: "domcontentloaded", timeout: 45000 });
    await page.waitForSelector("h1", { timeout: 15000 });

    const title = await page.title();
    const h1 = await page.$eval("h1", (el) => el.textContent?.trim() || "");
    const { text } = await extractContent(page);

    ok(title.length > 0, "Live page title should be non-empty");
    ok(h1.length > 0, "Live page H1 should be non-empty");
    ok(text.length > 500, "Live extracted text looks too small");

    // Basic quality checks (avoid obvious UI junk seen in the wild).
    ok(!text.includes("GO TO SLIDE"), "Live extraction still contains carousel junk");
    ok(!text.includes("Skip to Main Content"), "Live extraction still contains header junk");
    ok(text.toLowerCase().includes(h1.toLowerCase()), "Live extraction should include H1 text");

    console.log("PASS live: extraction quality smoke test");
  } finally {
    await browser.close();
  }
}

async function main() {
  const start = Date.now();
  await testDependenciesAndPlugins();
  await testRobotsRules();
  await testBrowserLaunchAndNavigation();
  await testLiveExtractionQuality();
  const elapsed = ((Date.now() - start) / 1000).toFixed(1);
  console.log(`PASS all tests (${elapsed}s)`);
}

main().catch((err) => {
  console.error("FAIL:", err.message);
  process.exit(1);
});
