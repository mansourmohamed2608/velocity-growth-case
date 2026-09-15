"use server";

import { randomBytes } from "node:crypto";

import { redirect } from "next/navigation";
import { z } from "zod";

import { requirePortalContext } from "@/lib/portal-context";
import { digestForPostgres } from "@/lib/public-report";
import { createClient } from "@/lib/supabase/server";

const publishSchema = z.object({
  campaignId: z.uuid(),
  password: z.string().min(12).max(128),
});

export async function publishReport(formData: FormData) {
  const context = await requirePortalContext();
  if (context.role !== "owner") throw new Error("Owner role is required to publish a report.");
  const parsed = publishSchema.safeParse({
    campaignId: formData.get("campaignId"),
    password: formData.get("password"),
  });
  if (!parsed.success)
    throw new Error("Use a report password between 12 and 128 characters and try again.");

  const token = randomBytes(32).toString("base64url");
  const supabase = await createClient();
  const result = await supabase.rpc("publish_campaign_report", {
    target_campaign_id: parsed.data.campaignId,
    target_token_digest: digestForPostgres(token),
    plain_password: parsed.data.password,
  });
  if (result.error) throw new Error("The campaign report could not be published.");

  redirect(`/portal/campaigns/${parsed.data.campaignId}/report?token=${encodeURIComponent(token)}`);
}
