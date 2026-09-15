export type BrandCode = "KILELE" | "KAROO" | "MARRAKECH";
export type Channel = "email" | "sms";
export type LifecycleStatus = "active" | "pending" | "bounced" | "unsubscribed";
export type ChannelStatus = "active" | "unavailable" | "bounced" | "unsubscribed";
export type EventType =
  | "delivered"
  | "bounced"
  | "opened"
  | "clicked"
  | "unsubscribed"
  | "complained";

export interface SourceRecord {
  rowNumber: number;
  values: Record<string, string>;
}

export interface ImportIssue {
  rowNumber: number;
  severity: "warning" | "error";
  fieldName: string | null;
  errorCode: string;
  reason: string;
  rawValue: string | null;
  rawRow: Record<string, string>;
}

export interface NormalizedContact {
  external_id: string;
  full_name: string;
  email: string | null;
  phone: string | null;
  country_code: string | null;
  city: string | null;
  signup_at: string;
  lifecycle_status: LifecycleStatus;
  marketing_consent: boolean;
  deleted_at: string | null;
  suppressed_until: string | null;
  email_status: ChannelStatus;
  sms_status: ChannelStatus;
  notes: string | null;
  source_precedence: number;
}

export interface NormalizedCampaign {
  external_id: string;
  name: string;
  channel: Channel;
  target_country_code: string | null;
  reported_sent: number;
  reported_delivered: number;
  reported_bounced: number;
  reported_opens: number;
  reported_clicks: number;
  spend: number;
  sent_at: string;
  send_local_time: string | null;
  parent_external_id: string | null;
}

export interface NormalizedEvent {
  provider_event_id: string;
  contact_external_id: string;
  campaign_external_id: string;
  event_type: EventType;
  channel: Channel;
  occurred_at: string;
  raw_payload: Record<string, string>;
}
