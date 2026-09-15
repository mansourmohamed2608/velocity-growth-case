import { describe, expect, it, vi } from "vitest";

import {
  dispatchProviderBatch,
  fetchProviderEventPage,
  normalizeProviderEvent,
  type ClaimedDispatch,
  type ProviderTransport,
} from "./provider-contract";

const claim: ClaimedDispatch = {
  send_id: "11111111-2222-4333-8444-555555555555",
  campaign_external_id: "KIL-001",
  campaign_name: "September returners",
  brand_code: "KILELE",
  channel: "email",
  recipient_count: 2,
  recipients: [
    { external_id: "CT-000001", destination: "one@example.test" },
    { external_id: "CT-000002", destination: "two@example.test" },
  ],
};

describe("dispatchProviderBatch", () => {
  it("uses the frozen send ID as the provider idempotency key", async () => {
    const transport = vi.fn<ProviderTransport>(async () =>
      Response.json({
        batch_id: "batch-123",
        accepted: [{ external_id: "CT-000001" }, "CT-000002"],
        rejected: [],
      }),
    );

    const result = await dispatchProviderBatch(
      claim,
      { baseUrl: "https://provider.example.test", apiKey: "fixture-credential" },
      transport,
    );

    expect(result).toEqual({
      batchId: "batch-123",
      acceptedIdentifiers: ["CT-000001", "CT-000002"],
      rejectedIdentifiers: [],
    });
    const [url, request] = transport.mock.calls[0];
    expect(url).toBe("https://provider.example.test/v1/messages");
    expect(request.headers).toMatchObject({
      Authorization: "Bearer fixture-credential",
      "Idempotency-Key": claim.send_id,
    });
    expect(JSON.parse(String(request.body))).toEqual({
      campaign: "KIL-001",
      brand: "KILELE",
      recipients: [
        { external_id: "CT-000001", email: "one@example.test" },
        { external_id: "CT-000002", email: "two@example.test" },
      ],
    });
  });

  it("retries the identical request after response loss", async () => {
    const transport = vi
      .fn<(_url: string, _init: RequestInit) => Promise<Response>>()
      .mockRejectedValueOnce(new TypeError("connection closed"))
      .mockResolvedValueOnce(
        Response.json({
          batch_id: "batch-stable",
          accepted: ["CT-000001", "CT-000002"],
          rejected: [],
        }),
      );
    const config = { baseUrl: "https://provider.example.test", apiKey: "fixture-credential" };

    await expect(dispatchProviderBatch(claim, config, transport)).rejects.toThrow(
      "connection closed",
    );
    await expect(dispatchProviderBatch(claim, config, transport)).resolves.toMatchObject({
      batchId: "batch-stable",
    });

    expect(transport).toHaveBeenCalledTimes(2);
    expect(transport.mock.calls[0][1].body).toBe(transport.mock.calls[1][1].body);
    expect(transport.mock.calls[0][1].headers).toEqual(transport.mock.calls[1][1].headers);
  });

  it("rejects an inconsistent snapshot before network I/O", async () => {
    const transport = vi.fn<(_url: string, _init: RequestInit) => Promise<Response>>();
    await expect(
      dispatchProviderBatch(
        { ...claim, recipient_count: 3 },
        { baseUrl: "https://provider.example.test", apiKey: "fixture-credential" },
        transport,
      ),
    ).rejects.toThrow("Recipient snapshot count");
    expect(transport).not.toHaveBeenCalled();
  });

  it("fails closed on an undocumented provider response", async () => {
    const transport = vi.fn<ProviderTransport>(async () =>
      Response.json({ batch_id: "batch-123", accepted: 2 }),
    );
    await expect(
      dispatchProviderBatch(
        claim,
        { baseUrl: "https://provider.example.test", apiKey: "fixture-credential" },
        transport,
      ),
    ).rejects.toThrow();
  });
});

describe("provider event reports", () => {
  it("normalizes documented events and preserves the opaque cursor", async () => {
    const transport = vi.fn<ProviderTransport>(async () =>
      Response.json({
        events: [
          {
            event_id: "evt-2",
            recipient: { external_id: "CT-000002" },
            type: "opened",
            timestamp: "2026-09-15T12:01:00Z",
          },
          {
            id: "evt-1",
            external_id: "CT-000001",
            event_type: "delivered",
            occurred_at: "2026-09-15T12:00:00Z",
          },
        ],
        next_cursor: "evt-2",
        has_more: true,
      }),
    );

    const page = await fetchProviderEventPage(
      {
        baseUrl: "https://provider.example.test",
        apiKey: "fixture-credential",
        batchId: "batch/with spaces",
        since: "evt-0",
      },
      transport,
    );

    expect(page.events.map((event) => [event.event_id, event.event_type])).toEqual([
      ["evt-2", "opened"],
      ["evt-1", "delivered"],
    ]);
    expect(page.nextCursor).toBe("evt-2");
    expect(page.hasMore).toBe(true);
    const [url] = transport.mock.calls[0];
    expect(url).toBe(
      "https://provider.example.test/v1/messages/batch%2Fwith%20spaces/events?since=evt-0",
    );
  });

  it("fails closed when an event lacks a recipient identity", () => {
    expect(() =>
      normalizeProviderEvent({
        event_id: "evt-1",
        type: "delivered",
        timestamp: "2026-09-15T12:00:00Z",
      }),
    ).toThrow("documented identifier");
  });
});
