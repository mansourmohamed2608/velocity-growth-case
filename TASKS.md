# Velocity Growth Acceptance Checklist

Status values are `TODO`, `PASS`, `FAIL`, and `N/A` (with justification). The employer PDF was reviewed in full on 15 Sep 2026.

## Discovery and governance

- [x] PASS — Review all five pages of the employer PDF.
- [x] PASS — Independently verify the seed SHA-256.
- [x] PASS — Inspect all 11 seed files, formats, relationships, and quality issues.
- [x] PASS — Inspect provider authentication, endpoints, schemas, limits, pagination, and identifiers.
- [x] PASS — Create project governance and architecture documents.

## Application and data

- [ ] TODO — Public, responsive production web application.
- [ ] TODO — All three brands live: Kilele Rides, Karoo Coaches, Marrakech Express.
- [ ] TODO — Six authorized accounts: one owner and one analyst per brand.
- [ ] TODO — Email/password and Google sign-in both work.
- [ ] TODO — Unauthorized authenticated identities get no tenant access.
- [ ] TODO — Idempotently import all valid contacts, campaigns, events, send-log rows, and the Kilele delta.
- [ ] TODO — Reject invalid rows and persist visible, actionable reasons.
- [ ] TODO — Re-import leaves stable logical counts.

## Tenant security and roles

- [ ] TODO — PostgreSQL RLS protects every exposed tenant-owned table.
- [ ] TODO — Direct Supabase requests cannot cross tenants.
- [ ] TODO — Guessed IDs, joins, missing frontend filters, and RPCs cannot cross tenants.
- [ ] TODO — Owners can send and publish; analysts are read-only.
- [ ] TODO — At least one automated test fails if central tenant isolation is removed.

## Portal

- [ ] TODO — Dashboard shows total customers and contactable customers.
- [ ] TODO — Dashboard shows daily signups for the latest 30-day data window.
- [ ] TODO — Dashboard shows per-campaign performance.
- [ ] TODO — Metric definitions and ambiguity are displayed.
- [ ] TODO — Contacts are server-paginated and usable for the largest brand.
- [ ] TODO — Campaign history/results and role-appropriate actions work.
- [ ] TODO — Loading, empty, error, and permission-denied states are honest.
- [ ] TODO — Phone and laptop layouts are usable and accessible.

## Safe sending

- [ ] TODO — Owner sees the exact eligible recipients and count before confirmation.
- [ ] TODO — Approval freezes an immutable recipient snapshot and audit metadata.
- [ ] TODO — Database uniqueness/locking prevents duplicate logical sends under concurrency.
- [ ] TODO — Retries, response loss, interruption, and partial failure are visible and recoverable.
- [ ] TODO — Provider dispatch is server-side and uses a stable idempotency key.
- [ ] TODO — Provider batch ID and per-recipient progress/results are inspectable.
- [ ] TODO — Analysts cannot preview privileged data or confirm/dispatch.

## Provider reconciliation

- [ ] TODO — Poll provider reports incrementally and safely after downtime.
- [ ] TODO — Deduplicate events by provider event ID.
- [ ] TODO — Delivered, bounced, opened, and unsubscribed facts converge under duplicate/out-of-order replay.
- [ ] TODO — Bounce/unsubscribe/complaint outcomes update contactability conservatively.
- [ ] TODO — Dashboard results derive from reconciled facts.

## Public report

- [ ] TODO — Owner can publish exactly one campaign using an opaque random token.
- [ ] TODO — Password is strongly hashed and checked server-side.
- [ ] TODO — Limited HTTP-only report session exposes only the bound campaign summary.
- [ ] TODO — Wrong/modified/guessed tokens, campaign substitution, enumeration, and tenant pivot fail.
- [ ] TODO — Report access cannot become portal access.

## Verification, deployment, and submission

- [ ] TODO — Format, lint, typecheck, unit, database, RLS, integration, and E2E checks pass.
- [ ] TODO — Fresh local migration/reset and two imports reproduce stable counts.
- [ ] TODO — Secret scan covers working tree, Git history, and browser bundle.
- [ ] TODO — Meaningful commit history pushed to the existing public GitHub repository.
- [ ] TODO — Migrations/functions/data deployed to hosted project `phtafctxyabkvqlcsulz`.
- [ ] TODO — Production app deployed with correct Supabase/Google redirect configuration.
- [ ] TODO — Production smoke and direct restricted-user Supabase isolation tests pass.
- [ ] TODO — `schema.sql`, `README.md`, `SUBMISSION.md`, and private credentials are complete.
- [ ] TODO — Employer-requested note is at most 300 words and answers all four questions.
- [ ] TODO — Final requirement and security audits pass with a clean pushed worktree.

