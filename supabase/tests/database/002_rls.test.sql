begin;

select plan(49);

insert into auth.users (id, email)
values
  ('10000000-0000-4000-8000-000000000001', 'owner.kilele@example.test'),
  ('10000000-0000-4000-8000-000000000002', 'analyst.kilele@example.test'),
  ('20000000-0000-4000-8000-000000000001', 'owner.karoo@example.test'),
  ('30000000-0000-4000-8000-000000000001', 'owner.marrakech@example.test'),
  ('90000000-0000-4000-8000-000000000001', 'unknown@example.test');

insert into public.brand_memberships (brand_id, user_id, role)
values
  ('11111111-1111-4111-8111-111111111111', '10000000-0000-4000-8000-000000000001', 'owner'),
  ('11111111-1111-4111-8111-111111111111', '10000000-0000-4000-8000-000000000002', 'analyst'),
  ('22222222-2222-4222-8222-222222222222', '20000000-0000-4000-8000-000000000001', 'owner'),
  ('33333333-3333-4333-8333-333333333333', '30000000-0000-4000-8000-000000000001', 'owner');

insert into public.contacts (
  id, brand_id, external_id, full_name, email, country_code, signup_at,
  lifecycle_status, marketing_consent, email_status, sms_status
)
values
  ('a1111111-1111-4111-8111-111111111111', '11111111-1111-4111-8111-111111111111', 'CT-900001', 'Kilele Contact', 'kilele@example.test', 'AQ', now(), 'active', true, 'active', 'unavailable'),
  ('a2222222-2222-4222-8222-222222222222', '22222222-2222-4222-8222-222222222222', 'CT-900001', 'Karoo Contact', 'karoo@example.test', 'BV', now(), 'active', true, 'active', 'unavailable'),
  ('a3333333-3333-4333-8333-333333333333', '33333333-3333-4333-8333-333333333333', 'CT-900001', 'Marrakech Contact', 'marrakech@example.test', 'TF', now(), 'active', true, 'active', 'unavailable');

insert into public.campaigns (id, brand_id, external_id, name, channel, target_country_code, sent_at)
values
  ('b1111111-1111-4111-8111-111111111111', '11111111-1111-4111-8111-111111111111', 'KIL-TEST', 'Kilele Campaign', 'email', 'AQ', now()),
  ('b2222222-2222-4222-8222-222222222222', '22222222-2222-4222-8222-222222222222', 'KAR-TEST', 'Karoo Campaign', 'email', 'BV', now()),
  ('b3333333-3333-4333-8333-333333333333', '33333333-3333-4333-8333-333333333333', 'MAR-TEST', 'Marrakech Campaign', 'email', 'TF', now());

insert into public.provider_events (
  brand_id, campaign_id, contact_id, source, provider_event_id,
  event_type, channel, occurred_at
)
values
  ('11111111-1111-4111-8111-111111111111', 'b1111111-1111-4111-8111-111111111111', 'a1111111-1111-4111-8111-111111111111', 'seed', 'EV-KILELE', 'opened', 'email', now()),
  ('22222222-2222-4222-8222-222222222222', 'b2222222-2222-4222-8222-222222222222', 'a2222222-2222-4222-8222-222222222222', 'seed', 'EV-KAROO', 'opened', 'email', now());

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000001', true);

