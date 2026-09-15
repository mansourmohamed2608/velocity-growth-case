


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
    CONSTRAINT "contacts_check" CHECK ((("email" IS NOT NULL) OR ("phone" IS NOT NULL))),
    CONSTRAINT "contacts_check1" CHECK ((("deleted_at" IS NULL) OR ("deleted_at" >= "signup_at"))),
    CONSTRAINT "contacts_country_code_check" CHECK ((("country_code" IS NULL) OR ("country_code" ~ '^[A-Z]{2}$'::"text"))),
    CONSTRAINT "contacts_email_check" CHECK ((("email" IS NULL) OR (("email" = "lower"("email")) AND ("email" ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'::"text")))),
    CONSTRAINT "contacts_external_id_check" CHECK (("external_id" ~ '^CT-[0-9]{6}$'::"text")),
    CONSTRAINT "contacts_full_name_check" CHECK (("btrim"("full_name") <> ''::"text")),
    CONSTRAINT "contacts_phone_check" CHECK ((("phone" IS NULL) OR ("btrim"("phone") <> ''::"text")))
);


ALTER TABLE "public"."contacts" OWNER TO "postgres";


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



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



GRANT ALL ON FUNCTION "public"."protect_recipient_snapshot"() TO "anon";
GRANT ALL ON FUNCTION "public"."protect_recipient_snapshot"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."protect_recipient_snapshot"() TO "service_role";



GRANT ALL ON FUNCTION "public"."protect_send_approval"() TO "anon";
GRANT ALL ON FUNCTION "public"."protect_send_approval"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."protect_send_approval"() TO "service_role";



GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "service_role";



GRANT ALL ON TABLE "public"."brand_memberships" TO "anon";
GRANT ALL ON TABLE "public"."brand_memberships" TO "authenticated";
GRANT ALL ON TABLE "public"."brand_memberships" TO "service_role";



GRANT ALL ON TABLE "public"."brands" TO "anon";
GRANT ALL ON TABLE "public"."brands" TO "authenticated";
GRANT ALL ON TABLE "public"."brands" TO "service_role";



GRANT ALL ON TABLE "public"."campaign_send_recipients" TO "anon";
GRANT ALL ON TABLE "public"."campaign_send_recipients" TO "authenticated";
GRANT ALL ON TABLE "public"."campaign_send_recipients" TO "service_role";



GRANT ALL ON TABLE "public"."campaign_sends" TO "anon";
GRANT ALL ON TABLE "public"."campaign_sends" TO "authenticated";
GRANT ALL ON TABLE "public"."campaign_sends" TO "service_role";



GRANT ALL ON TABLE "public"."campaigns" TO "anon";
GRANT ALL ON TABLE "public"."campaigns" TO "authenticated";
GRANT ALL ON TABLE "public"."campaigns" TO "service_role";



GRANT ALL ON TABLE "public"."contacts" TO "anon";
GRANT ALL ON TABLE "public"."contacts" TO "authenticated";
GRANT ALL ON TABLE "public"."contacts" TO "service_role";



GRANT ALL ON TABLE "public"."import_errors" TO "anon";
GRANT ALL ON TABLE "public"."import_errors" TO "authenticated";
GRANT ALL ON TABLE "public"."import_errors" TO "service_role";



GRANT ALL ON SEQUENCE "public"."import_errors_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."import_errors_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."import_errors_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."import_runs" TO "anon";
GRANT ALL ON TABLE "public"."import_runs" TO "authenticated";
GRANT ALL ON TABLE "public"."import_runs" TO "service_role";



GRANT ALL ON TABLE "public"."provider_events" TO "anon";
GRANT ALL ON TABLE "public"."provider_events" TO "authenticated";
GRANT ALL ON TABLE "public"."provider_events" TO "service_role";



GRANT ALL ON SEQUENCE "public"."provider_events_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."provider_events_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."provider_events_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."published_reports" TO "anon";
GRANT ALL ON TABLE "public"."published_reports" TO "authenticated";
GRANT ALL ON TABLE "public"."published_reports" TO "service_role";



GRANT ALL ON TABLE "public"."report_sessions" TO "anon";
GRANT ALL ON TABLE "public"."report_sessions" TO "authenticated";
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







