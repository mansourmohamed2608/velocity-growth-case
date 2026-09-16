# Relay — Velocity Growth client portal

Relay is a production client campaign portal for Kilele Rides, Karoo Coaches, and Marrakech Express. It imports the supplied growth data, keeps every brand isolated in PostgreSQL, supports owner/analyst roles, shows bounded campaign and contact analytics, prepares idempotent provider sends, reconciles provider events, and publishes password-protected single-campaign reports.

- Live app: <https://velocity-growth-case.vercel.app>
- Public repository: <https://github.com/mansourmohamed2608/velocity-growth-case>
- Hosted Supabase project: `phtafctxyabkvqlcsulz` (Frankfurt)

## Architecture and stack

The browser uses only Supabase Auth and a publishable key. Next.js App Router server actions handle OAuth callbacks, provider dispatch/reconciliation, and report publication. PostgreSQL is the authorization boundary: forced RLS checks `auth.uid()` against `brand_memberships`, while composite foreign keys keep related objects in one brand. No service-role or provider credential is shipped to the browser.

Stack: Next.js 16, React 19, TypeScript, Supabase PostgreSQL/Auth/PostgREST, PostgreSQL RLS and pgTAP, Vercel, Vitest, and Playwright. See [ARCHITECTURE.md](./ARCHITECTURE.md), [DECISIONS.md](./DECISIONS.md), and [DATA_NOTES.md](./DATA_NOTES.md) for the detailed design and source-data findings.

## Local setup

Requirements: Node.js 20.9+, Docker Desktop, and the Supabase CLI.

```bash
npm ci
cp .env.example .env.local
npm run db:start
npm run db:reset
```

Set these names in `.env.local`; never commit their values:

```text
NEXT_PUBLIC_SUPABASE_URL
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY
NEXT_PUBLIC_APP_URL
MESSAGING_PROVIDER_BASE_URL
MESSAGING_PROVIDER_API_KEY
```

Extract the employer archive into ignored `.work/seed`, verify its documented SHA-256, then load and verify it:

```bash
npm run data:import
npm run data:verify
npm run dev
```

`SOURCE_FILES=file-a.csv,file-b.csv` optionally limits an import run. Every source file is atomic and rerunnable. Private portal credentials are generated into ignored files with `npm run credentials:generate`; `npm run users:provision` requires server-side Supabase admin URL, service-role key, and publishable key environment variables.

## Database and tenancy

Migrations in `supabase/migrations` are authoritative; [supabase/schema.sql](./supabase/schema.sql) is the inspection snapshot. Apply locally with `npm run db:reset`, or to the already-linked hosted project with `npx supabase db push --linked` after testing.

`brand_memberships` is the only user-to-tenant mapping. Authenticated users can read only their brand; analysts have no mutation RPC grants; owners may approve sends and publish reports. An authenticated user without a membership receives no portal context and no tenant rows. The regression suite covers omitted filters, guessed UUIDs, joins, RPCs, analyst writes, and unknown users.

## Data and metrics

The importer validates formats and brand identity, rejects malformed rows, and persists row-level reasons in `import_errors`; `import_runs` exposes counts and failures to marketers. Natural keys are brand-scoped, and the Kilele delta has higher source precedence.

- Total customers: valid, deduplicated contacts after delta precedence.
- Contactable now: active, consented, non-deleted, non-suppressed contacts with an active address on at least one channel, adjusted by terminal provider facts.
- Daily signups: 30 calendar days ending at that tenant's latest valid source signup date.
- Reported campaign metrics: preserved from the campaign export, including its known inconsistencies.
- Event metrics: unique contacts per validated, deduplicated event type. They are never substituted for reported values.

Contacts are database-paginated. Campaign event totals use a tenant-keyed covering index and an index-only unique-contact aggregation so the largest tenant remains within hosted query limits.

## Sending and reconciliation

The owner first sees the exact eligible channel/country audience. Approval runs under a per-campaign advisory lock and stores one immutable recipient snapshot plus approver and timestamp. The send UUID is also the provider `Idempotency-Key`; retries reclaim the same logical send. Provider acceptance/rejection and per-recipient state live in `campaign_sends` and `campaign_send_recipients`.

Reconciliation polls one bounded page from the documented cursor endpoint per owner refresh and resumes from the persisted opaque cursor. Raw facts deduplicate by provider event ID, and projections use event time plus conservative terminal precedence so duplicate, late, replayed, or reversed events converge. Bounce, unsubscribe, and complaint facts update channel contactability. Provider events that do not belong to the frozen audience remain unbound and are counted visibly instead of blocking valid facts on the same page.

## Public reports

Owners publish one explicitly bound campaign using a random 256-bit token. Only its SHA-256 digest is stored. Passwords use bcrypt cost 12 inside PostgreSQL. Successful verification creates a separate one-hour, path-bound HTTP-only report session; anonymous users receive only one purpose-built aggregate RPC and no tenant-table grants.

## Verification

```bash
npm run format
npm run lint
npm run typecheck
npm test
npm run db:test
npm run test:concurrency
npm run build
npm run e2e
npm audit --audit-level=high
```

The completed checks include 14 unit tests, 79 database/RLS assertions, concurrent two-session approval verification, clean migration replay, two stable full imports, six-account role checks, and desktop/390px browser coverage locally and in production. The production suite also verifies that the completed approved send is inspectable and has no second-dispatch control.

## Deployment

Hosted migrations and seed data are deployed to Supabase project `phtafctxyabkvqlcsulz`. Vercel production holds the three public values and the two server-only provider values. Supabase Auth's Site URL and callback allow-list point at the stable Vercel domain; Google uses the existing hosted provider.

## Known limitations

- The provider documents no sandbox. Automated tests use an injected transport and never make a real send. One explicitly approved production SMS dispatch was completed for MAR-0002; its immutable attempt, acceptance, reconciliation, and skipped-noise counts remain inspectable by the owner.
- Provider report requests can return transient availability errors. Reconciliation is cursor-based, bounded to one page per web request, retryable, and preserves already-ingested facts.
- Google OAuth initiation, callback configuration, consent, and the permitted Kilele owner login have been verified in production.
- The source campaign exports intentionally contain inconsistent reported totals; the UI labels them separately from event-derived facts.

## AI tooling disclosure

OpenAI Codex was used for repository analysis, implementation, test generation, debugging, documentation, and deployment orchestration. Architectural and security decisions were validated against the employer brief, actual source data, provider documentation, executable tests, and production behavior.