select results_eq(
  $$select name from public.brands order by name$$,
  array['Kilele Rides'::text],
  'Kilele owner sees one brand'
);
select results_eq(
  $$select distinct brand_id::text from public.contacts order by brand_id::text$$,
  array['11111111-1111-4111-8111-111111111111'::text],
  'central isolation policy hides all foreign contacts without a client filter'
);
select is_empty(
  $$select * from public.contacts where brand_id = '22222222-2222-4222-8222-222222222222'$$,
  'Kilele cannot request Karoo contacts explicitly'
);
select is_empty(
  $$select * from public.campaigns where brand_id = '33333333-3333-4333-8333-333333333333'$$,
  'Kilele cannot request Marrakech campaigns explicitly'
);
select is_empty(
  $$select * from public.contacts where id = 'a2222222-2222-4222-8222-222222222222'$$,
  'a guessed foreign contact UUID returns no row'
);
select results_eq(
  $$select distinct event.brand_id::text from public.provider_events event
    join public.campaigns campaign on campaign.id = event.campaign_id
    order by event.brand_id::text$$,
  array['11111111-1111-4111-8111-111111111111'::text],
  'a relationship join cannot reveal a foreign event'
);
select results_eq(
  $$select brand_code || ':' || role::text from public.current_portal_context()$$,
  array['KILELE:owner'::text],
  'context RPC returns only the caller membership'
);
select lives_ok(
  $$select public.assert_brand_owner('11111111-1111-4111-8111-111111111111')$$,
  'owner authorization RPC accepts the matching owner'
);
select ok(
  (select total_customers = (select count(*) from public.contacts)
   from public.portal_dashboard_summary()),
  'dashboard aggregate sees exactly the RLS-visible contact set'
);
select results_eq(
  $$select external_id from public.portal_contacts_page('Kilele Contact', 25, 0)$$,
  array['CT-900001'::text],
  'contact pagination returns a matching same-tenant contact'
);
select results_eq(
  $$select public.portal_contacts_count(null)$$,
  $$select count(*)::bigint from public.contacts$$,
  'contact count matches the complete RLS-visible result set'
);
select is_empty(
  $$select * from public.portal_campaign_performance(100) where external_id = 'KAR-TEST'$$,
  'campaign performance cannot expose a foreign campaign'
);
select results_eq(
  $$select public.portal_send_audience_count('b1111111-1111-4111-8111-111111111111')$$,
  array[1::bigint],
  'owner preview calculates the exact currently eligible audience'
);
select results_eq(
  $$select external_id from public.portal_send_audience('b1111111-1111-4111-8111-111111111111', 25, 0)$$,
  array['CT-900001'::text],
  'owner preview returns only exact channel and country eligible recipients'
);
select results_eq(
  $$select recipient_count from public.approve_campaign_send(
    'b1111111-1111-4111-8111-111111111111',
    'dddddddd-dddd-4ddd-8ddd-dddddddddddd'
  )$$,
  array[1::integer],
  'owner approval atomically freezes the previewed audience'
);
select results_eq(
  $$select recipient_count from public.approve_campaign_send(
    'b1111111-1111-4111-8111-111111111111',
    'dddddddd-dddd-4ddd-8ddd-dddddddddddd'
  )$$,
  array[1::integer],
  'retrying the same confirmation key is idempotent'
);
select results_eq(
  $$select count(*)::bigint from public.campaign_send_recipients
    where contact_external_id = 'CT-900001'$$,
  array[1::bigint],
  'idempotent approval creates exactly one immutable recipient snapshot'
);
reset role;
select throws_ok(
  $$update public.campaign_send_recipients
    set destination = 'changed@example.test'
    where contact_external_id = 'CT-900001'$$,
  'P0001',
  'approved recipient snapshot is immutable',
  'even a privileged update cannot alter an approved recipient identity'
);
update public.contacts
set email = 'later-change@example.test'
where id = 'a1111111-1111-4111-8111-111111111111';
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000001', true);
select results_eq(
  $$select destination from public.campaign_send_recipients
    where contact_external_id = 'CT-900001'$$,
  array['kilele@example.test'::text],
  'later contact changes do not alter the historical approval snapshot'
);
select results_eq(
  $$select public.claim_campaign_dispatch(send.id)->>'recipient_count'
    from public.campaign_sends send where send.campaign_id = 'b1111111-1111-4111-8111-111111111111'$$,
  array['1'::text],
  'dispatch claim returns the complete frozen audience payload'
);
select results_eq(
  $$select public.claim_campaign_dispatch(send.id)->>'recipient_count'
    from public.campaign_sends send where send.campaign_id = 'b1111111-1111-4111-8111-111111111111'$$,
  array['1'::text],
  'an interrupted dispatch can reclaim the same immutable payload'
);
select results_eq(
  $$select result.status::text || ':' || result.accepted_count || ':' || result.rejected_count
    from public.campaign_sends send
    cross join lateral public.record_campaign_dispatch_result(
      send.id, 'batch-test-1', array['CT-900001'], array[]::text[]
    ) result
    where send.campaign_id = 'b1111111-1111-4111-8111-111111111111'$$,
  array['submitted:1:0'::text],
  'provider acceptance records the batch and per-recipient progress'
);
select results_eq(
  $$select result.status::text || ':' || result.accepted_count
    from public.campaign_sends send
    cross join lateral public.record_campaign_dispatch_result(
      send.id, 'batch-test-1', array['CT-900001'], array[]::text[]
    ) result
    where send.campaign_id = 'b1111111-1111-4111-8111-111111111111'$$,
  array['submitted:1'::text],
  'recording the same provider result twice is idempotent'
);
select results_eq(
  $$select result.inserted_events || ':' || result.delivered_count || ':' || result.opened_count
    from public.campaign_sends send
    cross join lateral public.ingest_provider_event_page(
      send.id,
      jsonb_build_array(
        jsonb_build_object('event_id', 'evt-open', 'recipient_identifier', 'CT-900001', 'event_type', 'opened', 'occurred_at', '2026-09-15T12:05:00Z', 'raw_payload', '{}'::jsonb),
        jsonb_build_object('event_id', 'evt-delivered', 'recipient_identifier', 'CT-900001', 'event_type', 'delivered', 'occurred_at', '2026-09-15T12:00:00Z', 'raw_payload', '{}'::jsonb),
        jsonb_build_object('event_id', 'evt-open', 'recipient_identifier', 'CT-900001', 'event_type', 'opened', 'occurred_at', '2026-09-15T12:05:00Z', 'raw_payload', '{}'::jsonb)
      ), null, false
    ) result
    where send.campaign_id = 'b1111111-1111-4111-8111-111111111111'$$,
  array['2:1:1'::text],
  'out-of-order events and a same-page duplicate ingest idempotently'
);
select results_eq(
  $$select result.inserted_events || ':' || result.bounced_count || ':' || result.unsubscribed_count
    from public.campaign_sends send
    cross join lateral public.ingest_provider_event_page(
      send.id,
      jsonb_build_array(
        jsonb_build_object('event_id', 'evt-delivered', 'recipient_identifier', 'CT-900001', 'event_type', 'delivered', 'occurred_at', '2026-09-15T12:00:00Z', 'raw_payload', '{}'::jsonb),
        jsonb_build_object('event_id', 'evt-bounced', 'recipient_identifier', 'CT-900001', 'event_type', 'bounced', 'occurred_at', '2026-09-15T12:10:00Z', 'raw_payload', '{}'::jsonb),
        jsonb_build_object('event_id', 'evt-unsubscribed', 'recipient_identifier', 'CT-900001', 'event_type', 'unsubscribed', 'occurred_at', '2026-09-15T11:00:00Z', 'raw_payload', '{}'::jsonb)
      ), 'evt-unsubscribed', false
    ) result
    where send.campaign_id = 'b1111111-1111-4111-8111-111111111111'$$,
  array['2:1:1'::text],
  'late duplicated terminal facts converge without double counting'
);
select results_eq(
  $$select status::text from public.campaign_send_recipients where contact_external_id = 'CT-900001'$$,
  array['unsubscribed'::text],
  'recipient state uses conservative terminal precedence, not arrival order'
);
select results_eq(
  $$select email_status::text from public.contacts where external_id = 'CT-900001'$$,
  array['unsubscribed'::text],
  'provider unsubscribe updates future email contactability'
);
select results_eq(
  $$select result.inserted_events || ':' || result.delivered_count || ':' || result.opened_count
    from public.campaign_sends send
    cross join lateral public.ingest_provider_event_page(
      send.id,
      jsonb_build_array(
        jsonb_build_object('event_id', 'evt-open', 'recipient_identifier', 'CT-900001', 'event_type', 'opened', 'occurred_at', '2026-09-15T12:05:00Z', 'raw_payload', '{}'::jsonb),
        jsonb_build_object('event_id', 'evt-delivered', 'recipient_identifier', 'CT-900001', 'event_type', 'delivered', 'occurred_at', '2026-09-15T12:00:00Z', 'raw_payload', '{}'::jsonb)
      ), null, false
    ) result
    where send.campaign_id = 'b1111111-1111-4111-8111-111111111111'$$,
  array['0:1:1'::text],
  'replaying a provider page inserts no duplicate events and keeps aggregates stable'
);
select throws_ok(
  $$select public.record_campaign_dispatch_result(
      send.id, 'different-batch', array['CT-900001'], array[]::text[]
    )
    from public.campaign_sends send
    where send.campaign_id = 'b1111111-1111-4111-8111-111111111111'$$,
  '23505',
  'provider batch id conflicts with the recorded dispatch',
  'a response cannot replace an already bound provider batch'
);
select throws_ok(
  $$select public.claim_campaign_dispatch(send.id)
    from public.campaign_sends send where send.campaign_id = 'b1111111-1111-4111-8111-111111111111'$$,
  '55000',
  'send is not dispatchable',
  'a submitted send cannot be dispatched again'
);
select throws_ok(
  $$select public.assert_brand_owner('22222222-2222-4222-8222-222222222222')$$,
  '42501',
  'owner role required',
  'owner authorization RPC rejects a foreign brand'
);
select throws_ok(
  $$insert into public.contacts (
      brand_id, external_id, full_name, email, signup_at, lifecycle_status,
      marketing_consent, email_status, sms_status
    ) values (
      '11111111-1111-4111-8111-111111111111', 'CT-900099', 'Direct write',
      'write@example.test', now(), 'active', true, 'active', 'unavailable'
    )$$,
  '42501',
  null,
  'owners cannot bypass workflows with direct table writes'
);

