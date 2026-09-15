import type {
  BrandCode,
  Channel,
  ChannelStatus,
  ImportIssue,
  LifecycleStatus,
  NormalizedCampaign,
  NormalizedContact,
  NormalizedEvent,
  SourceRecord,
} from "./types";

const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const contactIdPattern = /^CT-\d{6}$/;
const trueValues = new Set(["true", "1", "yes", "y"]);
const falseValues = new Set(["false", "0", "no", "n", "f"]);
const nullCountryValues = new Set(["", "null", "none", "n/a", "\\n", "-"]);

const countryAliases: Record<string, string> = {
  "254": "KE",
  KE: "KE",
  KEN: "KE",
  KENYA: "KE",
};

const brandOffsets: Record<BrandCode, string> = {
  KILELE: "+03:00",
  KAROO: "+02:00",
  MARRAKECH: "+01:00",
};

function sanitizeDiagnostic(value: string) {
  return value.replaceAll("\0", "[NUL]").replaceAll("\\", "＼");
}

function safeRawRow(row: SourceRecord, brandMismatch: boolean) {
  const visible = brandMismatch
    ? {
        external_id: row.values.external_id ?? "",
        brand_code: row.values.brand_code ?? "",
      }
    : row.values;
  return Object.fromEntries(
    Object.entries(visible).map(([key, value]) => [key, sanitizeDiagnostic(value)]),
  );
}

function makeIssue(
  row: SourceRecord,
  severity: ImportIssue["severity"],
  fieldName: string | null,
  errorCode: string,
  reason: string,
  rawValue: string | null = null,
  brandMismatch = false,
): ImportIssue {
  return {
    rowNumber: row.rowNumber,
    severity,
    fieldName,
    errorCode,
    reason,
    rawValue: rawValue === null ? null : sanitizeDiagnostic(rawValue),
    rawRow: safeRawRow(row, brandMismatch),
  };
}

function parseTimestamp(
  value: string,
  brand: BrandCode,
): { value: string | null; legacy: boolean } {
  const trimmed = value.trim();
  if (!trimmed) return { value: null, legacy: false };

  if (/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/.test(trimmed)) {
    const parsed = new Date(trimmed);
    return { value: Number.isNaN(parsed.valueOf()) ? null : parsed.toISOString(), legacy: false };
  }

  const legacy = /^(\d{2})\/(\d{2})\/(\d{4}) (\d{2}):(\d{2})$/.exec(trimmed);
  if (legacy) {
    const [, day, month, year, hour, minute] = legacy;
    const parsed = new Date(`${year}-${month}-${day}T${hour}:${minute}:00${brandOffsets[brand]}`);
    return { value: Number.isNaN(parsed.valueOf()) ? null : parsed.toISOString(), legacy: true };
  }

  return { value: null, legacy: false };
}

function optionalTimestamp(
  row: SourceRecord,
  field: string,
  brand: BrandCode,
  issues: ImportIssue[],
): string | null {
  const input = row.values[field]?.trim() ?? "";
  if (!input) return null;
  const parsed = parseTimestamp(input, brand);
  if (!parsed.value) {
    issues.push(
      makeIssue(
        row,
        "error",
        field,
        "INVALID_TIMESTAMP",
        `${field} is not a supported timestamp.`,
        input,
      ),
    );
    return null;
  }
  if (parsed.legacy) {
    issues.push(
      makeIssue(
        row,
        "warning",
        field,
        "NORMALIZED_LOCAL_TIMESTAMP",
        `${field} used a legacy local format and was converted with the brand time zone.`,
        input,
      ),
    );
  }
  return parsed.value;
}

function normalizeCountry(value: string): string | null | undefined {
  const normalized = value.trim().toUpperCase();
  if (nullCountryValues.has(value.trim().toLowerCase())) return null;
  if (countryAliases[normalized]) return countryAliases[normalized];
  if (/^[A-Z]{2}$/.test(normalized) && normalized !== "ZZ") return normalized;
  return undefined;
}

function normalizeStatus(value: string): LifecycleStatus | undefined {
  const status = value.trim().toLowerCase();
  if (status === "unsubscribe") return "unsubscribed";
  if (["active", "pending", "bounced", "unsubscribed"].includes(status)) {
    return status as LifecycleStatus;
  }
  return undefined;
}

function channelStatus(address: string | null, status: LifecycleStatus): ChannelStatus {
  if (!address) return "unavailable";
  if (status === "bounced") return "bounced";
  if (status === "unsubscribed") return "unsubscribed";
  return "active";
}

