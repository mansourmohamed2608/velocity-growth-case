# Architecture

## Boundaries

```text
Browser
  | Supabase Auth session (publishable key)
  v
Next.js portal ------------------------------+
  | tenant-scoped Supabase calls             |
  v                                          | HTTP-only report session
Supabase PostgREST / RPC                     v
  | PostgreSQL RLS + membership checks   Public report routes
  v                                          |
PostgreSQL <---- trusted Edge Functions -----+
                    |
                    | server-only API key + stable idempotency key
                    v
             Velocity Dispatcher
```

The browser receives only the Supabase project URL and publishable key. PostgreSQL RLS is always authoritative. Provider and privileged Supabase credentials exist only in trusted server/Edge Function environments.

## Tenant model

`brands` are the tenant roots. `brand_memberships` is the only authorization mapping from `auth.users` to a brand and role. Contacts, campaigns, import records, sends, events, and published reports are brand-bound. Composite foreign keys preserve brand identity across joins so a child cannot point at a parent in another brand.

## Authentication and authorization

Email/password and Google OAuth both terminate at Supabase Auth. A session without one of the six provisioned memberships can authenticate but sees no tenant rows. Read policies require membership; send/publish database functions additionally require `owner`.

## Import flow

The CLI importer parses each known source format, normalizes aliases and safe legacy values, and stages every row through validated database functions. `import_runs` records file hash/status/counts. `import_errors` records file, row, field, raw value, and reason. Brand-scoped source keys make reruns upserts rather than duplicates. The dated Kilele delta has a higher source precedence than the base export.

## Dashboard and lists

Database functions return tenant-scoped aggregates and bounded pages. Contacts never load unbounded into the browser. Query errors remain errors. Signup charts use the latest source-data date as the deterministic window end for historical seed data, and the UI states that definition.

## Send lifecycle

1. A tenant-scoped preview returns the current eligible audience.
2. The owner confirms with a campaign and unique confirmation key.
3. One transaction creates the logical send, immutable approval fields, and frozen recipient rows.
4. A trusted dispatcher claims pending work, posts one provider batch using the send UUID as the provider idempotency key, and records the batch ID/progress.
5. Retries resume the same logical send; they never create a second approval or provider batch.

## Provider events

A trusted reconciler polls `/v1/messages/{batch_id}/events` with the last cursor until `has_more` is false. Raw events are inserted idempotently. Recipient and contact state is projected from all facts using event time plus terminal-state precedence, so duplicates and order do not change the result.

## Public report

Publishing binds one opaque token to one brand and campaign and stores only a password hash. Password verification and report lookup run server-side. The resulting expiring report session can retrieve one purpose-built aggregate only; it cannot read tenant tables or create a portal session.

