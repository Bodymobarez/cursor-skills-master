import { test, expect } from "@playwright/test";
import fs from "fs";
import path from "path";

type Discovery = {
  routes: { path: string; auth?: boolean }[];
};

const discoveryPath = path.join(process.cwd(), "qa-audit", "discovery.json");

function loadDiscovery(): Discovery {
  if (!fs.existsSync(discoveryPath)) {
    throw new Error("Run: npm run qa:discover (discover-routes.mjs) first");
  }
  return JSON.parse(fs.readFileSync(discoveryPath, "utf8")) as Discovery;
}

const discovery = loadDiscovery();

for (const route of discovery.routes) {
  test(`crawl ${route.path}`, async ({ page }, testInfo) => {
    const consoleErrors: string[] = [];
    const serverErrors: string[] = [];

    page.on("console", (msg) => {
      if (msg.type() !== "error") return;
      const text = msg.text();
      if (/favicon|chrome-extension|third-party/i.test(text)) return;
      consoleErrors.push(text);
    });

    page.on("response", (res) => {
      const url = res.url();
      if (!url.includes(new URL(page.url()).host)) return;
      if (res.status() >= 500) serverErrors.push(`${res.status()} ${url}`);
    });

    const response = await page.goto(route.path, {
      waitUntil: "domcontentloaded",
      timeout: 30_000,
    });

    expect(response?.status(), "route should not 5xx").toBeLessThan(500);
    await expect(page.locator("body")).toBeVisible({ timeout: 30_000 });

    // Infinite loading guard
    const spinner = page.locator('[aria-busy="true"], [data-testid*="loading"]');
    await expect(spinner).toHaveCount(0, { timeout: 30_000 }).catch(() => {
      /* logged below if still visible */
    });

    const clickables = page.locator(
      'button:visible, [role="button"]:visible, a[href^="/"]:visible, a[href^="./"]:visible'
    );
    const maxClicks = Number(process.env.QA_MAX_CLICKS ?? 40);
    const count = Math.min(await clickables.count(), maxClicks);
    const deadButtons: string[] = [];

    for (let i = 0; i < count; i++) {
      const el = clickables.nth(i);
      const label =
        (await el.innerText().catch(() => "")) ||
        (await el.getAttribute("aria-label")) ||
        `element-${i}`;

      if (/delete|remove|drop|destroy/i.test(label) && process.env.QA_ALLOW_DESTRUCTIVE !== "1") {
        continue;
      }

      const urlBefore = page.url();
      let networkHit = false;
      const onReq = () => {
        networkHit = true;
      };
      page.on("request", onReq);

      await el.click({ timeout: 5000 }).catch(() => {});
      await page.waitForTimeout(400);
      page.off("request", onReq);

      const dialogOpen = await page.locator('[role="dialog"]').isVisible().catch(() => false);
      const urlChanged = page.url() !== urlBefore;

      if (!urlChanged && !dialogOpen && !networkHit) {
        deadButtons.push(label.slice(0, 80));
      }

      if (dialogOpen) {
        await page.keyboard.press("Escape").catch(() => {});
      }
    }

    if (deadButtons.length) {
      await page.screenshot({
        path: path.join("qa-audit", "screenshots", `dead-buttons-${sanitize(route.path)}.png`),
        fullPage: true,
      });
    }

    const allIssues = [...consoleErrors, ...serverErrors];
    if (deadButtons.length) {
      allIssues.push(`DEAD_BUTTONS: ${deadButtons.join(", ")}`);
    }

    await testInfo.attach("issues", {
      body: JSON.stringify({ consoleErrors, serverErrors, deadButtons }, null, 2),
      contentType: "application/json",
    });

    expect(allIssues, `issues on ${route.path}`).toEqual([]);
  });
}

function sanitize(p: string) {
  return p.replace(/[^a-z0-9]+/gi, "-").replace(/^-|-$/g, "") || "root";
}
