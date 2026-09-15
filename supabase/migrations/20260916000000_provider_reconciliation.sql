create or replace function public.ingest_provider_event_page(
  target_send_id uuid,
  event_page jsonb,
  target_next_cursor text,
  target_has_more boolean
)
returns table (
  inserted_events integer,
  provider_cursor text,
  delivered_count integer,
  opened_count integer,
  bounced_count integer,
  unsubscribed_count integer
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  selected_send public.campaign_sends%rowtype;
  unknown_recipients integer;
  inserted_total integer;
  last_page_event_id text;
begin
  if event_page is null or jsonb_typeof(event_page) <> 'array' then
    raise exception 'provider event page must be an array' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(target_send_id::text, 2));
  select * into selected_send
  from public.campaign_sends campaign_send
  where campaign_send.id = target_send_id;

  if not found or not private.is_brand_owner(selected_send.brand_id) then
    raise exception 'owner role required' using errcode = '42501';
  end if;
  if selected_send.source <> 'portal' or selected_send.provider_batch_id is null then
    raise exception 'send has no provider batch to reconcile' using errcode = '55000';
  end if;

  with parsed as (
    select *
    from jsonb_to_recordset(event_page) as event(
      event_id text,
      recipient_identifier text,
      event_type public.engagement_event_type,
      occurred_at timestamptz,
      raw_payload jsonb
    )
  )
  select count(*)::integer into unknown_recipients
  from parsed event
  where not exists (
    select 1
    from public.campaign_send_recipients recipient
    where recipient.send_id = selected_send.id
      and (
        recipient.contact_external_id = event.recipient_identifier
        or recipient.destination = event.recipient_identifier
      )
  );

  if unknown_recipients > 0 then
    raise exception 'provider page contains unknown recipients' using errcode = '22023';
  end if;

  with parsed as (
    select distinct on (event.event_id)
      event.event_id,
      event.recipient_identifier,
      event.event_type,
      event.occurred_at,
      coalesce(event.raw_payload, '{}'::jsonb) raw_payload
    from jsonb_to_recordset(event_page) as event(
      event_id text,
      recipient_identifier text,
      event_type public.engagement_event_type,
      occurred_at timestamptz,
      raw_payload jsonb
    )
    where nullif(btrim(event.event_id), '') is not null
      and nullif(btrim(event.recipient_identifier), '') is not null
      and event.occurred_at is not null
    order by event.event_id, event.occurred_at
  ), resolved as (
    select event.*, recipient.id recipient_id, recipient.contact_id
    from parsed event
    cross join lateral (
      select candidate.id, candidate.contact_id
      from public.campaign_send_recipients candidate
      where candidate.send_id = selected_send.id
        and (
          candidate.contact_external_id = event.recipient_identifier
          or candidate.destination = event.recipient_identifier
        )
      order by (candidate.contact_external_id = event.recipient_identifier) desc, candidate.id
      limit 1
    ) recipient
  )
  insert into public.provider_events (
    brand_id,
    campaign_id,
    contact_id,
    send_id,
    send_recipient_id,
    source,
    provider_event_id,
    event_type,
    channel,
    occurred_at,
    raw_payload
  )
  select
    selected_send.brand_id,
    selected_send.campaign_id,
    event.contact_id,
    selected_send.id,
    event.recipient_id,
    'provider',
    event.event_id,
    event.event_type,
    recipient.channel,
    event.occurred_at,
    event.raw_payload
  from resolved event
  join public.campaign_send_recipients recipient on recipient.id = event.recipient_id
  on conflict (brand_id, source, provider_event_id) do nothing;
  get diagnostics inserted_total = row_count;

  with facts as (
    select
      event.send_recipient_id,
      min(event.occurred_at) filter (where event.event_type = 'delivered') delivered_at,
      min(event.occurred_at) filter (where event.event_type = 'opened') first_opened_at,
      max(event.occurred_at) filter (where event.event_type = 'bounced') bounced_at,
      max(event.occurred_at) filter (where event.event_type = 'unsubscribed') unsubscribed_at,
      max(event.occurred_at) filter (where event.event_type = 'complained') complained_at,
      max(event.occurred_at) last_event_at,
      bool_or(event.event_type = 'delivered') has_delivered,
      bool_or(event.event_type = 'opened') has_opened,
      bool_or(event.event_type = 'bounced') has_bounced,
      bool_or(event.event_type = 'unsubscribed') has_unsubscribed,
      bool_or(event.event_type = 'complained') has_complained
    from public.provider_events event
    where event.send_id = selected_send.id
      and event.source = 'provider'
    group by event.send_recipient_id
  )
  update public.campaign_send_recipients recipient
  set delivered_at = facts.delivered_at,
      first_opened_at = facts.first_opened_at,
      bounced_at = facts.bounced_at,
      unsubscribed_at = facts.unsubscribed_at,
      complained_at = facts.complained_at,
      last_event_at = facts.last_event_at,
      status = case
        when facts.has_complained then 'complained'
        when facts.has_unsubscribed then 'unsubscribed'
        when facts.has_bounced then 'bounced'
        when facts.has_opened then 'opened'
        when facts.has_delivered then 'delivered'
        else recipient.status
      end
  from facts
  where recipient.id = facts.send_recipient_id;

  with channel_facts as (
    select
      event.contact_id,
      event.channel,
      bool_or(event.event_type = 'complained') has_complained,
      bool_or(event.event_type = 'unsubscribed') has_unsubscribed,
      bool_or(event.event_type = 'bounced') has_bounced
    from public.provider_events event
    where event.source = 'provider'
      and event.brand_id = selected_send.brand_id
      and event.event_type in ('complained', 'unsubscribed', 'bounced')
    group by event.contact_id, event.channel
  )
  update public.contacts contact
  set email_status = case
        when facts.channel <> 'email' then contact.email_status
        when facts.has_complained then 'complained'
        when facts.has_unsubscribed then 'unsubscribed'
        when facts.has_bounced then 'bounced'
        else contact.email_status
      end,
      sms_status = case
        when facts.channel <> 'sms' then contact.sms_status
        when facts.has_complained then 'complained'
        when facts.has_unsubscribed then 'unsubscribed'
        when facts.has_bounced then 'bounced'
        else contact.sms_status
      end
  from channel_facts facts
  where contact.id = facts.contact_id;

  select item.value->>'event_id' into last_page_event_id
  from jsonb_array_elements(event_page) with ordinality item(value, position)
  order by item.position desc
  limit 1;

  update public.campaign_sends campaign_send
  set provider_cursor = coalesce(nullif(target_next_cursor, ''), last_page_event_id, campaign_send.provider_cursor),
      delivered_count = totals.delivered_count,
      opened_count = totals.opened_count,
      bounced_count = totals.bounced_count,
      unsubscribed_count = totals.unsubscribed_count,
      reconciled_at = now(),
      last_error = case
        when target_has_more and nullif(target_next_cursor, '') is null
          then 'Provider indicated another page without a cursor.'
        else null
      end
  from (
    select
      count(*) filter (where recipient.delivered_at is not null)::integer delivered_count,
      count(*) filter (where recipient.first_opened_at is not null)::integer opened_count,
      count(*) filter (where recipient.bounced_at is not null)::integer bounced_count,
      count(*) filter (where recipient.unsubscribed_at is not null)::integer unsubscribed_count
    from public.campaign_send_recipients recipient
    where recipient.send_id = selected_send.id
  ) totals
  where campaign_send.id = selected_send.id
  returning
    inserted_total,
    campaign_send.provider_cursor,
    campaign_send.delivered_count,
    campaign_send.opened_count,
    campaign_send.bounced_count,
    campaign_send.unsubscribed_count
  into inserted_events, provider_cursor, delivered_count, opened_count, bounced_count, unsubscribed_count;

  return next;
end;
$$;

create or replace function public.record_campaign_reconciliation_failure(
  target_send_id uuid,
  safe_error text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  selected_brand_id uuid;
begin
  select campaign_send.brand_id into selected_brand_id
  from public.campaign_sends campaign_send
  where campaign_send.id = target_send_id;
  if not found or not private.is_brand_owner(selected_brand_id) then
    raise exception 'owner role required' using errcode = '42501';
  end if;
  update public.campaign_sends
  set last_error = left(coalesce(nullif(btrim(safe_error), ''), 'Provider report failed.'), 500)
  where id = target_send_id;
end;
$$;

revoke all on function public.ingest_provider_event_page(uuid, jsonb, text, boolean) from public, anon;
revoke all on function public.record_campaign_reconciliation_failure(uuid, text) from public, anon;
grant execute on function public.ingest_provider_event_page(uuid, jsonb, text, boolean) to authenticated;
grant execute on function public.record_campaign_reconciliation_failure(uuid, text) to authenticated;