select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000002', true);
select results_eq(
  $$select distinct brand_id::text from public.contacts order by brand_id::text$$,
  array['11111111-1111-4111-8111-111111111111'::text],
  'analyst may read only the matching tenant'
);
select throws_ok(
  $$insert into public.campaigns (
      brand_id, external_id, name, channel, sent_at
    ) values (
      '11111111-1111-4111-8111-111111111111', 'KIL-WRITE', 'Write', 'email', now()
    )$$,
  '42501',
  null,
  'analyst cannot insert'
);
select throws_ok(
  $$update public.contacts set full_name = 'Changed' where id = 'a1111111-1111-4111-8111-111111111111'$$,
  '42501',
  null,
  'analyst cannot update'
);
select throws_ok(
  $$delete from public.contacts where id = 'a1111111-1111-4111-8111-111111111111'$$,
  '42501',
  null,
  'analyst cannot delete'
);
select throws_ok(
  $$select public.assert_brand_owner('11111111-1111-4111-8111-111111111111')$$,
  '42501',
  'owner role required',
  'analyst cannot use an owner-only RPC'
);
select throws_ok(
  $$select public.portal_send_audience_count('b1111111-1111-4111-8111-111111111111')$$,
  '42501',
  'owner role required',
  'analyst cannot preview a send audience'
);
select throws_ok(
  $$select public.approve_campaign_send(
    'b1111111-1111-4111-8111-111111111111',
    'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'
  )$$,
  '42501',
  'owner role required',
  'analyst cannot confirm or retry a campaign send'
);
select throws_ok(
  $$select public.claim_campaign_dispatch(send.id)
    from public.campaign_sends send where send.campaign_id = 'b1111111-1111-4111-8111-111111111111'$$,
  '42501',
  'owner role required',
  'analyst cannot claim an approved provider dispatch'
);
select throws_ok(
  $$select public.ingest_provider_event_page(
      send.id, '[]'::jsonb, null, false
    )
    from public.campaign_sends send
    where send.campaign_id = 'b1111111-1111-4111-8111-111111111111'$$,
  '42501',
  'owner role required',
  'analyst cannot inject provider reconciliation facts'
);

