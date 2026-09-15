"use server";

import { redirect } from "next/navigation";
import { z } from "zod";

import { requirePortalContext } from "@/lib/portal-context";
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
