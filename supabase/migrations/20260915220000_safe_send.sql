create unique index if not exists campaign_sends_confirmation_uidx
  on public.campaign_sends (confirmation_key)
  where confirmation_key is not null;

create or replace function public.portal_send_audience_count(target_campaign_id uuid)
returns bigint
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  selected_campaign public.campaigns%rowtype;
  audience_count bigint;
begin
  select * into selected_campaign
  from public.campaigns campaign
  where campaign.id = target_campaign_id;

  if not found then
    raise exception 'campaign not found' using errcode = 'P0002';
  end if;
  perform public.assert_brand_owner(selected_campaign.brand_id);

  select count(*)::bigint into audience_count
  from public.contacts contact
  where contact.brand_id = selected_campaign.brand_id
    and contact.marketing_consent
    and contact.lifecycle_status = 'active'
    and contact.deleted_at is null
    and (contact.suppressed_until is null or contact.suppressed_until <= now())
    and (
      selected_campaign.target_country_code is null
      or contact.country_code = selected_campaign.target_country_code
    )
    and case selected_campaign.channel
      when 'email' then contact.email is not null and contact.email_status = 'active'
      when 'sms' then contact.phone is not null and contact.sms_status = 'active'
    end;

  return audience_count;
end;
$$;

create or replace function public.portal_send_audience(
  target_campaign_id uuid,
  page_size integer default 25,
  page_offset integer default 0
)
returns table (
  contact_id uuid,
  external_id text,
  full_name text,
  destination text,
  country_code text,
  total_count bigint
)
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  selected_campaign public.campaigns%rowtype;
begin
  select * into selected_campaign
  from public.campaigns campaign
  where campaign.id = target_campaign_id;

  if not found then
    raise exception 'campaign not found' using errcode = 'P0002';
  end if;
  perform public.assert_brand_owner(selected_campaign.brand_id);

  return query
  select
    contact.id,
    contact.external_id,
    contact.full_name,
    case selected_campaign.channel when 'email' then contact.email else contact.phone end,
    contact.country_code,
    count(*) over()::bigint
  from public.contacts contact
  where contact.brand_id = selected_campaign.brand_id
    and contact.marketing_consent
    and contact.lifecycle_status = 'active'
    and contact.deleted_at is null
    and (contact.suppressed_until is null or contact.suppressed_until <= now())
    and (
      selected_campaign.target_country_code is null
      or contact.country_code = selected_campaign.target_country_code
    )
    and case selected_campaign.channel
      when 'email' then contact.email is not null and contact.email_status = 'active'
      when 'sms' then contact.phone is not null and contact.sms_status = 'active'
    end
  order by contact.external_id, contact.id
  limit greatest(1, least(coalesce(page_size, 25), 100))
  offset greatest(coalesce(page_offset, 0), 0);
end;
$$;

