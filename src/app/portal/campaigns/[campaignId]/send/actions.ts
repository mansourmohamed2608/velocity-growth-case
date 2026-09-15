"use server";

import { redirect } from "next/navigation";
import { z } from "zod";

import { requirePortalContext } from "@/lib/portal-context";
import { dispatchClaimedBatch } from "@/lib/provider";
import { createClient } from "@/lib/supabase/server";

const approvalSchema = z.object({
  campaignId: z.uuid(),
  confirmationKey: z.uuid(),
});

export async function approveSend(formData: FormData) {
  const context = await requirePortalContext();
  if (context.role !== "owner") throw new Error("Owner role is required to approve a send.");

  const parsed = approvalSchema.safeParse({
    campaignId: formData.get("campaignId"),
    confirmationKey: formData.get("confirmationKey"),
  });
  if (!parsed.success) throw new Error("The send confirmation was invalid. Refresh and try again.");

  const supabase = await createClient();
  const { data, error } = await supabase
    .rpc("approve_campaign_send", {
      target_campaign_id: parsed.data.campaignId,
      target_confirmation_key: parsed.data.confirmationKey,
    })
    .single();
  if (error || !data)
    throw new Error("The audience could not be approved. No provider send occurred.");

  redirect(`/portal/campaigns/${parsed.data.campaignId}/send?approved=1`);
}

const dispatchSchema = z.object({ campaignId: z.uuid(), sendId: z.uuid() });

export async function dispatchSend(formData: FormData) {
  const context = await requirePortalContext();
  if (context.role !== "owner") throw new Error("Owner role is required to dispatch a send.");
  const parsed = dispatchSchema.safeParse({
    campaignId: formData.get("campaignId"),
    sendId: formData.get("sendId"),
  });
  if (!parsed.success) throw new Error("The dispatch request was invalid. Refresh and try again.");

  const supabase = await createClient();
  const claimResult = await supabase.rpc("claim_campaign_dispatch", {
    target_send_id: parsed.data.sendId,
  });
  if (claimResult.error || !claimResult.data)
    throw new Error("The approved send could not be claimed for dispatch.");

  let providerResult: Awaited<ReturnType<typeof dispatchClaimedBatch>>;
  try {
    providerResult = await dispatchClaimedBatch(claimResult.data);
  } catch (error) {
    const safeError =
      error instanceof Error && error.message.startsWith("Provider request failed with HTTP")
        ? error.message
        : "Provider dispatch failed before a valid result was recorded.";
    await supabase.rpc("record_campaign_dispatch_failure", {
      target_send_id: parsed.data.sendId,
      safe_error: safeError,
    });
    throw new Error(`${safeError} Retry is safe because the send ID is the idempotency key.`);
  }

  const recordResult = await supabase.rpc("record_campaign_dispatch_result", {
    target_send_id: parsed.data.sendId,
    target_provider_batch_id: providerResult.batchId,
    accepted_identifiers: providerResult.acceptedIdentifiers,
    rejected_identifiers: providerResult.rejectedIdentifiers,
  });
  if (recordResult.error)
    throw new Error(
      "The provider accepted the idempotent request, but local recording failed. Retry safely to recover the same batch.",
    );

  redirect(`/portal/campaigns/${parsed.data.campaignId}/send?dispatched=1`);
}
