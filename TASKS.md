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
- [ ] TODO — Email/password works for all six local accounts; Google sign-in still needs a production browser check.
- [x] PASS — Unauthorized authenticated identities get no tenant access (direct RLS and context-RPC regression tests).
- [x] PASS — Idempotently import all valid contacts, campaigns, events, send-log rows, and the Kilele delta.
- [x] PASS — Invalid rows and actionable reasons persist and are visible in the dashboard’s source-health panel.
- [x] PASS — Two clean full imports leave identical logical counts and zero duplicate natural keys.

## Tenant security and roles

- [x] PASS — PostgreSQL RLS protects every exposed tenant-owned table; report sessions have no client grants.
- [x] PASS — Direct Supabase requests cannot cross tenants.
- [x] PASS — Guessed IDs, joins, missing frontend filters, and RPCs cannot cross tenants.
- [x] PASS — Owners can send and publish; analysts are read-only (database authorization and authenticated browser checks).
- [x] PASS — The unfiltered three-tenant contact regression test fails if the central membership policy is removed.

## Portal

- [x] PASS — Dashboard shows SQL-reconciled total customers and derived contactable customers.
- [x] PASS — Dashboard shows daily signups for the 30-day window ending at the tenant’s latest data date.
- [x] PASS — Dashboard shows bounded per-campaign reported and event-derived performance.
- [x] PASS — Metric definitions and source ambiguity are displayed without silently substituting values.
- [x] PASS — Contacts use bounded server/database pagination, exact counts, and server-side search.
- [x] PASS — Campaign history/results and owner-only audience approval work; analysts see read-only controls.
- [x] PASS — Loading, empty, query-error, and permission-denied states are explicit and do not infer zeros.
- [x] PASS — Phone and laptop layouts pass authenticated and public browser checks at 390 px and 1440 px.

## Safe sending

- [x] PASS — Owner sees the exact channel/country-eligible recipients and count before confirmation.
- [x] PASS — Approval atomically freezes immutable recipient destinations, source facts, approver, and time.
- [x] PASS — Per-campaign advisory locking plus unique campaign/confirmation keys prevent duplicate logical sends.
- [x] PASS — Dispatch claims, attempts, safe errors, response loss, interruption, and partial classification are visible and retryable.
- [x] PASS — Provider dispatch is server-only and always uses the immutable send UUID as its idempotency key.
- [x] PASS — Provider batch ID and bounded per-recipient progress/results are persisted and inspectable.
- [x] PASS — Analysts cannot call audience-preview or confirmation RPCs; no client dispatch capability exists.

## Provider reconciliation

- [x] PASS — Provider reports poll incrementally from a persisted opaque cursor and resume safely after downtime.
- [x] PASS — Provider facts deduplicate by tenant/source/event ID, including duplicates within one page.
- [x] PASS — Delivered, bounced, opened, and unsubscribed states converge under duplicate and out-of-order replay.
- [x] PASS — Bounce/unsubscribe/complaint facts update channel contactability with conservative terminal precedence.
- [x] PASS — Event-derived dashboard results query the same reconciled fact table and remain distinct from source reports.

## Public report

- [x] PASS — Owner can publish or rotate exactly one campaign using a 256-bit opaque random token stored only as a digest.
- [x] PASS — Report passwords are bcrypt-hashed at cost 12 and verified only inside a security-definer database function.
- [x] PASS — A one-hour, path-bound HTTP-only report session exposes only the bound campaign summary RPC.
- [x] PASS — Wrong passwords, modified tokens, old sessions, campaign substitution, and tenant/customer pivots fail closed.
- [x] PASS — Report access uses no Supabase Auth identity and cannot become portal access.

## Verification, deployment, and submission

- [x] PASS — Format, lint, typecheck, unit, database, RLS, integration, and E2E checks pass.
- [x] PASS — Fresh local migration/reset and two imports reproduce stable counts.
- [ ] TODO — Secret scan covers working tree, Git history, and browser bundle.
- [ ] TODO — Meaningful commit history pushed to the existing public GitHub repository.
- [ ] TODO — Migrations/functions/data deployed to hosted project `phtafctxyabkvqlcsulz`.
- [ ] TODO — Production app deployed with correct Supabase/Google redirect configuration.
- [ ] TODO — Production smoke and direct restricted-user Supabase isolation tests pass.
- [ ] TODO — `schema.sql`, `README.md`, `SUBMISSION.md`, and private credentials are complete.
- [ ] TODO — Employer-requested note is at most 300 words and answers all four questions.
- [ ] TODO — Final requirement and security audits pass with a clean pushed worktree.