export function normalizeContact(
  row: SourceRecord,
  brand: BrandCode,
  sourcePrecedence: number,
): { value: NormalizedContact | null; issues: ImportIssue[] } {
  const issues: ImportIssue[] = [];
  const externalId = row.values.external_id?.trim() ?? "";
  const fullName = row.values.full_name?.trim() ?? "";
  const emailInput = row.values.email?.trim().toLowerCase() ?? "";
  const phone = row.values.phone?.trim() || null;
  const sourceBrand = row.values.brand_code?.trim().toUpperCase() ?? "";
  const brandMismatch = sourceBrand !== brand;

  for (const [field, value] of Object.entries(row.values)) {
    if (value.includes("\0")) {
      issues.push(
        makeIssue(
          row,
          "error",
          field,
          "UNSUPPORTED_CONTROL_CHARACTER",
          `${field} contains a NUL character that PostgreSQL cannot store.`,
          value,
        ),
      );
    }
  }

  if (!contactIdPattern.test(externalId)) {
    issues.push(
      makeIssue(
        row,
        "error",
        "external_id",
        "INVALID_EXTERNAL_ID",
        "external_id must match CT-######.",
        externalId,
      ),
    );
  }
  if (!fullName)
    issues.push(makeIssue(row, "error", "full_name", "MISSING_NAME", "full_name is required."));
  if (brandMismatch) {
    issues.push(
      makeIssue(
        row,
        "error",
        "brand_code",
        "BRAND_MISMATCH",
        `Row brand ${sourceBrand || "(missing)"} does not match ${brand}.`,
        sourceBrand,
        true,
      ),
    );
  }
  if (emailInput && !emailPattern.test(emailInput)) {
    issues.push(
      makeIssue(row, "error", "email", "INVALID_EMAIL", "Email address is malformed.", emailInput),
    );
  }
  if (!emailInput && !phone) {
    issues.push(
      makeIssue(
        row,
        "error",
        null,
        "MISSING_DESTINATION",
        "At least one email address or phone number is required.",
      ),
    );
  }

  const country = normalizeCountry(row.values.country ?? "");
  if (country === undefined) {
    issues.push(
      makeIssue(
        row,
        "error",
        "country",
        "INVALID_COUNTRY",
        "Country must be a supported two-letter code or known Kenya alias.",
        row.values.country ?? "",
      ),
    );
  }

  const signup = parseTimestamp(row.values.signup_at ?? "", brand);
  if (!signup.value) {
    issues.push(
      makeIssue(
        row,
        "error",
        "signup_at",
        "INVALID_SIGNUP_TIMESTAMP",
        "signup_at must include a valid time.",
        row.values.signup_at ?? "",
      ),
    );
  } else if (signup.legacy) {
    issues.push(
      makeIssue(
        row,
        "warning",
        "signup_at",
        "NORMALIZED_LOCAL_TIMESTAMP",
        "A legacy local signup time was converted with the brand time zone.",
        row.values.signup_at ?? "",
      ),
    );
  }

  const status = normalizeStatus(row.values.status ?? "");
  if (!status) {
    issues.push(
      makeIssue(
        row,
        "error",
        "status",
        "INVALID_STATUS",
        "Status must be active, pending, bounced, or unsubscribed.",
        row.values.status ?? "",
      ),
    );
  }

  const consentInput = row.values.consent_marketing?.trim().toLowerCase() ?? "";
  let consent = false;
  if (trueValues.has(consentInput)) consent = true;
  else if (falseValues.has(consentInput)) consent = false;
  else if (!consentInput) {
    issues.push(
      makeIssue(
        row,
        "warning",
        "consent_marketing",
        "MISSING_CONSENT_DEFAULTED_FALSE",
        "Missing consent was conservatively treated as false.",
      ),
    );
  } else {
    issues.push(
      makeIssue(
        row,
        "error",
        "consent_marketing",
        "INVALID_CONSENT",
        "Consent value is not recognized.",
        consentInput,
      ),
    );
  }

  const deletedAt = optionalTimestamp(row, "deleted_at", brand, issues);
  const suppressedUntil = optionalTimestamp(row, "suppressed_until", brand, issues);
  if (deletedAt && signup.value && new Date(deletedAt) < new Date(signup.value)) {
    issues.push(
      makeIssue(
        row,
        "error",
        "deleted_at",
        "DELETION_BEFORE_SIGNUP",
        "deleted_at cannot be earlier than signup_at.",
        row.values.deleted_at ?? "",
      ),
    );
  }
  if (
    issues.some((issue) => issue.severity === "error") ||
    !signup.value ||
    !status ||
    country === undefined
  ) {
    return { value: null, issues };
  }

  const email = emailInput || null;
  return {
    value: {
      external_id: externalId,
      full_name: fullName,
      email,
      phone,
      country_code: country,
      city: row.values.city?.trim() || null,
      signup_at: signup.value,
      lifecycle_status: status,
      marketing_consent: consent,
      deleted_at: deletedAt,
      suppressed_until: suppressedUntil,
      email_status: channelStatus(email, status),
      sms_status: channelStatus(phone, status),
      notes: row.values.notes?.trim() || null,
      source_precedence: sourcePrecedence,
    },
    issues,
  };
}

