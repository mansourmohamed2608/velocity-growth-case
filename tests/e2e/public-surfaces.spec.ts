import { expect, test } from "@playwright/test";

async function expectNoHorizontalOverflow(page: import("@playwright/test").Page) {
  await expect
    .poll(() => page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth))
    .toBe(true);
}

test("landing page is usable and contained", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByRole("heading", { level: 1 })).toContainText("Growth data");
  await expect(page.getByRole("link", { name: "Open your workspace" })).toBeVisible();
  await expectNoHorizontalOverflow(page);
});

test("login exposes both labeled authentication methods", async ({ page }) => {
  await page.goto("/login");
  await expect(page.getByRole("button", { name: "Continue with Google" })).toBeVisible();
  await expect(page.getByLabel("Email address")).toBeVisible();
  await expect(page.getByLabel("Password")).toBeVisible();
  await expectNoHorizontalOverflow(page);
});

test("anonymous portal access redirects to login", async ({ page }) => {
  await page.goto("/portal");
  await expect(page).toHaveURL(/\/login$/);
  await expect(page.getByRole("heading", { name: "Sign in to your workspace" })).toBeVisible();
});

test("public report capability remains password gated and separate from portal auth", async ({
  page,
}) => {
  await page.goto(`/r/${"A".repeat(43)}`);
  await expect(page.getByRole("heading", { name: "Enter the report password." })).toBeVisible();
  await expect(page.getByLabel("Password")).toBeVisible();
  await expect(page.getByText("does not sign you into the client portal")).toBeVisible();
  await expect(page.getByRole("link", { name: /contacts|campaigns/i })).toHaveCount(0);
  await expectNoHorizontalOverflow(page);
});
