import { test as setup, expect } from "@playwright/test";
import fs from "fs";
import path from "path";

const authFile = path.join("qa-audit", ".auth", "user.json");

setup("authenticate test user", async ({ page }) => {
  const email = process.env.QA_USER_EMAIL;
  const password = process.env.QA_USER_PASSWORD;

  if (!email || !password) {
    setup.skip(true, "QA_USER_EMAIL and QA_USER_PASSWORD required for auth setup");
    return;
  }

  fs.mkdirSync(path.dirname(authFile), { recursive: true });

  await page.goto("/login");
  await page.getByTestId("email").or(page.getByLabel(/email/i)).fill(email);
  await page
    .getByTestId("password")
    .or(page.getByLabel(/password/i))
    .fill(password);
  await page.getByRole("button", { name: /sign in|log in|login/i }).click();

  await expect(page).not.toHaveURL(/login/, { timeout: 15_000 });
  await page.context().storageState({ path: authFile });
});