function parseNonNegativeInteger(row: SourceRecord, field: string, issues: ImportIssue[]) {
  const input = row.values[field]?.trim() ?? "";
  if (!/^\d+$/.test(input)) {
    issues.push(
      makeIssue(
        row,
        "error",
        field,
        "INVALID_COUNT",
        `${field} must be a non-negative integer.`,
        input,
      ),
    );
    return null;
  }
  const value = Number(input);
  return Number.isSafeInteger(value) ? value : null;
}

export function normalizeCampaign(
  row: SourceRecord,
  brand: BrandCode,
): { value: NormalizedCampaign | null; issues: ImportIssue[] } {
  const issues: ImportIssue[] = [];
  for (const [field, value] of Object.entries(row.values)) {
    if (value.includes("\0")) {
      issues.push(
        makeIssue(
          row,
          "error",
          field,
          "UNSUPPORTED_CONTROL_CHARACTER",
          `${field} contains a NUL character that PostgreSQL cannot store.`,
          value,
        ),
      );
    }
  }
  const externalId = row.values.external_id?.trim() ?? "";
  const name = row.values.campaign_name?.trim() ?? "";
  const channelInput = row.values.channel?.trim().toLowerCase() ?? "";
  const channel = (["email", "sms"].includes(channelInput) ? channelInput : null) as Channel | null;
  if (!externalId)
    issues.push(
      makeIssue(
        row,
        "error",
        "external_id",
        "MISSING_CAMPAIGN_ID",
        "Campaign external_id is required.",
      ),
    );
  if (!name)
    issues.push(
      makeIssue(
        row,
        "error",
        "campaign_name",
        "MISSING_CAMPAIGN_NAME",
        "Campaign name is required.",
      ),
    );
  if (!channel)
    issues.push(
      makeIssue(
        row,
        "error",
        "channel",
        "INVALID_CHANNEL",
        "Channel must be email or sms.",
        channelInput,
      ),
    );

  const targetCountry = normalizeCountry(row.values.target_country ?? "");
  if (targetCountry === undefined)
    issues.push(
      makeIssue(
        row,
        "error",
        "target_country",
        "INVALID_COUNTRY",
        "Target country is invalid.",
        row.values.target_country ?? "",
      ),
    );

  const metricFields = [
    "reported_sent",
    "reported_delivered",
    "reported_bounced",
    "reported_opens",
    "reported_clicks",
  ] as const;
  const metrics = Object.fromEntries(
    metricFields.map((field) => [field, parseNonNegativeInteger(row, field, issues)]),
  ) as Record<(typeof metricFields)[number], number | null>;
  const spendInput = (row.values.spend ?? "").trim().replace(",", ".");
  const spend = Number(spendInput);
  if (!Number.isFinite(spend) || spend < 0)
    issues.push(
      makeIssue(
        row,
        "error",
        "spend",
        "INVALID_SPEND",
        "Spend must be a non-negative number.",
        row.values.spend ?? "",
      ),
    );

  const sentAt = parseTimestamp(row.values.sent_at_utc ?? "", brand);
  if (!sentAt.value)
    issues.push(
      makeIssue(
        row,
        "error",
        "sent_at_utc",
        "INVALID_SENT_TIMESTAMP",
        "sent_at_utc must be an ISO timestamp.",
        row.values.sent_at_utc ?? "",
      ),
    );

  if (Object.values(metrics).every((value) => value !== null)) {
    const sent = metrics.reported_sent!;
    const delivered = metrics.reported_delivered!;
    const bounced = metrics.reported_bounced!;
    const opens = metrics.reported_opens!;
    const clicks = metrics.reported_clicks!;
    if (sent !== delivered + bounced)
      issues.push(
        makeIssue(
          row,
          "warning",
          null,
          "SOURCE_METRIC_INCONSISTENCY",
          "Reported sent does not equal delivered plus bounced.",
        ),
      );
    if (opens > delivered)
      issues.push(
        makeIssue(
          row,
          "warning",
          "reported_opens",
          "SOURCE_METRIC_INCONSISTENCY",
          "Reported opens exceed delivered messages.",
        ),
      );
    if (clicks > opens)
      issues.push(
        makeIssue(
          row,
          "warning",
          "reported_clicks",
          "SOURCE_METRIC_INCONSISTENCY",
          "Reported clicks exceed opens.",
        ),
      );
  }

  if (
    issues.some((issue) => issue.severity === "error") ||
    !channel ||
    targetCountry === undefined ||
    !sentAt.value ||
    Object.values(metrics).some((value) => value === null)
  ) {
    return { value: null, issues };
  }

  const localTime = row.values.send_local_time?.trim() ?? "";
  return {
    value: {
      external_id: externalId,
      name,
      channel,
      target_country_code: targetCountry,
      reported_sent: metrics.reported_sent!,
      reported_delivered: metrics.reported_delivered!,
      reported_bounced: metrics.reported_bounced!,
      reported_opens: metrics.reported_opens!,
      reported_clicks: metrics.reported_clicks!,
      spend,
      sent_at: sentAt.value,
      send_local_time: /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$/.test(localTime) ? `${localTime}:00` : null,
      parent_external_id: row.values.parent_campaign_id?.trim() || null,
    },
    issues,
  };
}

