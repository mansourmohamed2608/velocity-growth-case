-- Velocity Growth client portal: authoritative base schema.
-- Authorization policies are added in the following tenant-security migration.

create extension if not exists pgcrypto with schema extensions;

create type public.portal_role as enum ('owner', 'analyst');
create type public.message_channel as enum ('email', 'sms');
create type public.contact_lifecycle_status as enum (
  'active',
  'pending',
  'bounced',
  'unsubscribed'
);
create type public.contact_channel_status as enum (
  'active',
  'unavailable',
  'bounced',
  'unsubscribed',
  'complained'
);
create type public.import_status as enum ('running', 'completed', 'completed_with_errors', 'failed');
create type public.import_issue_severity as enum ('warning', 'error');
create type public.send_source as enum ('imported', 'portal');
create type public.send_status as enum (
  'approved',
  'dispatching',
  'submitted',
  'partial',
  'completed',
  'failed'
);
create type public.recipient_status as enum (
  'frozen',
  'accepted',
  'rejected',
  'delivered',
  'opened',
  'bounced',
  'unsubscribed',
  'complained'
);
create type public.event_source as enum ('seed', 'provider');
create type public.engagement_event_type as enum (
  'delivered',
  'bounced',
  'opened',
  'clicked',
  'unsubscribed',
  'complained'
);

create table public.brands (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[A-Z][A-Z0-9_]*$'),
  name text not null unique check (btrim(name) <> ''),
  country_code text not null check (country_code ~ '^[A-Z]{2}$'),
  time_zone text not null check (btrim(time_zone) <> ''),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, code)
);

create table public.brand_memberships (
  brand_id uuid not null references public.brands(id) on delete restrict,
  user_id uuid not null references auth.users(id) on delete cascade,
  role public.portal_role not null,
  created_at timestamptz not null default now(),
  primary key (brand_id, user_id),
  unique (user_id)
);

create table public.import_runs (
  id uuid primary key default gen_random_uuid(),
  brand_id uuid not null references public.brands(id) on delete restrict,
  source_filename text not null check (btrim(source_filename) <> ''),
  source_kind text not null check (source_kind in ('contacts', 'contacts_delta', 'campaigns', 'events', 'send_log')),
  content_sha256 text not null check (content_sha256 ~ '^[0-9a-f]{64}$'),
  status public.import_status not null default 'running',
  source_rows integer not null default 0 check (source_rows >= 0),
  accepted_rows integer not null default 0 check (accepted_rows >= 0),
  rejected_rows integer not null default 0 check (rejected_rows >= 0),
  warning_rows integer not null default 0 check (warning_rows >= 0),
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  failure_reason text,
  created_by uuid references auth.users(id) on delete set null,
  check (accepted_rows + rejected_rows <= source_rows),
  check (
    (status = 'running' and completed_at is null)
    or (status <> 'running' and completed_at is not null)
  ),
  unique (brand_id, id)
);

create table public.import_errors (
  id bigint generated always as identity primary key,
  brand_id uuid not null references public.brands(id) on delete restrict,
  import_run_id uuid not null,
  row_number integer not null check (row_number >= 2),
  severity public.import_issue_severity not null default 'error',
  field_name text,
  error_code text not null check (btrim(error_code) <> ''),
  reason text not null check (btrim(reason) <> ''),
  raw_value text,
  raw_row jsonb not null default '{}'::jsonb check (jsonb_typeof(raw_row) = 'object'),
  created_at timestamptz not null default now(),
  foreign key (brand_id, import_run_id)
    references public.import_runs(brand_id, id) on delete cascade,
  unique (import_run_id, row_number, error_code, field_name)
);

