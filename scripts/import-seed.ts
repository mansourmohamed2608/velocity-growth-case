import { createHash } from "node:crypto";
import { access, readFile } from "node:fs/promises";
import path from "node:path";

import postgres, { type Sql } from "postgres";

import { readSourceCsv } from "./importer/csv";
import { normalizeCampaign, normalizeContact, normalizeEvent } from "./importer/normalize";
import type {
  BrandCode,
  ImportIssue,
  NormalizedCampaign,
  NormalizedContact,
  NormalizedEvent,
  SourceRecord,
} from "./importer/types";

type SourceKind = "contacts" | "contacts_delta" | "campaigns" | "events" | "send_log";

interface FileConfig {
  filename: string;
  brand: BrandCode;
  kind: SourceKind;
  delimiter: "," | ";";
  encoding: "utf8" | "win1252";
  sourcePrecedence?: number;
}

const files: FileConfig[] = [
  {
    filename: "kilele-contacts.csv",
    brand: "KILELE",
    kind: "contacts",
    delimiter: ",",
    encoding: "utf8",
    sourcePrecedence: 0,
  },
  {
    filename: "kilele-contacts-delta-2026-09-01.csv",
    brand: "KILELE",
    kind: "contacts_delta",
    delimiter: ",",
    encoding: "utf8",
    sourcePrecedence: 10,
  },
  {
    filename: "karoo-contacts.csv",
    brand: "KAROO",
    kind: "contacts",
    delimiter: ",",
    encoding: "win1252",
    sourcePrecedence: 0,
  },
  {
    filename: "marrakech-contacts.csv",
    brand: "MARRAKECH",
    kind: "contacts",
    delimiter: ";",
    encoding: "utf8",
    sourcePrecedence: 0,
  },
  {
    filename: "kilele-campaigns.csv",
    brand: "KILELE",
    kind: "campaigns",
    delimiter: ",",
    encoding: "utf8",
  },
  {
    filename: "karoo-campaigns.csv",
    brand: "KAROO",
    kind: "campaigns",
    delimiter: ",",
    encoding: "utf8",
  },
  {
    filename: "marrakech-campaigns.csv",
    brand: "MARRAKECH",
    kind: "campaigns",
    delimiter: ";",
    encoding: "utf8",
  },
  {
    filename: "kilele-send-log.csv",
    brand: "KILELE",
    kind: "send_log",
    delimiter: ",",
    encoding: "utf8",
  },
  {
    filename: "kilele-events.csv",
    brand: "KILELE",
    kind: "events",
    delimiter: ",",
    encoding: "utf8",
  },
  {
    filename: "karoo-events.csv",
    brand: "KAROO",
    kind: "events",
    delimiter: ",",
    encoding: "utf8",
  },
  {
    filename: "marrakech-events.csv",
    brand: "MARRAKECH",
    kind: "events",
    delimiter: ";",
    encoding: "utf8",
  },
];

interface FileResult {
  sourceRows: number;
  acceptedRows: number;
  rejectedRows: number;
  warningRows: number;
}

const chunk = <T>(values: T[], size = 1_000) => {
  const chunks: T[][] = [];
  for (let index = 0; index < values.length; index += size)
    chunks.push(values.slice(index, index + size));
  return chunks;
};

function issueForDuplicate(row: SourceRecord, entity: string): ImportIssue {
  return {
    rowNumber: row.rowNumber,
    severity: "warning",
    fieldName: "external_id",
    errorCode: "DUPLICATE_SOURCE_KEY",
    reason: `A later ${entity} row has the same source key; deterministic file order decides the stored value.`,
    rawValue: row.values.external_id ?? row.values.event_id ?? null,
    rawRow: row.values,
  };
}