const eventTypes: Record<string, NormalizedEvent["event_type"]> = {
  delivered: "delivered",
  bounce: "bounced",
  bounced: "bounced",
  open: "opened",
  opened: "opened",
  click: "clicked",
  clicked: "clicked",
  unsubscribe: "unsubscribed",
  unsubscribed: "unsubscribed",
  complaint: "complained",
  complained: "complained",
};

export function normalizeEvent(row: SourceRecord, brand: BrandCode) {
  const issues: ImportIssue[] = [];
  for (const [field, value] of Object.entries(row.values)) {
    if (value.includes("\0")) {
      issues.push(
        makeIssue(
          row,
          "error",
          field,
          "UNSUPPORTED_CONTROL_CHARACTER",
          `${field} contains a NUL character that PostgreSQL cannot store.`,
          value,
        ),
      );
    }
  }
  const id = row.values.event_id?.trim() ?? "";
  const contactId = row.values.external_contact_id?.trim() ?? "";
  const campaignId = row.values.campaign_external_id?.trim() ?? "";
  const type = eventTypes[row.values.event_type?.trim().toLowerCase() ?? ""];
  const channelInput = row.values.channel?.trim().toLowerCase() ?? "";
  const channel = (["email", "sms"].includes(channelInput) ? channelInput : null) as Channel | null;
  const occurredAt = parseTimestamp(row.values.occurred_at_utc ?? "", brand);

  if (!id)
    issues.push(makeIssue(row, "error", "event_id", "MISSING_EVENT_ID", "event_id is required."));
  if (!contactId)
    issues.push(
      makeIssue(
        row,
        "error",
        "external_contact_id",
        "MISSING_CONTACT_ID",
        "Event contact ID is required.",
      ),
    );
  if (!campaignId)
    issues.push(
      makeIssue(
        row,
        "error",
        "campaign_external_id",
        "MISSING_CAMPAIGN_ID",
        "Event campaign ID is required.",
      ),
    );
  if (!type)
    issues.push(
      makeIssue(
        row,
        "error",
        "event_type",
        "INVALID_EVENT_TYPE",
        "Event type is not recognized.",
        row.values.event_type ?? "",
      ),
    );
  if (!channel)
    issues.push(
      makeIssue(
        row,
        "error",
        "channel",
        "INVALID_CHANNEL",
        "Channel must be email or sms.",
        channelInput,
      ),
    );
  if (!occurredAt.value)
    issues.push(
      makeIssue(
        row,
        "error",
        "occurred_at_utc",
        "INVALID_EVENT_TIMESTAMP",
        "Event timestamp must be ISO-8601.",
        row.values.occurred_at_utc ?? "",
      ),
    );

  if (issues.some((issue) => issue.severity === "error") || !type || !channel || !occurredAt.value)
    return { value: null, issues };
  const value: NormalizedEvent = {
    provider_event_id: id,
    contact_external_id: contactId,
    campaign_external_id: campaignId,
    event_type: type,
    channel,
    occurred_at: occurredAt.value,
    raw_payload: row.values,
  };
  return { value, issues };
}
