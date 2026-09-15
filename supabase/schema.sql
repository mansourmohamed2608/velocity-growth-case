


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "private";


ALTER SCHEMA "private" OWNER TO "postgres";


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE TYPE "public"."contact_channel_status" AS ENUM (
    'active',
    'unavailable',
    'bounced',
    'unsubscribed',
    'complained'
);


ALTER TYPE "public"."contact_channel_status" OWNER TO "postgres";


CREATE TYPE "public"."contact_lifecycle_status" AS ENUM (
    'active',
    'pending',
    'bounced',
    'unsubscribed'
);


ALTER TYPE "public"."contact_lifecycle_status" OWNER TO "postgres";


CREATE TYPE "public"."engagement_event_type" AS ENUM (
    'delivered',
    'bounced',
    'opened',
    'clicked',
    'unsubscribed',
    'complained'
);


ALTER TYPE "public"."engagement_event_type" OWNER TO "postgres";


CREATE TYPE "public"."event_source" AS ENUM (
    'seed',
    'provider'
);


ALTER TYPE "public"."event_source" OWNER TO "postgres";


CREATE TYPE "public"."import_issue_severity" AS ENUM (
    'warning',
    'error'
);


ALTER TYPE "public"."import_issue_severity" OWNER TO "postgres";


CREATE TYPE "public"."import_status" AS ENUM (
    'running',
    'completed',
    'completed_with_errors',
    'failed'
);


ALTER TYPE "public"."import_status" OWNER TO "postgres";


CREATE TYPE "public"."message_channel" AS ENUM (
    'email',
    'sms'
);


ALTER TYPE "public"."message_channel" OWNER TO "postgres";


CREATE TYPE "public"."portal_role" AS ENUM (
    'owner',
    'analyst'
);


ALTER TYPE "public"."portal_role" OWNER TO "postgres";


CREATE TYPE "public"."recipient_status" AS ENUM (
    'frozen',
    'accepted',
    'rejected',
    'delivered',
    'opened',
    'bounced',
    'unsubscribed',
    'complained'
);


ALTER TYPE "public"."recipient_status" OWNER TO "postgres";


CREATE TYPE "public"."send_source" AS ENUM (
    'imported',
    'portal'
);


ALTER TYPE "public"."send_source" OWNER TO "postgres";


CREATE TYPE "public"."send_status" AS ENUM (
    'approved',
    'dispatching',
    'submitted',
    'partial',
    'completed',
    'failed'
);


ALTER TYPE "public"."send_status" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."current_brand_id"() RETURNS "uuid"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select (
    select membership.brand_id
    from public.brand_memberships membership
    where membership.user_id = (select auth.uid())
  );
$$;


ALTER FUNCTION "private"."current_brand_id"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."is_brand_member"("target_brand_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select exists (
    select 1
    from public.brand_memberships membership
    where membership.brand_id = target_brand_id
      and membership.user_id = (select auth.uid())
  );
$$;