select set_config('request.jwt.claim.sub', '20000000-0000-4000-8000-000000000001', true);
select is_empty(
  $$select * from public.contacts where brand_id = '11111111-1111-4111-8111-111111111111'$$,
  'Karoo cannot request Kilele contacts'
);
select results_eq(
  $$select distinct brand_id::text from public.contacts order by brand_id::text$$,
  array['22222222-2222-4222-8222-222222222222'::text],
  'Karoo direct unfiltered access returns only Karoo'
);

select set_config('request.jwt.claim.sub', '90000000-0000-4000-8000-000000000001', true);
select is_empty(
  $$select * from public.contacts$$,
  'unknown authenticated user sees no contacts'
);
select is_empty(
  $$select * from public.brands$$,
  'unknown authenticated user sees no brands'
);
select is_empty(
  $$select * from public.current_portal_context()$$,
  'unknown authenticated user gets no portal context'
);
select results_eq(
  $$select total_customers from public.portal_dashboard_summary()$$,
  array[0::bigint],
  'unknown authenticated user receives a zero-contact aggregate rather than tenant data'
);

reset role;
set local role anon;
select set_config('request.jwt.claim.role', 'anon', true);
select set_config('request.jwt.claim.sub', '', true);
select throws_ok(
  $$select * from public.contacts$$,
  '42501',
  null,
  'anonymous callers have no tenant-table grant'
);
select throws_ok(
  $$select * from public.report_sessions$$,
  '42501',
  null,
  'report sessions are never directly exposed'
);

select * from finish();
rollback;
