# Architecture and Security Decisions

## D-001 — PostgreSQL is the authorization boundary

**Decision:** Every tenant-owned table carries `brand_id` or reaches it through a constrained parent, has RLS enabled and forced, and uses membership predicates based on `auth.uid()`. Application filters are only a usability aid.

**Why:** Evaluators will call Supabase directly, omit filters, guess UUIDs, and traverse relationships. Authorization must survive every client and future route.

## D-002 — Membership is explicit and non-self-service

**Decision:** `brand_memberships` binds an Auth user to one brand and one role (`owner` or `analyst`). No policy lets a user create or edit their own membership. Google authentication creates an identity, not tenant access.

## D-003 — Source identities are brand-scoped

**Decision:** Natural uniqueness is `(brand_id, source_system, external_id)`, not a globally unique external ID. Cross-brand contact IDs overlap. Imports validate the row's embedded brand before assigning it to a brand.

## D-004 — Raw data is normalized conservatively

**Decision:** The importer supports documented delimiters, encodings, header aliases, boolean spellings, and known timestamp formats. Invalid or cross-brand rows are rejected with persisted reasons. Duplicate natural keys upsert deterministically; conflicts are audited. The Kilele delta is a later authoritative export and overrides matching base records.

## D-005 — Contactability is a derived safety rule

**Decision:** A contact is contactable only when marketing consent is true, the contact is active, not deleted, not currently suppressed, has a valid address for the campaign channel, and no reconciled terminal provider fact blocks that channel. Ambiguity is displayed in the UI.

## D-006 — Approval and dispatch are separate, idempotent phases

**Decision:** A database function creates one logical send and its immutable recipient snapshot under a unique confirmation key. Provider dispatch happens server-side with the logical send UUID as `Idempotency-Key`. Provider acceptance and local progress remain recoverable after response loss.

## D-007 — Events are facts, aggregates are projections

**Decision:** Persist raw provider events uniquely by provider event ID. Recompute monotonic recipient facts from the complete event set rather than trusting arrival order. The provider docs promise ordered exactly-once reports, but the employer will deliberately test duplicates and out-of-order delivery.

## D-008 — Public reports use capability plus limited session

**Decision:** A cryptographically random token locates a report; a password hash gates it. Successful server-side verification creates a separate opaque, expiring report session in an HTTP-only cookie. Public database functions return only the bound campaign summary and never grant anonymous table access.

## D-009 — No real messages in automated validation

**Decision:** Provider requests use an injectable transport in tests. Production dispatch is enabled only after audience and idempotency verification. The employer provider has no documented sandbox.

