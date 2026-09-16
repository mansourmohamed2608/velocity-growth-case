# Velocity Growth — Submission

## Public links and project access

- Live application: <https://velocity-growth-case.vercel.app>
- GitHub: <https://github.com/mansourmohamed2608/velocity-growth-case>
- Supabase project URL: <https://phtafctxyabkvqlcsulz.supabase.co>
- Supabase project ref: `phtafctxyabkvqlcsulz`
- Client key type: modern Supabase **publishable** key (RLS-protected; no secret/service-role key is deployed to the browser)
- Publishable key: `sb_publishable_X8YKm4CmjEqpkcY_K7YXEg_U9Ku5vP6`
- Google sign-in: live and production-verified with the permitted candidate-controlled Kilele owner account

The six email/password credentials, provider key, public-report URL, and report password are deliberately kept out of this public repository and are ready in `SUBMISSION_PRIVATE.md` for the submission email.

## Database surface

Tables: `brands`, `brand_memberships`, `import_runs`, `import_errors`, `contacts`, `campaigns`, `campaign_sends`, `campaign_send_recipients`, `provider_events`, `published_reports`, `report_sessions`.

Application RPCs: `current_portal_context`, `portal_dashboard_summary`, `portal_signup_series`, `portal_campaign_performance`, `portal_contacts_page`, `portal_contacts_count`, `portal_send_audience`, `portal_send_audience_count`, `approve_campaign_send`, `claim_campaign_dispatch`, `record_campaign_dispatch_result`, `record_campaign_dispatch_failure`, `ingest_provider_event_page`, `record_campaign_reconciliation_failure`, `publish_campaign_report`, `create_public_report_session`, `public_campaign_report`.

The deployed app uses only the publishable key. The Vercel server runtime separately holds the messaging provider key; no Supabase service-role key is required by application requests.

## Send and report inspection

Send progress is visible to the owner at `/portal/campaigns/{campaign-id}/send`. Database detail is in `campaign_sends` (approval, attempts, provider batch/cursor, counts, safe errors) and `campaign_send_recipients` (immutable approved destination and per-recipient status). Raw reconciled provider facts are in `provider_events`.

The explicitly approved MAR-0002 SMS send completed with one dispatch attempt: 449 frozen recipients, 449 provider-accepted, 0 rejected, 423 delivered, 120 opened, 26 bounced, and 17 unsubscribed at final reconciliation. One provider event outside the frozen audience was left unbound and counted rather than attached to a customer. The owner view exposes the reconciled totals and no longer offers a dispatch action.

One Kilele campaign report has been published and verified from a fresh anonymous browser. Its capability URL and separate password are in the private submission material rather than public Git history.

## Candidate and tooling

- AI tools: OpenAI Codex
- Engineering time: approximately one focused workday, plus environment and production-deployment verification
- Earliest start date: **Immediately**
- Notice period: **None**

## Required note (under 300 words)

I deliberately attacked the database with cross-brand reads, omitted brand filters, guessed foreign UUIDs, relationship joins, RPC calls, analyst writes, and an authenticated user with no membership. I reran malformed and duplicate imports, raced approvals from two sessions, replayed response-loss and partial-provider outcomes, reordered and duplicated events, tried wrong/modified report credentials, and tested the largest tenant in production. That last test exposed and fixed a real hosted statement timeout.

The central data-isolation predicate is `private.is_brand_member` in `supabase/migrations/20260915190000_tenant_security.sql:7`; forced RLS begins at line 80 and the tenant-table policies begin at line 103. Composite brand foreign keys in `20260915180000_initial_schema.sql` prevent cross-tenant relationships.

The number I am least certain about is **Contactable now**. Its calculation is deterministic and tested, but “contactable” is a business interpretation of consent, lifecycle status, suppression, address validity, and terminal provider facts. A different policy choice could legitimately produce another number. Reported campaign totals are also inconsistent in the supplied export, so the UI keeps reported and event-derived values separate.

Unfinished: no mandatory build or submission item remains. Provider delivery facts are inherently external, but the approved batch reached the end of its cursor report and the portal can safely resume incremental reconciliation if later facts become available.
