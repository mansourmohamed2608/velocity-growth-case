import { describe, expect, it } from "vitest";

import { normalizeCampaign, normalizeContact, normalizeEvent } from "./normalize";
import type { SourceRecord } from "./types";

const row = (values: Record<string, string>, rowNumber = 2): SourceRecord => ({
  rowNumber,
  values,
});

const validContact = {
  external_id: "CT-000001",
  full_name: "Amina Test",
  email: "AMINA@EXAMPLE.TEST",
  phone: "+254700000001",
  country: "kenya",
  city: "Nairobi",
  signup_at: "2026-02-03T10:00:00Z",
  status: "ACTIVE",
  consent_marketing: "Y",
  deleted_at: "",
  suppressed_until: "",
  brand_code: "KILELE",
  notes: "",
};

describe("contact normalization", () => {
  it("normalizes safe aliases and boolean/status values", () => {
    const result = normalizeContact(row(validContact), "KILELE", 0);
    expect(result.value).toMatchObject({
      email: "amina@example.test",
      country_code: "KE",
      lifecycle_status: "active",
      marketing_consent: true,
    });
    expect(result.issues).toHaveLength(0);
  });

  it("rejects and redacts a cross-brand leak row", () => {
    const result = normalizeContact(row({ ...validContact, brand_code: "KAROO" }), "KILELE", 0);
    expect(result.value).toBeNull();
    const issue = result.issues.find((item) => item.errorCode === "BRAND_MISMATCH");
    expect(issue?.rawRow).toEqual({ external_id: "CT-000001", brand_code: "KAROO" });
    expect(issue?.rawRow).not.toHaveProperty("email");
  });

  it("rejects malformed email and date-only signup input", () => {
    const result = normalizeContact(
      row({ ...validContact, email: "bad email", signup_at: "2026-02-03" }),
      "KILELE",
      0,
    );
    expect(result.value).toBeNull();
    expect(result.issues.map((item) => item.errorCode)).toEqual(
      expect.arrayContaining(["INVALID_EMAIL", "INVALID_SIGNUP_TIMESTAMP"]),
    );
  });

  it("rejects impossible deletion order and unsupported NUL input", () => {
    const result = normalizeContact(
      row({
        ...validContact,
        notes: "bad\0note",
        deleted_at: "2026-01-01T00:00:00Z",
      }),
      "KILELE",
      0,
    );
    expect(result.value).toBeNull();
    expect(result.issues.map((item) => item.errorCode)).toEqual(
      expect.arrayContaining(["UNSUPPORTED_CONTROL_CHARACTER", "DELETION_BEFORE_SIGNUP"]),
    );
    expect(
      result.issues.find((item) => item.errorCode === "UNSUPPORTED_CONTROL_CHARACTER")?.rawValue,
    ).toContain("[NUL]");
  });

  it("conservatively defaults missing consent to false with a warning", () => {
    const result = normalizeContact(row({ ...validContact, consent_marketing: "" }), "KILELE", 0);
    expect(result.value?.marketing_consent).toBe(false);
    expect(result.issues).toContainEqual(
      expect.objectContaining({
        severity: "warning",
        errorCode: "MISSING_CONSENT_DEFAULTED_FALSE",
      }),
    );
  });

  it("converts the known Kilele legacy timestamp with its brand offset", () => {
    const result = normalizeContact(
      row({ ...validContact, signup_at: "03/02/2026 10:00" }),
      "KILELE",
      0,
    );
    expect(result.value?.signup_at).toBe("2026-02-03T07:00:00.000Z");
    expect(result.issues).toContainEqual(
      expect.objectContaining({ errorCode: "NORMALIZED_LOCAL_TIMESTAMP" }),
    );
  });
});

describe("campaign and event normalization", () => {
  it("parses Marrakech decimal-comma spend", () => {
    const result = normalizeCampaign(
      row({
        external_id: "MAR-1",
        campaign_name: "Test",
        channel: "sms",
        target_country: "",
        reported_sent: "10",
        reported_delivered: "9",
        reported_bounced: "1",
        reported_opens: "2",
        reported_clicks: "1",
        spend: "221,09",
        sent_at_utc: "2026-03-01T10:00:00Z",
        send_local_time: "2026-03-01 11:00",
        parent_campaign_id: "",
      }),
      "MARRAKECH",
    );
    expect(result.value?.spend).toBe(221.09);
  });

  it("normalizes singular seed event names", () => {
    const result = normalizeEvent(
      row({
        event_id: "EV-1",
        external_contact_id: "CT-000001",
        campaign_external_id: "KIL-1",
        event_type: "open",
        channel: "email",
        occurred_at_utc: "2026-03-01T10:00:00Z",
      }),
      "KILELE",
    );
    expect(result.value?.event_type).toBe("opened");
  });
});
