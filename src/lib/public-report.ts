import { createHash } from "node:crypto";

import { createClient as createSupabaseClient } from "@supabase/supabase-js";

export const reportTokenPattern = /^[A-Za-z0-9_-]{43}$/;

export function digestForPostgres(value: string) {
  return `\\x${createHash("sha256").update(value).digest("hex")}`;
}

export function reportCookieName(token: string) {
  return `relay_report_${createHash("sha256").update(token).digest("hex").slice(0, 12)}`;
}

export function createPublicClient() {
  return createSupabaseClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,
    { auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false } },
  );
}

export interface PublicCampaignReport {
  brand_name: string;
  campaign_name: string;
  campaign_external_id: string;
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
}
