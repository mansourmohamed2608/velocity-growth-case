import { z } from "zod";

const claimedDispatchSchema = z
  .object({
    send_id: z.uuid(),
    campaign_external_id: z.string().min(1),
    campaign_name: z.string().min(1),
    brand_code: z.string().min(1),
    channel: z.enum(["email", "sms"]),
    recipient_count: z.number().int().positive().max(100_000),
    recipients: z.array(
      z.object({
        external_id: z.string().min(1),
        destination: z.string().min(1),
      }),
    ),
  })
  .refine((value) => value.recipients.length === value.recipient_count, {
    message: "Recipient snapshot count does not match the approved send.",
  });

const providerResponseSchema = z.object({
  batch_id: z.string().min(1),
  accepted: z.array(z.unknown()),
  rejected: z.array(z.unknown()),
});

export type ClaimedDispatch = z.infer<typeof claimedDispatchSchema>;

export interface ProviderDispatchResult {
  batchId: string;
  acceptedIdentifiers: string[];
  rejectedIdentifiers: string[];
}

export type ProviderTransport = (url: string, init: RequestInit) => Promise<Response>;

function recipientIdentifier(value: unknown): string {
  if (typeof value === "string" && value.trim()) return value;
  if (value && typeof value === "object") {
    const record = value as Record<string, unknown>;
    for (const key of ["id", "external_id", "contact_id", "recipient_id", "email"]) {
      const candidate = record[key];
      if (typeof candidate === "string" && candidate.trim()) return candidate;
    }
  }
  throw new Error("Provider returned a recipient without a documented identifier.");
}

export async function dispatchProviderBatch(
  claimInput: unknown,
  config: { baseUrl: string; apiKey: string },
  transport: ProviderTransport = fetch,
): Promise<ProviderDispatchResult> {
  const claim = claimedDispatchSchema.parse(claimInput);
  const endpoint = new URL("/v1/messages", config.baseUrl).toString();
  const body = {
    campaign: claim.campaign_external_id,
    brand: claim.brand_code,
    recipients: claim.recipients.map((recipient) =>
      claim.channel === "email"
        ? { external_id: recipient.external_id, email: recipient.destination }
        : { external_id: recipient.external_id, phone: recipient.destination },
    ),
  };

  const response = await transport(endpoint, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${config.apiKey}`,
      "Content-Type": "application/json",
      "Idempotency-Key": claim.send_id,
    },
    body: JSON.stringify(body),
    cache: "no-store",
  });
  if (!response.ok) throw new Error(`Provider request failed with HTTP ${response.status}.`);

  let json: unknown;
  try {
    json = await response.json();
  } catch {
    throw new Error("Provider returned a non-JSON response.");
  }
  const result = providerResponseSchema.parse(json);
  return {
    batchId: result.batch_id,
    acceptedIdentifiers: result.accepted.map(recipientIdentifier),
    rejectedIdentifiers: result.rejected.map(recipientIdentifier),
  };
}
