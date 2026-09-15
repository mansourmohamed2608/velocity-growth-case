"use server";

import { redirect } from "next/navigation";
import { z } from "zod";

import { requirePortalContext } from "@/lib/portal-context";
import { dispatchClaimedBatch, fetchClaimedEventPage } from "@/lib/provider";
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

export async function reconcileSend(formData: FormData) {
  const context = await requirePortalContext();
  if (context.role !== "owner")
    throw new Error("Owner role is required to refresh provider results.");
  const parsed = dispatchSchema.safeParse({
    campaignId: formData.get("campaignId"),
    sendId: formData.get("sendId"),
  });
  if (!parsed.success) throw new Error("The reconciliation request was invalid.");

  const supabase = await createClient();
  const sendResult = await supabase
    .from("campaign_sends")
    .select("provider_batch_id,provider_cursor")
    .eq("id", parsed.data.sendId)
    .single();
  if (sendResult.error || !sendResult.data.provider_batch_id)
    throw new Error("This send has no provider batch to refresh.");

  let cursor = sendResult.data.provider_cursor as string | null;
  try {
    for (let pageNumber = 0; pageNumber < 200; pageNumber += 1) {
      const page = await fetchClaimedEventPage(sendResult.data.provider_batch_id, cursor);
      const ingestResult = await supabase.rpc("ingest_provider_event_page", {
        target_send_id: parsed.data.sendId,
        event_page: page.events,
        target_next_cursor: page.nextCursor,
        target_has_more: page.hasMore,
      });
      if (ingestResult.error) throw new Error("A provider event page could not be stored safely.");
      cursor = page.nextCursor ?? page.events.at(-1)?.event_id ?? cursor;
      if (!page.hasMore) break;
      if (!page.nextCursor) throw new Error("Provider returned another page without a cursor.");
      if (pageNumber === 199) throw new Error("Provider report exceeded the safe page limit.");
    }
  } catch (error) {
    const safeError =
      error instanceof Error && error.message.startsWith("Provider report request failed with HTTP")
        ? error.message
        : "Provider results could not be fully reconciled; the saved cursor is safe to retry.";
    await supabase.rpc("record_campaign_reconciliation_failure", {
      target_send_id: parsed.data.sendId,
      safe_error: safeError,
    });
    throw new Error(safeError);
  }

  redirect(`/portal/campaigns/${parsed.data.campaignId}/send?reconciled=1`);
}