async function persistIssues(sql: Sql, brandId: string, runId: string, issues: ImportIssue[]) {
  const values = issues.map((issue) => ({
    brand_id: brandId,
    import_run_id: runId,
    row_number: issue.rowNumber,
    severity: issue.severity,
    field_name: issue.fieldName,
    error_code: issue.errorCode,
    reason: issue.reason,
    raw_value: issue.rawValue,
    raw_row: issue.rawRow,
  }));
  for (const batch of chunk(values)) {
    await sql`
      insert into public.import_errors (
        brand_id, import_run_id, row_number, severity, field_name,
        error_code, reason, raw_value, raw_row
      )
      select
        issue.brand_id, issue.import_run_id, issue.row_number, issue.severity,
        issue.field_name, issue.error_code, issue.reason, issue.raw_value, issue.raw_row
      from jsonb_to_recordset(${sql.json(batch)}) as issue(
        brand_id uuid,
        import_run_id uuid,
        row_number integer,
        severity public.import_issue_severity,
        field_name text,
        error_code text,
        reason text,
        raw_value text,
        raw_row jsonb
      )
      on conflict do nothing
    `;
  }
}

function resultFrom(rows: SourceRecord[], accepted: number, issues: ImportIssue[]): FileResult {
  const rejectedRows = new Set(
    issues.filter((issue) => issue.severity === "error").map((issue) => issue.rowNumber),
  ).size;
  const warningRows = new Set(
    issues.filter((issue) => issue.severity === "warning").map((issue) => issue.rowNumber),
  ).size;
  return { sourceRows: rows.length, acceptedRows: accepted, rejectedRows, warningRows };
}

async function importContacts(
  sql: Sql,
  rows: SourceRecord[],
  config: FileConfig,
  brandId: string,
  runId: string,
) {
  const contacts = new Map<string, NormalizedContact>();
  const issues: ImportIssue[] = [];
  let accepted = 0;

  for (const row of rows) {
    const normalized = normalizeContact(row, config.brand, config.sourcePrecedence ?? 0);
    issues.push(...normalized.issues);
    if (!normalized.value) continue;
    accepted += 1;
    if (contacts.has(normalized.value.external_id)) issues.push(issueForDuplicate(row, "contact"));
    contacts.set(normalized.value.external_id, normalized.value);
  }

  await sql.begin(async (transaction) => {
    const values = [...contacts.values()].map((contact) => ({ brand_id: brandId, ...contact }));
    for (const batch of chunk(values, 500)) {
      await transaction`
        insert into public.contacts ${transaction(
          batch,
          "brand_id",
          "external_id",
          "full_name",
          "email",
          "phone",
          "country_code",
          "city",
          "signup_at",
          "lifecycle_status",
          "marketing_consent",
          "deleted_at",
          "suppressed_until",
          "email_status",
          "sms_status",
          "notes",
          "source_precedence",
        )}
        on conflict (brand_id, external_id) do update set
          full_name = excluded.full_name,
          email = excluded.email,
          phone = excluded.phone,
          country_code = excluded.country_code,
          city = excluded.city,
          signup_at = excluded.signup_at,
          lifecycle_status = excluded.lifecycle_status,
          marketing_consent = excluded.marketing_consent,
          deleted_at = excluded.deleted_at,
          suppressed_until = excluded.suppressed_until,
          email_status = excluded.email_status,
          sms_status = excluded.sms_status,
          notes = excluded.notes,
          source_precedence = excluded.source_precedence,
          source_updated_at = now()
        where excluded.source_precedence >= public.contacts.source_precedence
      `;
    }
    await persistIssues(transaction, brandId, runId, issues);
  });
  return resultFrom(rows, accepted, issues);
}

