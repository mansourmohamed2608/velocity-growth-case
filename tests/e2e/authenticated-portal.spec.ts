import { readFile } from "node:fs/promises";
import path from "node:path";

import { expect, test, type Page } from "@playwright/test";

import type { PortalCredentialFile } from "../../scripts/portal-credentials";

async function credentials() {
  const file = process.env.PORTAL_CREDENTIALS_FILE ?? ".work/portal-credentials.json";
  return JSON.parse(await readFile(path.resolve(file), "utf8")) as PortalCredentialFile;
}

async function signIn(page: Page, email: string, password: string) {
  await page.goto("/login");
  await page.getByLabel("Email address").fill(email);
  await page.getByLabel("Password").fill(password);
  await page.getByRole("button", { name: "Sign in" }).click();
  await expect(page).toHaveURL(/\/portal$/);
}

test("all six email/password identities receive only their assigned brand and role", async ({
  page,
}, testInfo) => {
  test.skip(testInfo.project.name !== "desktop", "Role matrix runs once at desktop width.");
  const privateCredentials = await credentials();
  expect(privateCredentials.accounts).toHaveLength(6);

  for (const account of privateCredentials.accounts) {
    await page.context().clearCookies();
    await signIn(page, account.email, account.password);
    await expect(page.locator(".portal-meta")).toContainText(account.brandName);
    await expect(page.locator(".portal-meta")).toContainText(account.role);
  }
});

test("owner can navigate bounded data and preview a send without dispatching", async ({
  page,
}, testInfo) => {
  test.skip(testInfo.project.name !== "desktop", "Owner workflow runs once at desktop width.");
  const owner = (await credentials()).accounts.find(
    (account) => account.brandCode === "KAROO" && account.role === "owner",
  )!;
  await signIn(page, owner.email, owner.password);
  await expect(page.getByRole("link", { name: "Skip to main content" })).toHaveCount(1);
  await expect(page.getByText("Total customers")).toBeVisible();
  const dailyValues = page.getByText("View exact daily values");
  await expect(dailyValues).toBeVisible();
  await dailyValues.click();
  await expect(
    page.getByRole("region", { name: "Exact daily signup values" }).getByRole("row"),
  ).toHaveCount(31);

  await page.getByRole("link", { name: "Contacts" }).click();
  await expect(page.getByRole("heading", { name: "Contacts" })).toBeVisible();
  await expect(page.getByText(/12,406 contacts/)).toBeVisible();
  await expect(page.getByRole("link", { name: "Next →" })).toBeVisible();

  await page.getByRole("link", { name: "Campaigns", exact: true }).click();
  await expect(page.getByRole("heading", { name: "Campaigns", exact: true })).toBeVisible();
  await page.getByRole("link", { name: "Prepare send" }).first().click();
  await expect(page.getByText("Exact eligible audience")).toBeVisible();
  await expect(page.getByRole("button", { name: /Approve .* recipients/ })).toBeVisible();
  await expect(page.getByRole("button", { name: /Dispatch approved audience/ })).toHaveCount(0);
});

test("analyst sees read-only campaigns and no send or publication action", async ({
  page,
}, testInfo) => {
  test.skip(testInfo.project.name !== "desktop", "Analyst workflow runs once at desktop width.");
  const analyst = (await credentials()).accounts.find(
    (account) => account.brandCode === "KAROO" && account.role === "analyst",
  )!;
  await signIn(page, analyst.email, analyst.password);
  await page.getByRole("link", { name: "Campaigns", exact: true }).click();
  await expect(page.getByText("Analyst · read-only access")).toBeVisible();
  await expect(page.getByRole("link", { name: "Prepare send" })).toHaveCount(0);
  await expect(page.getByRole("link", { name: "Publish report" })).toHaveCount(0);
});

test("largest production tenant can load campaign metrics and an exact send preview", async ({
  page,
}, testInfo) => {
  const baseUrl = String(testInfo.project.use.baseURL ?? "");
  test.skip(
    testInfo.project.name !== "desktop" || !baseUrl.startsWith("https://"),
    "The hosted largest-tenant performance check runs once against production.",
  );
  const owner = (await credentials()).accounts.find(
    (account) => account.brandCode === "KILELE" && account.role === "owner",
  )!;
  await signIn(page, owner.email, owner.password);
  await page.getByRole("link", { name: "Campaigns", exact: true }).click();
  await expect(page.getByRole("heading", { name: "Campaigns", exact: true })).toBeVisible();
  await page.getByRole("link", { name: "Prepare send" }).first().click();
  await expect(page.getByText("Exact eligible audience")).toBeVisible();
  await expect(page.getByRole("button", { name: /Approve .* recipients/ })).toBeVisible();
});

test("approved production send is inspectable and cannot be dispatched again", async ({
  page,
}, testInfo) => {
  const baseUrl = String(testInfo.project.use.baseURL ?? "");
  test.skip(
    testInfo.project.name !== "desktop" || !baseUrl.startsWith("https://"),
    "The completed-send audit runs once against production.",
  );
  const owner = (await credentials()).accounts.find(
    (account) => account.brandCode === "MARRAKECH" && account.role === "owner",
  )!;
  await signIn(page, owner.email, owner.password);
  await page.getByRole("link", { name: "Campaigns", exact: true }).click();
  const campaignRow = page.getByRole("row").filter({ hasText: "MAR-0002" });
  await campaignRow.getByRole("link", { name: "View submitted" }).click();
  await expect(page.getByText("MAR-0002 · sms · All countries")).toBeVisible();
  await expect(page.getByText("Frozen recipients").locator("..")).toContainText("449");
  await expect(page.getByText("Provider accepted").locator("..")).toContainText("449");
  await expect(page.getByText("1 unbound provider event was skipped safely.")).toBeVisible();
  await expect(page.getByRole("button", { name: "Dispatch approved audience" })).toHaveCount(0);
});

test("authenticated portal remains contained at a phone viewport", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "phone", "Phone layout runs only in the phone project.");
  const owner = (await credentials()).accounts.find(
    (account) => account.brandCode === "MARRAKECH" && account.role === "owner",
  )!;
  await signIn(page, owner.email, owner.password);
  await expect(page.getByRole("navigation", { name: "Portal navigation" })).toBeVisible();
  await expect
    .poll(() => page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth))
    .toBe(true);
});
