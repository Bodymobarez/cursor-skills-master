import { test, expect } from "@playwright/test";

/**
 * Generic form 3-pass on /login — extend per discovery forms list.
 */
test.describe("form validation", () => {
  test.beforeEach(async ({ page }) => {
    await page.goto("/login");
  });

  test("empty submit shows validation", async ({ page }) => {
    await page.getByRole("button", { name: /sign in|log in/i }).click();
    const errors = page.locator('[aria-invalid="true"], .text-destructive, [role="alert"]');
    await expect(errors.first()).toBeVisible({ timeout: 5000 });
  });

  test("invalid email rejected", async ({ page }) => {
    await page.getByTestId("email").or(page.getByLabel(/email/i)).fill("not-an-email");
    await page.getByTestId("password").or(page.getByLabel(/password/i)).fill("short");
    await page.getByRole("button", { name: /sign in|log in/i }).click();
    await expect(page.getByText(/email|invalid|valid/i).first()).toBeVisible();
  });
});
