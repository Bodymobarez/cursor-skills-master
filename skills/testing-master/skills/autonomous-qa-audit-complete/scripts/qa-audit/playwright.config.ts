import { defineConfig, devices } from "@playwright/test";

const baseURL = process.env.QA_BASE_URL ?? "http://localhost:3000";

export default defineConfig({
  testDir: __dirname,
  testMatch: /.*\.spec\.ts/,
  fullyParallel: false,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 1,
  workers: 1,
  timeout: 120_000,
  reporter: [
    ["list"],
    ["html", { outputFolder: "qa-audit/reports/html", open: "never" }],
    ["json", { outputFile: "qa-audit/reports/results.json" }],
  ],
  use: {
    baseURL,
    trace: "on-first-retry",
    screenshot: "only-on-failure",
    video: "retain-on-failure",
  },
  projects: [
    { name: "setup", testMatch: /auth\.setup\.ts/ },
    {
      name: "crawl",
      testMatch: /crawl\.spec\.ts/,
      dependencies: ["setup"],
      use: {
        ...devices["Desktop Chrome"],
        storageState: "qa-audit/.auth/user.json",
      },
    },
    {
      name: "mobile",
      testMatch: /crawl\.spec\.ts/,
      dependencies: ["setup"],
      use: {
        ...devices["iPhone 13"],
        storageState: "qa-audit/.auth/user.json",
      },
    },
    { name: "flows", testMatch: /flows\./ },
    { name: "api", testMatch: /api\./ },
  ],
  webServer: process.env.QA_SKIP_WEB_SERVER
    ? undefined
    : {
        command: process.env.QA_DEV_COMMAND ?? "npm run dev",
        url: baseURL,
        reuseExistingServer: !process.env.CI,
        timeout: 120_000,
      },
});
