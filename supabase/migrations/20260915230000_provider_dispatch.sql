create function public.claim_campaign_dispatch(target_send_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  selected_send public.campaign_sends%rowtype;
  selected_campaign public.campaigns%rowtype;
  selected_brand public.brands%rowtype;
  snapshot_count integer;
  payload jsonb;
begin
  if (select auth.uid()) is null then
    raise exception 'owner role required' using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(target_send_id::text, 1));

  select * into selected_send
  from public.campaign_sends campaign_send
  where campaign_send.id = target_send_id;

  if not found or not private.is_brand_owner(selected_send.brand_id) then
    raise exception 'owner role required' using errcode = '42501';
  end if;
  if selected_send.source <> 'portal' then
    raise exception 'imported sends cannot be dispatched' using errcode = '22023';
  end if;
  if selected_send.status not in ('approved', 'dispatching', 'failed') then
    raise exception 'send is not dispatchable' using errcode = '55000';
  end if;

  select * into selected_campaign
  from public.campaigns campaign
  where campaign.id = selected_send.campaign_id
    and campaign.brand_id = selected_send.brand_id;
  select * into selected_brand
  from public.brands brand
  where brand.id = selected_send.brand_id;

  select count(*)::integer into snapshot_count
  from public.campaign_send_recipients recipient
  where recipient.send_id = selected_send.id;

  if snapshot_count = 0 or snapshot_count <> selected_send.recipient_count then
    raise exception 'approved recipient snapshot is incomplete' using errcode = '55000';
  end if;
  if snapshot_count > 100000 then
    raise exception 'approved audience exceeds provider batch limit' using errcode = '22023';
  end if;

  update public.campaign_sends
  set status = 'dispatching',
      dispatch_attempts = dispatch_attempts + 1,
      last_error = null
  where id = selected_send.id;

  select jsonb_build_object(
    'send_id', selected_send.id,
    'campaign_external_id', selected_campaign.external_id,
    'campaign_name', selected_campaign.name,
    'brand_code', selected_brand.code,
    'channel', selected_campaign.channel,
    'recipient_count', selected_send.recipient_count,
    'recipients', jsonb_agg(
      jsonb_build_object(
        'external_id', recipient.contact_external_id,
        'destination', recipient.destination
      ) order by recipient.contact_external_id
    )
  ) into payload
  from public.campaign_send_recipients recipient
  where recipient.send_id = selected_send.id;

  return payload;
end;
$$;

create function public.record_campaign_dispatch_result(
  target_send_id uuid,
  target_provider_batch_id text,
  accepted_identifiers text[],
  rejected_identifiers text[]
)
returns table (
  send_id uuid,
  status public.send_status,
  accepted_count integer,
  rejected_count integer,
  unclassified_count integer
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  selected_send public.campaign_sends%rowtype;
  accepted_total integer;
  rejected_total integer;
  unclassified_total integer;
  final_status public.send_status;
begin
  if nullif(btrim(target_provider_batch_id), '') is null then
    raise exception 'provider batch id is required' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(target_send_id::text, 1));
  select * into selected_send
  from public.campaign_sends campaign_send
  where campaign_send.id = target_send_id;

  if not found or not private.is_brand_owner(selected_send.brand_id) then
    raise exception 'owner role required' using errcode = '42501';
  end if;
  if selected_send.source <> 'portal' then
    raise exception 'imported sends cannot record dispatch' using errcode = '22023';
  end if;
  if selected_send.provider_batch_id is not null
    and selected_send.provider_batch_id <> target_provider_batch_id then
    raise exception 'provider batch id conflicts with the recorded dispatch' using errcode = '23505';
  end if;

  update public.campaign_send_recipients recipient
  set status = 'accepted',
      provider_recipient_id = recipient.contact_external_id,
      accepted_at = coalesce(recipient.accepted_at, now()),
      provider_error = null
  where recipient.send_id = selected_send.id
    and (
      recipient.contact_external_id = any(coalesce(accepted_identifiers, array[]::text[]))
      or recipient.destination = any(coalesce(accepted_identifiers, array[]::text[]))
    )
    and recipient.status in ('frozen', 'accepted', 'rejected');

  update public.campaign_send_recipients recipient
  set status = 'rejected',
      provider_recipient_id = recipient.contact_external_id,
      provider_error = 'Provider rejected this recipient.'
  where recipient.send_id = selected_send.id
    and (
      recipient.contact_external_id = any(coalesce(rejected_identifiers, array[]::text[]))
      or recipient.destination = any(coalesce(rejected_identifiers, array[]::text[]))
    )
    and recipient.status in ('frozen', 'accepted', 'rejected');

  select
    count(*) filter (where recipient.status = 'accepted')::integer,
    count(*) filter (where recipient.status = 'rejected')::integer,
    count(*) filter (where recipient.status = 'frozen')::integer
  into accepted_total, rejected_total, unclassified_total
  from public.campaign_send_recipients recipient
  where recipient.send_id = selected_send.id;

  final_status := case
    when accepted_total = 0 and rejected_total > 0 and unclassified_total = 0 then 'failed'
    when rejected_total > 0 or unclassified_total > 0 then 'partial'
    else 'submitted'
  end;

  update public.campaign_sends campaign_send
  set provider_batch_id = target_provider_batch_id,
      accepted_count = accepted_total,
      rejected_count = rejected_total,
      status = final_status,
      dispatched_at = coalesce(campaign_send.dispatched_at, now()),
      last_error = case
        when unclassified_total > 0
          then unclassified_total || ' recipients were not classified by the provider response.'
        else null
      end
  where campaign_send.id = selected_send.id;

  return query select selected_send.id, final_status, accepted_total, rejected_total, unclassified_total;
end;
$$;

create function public.record_campaign_dispatch_failure(target_send_id uuid, safe_error text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  selected_send public.campaign_sends%rowtype;
begin
  select * into selected_send
  from public.campaign_sends campaign_send
  where campaign_send.id = target_send_id;
  if not found or not private.is_brand_owner(selected_send.brand_id) then
    raise exception 'owner role required' using errcode = '42501';
  end if;
  if selected_send.status = 'dispatching' then
    update public.campaign_sends
    set status = 'failed',
        last_error = left(coalesce(nullif(btrim(safe_error), ''), 'Provider request failed.'), 500)
    where id = selected_send.id;
  end if;
end;
$$;

revoke all on function public.claim_campaign_dispatch(uuid) from public, anon;
revoke all on function public.record_campaign_dispatch_result(uuid, text, text[], text[]) from public, anon;
revoke all on function public.record_campaign_dispatch_failure(uuid, text) from public, anon;

grant execute on function public.claim_campaign_dispatch(uuid) to authenticated;
grant execute on function public.record_campaign_dispatch_result(uuid, text, text[], text[]) to authenticated;
grant execute on function public.record_campaign_dispatch_failure(uuid, text) to authenticated;