ALTER FUNCTION "private"."is_brand_member"("target_brand_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."is_brand_owner"("target_brand_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select exists (
    select 1
    from public.brand_memberships membership
    where membership.brand_id = target_brand_id
      and membership.user_id = (select auth.uid())
      and membership.role = 'owner'
  );
$$;


ALTER FUNCTION "private"."is_brand_owner"("target_brand_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."approve_campaign_send"("target_campaign_id" "uuid", "target_confirmation_key" "uuid") RETURNS TABLE("send_id" "uuid", "approved_at" timestamp with time zone, "recipient_count" integer, "status" "public"."send_status")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."approve_campaign_send"("target_campaign_id" "uuid", "target_confirmation_key" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."assert_brand_owner"("target_brand_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if not private.is_brand_owner(target_brand_id) then
    raise exception 'owner role required' using errcode = '42501';
  end if;
end;
$$;


ALTER FUNCTION "public"."assert_brand_owner"("target_brand_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."claim_campaign_dispatch"("target_send_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."claim_campaign_dispatch"("target_send_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_public_report_session"("target_token_digest" "bytea", "plain_password" "text", "target_session_digest" "bytea") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."create_public_report_session"("target_token_digest" "bytea", "plain_password" "text", "target_session_digest" "bytea") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."current_portal_context"() RETURNS TABLE("brand_id" "uuid", "brand_code" "text", "brand_name" "text", "role" "public"."portal_role")
    LANGUAGE "sql" STABLE
    SET "search_path" TO ''
    AS $$
  select brand.id, brand.code, brand.name, membership.role
  from public.brand_memberships membership
  join public.brands brand on brand.id = membership.brand_id
  where membership.user_id = (select auth.uid());
$$;


ALTER FUNCTION "public"."current_portal_context"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ingest_provider_event_page"("target_send_id" "uuid", "event_page" "jsonb", "target_next_cursor" "text", "target_has_more" boolean) RETURNS TABLE("inserted_events" integer, "provider_cursor" "text", "delivered_count" integer, "opened_count" integer, "bounced_count" integer, "unsubscribed_count" integer)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."ingest_provider_event_page"("target_send_id" "uuid", "event_page" "jsonb", "target_next_cursor" "text", "target_has_more" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."portal_campaign_performance"("result_limit" integer DEFAULT 100) RETURNS TABLE("id" "uuid", "external_id" "text", "name" "text", "channel" "public"."message_channel", "sent_at" timestamp with time zone, "reported_sent" bigint, "reported_delivered" bigint, "reported_bounced" bigint, "reported_opens" bigint, "reported_clicks" bigint, "spend" numeric, "event_delivered" bigint, "event_bounced" bigint, "event_opened" bigint, "event_clicked" bigint, "event_unsubscribed" bigint, "event_complained" bigint, "send_status" "public"."send_status", "send_recipient_count" integer)
    LANGUAGE "sql" STABLE
    SET "search_path" TO ''
    AS $$
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
    where event.brand_id = (select private.current_brand_id())
      and event.campaign_id = campaign.id
  ) event_totals on true
  left join public.campaign_sends send
    on send.brand_id = (select private.current_brand_id())
   and send.campaign_id = campaign.id
  where campaign.brand_id = (select private.current_brand_id())
  order by campaign.sent_at desc, campaign.id
  limit greatest(1, least(coalesce(result_limit, 100), 100));
$$;


ALTER FUNCTION "public"."portal_campaign_performance"("result_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."portal_contacts_count"("search_text" "text" DEFAULT NULL::"text") RETURNS bigint
    LANGUAGE "sql" STABLE
    SET "search_path" TO ''
    AS $$
  select count(*)::bigint
  from public.contacts contact
  where contact.brand_id = (select private.current_brand_id())
    and (
      nullif(btrim(search_text), '') is null
      or contact.external_id ilike '%' || btrim(search_text) || '%'
      or contact.full_name ilike '%' || btrim(search_text) || '%'
      or coalesce(contact.email, '') ilike '%' || btrim(search_text) || '%'
    );
$$;


ALTER FUNCTION "public"."portal_contacts_count"("search_text" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."portal_contacts_page"("search_text" "text" DEFAULT NULL::"text", "page_size" integer DEFAULT 25, "page_offset" integer DEFAULT 0) RETURNS TABLE("id" "uuid", "external_id" "text", "full_name" "text", "email" "text", "phone" "text", "country_code" "text", "city" "text", "signup_at" timestamp with time zone, "lifecycle_status" "public"."contact_lifecycle_status", "marketing_consent" boolean, "email_status" "public"."contact_channel_status", "sms_status" "public"."contact_channel_status", "is_contactable" boolean, "contactability_reason" "text", "total_count" bigint)
    LANGUAGE "sql" STABLE
    SET "search_path" TO ''
    AS $$
  with matching as (
    select contact.*
    from public.contacts contact
    where contact.brand_id = (select private.current_brand_id())
      and (
        nullif(btrim(search_text), '') is null
        or contact.external_id ilike '%' || btrim(search_text) || '%'
        or contact.full_name ilike '%' || btrim(search_text) || '%'
        or coalesce(contact.email, '') ilike '%' || btrim(search_text) || '%'
      )
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


ALTER FUNCTION "public"."portal_contacts_page"("search_text" "text", "page_size" integer, "page_offset" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."portal_dashboard_summary"() RETURNS TABLE("total_customers" bigint, "contactable_customers" bigint, "latest_signup_date" "date")
    LANGUAGE "sql" STABLE
    SET "search_path" TO ''
    AS $$
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
  from public.contacts contact
  where contact.brand_id = (select private.current_brand_id());
$$;


ALTER FUNCTION "public"."portal_dashboard_summary"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."portal_send_audience"("target_campaign_id" "uuid", "page_size" integer DEFAULT 25, "page_offset" integer DEFAULT 0) RETURNS TABLE("contact_id" "uuid", "external_id" "text", "full_name" "text", "destination" "text", "country_code" "text", "total_count" bigint)
    LANGUAGE "plpgsql" STABLE
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."portal_send_audience"("target_campaign_id" "uuid", "page_size" integer, "page_offset" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."portal_send_audience_count"("target_campaign_id" "uuid") RETURNS bigint
    LANGUAGE "plpgsql" STABLE
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."portal_send_audience_count"("target_campaign_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."portal_signup_series"() RETURNS TABLE("signup_date" "date", "signup_count" bigint, "window_end" "date")
    LANGUAGE "sql" STABLE
    SET "search_path" TO ''
    AS $$
  with boundary as (
    select max(contact.signup_at)::date as window_end
    from public.contacts contact
    where contact.brand_id = (select private.current_brand_id())
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
    where contact.brand_id = (select private.current_brand_id())
      and contact.signup_at >= boundary.window_end - 29
      and contact.signup_at < boundary.window_end + 1
    group by contact.signup_at::date
  )
  select days.signup_date, coalesce(totals.signup_count, 0)::bigint, days.window_end
  from days
  left join totals using (signup_date)
  order by days.signup_date;
$$;


ALTER FUNCTION "public"."portal_signup_series"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."protect_recipient_snapshot"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."protect_recipient_snapshot"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."protect_send_approval"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."protect_send_approval"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."public_campaign_report"("target_session_digest" "bytea") RETURNS TABLE("brand_name" "text", "campaign_name" "text", "campaign_external_id" "text", "channel" "public"."message_channel", "sent_at" timestamp with time zone, "reported_sent" bigint, "reported_delivered" bigint, "reported_bounced" bigint, "reported_opens" bigint, "reported_clicks" bigint, "spend" numeric, "event_delivered" bigint, "event_bounced" bigint, "event_opened" bigint, "event_clicked" bigint, "event_unsubscribed" bigint, "event_complained" bigint)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."public_campaign_report"("target_session_digest" "bytea") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."publish_campaign_report"("target_campaign_id" "uuid", "target_token_digest" "bytea", "plain_password" "text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."publish_campaign_report"("target_campaign_id" "uuid", "target_token_digest" "bytea", "plain_password" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_campaign_dispatch_failure"("target_send_id" "uuid", "safe_error" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."record_campaign_dispatch_failure"("target_send_id" "uuid", "safe_error" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_campaign_dispatch_result"("target_send_id" "uuid", "target_provider_batch_id" "text", "accepted_identifiers" "text"[], "rejected_identifiers" "text"[]) RETURNS TABLE("send_id" "uuid", "status" "public"."send_status", "accepted_count" integer, "rejected_count" integer, "unclassified_count" integer)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."record_campaign_dispatch_result"("target_send_id" "uuid", "target_provider_batch_id" "text", "accepted_identifiers" "text"[], "rejected_identifiers" "text"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_campaign_reconciliation_failure"("target_send_id" "uuid", "safe_error" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."record_campaign_reconciliation_failure"("target_send_id" "uuid", "safe_error" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
begin
  new.updated_at = now();
  return new;
end;
$$;


ALTER FUNCTION "public"."set_updated_at"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."brand_memberships" (
    "brand_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "role" "public"."portal_role" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);

ALTER TABLE ONLY "public"."brand_memberships" FORCE ROW LEVEL SECURITY;


ALTER TABLE "public"."brand_memberships" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."brands" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "code" "text" NOT NULL,
    "name" "text" NOT NULL,
    "country_code" "text" NOT NULL,
    "time_zone" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "brands_code_check" CHECK (("code" ~ '^[A-Z][A-Z0-9_]*$'::"text")),
    CONSTRAINT "brands_country_code_check" CHECK (("country_code" ~ '^[A-Z]{2}$'::"text")),
    CONSTRAINT "brands_name_check" CHECK (("btrim"("name") <> ''::"text")),
    CONSTRAINT "brands_time_zone_check" CHECK (("btrim"("time_zone") <> ''::"text"))
);

ALTER TABLE ONLY "public"."brands" FORCE ROW LEVEL SECURITY;


ALTER TABLE "public"."brands" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."campaign_send_recipients" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "brand_id" "uuid" NOT NULL,
    "send_id" "uuid" NOT NULL,
    "contact_id" "uuid" NOT NULL,
    "contact_external_id" "text" NOT NULL,
    "channel" "public"."message_channel" NOT NULL,
    "destination" "text" NOT NULL,
    "approved_snapshot" "jsonb" NOT NULL,
    "status" "public"."recipient_status" DEFAULT 'frozen'::"public"."recipient_status" NOT NULL,
    "provider_recipient_id" "text",
    "provider_error" "text",
    "accepted_at" timestamp with time zone,
    "delivered_at" timestamp with time zone,
    "first_opened_at" timestamp with time zone,
    "bounced_at" timestamp with time zone,
    "unsubscribed_at" timestamp with time zone,
    "complained_at" timestamp with time zone,
    "last_event_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "campaign_send_recipients_approved_snapshot_check" CHECK (("jsonb_typeof"("approved_snapshot") = 'object'::"text")),
    CONSTRAINT "campaign_send_recipients_destination_check" CHECK (("btrim"("destination") <> ''::"text"))
);

ALTER TABLE ONLY "public"."campaign_send_recipients" FORCE ROW LEVEL SECURITY;


ALTER TABLE "public"."campaign_send_recipients" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."campaign_sends" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "brand_id" "uuid" NOT NULL,
    "campaign_id" "uuid" NOT NULL,
    "source" "public"."send_source" DEFAULT 'portal'::"public"."send_source" NOT NULL,
    "confirmation_key" "uuid",
    "approved_by" "uuid",
    "approved_at" timestamp with time zone,
    "recipient_count" integer NOT NULL,
    "status" "public"."send_status" NOT NULL,
    "provider_batch_id" "text",
    "provider_cursor" "text",
    "accepted_count" integer DEFAULT 0 NOT NULL,
    "rejected_count" integer DEFAULT 0 NOT NULL,
    "delivered_count" integer DEFAULT 0 NOT NULL,
    "opened_count" integer DEFAULT 0 NOT NULL,
    "bounced_count" integer DEFAULT 0 NOT NULL,
    "unsubscribed_count" integer DEFAULT 0 NOT NULL,
    "last_error" "text",
    "dispatch_attempts" integer DEFAULT 0 NOT NULL,
    "dispatched_at" timestamp with time zone,
    "reconciled_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "campaign_sends_accepted_count_check" CHECK (("accepted_count" >= 0)),
    CONSTRAINT "campaign_sends_bounced_count_check" CHECK (("bounced_count" >= 0)),
    CONSTRAINT "campaign_sends_check" CHECK (((("source" = 'portal'::"public"."send_source") AND ("confirmation_key" IS NOT NULL) AND ("approved_by" IS NOT NULL) AND ("approved_at" IS NOT NULL)) OR (("source" = 'imported'::"public"."send_source") AND ("confirmation_key" IS NULL) AND ("approved_by" IS NULL)))),
    CONSTRAINT "campaign_sends_check1" CHECK ((("accepted_count" + "rejected_count") <= "recipient_count")),
    CONSTRAINT "campaign_sends_check2" CHECK (("delivered_count" <= "accepted_count")),
    CONSTRAINT "campaign_sends_check3" CHECK (("opened_count" <= "accepted_count")),
    CONSTRAINT "campaign_sends_check4" CHECK (("bounced_count" <= "accepted_count")),
    CONSTRAINT "campaign_sends_check5" CHECK (("unsubscribed_count" <= "accepted_count")),
    CONSTRAINT "campaign_sends_delivered_count_check" CHECK (("delivered_count" >= 0)),
    CONSTRAINT "campaign_sends_dispatch_attempts_check" CHECK (("dispatch_attempts" >= 0)),
    CONSTRAINT "campaign_sends_opened_count_check" CHECK (("opened_count" >= 0)),
    CONSTRAINT "campaign_sends_recipient_count_check" CHECK (("recipient_count" >= 0)),
    CONSTRAINT "campaign_sends_rejected_count_check" CHECK (("rejected_count" >= 0)),
    CONSTRAINT "campaign_sends_unsubscribed_count_check" CHECK (("unsubscribed_count" >= 0))
);

ALTER TABLE ONLY "public"."campaign_sends" FORCE ROW LEVEL SECURITY;


ALTER TABLE "public"."campaign_sends" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."campaigns" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "brand_id" "uuid" NOT NULL,
    "external_id" "text" NOT NULL,
    "name" "text" NOT NULL,
    "channel" "public"."message_channel" NOT NULL,
    "target_country_code" "text",
    "reported_sent" bigint DEFAULT 0 NOT NULL,
    "reported_delivered" bigint DEFAULT 0 NOT NULL,
    "reported_bounced" bigint DEFAULT 0 NOT NULL,
    "reported_opens" bigint DEFAULT 0 NOT NULL,
    "reported_clicks" bigint DEFAULT 0 NOT NULL,
    "spend" numeric(14,2) DEFAULT 0 NOT NULL,
    "sent_at" timestamp with time zone NOT NULL,
    "send_local_time" timestamp without time zone,
    "parent_campaign_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "campaigns_check" CHECK ((("parent_campaign_id" IS NULL) OR ("parent_campaign_id" <> "id"))),
    CONSTRAINT "campaigns_external_id_check" CHECK (("btrim"("external_id") <> ''::"text")),
    CONSTRAINT "campaigns_name_check" CHECK (("btrim"("name") <> ''::"text")),
    CONSTRAINT "campaigns_reported_bounced_check" CHECK (("reported_bounced" >= 0)),
    CONSTRAINT "campaigns_reported_clicks_check" CHECK (("reported_clicks" >= 0)),
    CONSTRAINT "campaigns_reported_delivered_check" CHECK (("reported_delivered" >= 0)),
    CONSTRAINT "campaigns_reported_opens_check" CHECK (("reported_opens" >= 0)),
    CONSTRAINT "campaigns_reported_sent_check" CHECK (("reported_sent" >= 0)),
    CONSTRAINT "campaigns_spend_check" CHECK (("spend" >= (0)::numeric)),
    CONSTRAINT "campaigns_target_country_code_check" CHECK ((("target_country_code" IS NULL) OR ("target_country_code" ~ '^[A-Z]{2}$'::"text")))
);

ALTER TABLE ONLY "public"."campaigns" FORCE ROW LEVEL SECURITY;


ALTER TABLE "public"."campaigns" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."contacts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "brand_id" "uuid" NOT NULL,
    "external_id" "text" NOT NULL,
    "full_name" "text" NOT NULL,
    "email" "text",
    "phone" "text",
    "country_code" "text",
    "city" "text",
    "signup_at" timestamp with time zone NOT NULL,
    "lifecycle_status" "public"."contact_lifecycle_status" NOT NULL,
    "marketing_consent" boolean NOT NULL,
    "deleted_at" timestamp with time zone,
    "suppressed_until" timestamp with time zone,
    "email_status" "public"."contact_channel_status" DEFAULT 'unavailable'::"public"."contact_channel_status" NOT NULL,
    "sms_status" "public"."contact_channel_status" DEFAULT 'unavailable'::"public"."contact_channel_status" NOT NULL,
    "notes" "text",
    "source_updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "source_precedence" smallint DEFAULT 0 NOT NULL,
    CONSTRAINT "contacts_check" CHECK ((("email" IS NOT NULL) OR ("phone" IS NOT NULL))),
    CONSTRAINT "contacts_check1" CHECK ((("deleted_at" IS NULL) OR ("deleted_at" >= "signup_at"))),
    CONSTRAINT "contacts_country_code_check" CHECK ((("country_code" IS NULL) OR ("country_code" ~ '^[A-Z]{2}$'::"text"))),
    CONSTRAINT "contacts_email_check" CHECK ((("email" IS NULL) OR (("email" = "lower"("email")) AND ("email" ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'::"text")))),
    CONSTRAINT "contacts_external_id_check" CHECK (("external_id" ~ '^CT-[0-9]{6}$'::"text")),
    CONSTRAINT "contacts_full_name_check" CHECK (("btrim"("full_name") <> ''::"text")),
    CONSTRAINT "contacts_phone_check" CHECK ((("phone" IS NULL) OR ("btrim"("phone") <> ''::"text"))),
    CONSTRAINT "contacts_source_precedence_check" CHECK (("source_precedence" >= 0))
);

ALTER TABLE ONLY "public"."contacts" FORCE ROW LEVEL SECURITY;


ALTER TABLE "public"."contacts" OWNER TO "postgres";


COMMENT ON COLUMN "public"."contacts"."source_precedence" IS 'Higher-precedence source exports may update lower-precedence rows; base reruns cannot overwrite dated corrections.';



CREATE TABLE IF NOT EXISTS "public"."import_errors" (
    "id" bigint NOT NULL,
    "brand_id" "uuid" NOT NULL,
    "import_run_id" "uuid" NOT NULL,
    "row_number" integer NOT NULL,
    "severity" "public"."import_issue_severity" DEFAULT 'error'::"public"."import_issue_severity" NOT NULL,
    "field_name" "text",
    "error_code" "text" NOT NULL,
    "reason" "text" NOT NULL,
    "raw_value" "text",
    "raw_row" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "import_errors_error_code_check" CHECK (("btrim"("error_code") <> ''::"text")),
    CONSTRAINT "import_errors_raw_row_check" CHECK (("jsonb_typeof"("raw_row") = 'object'::"text")),
    CONSTRAINT "import_errors_reason_check" CHECK (("btrim"("reason") <> ''::"text")),
    CONSTRAINT "import_errors_row_number_check" CHECK (("row_number" >= 2))
);

ALTER TABLE ONLY "public"."import_errors" FORCE ROW LEVEL SECURITY;


ALTER TABLE "public"."import_errors" OWNER TO "postgres";


ALTER TABLE "public"."import_errors" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."import_errors_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."import_runs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "brand_id" "uuid" NOT NULL,
    "source_filename" "text" NOT NULL,
    "source_kind" "text" NOT NULL,
    "content_sha256" "text" NOT NULL,
    "status" "public"."import_status" DEFAULT 'running'::"public"."import_status" NOT NULL,
    "source_rows" integer DEFAULT 0 NOT NULL,
    "accepted_rows" integer DEFAULT 0 NOT NULL,
    "rejected_rows" integer DEFAULT 0 NOT NULL,
    "warning_rows" integer DEFAULT 0 NOT NULL,
    "started_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "completed_at" timestamp with time zone,
    "failure_reason" "text",
    "created_by" "uuid",
    CONSTRAINT "import_runs_accepted_rows_check" CHECK (("accepted_rows" >= 0)),
    CONSTRAINT "import_runs_check" CHECK ((("accepted_rows" + "rejected_rows") <= "source_rows")),
    CONSTRAINT "import_runs_check1" CHECK (((("status" = 'running'::"public"."import_status") AND ("completed_at" IS NULL)) OR (("status" <> 'running'::"public"."import_status") AND ("completed_at" IS NOT NULL)))),
    CONSTRAINT "import_runs_content_sha256_check" CHECK (("content_sha256" ~ '^[0-9a-f]{64}$'::"text")),
    CONSTRAINT "import_runs_rejected_rows_check" CHECK (("rejected_rows" >= 0)),
    CONSTRAINT "import_runs_source_filename_check" CHECK (("btrim"("source_filename") <> ''::"text")),
    CONSTRAINT "import_runs_source_kind_check" CHECK (("source_kind" = ANY (ARRAY['contacts'::"text", 'contacts_delta'::"text", 'campaigns'::"text", 'events'::"text", 'send_log'::"text"]))),
    CONSTRAINT "import_runs_source_rows_check" CHECK (("source_rows" >= 0)),
    CONSTRAINT "import_runs_warning_rows_check" CHECK (("warning_rows" >= 0))
);

ALTER TABLE ONLY "public"."import_runs" FORCE ROW LEVEL SECURITY;


ALTER TABLE "public"."import_runs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."provider_events" (
    "id" bigint NOT NULL,
    "brand_id" "uuid" NOT NULL,
    "campaign_id" "uuid" NOT NULL,
    "contact_id" "uuid" NOT NULL,
    "send_id" "uuid",
    "send_recipient_id" "uuid",
    "source" "public"."event_source" NOT NULL,
    "provider_event_id" "text" NOT NULL,
    "event_type" "public"."engagement_event_type" NOT NULL,
    "channel" "public"."message_channel" NOT NULL,
    "occurred_at" timestamp with time zone NOT NULL,
    "raw_payload" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "received_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "provider_events_check" CHECK (((("send_id" IS NULL) AND ("send_recipient_id" IS NULL)) OR (("send_id" IS NOT NULL) AND ("send_recipient_id" IS NOT NULL)))),
    CONSTRAINT "provider_events_provider_event_id_check" CHECK (("btrim"("provider_event_id") <> ''::"text")),
    CONSTRAINT "provider_events_raw_payload_check" CHECK (("jsonb_typeof"("raw_payload") = 'object'::"text"))
);

ALTER TABLE ONLY "public"."provider_events" FORCE ROW LEVEL SECURITY;


ALTER TABLE "public"."provider_events" OWNER TO "postgres";


ALTER TABLE "public"."provider_events" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."provider_events_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."published_reports" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "brand_id" "uuid" NOT NULL,
    "campaign_id" "uuid" NOT NULL,
    "created_by" "uuid" NOT NULL,
    "token_digest" "bytea" NOT NULL,
    "password_hash" "text" NOT NULL,
    "expires_at" timestamp with time zone,
    "revoked_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "published_reports_check" CHECK ((("expires_at" IS NULL) OR ("expires_at" > "created_at"))),
    CONSTRAINT "published_reports_check1" CHECK ((("revoked_at" IS NULL) OR ("revoked_at" >= "created_at"))),
    CONSTRAINT "published_reports_password_hash_check" CHECK (("char_length"("password_hash") >= 50)),
    CONSTRAINT "published_reports_token_digest_check" CHECK (("octet_length"("token_digest") = 32))
);

ALTER TABLE ONLY "public"."published_reports" FORCE ROW LEVEL SECURITY;


ALTER TABLE "public"."published_reports" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."report_sessions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "brand_id" "uuid" NOT NULL,
    "published_report_id" "uuid" NOT NULL,
    "session_digest" "bytea" NOT NULL,
    "expires_at" timestamp with time zone NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "last_accessed_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "report_sessions_check" CHECK (("expires_at" > "created_at")),
    CONSTRAINT "report_sessions_session_digest_check" CHECK (("octet_length"("session_digest") = 32))
);

ALTER TABLE ONLY "public"."report_sessions" FORCE ROW LEVEL SECURITY;


ALTER TABLE "public"."report_sessions" OWNER TO "postgres";


ALTER TABLE ONLY "public"."brand_memberships"
    ADD CONSTRAINT "brand_memberships_pkey" PRIMARY KEY ("brand_id", "user_id");



ALTER TABLE ONLY "public"."brand_memberships"
    ADD CONSTRAINT "brand_memberships_user_id_key" UNIQUE ("user_id");



ALTER TABLE ONLY "public"."brands"
    ADD CONSTRAINT "brands_code_key" UNIQUE ("code");



ALTER TABLE ONLY "public"."brands"
    ADD CONSTRAINT "brands_id_code_key" UNIQUE ("id", "code");



ALTER TABLE ONLY "public"."brands"
    ADD CONSTRAINT "brands_name_key" UNIQUE ("name");



ALTER TABLE ONLY "public"."brands"
    ADD CONSTRAINT "brands_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."campaign_send_recipients"
    ADD CONSTRAINT "campaign_send_recipients_brand_id_send_id_id_key" UNIQUE ("brand_id", "send_id", "id");



ALTER TABLE ONLY "public"."campaign_send_recipients"
    ADD CONSTRAINT "campaign_send_recipients_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."campaign_send_recipients"
    ADD CONSTRAINT "campaign_send_recipients_send_id_contact_id_key" UNIQUE ("send_id", "contact_id");



ALTER TABLE ONLY "public"."campaign_sends"
    ADD CONSTRAINT "campaign_sends_brand_id_campaign_id_key" UNIQUE ("brand_id", "campaign_id");



ALTER TABLE ONLY "public"."campaign_sends"
    ADD CONSTRAINT "campaign_sends_brand_id_id_key" UNIQUE ("brand_id", "id");



ALTER TABLE ONLY "public"."campaign_sends"
    ADD CONSTRAINT "campaign_sends_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."campaigns"
    ADD CONSTRAINT "campaigns_brand_id_external_id_key" UNIQUE ("brand_id", "external_id");



ALTER TABLE ONLY "public"."campaigns"
    ADD CONSTRAINT "campaigns_brand_id_id_key" UNIQUE ("brand_id", "id");



ALTER TABLE ONLY "public"."campaigns"
    ADD CONSTRAINT "campaigns_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."contacts"
    ADD CONSTRAINT "contacts_brand_id_external_id_key" UNIQUE ("brand_id", "external_id");



ALTER TABLE ONLY "public"."contacts"
    ADD CONSTRAINT "contacts_brand_id_id_key" UNIQUE ("brand_id", "id");



ALTER TABLE ONLY "public"."contacts"
    ADD CONSTRAINT "contacts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."import_errors"
    ADD CONSTRAINT "import_errors_import_run_id_row_number_error_code_field_nam_key" UNIQUE ("import_run_id", "row_number", "error_code", "field_name");



ALTER TABLE ONLY "public"."import_errors"
    ADD CONSTRAINT "import_errors_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."import_runs"
    ADD CONSTRAINT "import_runs_brand_id_id_key" UNIQUE ("brand_id", "id");



ALTER TABLE ONLY "public"."import_runs"
    ADD CONSTRAINT "import_runs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."provider_events"
    ADD CONSTRAINT "provider_events_brand_id_source_provider_event_id_key" UNIQUE ("brand_id", "source", "provider_event_id");



ALTER TABLE ONLY "public"."provider_events"
    ADD CONSTRAINT "provider_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."published_reports"
    ADD CONSTRAINT "published_reports_brand_id_campaign_id_key" UNIQUE ("brand_id", "campaign_id");



ALTER TABLE ONLY "public"."published_reports"
    ADD CONSTRAINT "published_reports_brand_id_id_key" UNIQUE ("brand_id", "id");



ALTER TABLE ONLY "public"."published_reports"
    ADD CONSTRAINT "published_reports_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."published_reports"
    ADD CONSTRAINT "published_reports_token_digest_key" UNIQUE ("token_digest");



ALTER TABLE ONLY "public"."report_sessions"
    ADD CONSTRAINT "report_sessions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."report_sessions"
    ADD CONSTRAINT "report_sessions_session_digest_key" UNIQUE ("session_digest");



CREATE INDEX "campaign_send_recipients_send_status_idx" ON "public"."campaign_send_recipients" USING "btree" ("send_id", "status");



CREATE INDEX "campaign_sends_brand_status_idx" ON "public"."campaign_sends" USING "btree" ("brand_id", "status", "created_at");



CREATE UNIQUE INDEX "campaign_sends_confirmation_uidx" ON "public"."campaign_sends" USING "btree" ("confirmation_key") WHERE ("confirmation_key" IS NOT NULL);



CREATE UNIQUE INDEX "campaign_sends_provider_batch_uidx" ON "public"."campaign_sends" USING "btree" ("provider_batch_id") WHERE ("provider_batch_id" IS NOT NULL);



CREATE INDEX "campaigns_brand_sent_idx" ON "public"."campaigns" USING "btree" ("brand_id", "sent_at" DESC, "id");



CREATE INDEX "contacts_brand_email_idx" ON "public"."contacts" USING "btree" ("brand_id", "email") WHERE ("email" IS NOT NULL);



CREATE INDEX "contacts_brand_name_idx" ON "public"."contacts" USING "btree" ("brand_id", "full_name", "id");



CREATE INDEX "contacts_brand_signup_idx" ON "public"."contacts" USING "btree" ("brand_id", "signup_at" DESC, "id");



CREATE INDEX "import_errors_brand_run_idx" ON "public"."import_errors" USING "btree" ("brand_id", "import_run_id", "row_number");



CREATE INDEX "import_runs_brand_started_idx" ON "public"."import_runs" USING "btree" ("brand_id", "started_at" DESC);



CREATE INDEX "provider_events_campaign_time_idx" ON "public"."provider_events" USING "btree" ("brand_id", "campaign_id", "occurred_at", "id");



CREATE INDEX "provider_events_contact_time_idx" ON "public"."provider_events" USING "btree" ("brand_id", "contact_id", "occurred_at", "id");



CREATE INDEX "provider_events_send_time_idx" ON "public"."provider_events" USING "btree" ("send_id", "occurred_at", "id") WHERE ("send_id" IS NOT NULL);



CREATE INDEX "report_sessions_expiry_idx" ON "public"."report_sessions" USING "btree" ("expires_at");



CREATE OR REPLACE TRIGGER "brands_set_updated_at" BEFORE UPDATE ON "public"."brands" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "campaign_send_recipients_protect_snapshot" BEFORE UPDATE ON "public"."campaign_send_recipients" FOR EACH ROW EXECUTE FUNCTION "public"."protect_recipient_snapshot"();



CREATE OR REPLACE TRIGGER "campaign_send_recipients_set_updated_at" BEFORE UPDATE ON "public"."campaign_send_recipients" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "campaign_sends_protect_approval" BEFORE UPDATE ON "public"."campaign_sends" FOR EACH ROW EXECUTE FUNCTION "public"."protect_send_approval"();



CREATE OR REPLACE TRIGGER "campaign_sends_set_updated_at" BEFORE UPDATE ON "public"."campaign_sends" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "campaigns_set_updated_at" BEFORE UPDATE ON "public"."campaigns" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "contacts_set_updated_at" BEFORE UPDATE ON "public"."contacts" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "published_reports_set_updated_at" BEFORE UPDATE ON "public"."published_reports" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



ALTER TABLE ONLY "public"."brand_memberships"
    ADD CONSTRAINT "brand_memberships_brand_id_fkey" FOREIGN KEY ("brand_id") REFERENCES "public"."brands"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."brand_memberships"
    ADD CONSTRAINT "brand_memberships_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."campaign_send_recipients"
    ADD CONSTRAINT "campaign_send_recipients_brand_id_contact_id_fkey" FOREIGN KEY ("brand_id", "contact_id") REFERENCES "public"."contacts"("brand_id", "id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."campaign_send_recipients"
    ADD CONSTRAINT "campaign_send_recipients_brand_id_send_id_fkey" FOREIGN KEY ("brand_id", "send_id") REFERENCES "public"."campaign_sends"("brand_id", "id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."campaign_sends"
    ADD CONSTRAINT "campaign_sends_approved_by_fkey" FOREIGN KEY ("approved_by") REFERENCES "auth"."users"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."campaign_sends"
    ADD CONSTRAINT "campaign_sends_brand_id_campaign_id_fkey" FOREIGN KEY ("brand_id", "campaign_id") REFERENCES "public"."campaigns"("brand_id", "id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."campaigns"
    ADD CONSTRAINT "campaigns_brand_id_fkey" FOREIGN KEY ("brand_id") REFERENCES "public"."brands"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."campaigns"
    ADD CONSTRAINT "campaigns_brand_id_parent_campaign_id_fkey" FOREIGN KEY ("brand_id", "parent_campaign_id") REFERENCES "public"."campaigns"("brand_id", "id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."contacts"
    ADD CONSTRAINT "contacts_brand_id_fkey" FOREIGN KEY ("brand_id") REFERENCES "public"."brands"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."import_errors"
    ADD CONSTRAINT "import_errors_brand_id_fkey" FOREIGN KEY ("brand_id") REFERENCES "public"."brands"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."import_errors"
    ADD CONSTRAINT "import_errors_brand_id_import_run_id_fkey" FOREIGN KEY ("brand_id", "import_run_id") REFERENCES "public"."import_runs"("brand_id", "id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."import_runs"
    ADD CONSTRAINT "import_runs_brand_id_fkey" FOREIGN KEY ("brand_id") REFERENCES "public"."brands"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."import_runs"
    ADD CONSTRAINT "import_runs_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."provider_events"
    ADD CONSTRAINT "provider_events_brand_id_campaign_id_fkey" FOREIGN KEY ("brand_id", "campaign_id") REFERENCES "public"."campaigns"("brand_id", "id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."provider_events"
    ADD CONSTRAINT "provider_events_brand_id_contact_id_fkey" FOREIGN KEY ("brand_id", "contact_id") REFERENCES "public"."contacts"("brand_id", "id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."provider_events"
    ADD CONSTRAINT "provider_events_brand_id_send_id_fkey" FOREIGN KEY ("brand_id", "send_id") REFERENCES "public"."campaign_sends"("brand_id", "id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."provider_events"
    ADD CONSTRAINT "provider_events_brand_id_send_id_send_recipient_id_fkey" FOREIGN KEY ("brand_id", "send_id", "send_recipient_id") REFERENCES "public"."campaign_send_recipients"("brand_id", "send_id", "id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."published_reports"
    ADD CONSTRAINT "published_reports_brand_id_campaign_id_fkey" FOREIGN KEY ("brand_id", "campaign_id") REFERENCES "public"."campaigns"("brand_id", "id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."published_reports"
    ADD CONSTRAINT "published_reports_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."report_sessions"
    ADD CONSTRAINT "report_sessions_brand_id_published_report_id_fkey" FOREIGN KEY ("brand_id", "published_report_id") REFERENCES "public"."published_reports"("brand_id", "id") ON DELETE CASCADE;



ALTER TABLE "public"."brand_memberships" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."brands" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "brands_member_select" ON "public"."brands" FOR SELECT TO "authenticated" USING (( SELECT "private"."is_brand_member"("brands"."id") AS "is_brand_member"));



ALTER TABLE "public"."campaign_send_recipients" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "campaign_send_recipients_member_select" ON "public"."campaign_send_recipients" FOR SELECT TO "authenticated" USING (( SELECT "private"."is_brand_member"("campaign_send_recipients"."brand_id") AS "is_brand_member"));



ALTER TABLE "public"."campaign_sends" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "campaign_sends_member_select" ON "public"."campaign_sends" FOR SELECT TO "authenticated" USING (( SELECT "private"."is_brand_member"("campaign_sends"."brand_id") AS "is_brand_member"));



ALTER TABLE "public"."campaigns" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "campaigns_member_select" ON "public"."campaigns" FOR SELECT TO "authenticated" USING (( SELECT "private"."is_brand_member"("campaigns"."brand_id") AS "is_brand_member"));



ALTER TABLE "public"."contacts" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "contacts_member_select" ON "public"."contacts" FOR SELECT TO "authenticated" USING (( SELECT "private"."is_brand_member"("contacts"."brand_id") AS "is_brand_member"));



ALTER TABLE "public"."import_errors" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "import_errors_member_select" ON "public"."import_errors" FOR SELECT TO "authenticated" USING (( SELECT "private"."is_brand_member"("import_errors"."brand_id") AS "is_brand_member"));



ALTER TABLE "public"."import_runs" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "import_runs_member_select" ON "public"."import_runs" FOR SELECT TO "authenticated" USING (( SELECT "private"."is_brand_member"("import_runs"."brand_id") AS "is_brand_member"));



CREATE POLICY "memberships_self_select" ON "public"."brand_memberships" FOR SELECT TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



ALTER TABLE "public"."provider_events" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "provider_events_member_select" ON "public"."provider_events" FOR SELECT TO "authenticated" USING (( SELECT "private"."is_brand_member"("provider_events"."brand_id") AS "is_brand_member"));



ALTER TABLE "public"."published_reports" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "published_reports_owner_select" ON "public"."published_reports" FOR SELECT TO "authenticated" USING (( SELECT "private"."is_brand_owner"("published_reports"."brand_id") AS "is_brand_owner"));



ALTER TABLE "public"."report_sessions" ENABLE ROW LEVEL SECURITY;


GRANT USAGE ON SCHEMA "private" TO "authenticated";



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



REVOKE ALL ON FUNCTION "private"."current_brand_id"() FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."current_brand_id"() TO "authenticated";



REVOKE ALL ON FUNCTION "private"."is_brand_member"("target_brand_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."is_brand_member"("target_brand_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "private"."is_brand_owner"("target_brand_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."is_brand_owner"("target_brand_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."approve_campaign_send"("target_campaign_id" "uuid", "target_confirmation_key" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."approve_campaign_send"("target_campaign_id" "uuid", "target_confirmation_key" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."approve_campaign_send"("target_campaign_id" "uuid", "target_confirmation_key" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."assert_brand_owner"("target_brand_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."assert_brand_owner"("target_brand_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."assert_brand_owner"("target_brand_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."claim_campaign_dispatch"("target_send_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."claim_campaign_dispatch"("target_send_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."claim_campaign_dispatch"("target_send_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_public_report_session"("target_token_digest" "bytea", "plain_password" "text", "target_session_digest" "bytea") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_public_report_session"("target_token_digest" "bytea", "plain_password" "text", "target_session_digest" "bytea") TO "anon";
GRANT ALL ON FUNCTION "public"."create_public_report_session"("target_token_digest" "bytea", "plain_password" "text", "target_session_digest" "bytea") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_public_report_session"("target_token_digest" "bytea", "plain_password" "text", "target_session_digest" "bytea") TO "service_role";



REVOKE ALL ON FUNCTION "public"."current_portal_context"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."current_portal_context"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."current_portal_context"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."ingest_provider_event_page"("target_send_id" "uuid", "event_page" "jsonb", "target_next_cursor" "text", "target_has_more" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."ingest_provider_event_page"("target_send_id" "uuid", "event_page" "jsonb", "target_next_cursor" "text", "target_has_more" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."ingest_provider_event_page"("target_send_id" "uuid", "event_page" "jsonb", "target_next_cursor" "text", "target_has_more" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "public"."portal_campaign_performance"("result_limit" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."portal_campaign_performance"("result_limit" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."portal_campaign_performance"("result_limit" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."portal_contacts_count"("search_text" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."portal_contacts_count"("search_text" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."portal_contacts_count"("search_text" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."portal_contacts_page"("search_text" "text", "page_size" integer, "page_offset" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."portal_contacts_page"("search_text" "text", "page_size" integer, "page_offset" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."portal_contacts_page"("search_text" "text", "page_size" integer, "page_offset" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."portal_dashboard_summary"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."portal_dashboard_summary"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."portal_dashboard_summary"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."portal_send_audience"("target_campaign_id" "uuid", "page_size" integer, "page_offset" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."portal_send_audience"("target_campaign_id" "uuid", "page_size" integer, "page_offset" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."portal_send_audience"("target_campaign_id" "uuid", "page_size" integer, "page_offset" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."portal_send_audience_count"("target_campaign_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."portal_send_audience_count"("target_campaign_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."portal_send_audience_count"("target_campaign_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."portal_signup_series"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."portal_signup_series"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."portal_signup_series"() TO "service_role";



GRANT ALL ON FUNCTION "public"."protect_recipient_snapshot"() TO "anon";
GRANT ALL ON FUNCTION "public"."protect_recipient_snapshot"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."protect_recipient_snapshot"() TO "service_role";



GRANT ALL ON FUNCTION "public"."protect_send_approval"() TO "anon";
GRANT ALL ON FUNCTION "public"."protect_send_approval"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."protect_send_approval"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."public_campaign_report"("target_session_digest" "bytea") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."public_campaign_report"("target_session_digest" "bytea") TO "anon";
GRANT ALL ON FUNCTION "public"."public_campaign_report"("target_session_digest" "bytea") TO "authenticated";
GRANT ALL ON FUNCTION "public"."public_campaign_report"("target_session_digest" "bytea") TO "service_role";



REVOKE ALL ON FUNCTION "public"."publish_campaign_report"("target_campaign_id" "uuid", "target_token_digest" "bytea", "plain_password" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."publish_campaign_report"("target_campaign_id" "uuid", "target_token_digest" "bytea", "plain_password" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."publish_campaign_report"("target_campaign_id" "uuid", "target_token_digest" "bytea", "plain_password" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."record_campaign_dispatch_failure"("target_send_id" "uuid", "safe_error" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."record_campaign_dispatch_failure"("target_send_id" "uuid", "safe_error" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."record_campaign_dispatch_failure"("target_send_id" "uuid", "safe_error" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."record_campaign_dispatch_result"("target_send_id" "uuid", "target_provider_batch_id" "text", "accepted_identifiers" "text"[], "rejected_identifiers" "text"[]) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."record_campaign_dispatch_result"("target_send_id" "uuid", "target_provider_batch_id" "text", "accepted_identifiers" "text"[], "rejected_identifiers" "text"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."record_campaign_dispatch_result"("target_send_id" "uuid", "target_provider_batch_id" "text", "accepted_identifiers" "text"[], "rejected_identifiers" "text"[]) TO "service_role";



REVOKE ALL ON FUNCTION "public"."record_campaign_reconciliation_failure"("target_send_id" "uuid", "safe_error" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."record_campaign_reconciliation_failure"("target_send_id" "uuid", "safe_error" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."record_campaign_reconciliation_failure"("target_send_id" "uuid", "safe_error" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "service_role";



GRANT ALL ON TABLE "public"."brand_memberships" TO "service_role";
GRANT SELECT ON TABLE "public"."brand_memberships" TO "authenticated";



GRANT ALL ON TABLE "public"."brands" TO "service_role";
GRANT SELECT ON TABLE "public"."brands" TO "authenticated";



GRANT ALL ON TABLE "public"."campaign_send_recipients" TO "service_role";
GRANT SELECT ON TABLE "public"."campaign_send_recipients" TO "authenticated";



GRANT ALL ON TABLE "public"."campaign_sends" TO "service_role";
GRANT SELECT ON TABLE "public"."campaign_sends" TO "authenticated";



GRANT ALL ON TABLE "public"."campaigns" TO "service_role";
GRANT SELECT ON TABLE "public"."campaigns" TO "authenticated";



GRANT ALL ON TABLE "public"."contacts" TO "service_role";
GRANT SELECT ON TABLE "public"."contacts" TO "authenticated";



GRANT ALL ON TABLE "public"."import_errors" TO "service_role";
GRANT SELECT ON TABLE "public"."import_errors" TO "authenticated";



GRANT ALL ON SEQUENCE "public"."import_errors_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."import_errors_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."import_errors_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."import_runs" TO "service_role";
GRANT SELECT ON TABLE "public"."import_runs" TO "authenticated";



GRANT ALL ON TABLE "public"."provider_events" TO "service_role";
GRANT SELECT ON TABLE "public"."provider_events" TO "authenticated";



GRANT ALL ON SEQUENCE "public"."provider_events_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."provider_events_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."provider_events_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."published_reports" TO "service_role";
GRANT SELECT ON TABLE "public"."published_reports" TO "authenticated";



GRANT ALL ON TABLE "public"."report_sessions" TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";







