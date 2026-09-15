import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { readFile } from "node:fs/promises";
import path from "node:path";

import { createClient, type SupabaseClient } from "@supabase/supabase-js";

import type { PortalCredentialFile } from "./portal-credentials";

async function main() {
  const adminUrl = process.env.SUPABASE_ADMIN_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  const publishableKey = process.env.SUPABASE_PUBLISHABLE_KEY;
  if (!adminUrl || !serviceRoleKey || !publishableKey)
    throw new Error("Supabase admin URL, service role key, and publishable key are required.");

  const credentials = JSON.parse(
    await readFile(path.resolve(".work/portal-credentials.json"), "utf8"),
  ) as PortalCredentialFile;
  assert.equal(credentials.accounts.length, 6, "exactly six portal credentials are required");

  const admin = createClient(adminUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
  const { data: brandRows, error: brandError } = await admin.from("brands").select("id,code");
  if (brandError) throw brandError;
  const brands = new Map((brandRows ?? []).map((brand) => [brand.code, brand.id]));

  const { data: existingData, error: listError } = await admin.auth.admin.listUsers({
    page: 1,
    perPage: 1000,
  });
  if (listError) throw listError;
  const existingUsers = new Map(
    existingData.users.map((user) => [user.email?.toLowerCase(), user]),
  );

  for (const account of credentials.accounts) {
    const existing = existingUsers.get(account.email.toLowerCase());
    const userResult = existing
      ? await admin.auth.admin.updateUserById(existing.id, {
          password: account.password,
          email_confirm: true,
        })
      : await admin.auth.admin.createUser({
          email: account.email,
          password: account.password,
          email_confirm: true,
        });
    if (userResult.error || !userResult.data.user)
      throw userResult.error ?? new Error("User missing");
    const brandId = brands.get(account.brandCode);
    if (!brandId) throw new Error(`Brand ${account.brandCode} is missing.`);
    const deleteResult = await admin
      .from("brand_memberships")
      .delete()
      .eq("user_id", userResult.data.user.id);
    if (deleteResult.error) throw deleteResult.error;
    const membershipResult = await admin.from("brand_memberships").insert({
      brand_id: brandId,
      user_id: userResult.data.user.id,
      role: account.role,
    });
    if (membershipResult.error) throw membershipResult.error;
  }

  for (const account of credentials.accounts) {
    const client: SupabaseClient = createClient(adminUrl, publishableKey, {
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    });
    const login = await client.auth.signInWithPassword({
      email: account.email,
      password: account.password,
    });
    if (login.error) throw login.error;
    const context = await client.rpc("current_portal_context").single();
    if (context.error) throw context.error;
    const portalContext = context.data as { brand_code: string; role: string };
    assert.equal(portalContext.brand_code, account.brandCode);
    assert.equal(portalContext.role, account.role);
    await client.auth.signOut();
  }

  const unknownEmail = `unknown.${randomBytes(6).toString("hex")}@example.test`;
  const unknownPassword = `${randomBytes(18).toString("base64url")}!8b`;
  const unknown = await admin.auth.admin.createUser({
    email: unknownEmail,
    password: unknownPassword,
    email_confirm: true,
  });
  if (unknown.error || !unknown.data.user) throw unknown.error ?? new Error("Unknown user missing");
  try {
    const client: SupabaseClient = createClient(adminUrl, publishableKey, {
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    });
    const login = await client.auth.signInWithPassword({
      email: unknownEmail,
      password: unknownPassword,
    });
    if (login.error) throw login.error;
    const context = await client.rpc("current_portal_context").maybeSingle();
    assert.equal(context.error, null);
    assert.equal(context.data, null, "unlisted authenticated identity must have no context");
    const contacts = await client.from("contacts").select("id").limit(1);
    assert.equal(contacts.error, null);
    assert.deepEqual(contacts.data, [], "unlisted authenticated identity must see zero contacts");
  } finally {
    await admin.auth.admin.deleteUser(unknown.data.user.id);
  }

  console.log(
    "Provisioned and verified six role accounts; an unlisted identity received zero access.",
  );
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : "Portal user provisioning failed");
  process.exitCode = 1;
});
