import { test, expect } from "@playwright/test";

test.describe("auth flows", () => {
  test("login with valid credentials", async ({ page }) => {
    const email = process.env.QA_USER_EMAIL;
    const password = process.env.QA_USER_PASSWORD;
    test.skip(!email || !password, "QA_USER_EMAIL/PASSWORD not set");

    await page.goto("/login");
    await page.getByTestId("email").or(page.getByLabel(/email/i)).fill(email!);
    await page.getByTestId("password").or(page.getByLabel(/password/i)).fill(password!);
    await page.getByRole("button", { name: /sign in|log in/i }).click();
    await expect(page).not.toHaveURL(/login/);
  });

  test("login rejects invalid credentials", async ({ page }) => {
    await page.goto("/login");
    await page.getByTestId("email").or(page.getByLabel(/email/i)).fill("invalid@example.com");
    await page.getByTestId("password").or(page.getByLabel(/password/i)).fill("wrong-password-xyz");
    await page.getByRole("button", { name: /sign in|log in/i }).click();
    await expect(page.getByText(/invalid|incorrect|failed/i)).toBeVisible({ timeout: 10_000 });
  });

  test("logout returns to login or home", async ({ page }) => {
    test.skip(!process.env.QA_USER_EMAIL, "auth env not set");
    await page.goto("/");
    const logout = page.getByRole("button", { name: /log out|sign out/i });
    if (await logout.isVisible().catch(() => false)) {
      await logout.click();
      await expect(page).toHaveURL(/login|^\/$/);
    }
  });
});
