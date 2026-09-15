import { createClient } from "@/lib/supabase/server";

export interface DashboardSummary {
  total_customers: number;
  contactable_customers: number;
  latest_signup_date: string | null;
}

export interface SignupPoint {
  signup_date: string;
  signup_count: number;
  window_end: string;
}

export interface CampaignPerformance {
  id: string;
  external_id: string;
  name: string;
  channel: "email" | "sms";
  sent_at: string;
  reported_sent: number;
  reported_delivered: number;
  reported_bounced: number;
  reported_opens: number;
  reported_clicks: number;
  spend: number;
  event_delivered: number;
  event_bounced: number;
  event_opened: number;
  event_clicked: number;
  event_unsubscribed: number;
  event_complained: number;
  send_status: string | null;
  send_recipient_count: number | null;
}

export interface ContactRow {
  id: string;
  external_id: string;
  full_name: string;
  email: string | null;
  phone: string | null;
  country_code: string | null;
  city: string | null;
  signup_at: string;
  lifecycle_status: string;
  marketing_consent: boolean;
  email_status: string;
  sms_status: string;
  is_contactable: boolean;
  contactability_reason: string;
  total_count: number;
}

export interface ImportRun {
  id: string;
  source_filename: string;
  status: string;
  source_rows: number;
  accepted_rows: number;
  rejected_rows: number;
  warning_rows: number;
  completed_at: string | null;
}

export interface ImportIssue {
  id: number;
  row_number: number;
  severity: "warning" | "error";
  error_code: string;
  reason: string;
}

export interface SendAudienceRow {
  contact_id: string;
  external_id: string;
  full_name: string;
  destination: string;
  country_code: string | null;
  total_count: number;
}

export interface CampaignForSend {
  id: string;
  external_id: string;
  name: string;
  channel: "email" | "sms";
  target_country_code: string | null;
}

export interface CampaignSend {
  id: string;
  source: "imported" | "portal";
  approved_at: string | null;
  recipient_count: number;
  status: string;
  provider_batch_id: string | null;
  accepted_count: number;
  rejected_count: number;
  delivered_count: number;
  opened_count: number;
  bounced_count: number;
  unsubscribed_count: number;
  last_error: string | null;
}

export interface FrozenRecipient {
  id: string;
  contact_external_id: string;
  destination: string;
  status: string;
  approved_snapshot: { full_name?: string; country_code?: string | null };
}

function requireData<T>(data: T | null, error: { message: string } | null, label: string): T {
  if (error) throw new Error(`${label} could not be loaded.`, { cause: error });
  if (data === null) throw new Error(`${label} returned no response.`);
  return data;
}

export async function getDashboardData() {
  const supabase = await createClient();
  const [summaryResult, signupResult, campaignResult, runsResult, issuesResult] = await Promise.all(
    [
      supabase.rpc("portal_dashboard_summary").single(),
      supabase.rpc("portal_signup_series"),
      supabase.rpc("portal_campaign_performance", { result_limit: 6 }),
      supabase
        .from("import_runs")
        .select(
          "id,source_filename,status,source_rows,accepted_rows,rejected_rows,warning_rows,completed_at",
        )
        .order("started_at", { ascending: false })
        .limit(5),
      supabase
        .from("import_errors")
        .select("id,row_number,severity,error_code,reason")
        .order("id", { ascending: false })
        .limit(6),
    ],
  );

  return {
    summary: requireData(
      summaryResult.data as DashboardSummary | null,
      summaryResult.error,
      "Dashboard totals",
    ),
    signups: requireData(signupResult.data as SignupPoint[] | null, signupResult.error, "Signups"),
    campaigns: requireData(
      campaignResult.data as CampaignPerformance[] | null,
      campaignResult.error,
      "Campaign performance",
    ),
    runs: requireData(runsResult.data as ImportRun[] | null, runsResult.error, "Import history"),
    issues: requireData(
      issuesResult.data as ImportIssue[] | null,
      issuesResult.error,
      "Import diagnostics",
    ),
  };
}

export async function getContactsPage(search: string, page: number, pageSize = 25) {
  const supabase = await createClient();
  const offset = (page - 1) * pageSize;
  const [pageResult, countResult] = await Promise.all([
    supabase.rpc("portal_contacts_page", {
      search_text: search || null,
      page_size: pageSize,
      page_offset: offset,
    }),
    supabase.rpc("portal_contacts_count", { search_text: search || null }),
  ]);
  const rows = requireData(pageResult.data as ContactRow[] | null, pageResult.error, "Contacts");
  const total = requireData(countResult.data as number | null, countResult.error, "Contact count");
  return { rows, total, pageSize };
}

export async function getCampaigns() {
  const supabase = await createClient();
  const result = await supabase.rpc("portal_campaign_performance", { result_limit: 100 });
  return requireData(result.data as CampaignPerformance[] | null, result.error, "Campaign history");
}

export async function getSendPreparation(campaignId: string, page: number, pageSize = 25) {
  const supabase = await createClient();
  const campaignResult = await supabase
    .from("campaigns")
    .select("id,external_id,name,channel,target_country_code")
    .eq("id", campaignId)
    .maybeSingle();
  const campaign = requireData(
    campaignResult.data as CampaignForSend | null,
    campaignResult.error,
    "Campaign",
  );

  const sendResult = await supabase
    .from("campaign_sends")
    .select(
      "id,source,approved_at,recipient_count,status,provider_batch_id,accepted_count,rejected_count,delivered_count,opened_count,bounced_count,unsubscribed_count,last_error",
    )
    .eq("campaign_id", campaignId)
    .maybeSingle();
  if (sendResult.error)
    throw new Error("Campaign send could not be loaded.", { cause: sendResult.error });
  const send = sendResult.data as CampaignSend | null;
  const offset = (page - 1) * pageSize;

  if (send) {
    const recipientsResult = await supabase
      .from("campaign_send_recipients")
      .select("id,contact_external_id,destination,status,approved_snapshot", { count: "exact" })
      .eq("send_id", send.id)
      .order("contact_external_id")
      .range(offset, offset + pageSize - 1);
    return {
      campaign,
      send,
      recipients: requireData(
        recipientsResult.data as FrozenRecipient[] | null,
        recipientsResult.error,
        "Approved recipients",
      ),
      total: recipientsResult.count ?? send.recipient_count,
      pageSize,
    };
  }

  const [audienceResult, countResult] = await Promise.all([
    supabase.rpc("portal_send_audience", {
      target_campaign_id: campaignId,
      page_size: pageSize,
      page_offset: offset,
    }),
    supabase.rpc("portal_send_audience_count", { target_campaign_id: campaignId }),
  ]);
  return {
    campaign,
    send: null,
    recipients: requireData(
      audienceResult.data as SendAudienceRow[] | null,
      audienceResult.error,
      "Eligible audience",
    ),
    total: requireData(countResult.data as number | null, countResult.error, "Audience count"),
    pageSize,
  };
}