async function importCampaigns(
  sql: Sql,
  rows: SourceRecord[],
  config: FileConfig,
  brandId: string,
  runId: string,
) {
  const campaigns = new Map<string, NormalizedCampaign>();
  const issues: ImportIssue[] = [];
  let accepted = 0;
  for (const row of rows) {
    const normalized = normalizeCampaign(row, config.brand);
    issues.push(...normalized.issues);
    if (!normalized.value) continue;
    accepted += 1;
    if (campaigns.has(normalized.value.external_id))
      issues.push(issueForDuplicate(row, "campaign"));
    campaigns.set(normalized.value.external_id, normalized.value);
  }

  await sql.begin(async (transaction) => {
    const values = [...campaigns.values()].map(({ parent_external_id: _, ...campaign }) => ({
      brand_id: brandId,
      ...campaign,
    }));
    for (const batch of chunk(values, 500)) {
      await transaction`
        insert into public.campaigns ${transaction(
          batch,
          "brand_id",
          "external_id",
          "name",
          "channel",
          "target_country_code",
          "reported_sent",
          "reported_delivered",
          "reported_bounced",
          "reported_opens",
          "reported_clicks",
          "spend",
          "sent_at",
          "send_local_time",
        )}
        on conflict (brand_id, external_id) do update set
          name = excluded.name,
          channel = excluded.channel,
          target_country_code = excluded.target_country_code,
          reported_sent = excluded.reported_sent,
          reported_delivered = excluded.reported_delivered,
          reported_bounced = excluded.reported_bounced,
          reported_opens = excluded.reported_opens,
          reported_clicks = excluded.reported_clicks,
          spend = excluded.spend,
          sent_at = excluded.sent_at,
          send_local_time = excluded.send_local_time
      `;
    }

    const ids = await transaction<{ id: string; external_id: string }[]>`
      select id, external_id from public.campaigns where brand_id = ${brandId}
    `;
    const campaignIds = new Map(ids.map((campaign) => [campaign.external_id, campaign.id]));
    for (const [externalId, campaign] of campaigns) {
      if (!campaign.parent_external_id) continue;
      const parentId = campaignIds.get(campaign.parent_external_id);
      if (!parentId) {
        const sourceRow = rows.find((row) => row.values.external_id?.trim() === externalId)!;
        issues.push({
          rowNumber: sourceRow.rowNumber,
          severity: "warning",
          fieldName: "parent_campaign_id",
          errorCode: "UNKNOWN_PARENT_CAMPAIGN",
          reason: "Parent campaign is absent from this brand and was not linked.",
          rawValue: campaign.parent_external_id,
          rawRow: sourceRow.values,
        });
        continue;
      }
      await transaction`
        update public.campaigns set parent_campaign_id = ${parentId}
        where brand_id = ${brandId} and external_id = ${externalId}
      `;
    }
    await persistIssues(transaction, brandId, runId, issues);
  });
  return resultFrom(rows, accepted, issues);
}

async function importEvents(
  sql: Sql,
  rows: SourceRecord[],
  config: FileConfig,
  brandId: string,
  runId: string,
) {
  const contactRows = await sql<{ id: string; external_id: string }[]>`
    select id, external_id from public.contacts where brand_id = ${brandId}
  `;
  const campaignRows = await sql<{ id: string; external_id: string }[]>`
    select id, external_id from public.campaigns where brand_id = ${brandId}
  `;
  const contacts = new Map(contactRows.map((record) => [record.external_id, record.id]));
  const campaigns = new Map(campaignRows.map((record) => [record.external_id, record.id]));
  const events = new Map<string, NormalizedEvent>();
  const issues: ImportIssue[] = [];
  let accepted = 0;

  for (const row of rows) {
    const normalized = normalizeEvent(row, config.brand);
    issues.push(...normalized.issues);
    if (!normalized.value) continue;
    const event = normalized.value;
    if (!contacts.has(event.contact_external_id)) {
      issues.push({
        rowNumber: row.rowNumber,
        severity: "error",
        fieldName: "external_contact_id",
        errorCode: "UNKNOWN_CONTACT",
        reason: "Event contact was not imported for this brand.",
        rawValue: event.contact_external_id,
        rawRow: row.values,
      });
      continue;
    }
    if (!campaigns.has(event.campaign_external_id)) {
      issues.push({
        rowNumber: row.rowNumber,
        severity: "error",
        fieldName: "campaign_external_id",
        errorCode: "UNKNOWN_CAMPAIGN",
        reason: "Event campaign was not imported for this brand.",
        rawValue: event.campaign_external_id,
        rawRow: row.values,
      });
      continue;
    }
    accepted += 1;
    if (events.has(event.provider_event_id)) issues.push(issueForDuplicate(row, "event"));
    events.set(event.provider_event_id, event);
  }

  await sql.begin(async (transaction) => {
    const values = [...events.values()].map((event) => ({
      brand_id: brandId,
      campaign_id: campaigns.get(event.campaign_external_id)!,
      contact_id: contacts.get(event.contact_external_id)!,
      source: "seed",
      provider_event_id: event.provider_event_id,
      event_type: event.event_type,
      channel: event.channel,
      occurred_at: event.occurred_at,
      raw_payload: event.raw_payload,
    }));
    for (const batch of chunk(values, 750)) {
      await transaction`
        insert into public.provider_events ${transaction(
          batch,
          "brand_id",
          "campaign_id",
          "contact_id",
          "source",
          "provider_event_id",
          "event_type",
          "channel",
          "occurred_at",
          "raw_payload",
        )}
        on conflict (brand_id, source, provider_event_id) do nothing
      `;
    }
    await persistIssues(transaction, brandId, runId, issues);
  });
  return resultFrom(rows, accepted, issues);
}

