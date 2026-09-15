import "server-only";

import { dispatchProviderBatch } from "@/lib/provider-contract";

export async function dispatchClaimedBatch(claim: unknown) {
  const baseUrl = process.env.MESSAGING_PROVIDER_BASE_URL;
  const apiKey = process.env.MESSAGING_PROVIDER_API_KEY;
  if (!baseUrl || !apiKey) throw new Error("Messaging provider configuration is unavailable.");
  return dispatchProviderBatch(claim, { baseUrl, apiKey });
}
