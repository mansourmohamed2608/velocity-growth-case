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
