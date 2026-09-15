import "server-only";

import { dispatchProviderBatch, fetchProviderEventPage } from "@/lib/provider-contract";

function providerConfig() {
  const baseUrl = process.env.MESSAGING_PROVIDER_BASE_URL;
  const apiKey = process.env.MESSAGING_PROVIDER_API_KEY;
  if (!baseUrl || !apiKey) throw new Error("Messaging provider configuration is unavailable.");
  return { baseUrl, apiKey };
}

export async function dispatchClaimedBatch(claim: unknown) {
  return dispatchProviderBatch(claim, providerConfig());
}

export async function fetchClaimedEventPage(batchId: string, since?: string | null) {
  return fetchProviderEventPage({ ...providerConfig(), batchId, since });
}