async function importSendLog(sql: Sql, rows: SourceRecord[], brandId: string, runId: string) {
  const campaignRows = await sql<{ id: string; external_id: string }[]>`
    select id, external_id from public.campaigns where brand_id = ${brandId}
  `;
  const campaigns = new Map(campaignRows.map((record) => [record.external_id, record.id]));
  const issues: ImportIssue[] = [];
  const sends = new Map<string, Record<string, unknown>>();
  let accepted = 0;

  for (const row of rows) {
    const campaignId = campaigns.get(row.values.campaign_external_id?.trim() ?? "");
    const recipientCount = Number(row.values.recipient_count);
    const queuedAt = new Date(row.values.queued_at_utc ?? "");
    if (!campaignId)
      issues.push({
        rowNumber: row.rowNumber,
        severity: "error",
        fieldName: "campaign_external_id",
        errorCode: "UNKNOWN_CAMPAIGN",
        reason: "Send-log campaign was not imported for this brand.",
        rawValue: row.values.campaign_external_id ?? null,
        rawRow: row.values,
      });
    if (!Number.isSafeInteger(recipientCount) || recipientCount < 0)
      issues.push({
        rowNumber: row.rowNumber,
        severity: "error",
        fieldName: "recipient_count",
        errorCode: "INVALID_COUNT",
        reason: "recipient_count must be a non-negative integer.",
        rawValue: row.values.recipient_count ?? null,
        rawRow: row.values,
      });
    if (Number.isNaN(queuedAt.valueOf()))
      issues.push({
        rowNumber: row.rowNumber,
        severity: "error",
        fieldName: "queued_at_utc",
        errorCode: "INVALID_TIMESTAMP",
        reason: "queued_at_utc must be ISO-8601.",
        rawValue: row.values.queued_at_utc ?? null,
        rawRow: row.values,
      });
    if (
      !campaignId ||
      !Number.isSafeInteger(recipientCount) ||
      recipientCount < 0 ||
      Number.isNaN(queuedAt.valueOf())
    )
      continue;
    accepted += 1;
    if (sends.has(campaignId)) {
      issues.push({
        rowNumber: row.rowNumber,
        severity: "warning",
        fieldName: "batch_key",
        errorCode: "DUPLICATE_SOURCE_KEY",
        reason:
          "This send-log campaign/batch already appeared; one deterministic imported send is stored.",
        rawValue: row.values.batch_key ?? null,
        rawRow: row.values,
      });
    }
    sends.set(campaignId, {
      brand_id: brandId,
      campaign_id: campaignId,
      source: "imported",
      approved_at: queuedAt.toISOString(),
      recipient_count: recipientCount,
      status: "submitted",
      provider_batch_id: row.values.batch_key.trim(),
      accepted_count: recipientCount,
    });
  }

  await sql.begin(async (transaction) => {
    const values = [...sends.values()];
    if (values.length) {
      await transaction`
        insert into public.campaign_sends ${transaction(values, "brand_id", "campaign_id", "source", "approved_at", "recipient_count", "status", "provider_batch_id", "accepted_count")}
        on conflict (brand_id, campaign_id) do update set
          provider_batch_id = excluded.provider_batch_id,
          approved_at = excluded.approved_at,
          recipient_count = excluded.recipient_count,
          accepted_count = excluded.accepted_count,
          status = excluded.status
        where public.campaign_sends.source = 'imported'
      `;
    }
    await persistIssues(transaction, brandId, runId, issues);
  });
  return resultFrom(rows, accepted, issues);
}