create table public.contacts (
  id uuid primary key default gen_random_uuid(),
  brand_id uuid not null references public.brands(id) on delete restrict,
  external_id text not null check (external_id ~ '^CT-[0-9]{6}$'),
  full_name text not null check (btrim(full_name) <> ''),
  email text check (email is null or (email = lower(email) and email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$')),
  phone text check (phone is null or btrim(phone) <> ''),
  country_code text check (country_code is null or country_code ~ '^[A-Z]{2}$'),
  city text,
  signup_at timestamptz not null,
  lifecycle_status public.contact_lifecycle_status not null,
  marketing_consent boolean not null,
  deleted_at timestamptz,
  suppressed_until timestamptz,
  email_status public.contact_channel_status not null default 'unavailable',
  sms_status public.contact_channel_status not null default 'unavailable',
  notes text,
  source_updated_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (brand_id, external_id),
  unique (brand_id, id),
  check (email is not null or phone is not null),
  check (deleted_at is null or deleted_at >= signup_at)
);

create table public.campaigns (
  id uuid primary key default gen_random_uuid(),
  brand_id uuid not null references public.brands(id) on delete restrict,
  external_id text not null check (btrim(external_id) <> ''),
  name text not null check (btrim(name) <> ''),
  channel public.message_channel not null,
  target_country_code text check (target_country_code is null or target_country_code ~ '^[A-Z]{2}$'),
  reported_sent bigint not null default 0 check (reported_sent >= 0),
  reported_delivered bigint not null default 0 check (reported_delivered >= 0),
  reported_bounced bigint not null default 0 check (reported_bounced >= 0),
  reported_opens bigint not null default 0 check (reported_opens >= 0),
  reported_clicks bigint not null default 0 check (reported_clicks >= 0),
  spend numeric(14, 2) not null default 0 check (spend >= 0),
  sent_at timestamptz not null,
  send_local_time timestamp without time zone,
  parent_campaign_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (brand_id, external_id),
  unique (brand_id, id),
  foreign key (brand_id, parent_campaign_id)
    references public.campaigns(brand_id, id) on delete set null,
  check (parent_campaign_id is null or parent_campaign_id <> id)
);

create table public.campaign_sends (
  id uuid primary key default gen_random_uuid(),
  brand_id uuid not null,
  campaign_id uuid not null,
  source public.send_source not null default 'portal',
  confirmation_key uuid,
  approved_by uuid references auth.users(id) on delete restrict,
  approved_at timestamptz,
  recipient_count integer not null check (recipient_count >= 0),
  status public.send_status not null,
  provider_batch_id text,
  provider_cursor text,
  accepted_count integer not null default 0 check (accepted_count >= 0),
  rejected_count integer not null default 0 check (rejected_count >= 0),
  delivered_count integer not null default 0 check (delivered_count >= 0),
  opened_count integer not null default 0 check (opened_count >= 0),
  bounced_count integer not null default 0 check (bounced_count >= 0),
  unsubscribed_count integer not null default 0 check (unsubscribed_count >= 0),
  last_error text,
  dispatch_attempts integer not null default 0 check (dispatch_attempts >= 0),
  dispatched_at timestamptz,
  reconciled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (brand_id, campaign_id),
  unique (brand_id, id),
  foreign key (brand_id, campaign_id)
    references public.campaigns(brand_id, id) on delete restrict,
  check (
    (source = 'portal' and confirmation_key is not null and approved_by is not null and approved_at is not null)
    or (source = 'imported' and confirmation_key is null and approved_by is null)
  ),
  check (accepted_count + rejected_count <= recipient_count),
  check (delivered_count <= accepted_count),
  check (opened_count <= accepted_count),
  check (bounced_count <= accepted_count),
  check (unsubscribed_count <= accepted_count)
);

create unique index campaign_sends_provider_batch_uidx
  on public.campaign_sends (provider_batch_id)
  where provider_batch_id is not null;

create table public.campaign_send_recipients (
  id uuid primary key default gen_random_uuid(),
  brand_id uuid not null,
  send_id uuid not null,
  contact_id uuid not null,
  contact_external_id text not null,
  channel public.message_channel not null,
  destination text not null check (btrim(destination) <> ''),
  approved_snapshot jsonb not null check (jsonb_typeof(approved_snapshot) = 'object'),
  status public.recipient_status not null default 'frozen',
  provider_recipient_id text,
  provider_error text,
  accepted_at timestamptz,
  delivered_at timestamptz,
  first_opened_at timestamptz,
  bounced_at timestamptz,
  unsubscribed_at timestamptz,
  complained_at timestamptz,
  last_event_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (send_id, contact_id),
  unique (brand_id, send_id, id),
  foreign key (brand_id, send_id)
    references public.campaign_sends(brand_id, id) on delete restrict,
  foreign key (brand_id, contact_id)
    references public.contacts(brand_id, id) on delete restrict
);

create table public.provider_events (
  id bigint generated always as identity primary key,
  brand_id uuid not null,
  campaign_id uuid not null,
  contact_id uuid not null,
  send_id uuid,
  send_recipient_id uuid,
  source public.event_source not null,
  provider_event_id text not null check (btrim(provider_event_id) <> ''),
  event_type public.engagement_event_type not null,
  channel public.message_channel not null,
  occurred_at timestamptz not null,
  raw_payload jsonb not null default '{}'::jsonb check (jsonb_typeof(raw_payload) = 'object'),
  received_at timestamptz not null default now(),
  unique (brand_id, source, provider_event_id),
  foreign key (brand_id, campaign_id)
    references public.campaigns(brand_id, id) on delete restrict,
  foreign key (brand_id, contact_id)
    references public.contacts(brand_id, id) on delete restrict,
  foreign key (brand_id, send_id)
    references public.campaign_sends(brand_id, id) on delete restrict,
  foreign key (brand_id, send_id, send_recipient_id)
    references public.campaign_send_recipients(brand_id, send_id, id) on delete restrict,
  check (
    (send_id is null and send_recipient_id is null)
    or (send_id is not null and send_recipient_id is not null)
  )
);

create table public.published_reports (
  id uuid primary key default gen_random_uuid(),
  brand_id uuid not null,
  campaign_id uuid not null,
  created_by uuid not null references auth.users(id) on delete restrict,
  token_digest bytea not null unique check (octet_length(token_digest) = 32),
  password_hash text not null check (char_length(password_hash) >= 50),
  expires_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (brand_id, id),
  unique (brand_id, campaign_id),
  foreign key (brand_id, campaign_id)
    references public.campaigns(brand_id, id) on delete restrict,
  check (expires_at is null or expires_at > created_at),
  check (revoked_at is null or revoked_at >= created_at)
);

create table public.report_sessions (
  id uuid primary key default gen_random_uuid(),
  brand_id uuid not null,
  published_report_id uuid not null,
  session_digest bytea not null unique check (octet_length(session_digest) = 32),
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  last_accessed_at timestamptz not null default now(),
  foreign key (brand_id, published_report_id)
    references public.published_reports(brand_id, id) on delete cascade,
  check (expires_at > created_at)
);

create index contacts_brand_signup_idx on public.contacts (brand_id, signup_at desc, id);
create index contacts_brand_name_idx on public.contacts (brand_id, full_name, id);
create index contacts_brand_email_idx on public.contacts (brand_id, email) where email is not null;
create index campaigns_brand_sent_idx on public.campaigns (brand_id, sent_at desc, id);
create index import_runs_brand_started_idx on public.import_runs (brand_id, started_at desc);
create index import_errors_brand_run_idx on public.import_errors (brand_id, import_run_id, row_number);
create index campaign_sends_brand_status_idx on public.campaign_sends (brand_id, status, created_at);
create index campaign_send_recipients_send_status_idx on public.campaign_send_recipients (send_id, status);
create index provider_events_campaign_time_idx on public.provider_events (brand_id, campaign_id, occurred_at, id);
create index provider_events_contact_time_idx on public.provider_events (brand_id, contact_id, occurred_at, id);
create index provider_events_send_time_idx on public.provider_events (send_id, occurred_at, id) where send_id is not null;
create index report_sessions_expiry_idx on public.report_sessions (expires_at);

create function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create function public.protect_send_approval()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if row(
    new.brand_id,
    new.campaign_id,
    new.source,
    new.confirmation_key,
    new.approved_by,
    new.approved_at,
    new.recipient_count
  ) is distinct from row(
    old.brand_id,
    old.campaign_id,
    old.source,
    old.confirmation_key,
    old.approved_by,
    old.approved_at,
    old.recipient_count
  ) then
    raise exception 'approved send identity and audience are immutable';
  end if;
  return new;
end;
$$;

create function public.protect_recipient_snapshot()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if row(
    new.brand_id,
    new.send_id,
    new.contact_id,
    new.contact_external_id,
    new.channel,
    new.destination,
    new.approved_snapshot
  ) is distinct from row(
    old.brand_id,
    old.send_id,
    old.contact_id,
    old.contact_external_id,
    old.channel,
    old.destination,
    old.approved_snapshot
  ) then
    raise exception 'approved recipient snapshot is immutable';
  end if;
  return new;
end;
$$;

create trigger brands_set_updated_at before update on public.brands
for each row execute function public.set_updated_at();
create trigger contacts_set_updated_at before update on public.contacts
for each row execute function public.set_updated_at();
create trigger campaigns_set_updated_at before update on public.campaigns
for each row execute function public.set_updated_at();
create trigger campaign_sends_set_updated_at before update on public.campaign_sends
for each row execute function public.set_updated_at();
create trigger campaign_send_recipients_set_updated_at before update on public.campaign_send_recipients
for each row execute function public.set_updated_at();
create trigger published_reports_set_updated_at before update on public.published_reports
for each row execute function public.set_updated_at();
create trigger campaign_sends_protect_approval before update on public.campaign_sends
for each row execute function public.protect_send_approval();
create trigger campaign_send_recipients_protect_snapshot before update on public.campaign_send_recipients
for each row execute function public.protect_recipient_snapshot();

insert into public.brands (id, code, name, country_code, time_zone)
values
  ('11111111-1111-4111-8111-111111111111', 'KILELE', 'Kilele Rides', 'KE', 'Africa/Nairobi'),
  ('22222222-2222-4222-8222-222222222222', 'KAROO', 'Karoo Coaches', 'ZA', 'Africa/Johannesburg'),
  ('33333333-3333-4333-8333-333333333333', 'MARRAKECH', 'Marrakech Express', 'MA', 'Africa/Casablanca')
on conflict (code) do update
set name = excluded.name,
    country_code = excluded.country_code,
    time_zone = excluded.time_zone;

