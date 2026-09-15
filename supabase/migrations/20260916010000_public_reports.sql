drop policy if exists published_reports_member_select on public.published_reports;
drop policy if exists published_reports_owner_select on public.published_reports;
create policy published_reports_owner_select
on public.published_reports for select to authenticated
using ((select private.is_brand_owner(brand_id)));

create or replace function public.publish_campaign_report(
  target_campaign_id uuid,
  target_token_digest bytea,
  plain_password text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  selected_campaign public.campaigns%rowtype;
  published_id uuid;
begin
  select * into selected_campaign
  from public.campaigns campaign
  where campaign.id = target_campaign_id;
  if not found or not private.is_brand_owner(selected_campaign.brand_id) then
    raise exception 'owner role required' using errcode = '42501';
  end if;
  if octet_length(target_token_digest) <> 32 then
    raise exception 'token digest must be 32 bytes' using errcode = '22023';
  end if;
  if char_length(plain_password) < 12 or char_length(plain_password) > 128 then
    raise exception 'report password must be 12 to 128 characters' using errcode = '22023';
  end if;

  insert into public.published_reports (
    brand_id,
    campaign_id,
    created_by,
    token_digest,
    password_hash
  )
  values (
    selected_campaign.brand_id,
    selected_campaign.id,
    (select auth.uid()),
    target_token_digest,
    extensions.crypt(plain_password, extensions.gen_salt('bf', 12))
  )
  on conflict (brand_id, campaign_id) do update set
    created_by = excluded.created_by,
    token_digest = excluded.token_digest,
    password_hash = excluded.password_hash,
    expires_at = null,
    revoked_at = null
  returning id into published_id;

  delete from public.report_sessions session
  where session.published_report_id = published_id;

  return published_id;
end;
$$;

create or replace function public.create_public_report_session(
  target_token_digest bytea,
  plain_password text,
  target_session_digest bytea
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  selected_report public.published_reports%rowtype;
begin
  if octet_length(target_token_digest) <> 32 or octet_length(target_session_digest) <> 32 then
    return false;
  end if;

  select * into selected_report
  from public.published_reports report
  where report.token_digest = target_token_digest
    and report.revoked_at is null
    and (report.expires_at is null or report.expires_at > now());

  if not found
    or selected_report.password_hash <> extensions.crypt(plain_password, selected_report.password_hash) then
    return false;
  end if;

  insert into public.report_sessions (
    brand_id,
    published_report_id,
    session_digest,
    expires_at
  )
  values (
    selected_report.brand_id,
    selected_report.id,
    target_session_digest,
    now() + interval '1 hour'
  );
  return true;
end;
$$;

create or replace function public.public_campaign_report(target_session_digest bytea)
returns table (
  brand_name text,
  campaign_name text,
  campaign_external_id text,
  channel public.message_channel,
  sent_at timestamptz,
  reported_sent bigint,
  reported_delivered bigint,
  reported_bounced bigint,
  reported_opens bigint,
  reported_clicks bigint,
  spend numeric,
  event_delivered bigint,
  event_bounced bigint,
  event_opened bigint,
  event_clicked bigint,
  event_unsubscribed bigint,
  event_complained bigint
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.report_sessions session
  set last_accessed_at = now()
  from public.published_reports report
  where session.session_digest = target_session_digest
    and session.published_report_id = report.id
    and session.brand_id = report.brand_id
    and session.expires_at > now()
    and report.revoked_at is null
    and (report.expires_at is null or report.expires_at > now());

  if not found then
    return;
  end if;

  return query
  select
    brand.name,
    campaign.name,
    campaign.external_id,
    campaign.channel,
    campaign.sent_at,
    campaign.reported_sent,
    campaign.reported_delivered,
    campaign.reported_bounced,
    campaign.reported_opens,
    campaign.reported_clicks,
    campaign.spend,
    count(distinct event.contact_id) filter (where event.event_type = 'delivered')::bigint,
    count(distinct event.contact_id) filter (where event.event_type = 'bounced')::bigint,
    count(distinct event.contact_id) filter (where event.event_type = 'opened')::bigint,
    count(distinct event.contact_id) filter (where event.event_type = 'clicked')::bigint,
    count(distinct event.contact_id) filter (where event.event_type = 'unsubscribed')::bigint,
    count(distinct event.contact_id) filter (where event.event_type = 'complained')::bigint
  from public.report_sessions session
  join public.published_reports report
    on report.id = session.published_report_id and report.brand_id = session.brand_id
  join public.campaigns campaign
    on campaign.id = report.campaign_id and campaign.brand_id = report.brand_id
  join public.brands brand on brand.id = report.brand_id
  left join public.provider_events event
    on event.campaign_id = campaign.id and event.brand_id = campaign.brand_id
  where session.session_digest = target_session_digest
    and session.expires_at > now()
    and report.revoked_at is null
    and (report.expires_at is null or report.expires_at > now())
  group by brand.name, campaign.id;
end;
$$;

revoke all on function public.publish_campaign_report(uuid, bytea, text) from public, anon;
revoke all on function public.create_public_report_session(bytea, text, bytea) from public;
revoke all on function public.public_campaign_report(bytea) from public;

grant execute on function public.publish_campaign_report(uuid, bytea, text) to authenticated;
grant execute on function public.create_public_report_session(bytea, text, bytea) to anon, authenticated;
grant execute on function public.public_campaign_report(bytea) to anon, authenticated;
