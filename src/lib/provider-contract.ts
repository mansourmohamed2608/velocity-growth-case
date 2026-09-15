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

const providerEventPageSchema = z.object({
  events: z.array(z.unknown()),
  next_cursor: z.string().min(1).nullable(),
  has_more: z.boolean(),
});

const providerEventTypes = {
  delivered: "delivered",
  bounced: "bounced",
  bounce: "bounced",
  opened: "opened",
  open: "opened",
  unsubscribed: "unsubscribed",
  unsubscribe: "unsubscribed",
} as const;

export type ClaimedDispatch = z.infer<typeof claimedDispatchSchema>;

export interface ProviderDispatchResult {
  batchId: string;
  acceptedIdentifiers: string[];
  rejectedIdentifiers: string[];
}

export interface NormalizedProviderEvent {
  event_id: string;
  recipient_identifier: string;
  event_type: (typeof providerEventTypes)[keyof typeof providerEventTypes];
  occurred_at: string;
  raw_payload: Record<string, unknown>;
}

export interface ProviderEventPage {
  events: NormalizedProviderEvent[];
  nextCursor: string | null;
  hasMore: boolean;
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

function requiredString(record: Record<string, unknown>, keys: string[], label: string) {
  for (const key of keys) {
    const value = record[key];
    if (typeof value === "string" && value.trim()) return value.trim();
  }
  throw new Error(`Provider event is missing ${label}.`);
}

export function normalizeProviderEvent(value: unknown): NormalizedProviderEvent {
  if (!value || typeof value !== "object" || Array.isArray(value))
    throw new Error("Provider event must be an object.");
  const raw = value as Record<string, unknown>;
  const eventId = requiredString(raw, ["event_id", "id"], "event_id");
  const eventTypeInput = requiredString(raw, ["event_type", "type"], "event_type").toLowerCase();
  const eventType = providerEventTypes[eventTypeInput as keyof typeof providerEventTypes];
  if (!eventType) throw new Error(`Provider returned unsupported event type ${eventTypeInput}.`);

  let recipient: unknown = raw.recipient;
  if (recipient === undefined) {
    for (const key of ["recipient_id", "external_id", "contact_id", "email"]) {
      if (raw[key] !== undefined) {
        recipient = { [key]: raw[key] };
        break;
      }
    }
  }
  const occurredAtInput = requiredString(
    raw,
    ["occurred_at", "occurred_at_utc", "timestamp", "created_at"],
    "event timestamp",
  );
  const occurredAt = new Date(occurredAtInput);
  if (Number.isNaN(occurredAt.valueOf())) throw new Error("Provider event timestamp is invalid.");

  return {
    event_id: eventId,
    recipient_identifier: recipientIdentifier(recipient),
    event_type: eventType,
    occurred_at: occurredAt.toISOString(),
    raw_payload: raw,
  };
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

export async function fetchProviderEventPage(
  input: { baseUrl: string; apiKey: string; batchId: string; since?: string | null },
  transport: ProviderTransport = fetch,
): Promise<ProviderEventPage> {
  const endpoint = new URL(
    `/v1/messages/${encodeURIComponent(input.batchId)}/events`,
    input.baseUrl,
  );
  if (input.since) endpoint.searchParams.set("since", input.since);
  const response = await transport(endpoint.toString(), {
    method: "GET",
    headers: { Authorization: `Bearer ${input.apiKey}` },
    cache: "no-store",
  });
  if (!response.ok) throw new Error(`Provider report request failed with HTTP ${response.status}.`);

  let json: unknown;
  try {
    json = await response.json();
  } catch {
    throw new Error("Provider report returned a non-JSON response.");
  }
  const page = providerEventPageSchema.parse(json);
  return {
    events: page.events.map(normalizeProviderEvent),
    nextCursor: page.next_cursor,
    hasMore: page.has_more,
  };
}