async function sha256(filePath: string) {
  return createHash("sha256")
    .update(await readFile(filePath))
    .digest("hex");
}

async function main() {
  const seedDir = path.resolve(process.env.SOURCE_DATA_DIR ?? ".work/seed");
  const databaseUrl =
    process.env.DATABASE_URL ?? "postgresql://postgres:postgres@127.0.0.1:54322/postgres";
  await Promise.all(files.map((file) => access(path.join(seedDir, file.filename))));

  const sql = postgres(databaseUrl, { max: 4, onnotice: () => undefined });
  let hasImporterLock = false;
  try {
    const [lock] = await sql<{ acquired: boolean }[]>`
      select pg_try_advisory_lock(hashtextextended('velocity-growth-seed-import', 0)) as acquired
    `;
    if (!lock.acquired) throw new Error("Another seed importer is already running.");
    hasImporterLock = true;
    await sql`
      update public.import_runs
      set status = 'failed',
          failure_reason = 'A previous importer process ended before completing this file.',
          completed_at = now()
      where status = 'running'
    `;

    const brandRows = await sql<
      { id: string; code: BrandCode }[]
    >`select id, code from public.brands`;
    const brands = new Map(brandRows.map((brand) => [brand.code, brand.id]));
    for (const config of files) {
      const filePath = path.join(seedDir, config.filename);
      const brandId = brands.get(config.brand);
      if (!brandId) throw new Error(`Missing brand ${config.brand}`);
      const digest = await sha256(filePath);
      const [run] = await sql<{ id: string }[]>`
        insert into public.import_runs (brand_id, source_filename, source_kind, content_sha256)
        values (${brandId}, ${config.filename}, ${config.kind}, ${digest})
        returning id
      `;

      try {
        const rows = await readSourceCsv(filePath, config);
        let result: FileResult;
        if (config.kind === "contacts" || config.kind === "contacts_delta")
          result = await importContacts(sql, rows, config, brandId, run.id);
        else if (config.kind === "campaigns")
          result = await importCampaigns(sql, rows, config, brandId, run.id);
        else if (config.kind === "events")
          result = await importEvents(sql, rows, config, brandId, run.id);
        else result = await importSendLog(sql, rows, brandId, run.id);

        const status =
          result.rejectedRows || result.warningRows ? "completed_with_errors" : "completed";
        await sql`
          update public.import_runs set
            status = ${status}, source_rows = ${result.sourceRows}, accepted_rows = ${result.acceptedRows},
            rejected_rows = ${result.rejectedRows}, warning_rows = ${result.warningRows}, completed_at = now()
          where id = ${run.id}
        `;
        console.log(
          `${config.filename}: ${result.acceptedRows} accepted, ${result.rejectedRows} rejected, ${result.warningRows} warned`,
        );
      } catch (error) {
        const message = error instanceof Error ? error.message : "Unknown import failure";
        await sql`update public.import_runs set status = 'failed', failure_reason = ${message}, completed_at = now() where id = ${run.id}`;
        throw error;
      }
    }
  } finally {
    if (hasImporterLock) {
      await sql`select pg_advisory_unlock(hashtextextended('velocity-growth-seed-import', 0))`;
    }
    await sql.end();
  }
}

main().catch((error) => {
  if (error instanceof Error) {
    const databaseError = error as Error & {
      code?: string;
      table_name?: string;
      constraint_name?: string;
    };
    console.error(
      [
        databaseError.message,
        databaseError.code,
        databaseError.table_name,
        databaseError.constraint_name,
      ]
        .filter(Boolean)
        .join(" · "),
    );
  } else {
    console.error("Unknown import failure");
  }
  process.exitCode = 1;
});
