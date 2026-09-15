-- Campaign metrics must remain bounded for the largest tenant. The covering
-- index supports an index-only unique-customer scan, while the definer function
-- resolves exactly one caller membership before bypassing per-event RLS checks.

create index provider_events_brand_campaign_type_contact_idx
on public.provider_events (brand_id, campaign_id, event_type, contact_id);

create or replace function public.portal_campaign_performance(result_limit integer default 100)
returns table (
  id uuid,
  external_id text,
  name text,
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
  event_complained bigint,
  send_status public.send_status,
  send_recipient_count integer
)
language sql
stable
security definer
set search_path = ''
as $$
  with tenant as (
    select private.current_brand_id() as brand_id
  ), unique_events as (
    select distinct event.campaign_id, event.event_type, event.contact_id
    from public.provider_events event
    cross join tenant
    where event.brand_id = tenant.brand_id
  ), event_totals as (
    select
      event.campaign_id,
      count(*) filter (where event.event_type = 'delivered')::bigint as delivered,
      count(*) filter (where event.event_type = 'bounced')::bigint as bounced,
      count(*) filter (where event.event_type = 'opened')::bigint as opened,
      count(*) filter (where event.event_type = 'clicked')::bigint as clicked,
      count(*) filter (where event.event_type = 'unsubscribed')::bigint as unsubscribed,
      count(*) filter (where event.event_type = 'complained')::bigint as complained
    from unique_events event
    group by event.campaign_id
  )
  select
    campaign.id,
    campaign.external_id,
    campaign.name,
    campaign.channel,
    campaign.sent_at,
    campaign.reported_sent,
    campaign.reported_delivered,
    campaign.reported_bounced,
    campaign.reported_opens,
    campaign.reported_clicks,
    campaign.spend,
    coalesce(event_totals.delivered, 0)::bigint,
    coalesce(event_totals.bounced, 0)::bigint,
    coalesce(event_totals.opened, 0)::bigint,
    coalesce(event_totals.clicked, 0)::bigint,
    coalesce(event_totals.unsubscribed, 0)::bigint,
    coalesce(event_totals.complained, 0)::bigint,
    send.status,
    send.recipient_count
  from public.campaigns campaign
  cross join tenant
  left join event_totals on event_totals.campaign_id = campaign.id
  left join public.campaign_sends send
    on send.brand_id = tenant.brand_id
   and send.campaign_id = campaign.id
  where campaign.brand_id = tenant.brand_id
  order by campaign.sent_at desc, campaign.id
  limit greatest(1, least(coalesce(result_limit, 100), 100));
$$;

revoke all on function public.portal_campaign_performance(integer) from public, anon;
grant execute on function public.portal_campaign_performance(integer) to authenticated;
