import { randomBytes } from "node:crypto";
import { access, mkdir, writeFile } from "node:fs/promises";
import path from "node:path";

import type { PortalCredential, PortalCredentialFile } from "./portal-credentials";

const privateDataPath = path.resolve(".work/portal-credentials.json");
const privateSubmissionPath = path.resolve("SUBMISSION_PRIVATE.md");

function password() {
  return `${randomBytes(18).toString("base64url")}!7a`;
}

async function main() {
  try {
    await access(privateDataPath);
    console.log("Private portal credentials already exist; no values were changed.");
    return;
  } catch {
    // The file is generated once below.
  }

  const googleOwnerEmail = process.env.GOOGLE_OWNER_EMAIL?.trim().toLowerCase();
  if (!googleOwnerEmail) throw new Error("GOOGLE_OWNER_EMAIL is required to generate credentials.");
  const suffix = randomBytes(5).toString("hex");
  const accountSpecs: Array<Omit<PortalCredential, "email" | "password"> & { email: string }> = [
    { brandCode: "KILELE", brandName: "Kilele Rides", role: "owner", email: googleOwnerEmail },
    {
      brandCode: "KILELE",
      brandName: "Kilele Rides",
      role: "analyst",
      email: `kilele.analyst.${suffix}@example.test`,
    },
    {
      brandCode: "KAROO",
      brandName: "Karoo Coaches",
      role: "owner",
      email: `karoo.owner.${suffix}@example.test`,
    },
    {
      brandCode: "KAROO",
      brandName: "Karoo Coaches",
      role: "analyst",
      email: `karoo.analyst.${suffix}@example.test`,
    },
    {
      brandCode: "MARRAKECH",
      brandName: "Marrakech Express",
      role: "owner",
      email: `marrakech.owner.${suffix}@example.test`,
    },
    {
      brandCode: "MARRAKECH",
      brandName: "Marrakech Express",
      role: "analyst",
      email: `marrakech.analyst.${suffix}@example.test`,
    },
  ];
  const credentials: PortalCredentialFile = {
    accounts: accountSpecs.map((account) => ({ ...account, password: password() })),
    reportPassword: password(),
  };

  await mkdir(path.dirname(privateDataPath), { recursive: true });
  await writeFile(privateDataPath, `${JSON.stringify(credentials, null, 2)}\n`, { mode: 0o600 });
  const accountSections = credentials.accounts
    .map(
      (account) =>
        `### ${account.brandName} — ${account.role}\n\n- Email: ${account.email}\n- Password: ${account.password}`,
    )
    .join("\n\n");
  await writeFile(
    privateSubmissionPath,
    `# Private Submission Material\n\nDo not commit or share publicly.\n\n${accountSections}\n\n## Provider\n\n- API key: stored only as MESSAGING_PROVIDER_API_KEY in .env.local / production secret storage\n\n## Public report\n\n- Password: ${credentials.reportPassword}\n- URL: populated after production publication\n`,
    { mode: 0o600 },
  );
  console.log("Generated six private portal credentials without printing their values.");
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : "Credential generation failed");
  process.exitCode = 1;
});
