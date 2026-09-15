begin;

select plan(22);

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
  id, brand_id, external_id, full_name, email, signup_at,
  lifecycle_status, marketing_consent, email_status, sms_status
)
values
  ('a1111111-1111-4111-8111-111111111111', '11111111-1111-4111-8111-111111111111', 'CT-900001', 'Kilele Contact', 'kilele@example.test', now(), 'active', true, 'active', 'unavailable'),
  ('a2222222-2222-4222-8222-222222222222', '22222222-2222-4222-8222-222222222222', 'CT-900001', 'Karoo Contact', 'karoo@example.test', now(), 'active', true, 'active', 'unavailable'),
  ('a3333333-3333-4333-8333-333333333333', '33333333-3333-4333-8333-333333333333', 'CT-900001', 'Marrakech Contact', 'marrakech@example.test', now(), 'active', true, 'active', 'unavailable');

insert into public.campaigns (id, brand_id, external_id, name, channel, sent_at)
values
  ('b1111111-1111-4111-8111-111111111111', '11111111-1111-4111-8111-111111111111', 'KIL-TEST', 'Kilele Campaign', 'email', now()),
  ('b2222222-2222-4222-8222-222222222222', '22222222-2222-4222-8222-222222222222', 'KAR-TEST', 'Karoo Campaign', 'email', now()),
  ('b3333333-3333-4333-8333-333333333333', '33333333-3333-4333-8333-333333333333', 'MAR-TEST', 'Marrakech Campaign', 'email', now());

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
