begin;

select plan(16);

select has_table('public', 'brands', 'brands table exists');
select has_table('public', 'contacts', 'contacts table exists');
select has_table('public', 'campaigns', 'campaigns table exists');
select has_table('public', 'campaign_sends', 'campaign sends table exists');
select has_table('public', 'provider_events', 'provider events table exists');
select has_table('public', 'published_reports', 'published reports table exists');

select results_eq(
  $$select count(*)::bigint from public.brands$$,
  array[3::bigint],
  'three deterministic brands are seeded'
);

select throws_ok(
  $$insert into public.contacts (
      brand_id, external_id, full_name, signup_at, lifecycle_status,
      marketing_consent, email_status, sms_status
    ) values (
      '11111111-1111-4111-8111-111111111111', 'bad', 'Bad id', now(),
      'active', true, 'unavailable', 'unavailable'
    )$$,
  '23514',
  null,
  'malformed contact external IDs are rejected'
);

select throws_ok(
  $$insert into public.contacts (
      brand_id, external_id, full_name, email, signup_at, lifecycle_status,
      marketing_consent, email_status, sms_status
    ) values (
      '11111111-1111-4111-8111-111111111111', 'CT-999991', 'Bad email',
      'not an email', now(), 'active', true, 'active', 'unavailable'
    )$$,
  '23514',
  null,
  'malformed emails are rejected'
);

insert into public.contacts (
  id, brand_id, external_id, full_name, email, signup_at, lifecycle_status,
  marketing_consent, email_status, sms_status
) values (
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  '11111111-1111-4111-8111-111111111111',
  'CT-999992', 'Test Contact', 'test@example.test', now(), 'active', true,
  'active', 'unavailable'
);

select throws_ok(
  $$insert into public.contacts (
      brand_id, external_id, full_name, email, signup_at, lifecycle_status,
      marketing_consent, email_status, sms_status
    ) values (
      '11111111-1111-4111-8111-111111111111', 'CT-999992', 'Duplicate',
      'duplicate@example.test', now(), 'active', true, 'active', 'unavailable'
    )$$,
  '23505',
  null,
  'brand-scoped contact source IDs are unique'
);

insert into public.campaigns (
  id, brand_id, external_id, name, channel, sent_at
) values (
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  '22222222-2222-4222-8222-222222222222',
  'KAR-TEST', 'Karoo test', 'email', now()
);

select throws_ok(
  $$insert into public.provider_events (
      brand_id, campaign_id, contact_id, source, provider_event_id,
      event_type, channel, occurred_at
    ) values (
      '11111111-1111-4111-8111-111111111111',
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'seed', 'EV-CROSS-BRAND', 'opened', 'email', now()
    )$$,
  '23503',
  null,
  'composite foreign keys reject cross-brand event joins'
);

select throws_ok(
  $$insert into public.campaigns (
      brand_id, external_id, name, channel, reported_sent, sent_at
    ) values (
      '11111111-1111-4111-8111-111111111111',
      'KIL-NEGATIVE', 'Negative', 'email', -1, now()
    )$$,
  '23514',
  null,
  'negative campaign counts are rejected'
);

select throws_ok(
  $$insert into public.import_runs (
      brand_id, source_filename, source_kind, content_sha256,
      status, source_rows, accepted_rows, rejected_rows, completed_at
    ) values (
      '11111111-1111-4111-8111-111111111111', 'x.csv', 'contacts',
      repeat('a', 64), 'completed', 1, 1, 1, now()
    )$$,
  '23514',
  null,
  'import counters cannot exceed source rows'
);

select throws_ok(
  $$insert into public.published_reports (
      brand_id, campaign_id, created_by, token_digest, password_hash
    ) values (
      '22222222-2222-4222-8222-222222222222',
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      gen_random_uuid(), decode('00', 'hex'), repeat('x', 60)
    )$$,
  '23514',
  null,
  'short public report token digests are rejected'
);

select has_index(
  'public',
  'contacts',
  'contacts_brand_signup_idx',
  'contacts have a tenant pagination/index path'
);

select has_index(
  'public',
  'provider_events',
  'provider_events_campaign_time_idx',
  'campaign event aggregation is indexed'
);

select * from finish();
rollback;
