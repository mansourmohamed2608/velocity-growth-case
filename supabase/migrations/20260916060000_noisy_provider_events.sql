-- A provider report may contain an event for an identifier outside the frozen
-- send audience. Keep that event unbound, advance the provider cursor, and make
-- the skipped count visible instead of blocking every valid event on the page.

alter table public.campaign_sends
  add column skipped_event_count integer not null default 0,
  add constraint campaign_sends_skipped_event_count_nonnegative
    check (skipped_event_count >= 0);

alter function public.ingest_provider_event_page(uuid, jsonb, text, boolean)
  rename to ingest_provider_event_page_strict;

revoke all on function public.ingest_provider_event_page_strict(uuid, jsonb, text, boolean)
from public, anon, authenticated;

create function public.ingest_provider_event_page(
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
  filtered_page jsonb;
  skipped_total integer;
begin
  if event_page is null or jsonb_typeof(event_page) <> 'array' then
    raise exception 'provider event page must be an array' using errcode = '22023';
  end if;

  select * into selected_send
  from public.campaign_sends campaign_send
  where campaign_send.id = target_send_id;

  if not found or not private.is_brand_owner(selected_send.brand_id) then
    raise exception 'owner role required' using errcode = '42501';
  end if;

  with classified as (
    select
      item.value,
      item.position,
      exists (
        select 1
        from public.campaign_send_recipients recipient
        where recipient.send_id = selected_send.id
          and (
            recipient.contact_external_id = item.value->>'recipient_identifier'
            or recipient.destination = item.value->>'recipient_identifier'
          )
      ) as is_known
    from jsonb_array_elements(event_page) with ordinality item(value, position)
  )
  select
    coalesce(jsonb_agg(classified.value order by classified.position)
      filter (where classified.is_known), '[]'::jsonb),
    count(*) filter (where not classified.is_known)::integer
  into filtered_page, skipped_total
  from classified;

  return query
  select *
  from public.ingest_provider_event_page_strict(
    target_send_id,
    filtered_page,
    target_next_cursor,
    target_has_more
  );

  if skipped_total > 0 then
    update public.campaign_sends campaign_send
    set skipped_event_count = campaign_send.skipped_event_count + skipped_total,
        last_error = skipped_total || case when skipped_total = 1
          then ' provider event referenced an unknown recipient and was skipped.'
          else ' provider events referenced unknown recipients and were skipped.'
        end
    where campaign_send.id = selected_send.id;
  end if;
end;
$$;

revoke all on function public.ingest_provider_event_page(uuid, jsonb, text, boolean)
from public, anon;
grant execute on function public.ingest_provider_event_page(uuid, jsonb, text, boolean)
to authenticated;