create or replace function public.approve_campaign_send(
  target_campaign_id uuid,
  target_confirmation_key uuid
)
returns table (
  send_id uuid,
  approved_at timestamptz,
  recipient_count integer,
  status public.send_status
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  selected_campaign public.campaigns%rowtype;
  existing_send public.campaign_sends%rowtype;
  eligible_count bigint;
begin
  if (select auth.uid()) is null then
    raise exception 'owner role required' using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(target_campaign_id::text, 0));

  select * into selected_campaign
  from public.campaigns campaign
  where campaign.id = target_campaign_id;

  if not found or not private.is_brand_owner(selected_campaign.brand_id) then
    raise exception 'owner role required' using errcode = '42501';
  end if;

  select * into existing_send
  from public.campaign_sends campaign_send
  where campaign_send.brand_id = selected_campaign.brand_id
    and campaign_send.campaign_id = selected_campaign.id;

  if found then
    if existing_send.source = 'portal'
      and existing_send.confirmation_key = target_confirmation_key then
      return query
      select existing_send.id, existing_send.approved_at,
        existing_send.recipient_count, existing_send.status;
      return;
    end if;
    raise exception 'campaign already has a recorded send' using errcode = '23505';
  end if;

  select count(*)::bigint into eligible_count
  from public.contacts contact
  where contact.brand_id = selected_campaign.brand_id
    and contact.marketing_consent
    and contact.lifecycle_status = 'active'
    and contact.deleted_at is null
    and (contact.suppressed_until is null or contact.suppressed_until <= now())
    and (
      selected_campaign.target_country_code is null
      or contact.country_code = selected_campaign.target_country_code
    )
    and case selected_campaign.channel
      when 'email' then contact.email is not null and contact.email_status = 'active'
      when 'sms' then contact.phone is not null and contact.sms_status = 'active'
    end;

  if eligible_count > 100000 then
    raise exception 'eligible audience exceeds provider batch limit' using errcode = '22023';
  end if;
  if eligible_count = 0 then
    raise exception 'campaign has no eligible recipients' using errcode = '22023';
  end if;

  return query
  with eligible as materialized (
    select
      contact.id,
      contact.external_id,
      contact.full_name,
      contact.email,
      contact.phone,
      contact.country_code,
      contact.city,
      contact.lifecycle_status,
      contact.marketing_consent,
      contact.email_status,
      contact.sms_status,
      case selected_campaign.channel when 'email' then contact.email else contact.phone end as destination
    from public.contacts contact
    where contact.brand_id = selected_campaign.brand_id
      and contact.marketing_consent
      and contact.lifecycle_status = 'active'
      and contact.deleted_at is null
      and (contact.suppressed_until is null or contact.suppressed_until <= now())
      and (
        selected_campaign.target_country_code is null
        or contact.country_code = selected_campaign.target_country_code
      )
      and case selected_campaign.channel
        when 'email' then contact.email is not null and contact.email_status = 'active'
        when 'sms' then contact.phone is not null and contact.sms_status = 'active'
      end
  ), new_send as (
    insert into public.campaign_sends as inserted_send (
      brand_id,
      campaign_id,
      source,
      confirmation_key,
      approved_by,
      approved_at,
      recipient_count,
      status
    )
    select
      selected_campaign.brand_id,
      selected_campaign.id,
      'portal',
      target_confirmation_key,
      (select auth.uid()),
      now(),
      count(*)::integer,
      'approved'
    from eligible
    returning
      inserted_send.id,
      inserted_send.brand_id,
      inserted_send.approved_at,
      inserted_send.recipient_count,
      inserted_send.status
  ), frozen as (
    insert into public.campaign_send_recipients as inserted_recipient (
      brand_id,
      send_id,
      contact_id,
      contact_external_id,
      channel,
      destination,
      approved_snapshot,
      status
    )
    select
      new_send.brand_id,
      new_send.id,
      eligible.id,
      eligible.external_id,
      selected_campaign.channel,
      eligible.destination,
      jsonb_build_object(
        'approved_at', new_send.approved_at,
        'full_name', eligible.full_name,
        'email', eligible.email,
        'phone', eligible.phone,
        'country_code', eligible.country_code,
        'city', eligible.city,
        'lifecycle_status', eligible.lifecycle_status,
        'marketing_consent', eligible.marketing_consent,
        'email_status', eligible.email_status,
        'sms_status', eligible.sms_status
      ),
      'frozen'
    from eligible
    cross join new_send
    returning inserted_recipient.send_id
  )
  select new_send.id, new_send.approved_at, new_send.recipient_count, new_send.status
  from new_send
  where (select count(*) from frozen) = new_send.recipient_count;
end;
$$;

revoke all on function public.portal_send_audience_count(uuid) from public, anon;
revoke all on function public.portal_send_audience(uuid, integer, integer) from public, anon;
revoke all on function public.approve_campaign_send(uuid, uuid) from public, anon;

grant execute on function public.portal_send_audience_count(uuid) to authenticated;
grant execute on function public.portal_send_audience(uuid, integer, integer) to authenticated;
grant execute on function public.approve_campaign_send(uuid, uuid) to authenticated;
