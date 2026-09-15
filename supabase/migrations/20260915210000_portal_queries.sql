-- Bounded, tenant-scoped portal read models. These are security-invoker functions:
-- table grants and RLS remain the authorization boundary for every query.

create function public.portal_dashboard_summary()
returns table (
  total_customers bigint,
  contactable_customers bigint,
  latest_signup_date date
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    count(*)::bigint,
    count(*) filter (
      where contact.marketing_consent
        and contact.lifecycle_status = 'active'
        and contact.deleted_at is null
        and (contact.suppressed_until is null or contact.suppressed_until <= now())
        and (
          (contact.email is not null and contact.email_status = 'active')
          or (contact.phone is not null and contact.sms_status = 'active')
        )
    )::bigint,
    max(contact.signup_at)::date
  from public.contacts contact;
$$;

create function public.portal_signup_series()
returns table (
  signup_date date,
  signup_count bigint,
  window_end date
)
language sql
stable
security invoker
set search_path = ''
as $$
  with boundary as (
    select max(contact.signup_at)::date as window_end
    from public.contacts contact
  ), days as (
    select day::date as signup_date, boundary.window_end
    from boundary
    cross join lateral generate_series(
      boundary.window_end - 29,
      boundary.window_end,
      interval '1 day'
    ) day
    where boundary.window_end is not null
  ), totals as (
    select contact.signup_at::date as signup_date, count(*)::bigint as signup_count
    from public.contacts contact
    cross join boundary
    where contact.signup_at >= boundary.window_end - 29
      and contact.signup_at < boundary.window_end + 1
    group by contact.signup_at::date
  )
  select days.signup_date, coalesce(totals.signup_count, 0)::bigint, days.window_end
  from days
  left join totals using (signup_date)
  order by days.signup_date;
$$;

create function public.portal_campaign_performance(result_limit integer default 100)
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
security invoker
set search_path = ''
as $$
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
  left join lateral (
    select
      count(distinct event.contact_id) filter (where event.event_type = 'delivered') delivered,
      count(distinct event.contact_id) filter (where event.event_type = 'bounced') bounced,
      count(distinct event.contact_id) filter (where event.event_type = 'opened') opened,
      count(distinct event.contact_id) filter (where event.event_type = 'clicked') clicked,
      count(distinct event.contact_id) filter (where event.event_type = 'unsubscribed') unsubscribed,
      count(distinct event.contact_id) filter (where event.event_type = 'complained') complained
    from public.provider_events event
    where event.campaign_id = campaign.id
  ) event_totals on true
  left join public.campaign_sends send on send.campaign_id = campaign.id
  order by campaign.sent_at desc, campaign.id
  limit greatest(1, least(coalesce(result_limit, 100), 100));
$$;

create function public.portal_contacts_page(
  search_text text default null,
  page_size integer default 25,
  page_offset integer default 0
)
returns table (
  id uuid,
  external_id text,
  full_name text,
  email text,
  phone text,
  country_code text,
  city text,
  signup_at timestamptz,
  lifecycle_status public.contact_lifecycle_status,
  marketing_consent boolean,
  email_status public.contact_channel_status,
  sms_status public.contact_channel_status,
  is_contactable boolean,
  contactability_reason text,
  total_count bigint
)
language sql
stable
security invoker
set search_path = ''
as $$
  with matching as (
    select contact.*
    from public.contacts contact
    where nullif(btrim(search_text), '') is null
      or contact.external_id ilike '%' || btrim(search_text) || '%'
      or contact.full_name ilike '%' || btrim(search_text) || '%'
      or coalesce(contact.email, '') ilike '%' || btrim(search_text) || '%'
  )
  select
    contact.id,
    contact.external_id,
    contact.full_name,
    contact.email,
    contact.phone,
    contact.country_code,
    contact.city,
    contact.signup_at,
    contact.lifecycle_status,
    contact.marketing_consent,
    contact.email_status,
    contact.sms_status,
    (
      contact.marketing_consent
      and contact.lifecycle_status = 'active'
      and contact.deleted_at is null
      and (contact.suppressed_until is null or contact.suppressed_until <= now())
      and (
        (contact.email is not null and contact.email_status = 'active')
        or (contact.phone is not null and contact.sms_status = 'active')
      )
    ) as is_contactable,
    case
      when contact.deleted_at is not null then 'Deleted'
      when not contact.marketing_consent then 'No marketing consent'
      when contact.lifecycle_status <> 'active' then 'Lifecycle status: ' || contact.lifecycle_status::text
      when contact.suppressed_until > now() then 'Temporarily suppressed'
      when not (
        (contact.email is not null and contact.email_status = 'active')
        or (contact.phone is not null and contact.sms_status = 'active')
      ) then 'No active channel'
      else 'Contactable'
    end,
    count(*) over()::bigint
  from matching contact
  order by contact.signup_at desc, contact.id
  limit greatest(1, least(coalesce(page_size, 25), 100))
  offset greatest(coalesce(page_offset, 0), 0);
$$;

revoke all on function public.portal_dashboard_summary() from public, anon;
revoke all on function public.portal_signup_series() from public, anon;
revoke all on function public.portal_campaign_performance(integer) from public, anon;
revoke all on function public.portal_contacts_page(text, integer, integer) from public, anon;

grant execute on function public.portal_dashboard_summary() to authenticated;
grant execute on function public.portal_signup_series() to authenticated;
grant execute on function public.portal_campaign_performance(integer) to authenticated;
grant execute on function public.portal_contacts_page(text, integer, integer) to authenticated;
