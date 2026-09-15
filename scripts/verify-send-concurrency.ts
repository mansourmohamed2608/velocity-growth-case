import assert from "node:assert/strict";

import postgres, { type Sql } from "postgres";

const userId = "eeeeeeee-0000-4000-8000-000000000001";
const brandId = "11111111-1111-4111-8111-111111111111";
const contactId = "eeeeeeee-0000-4000-8000-000000000002";
const campaignOne = "eeeeeeee-0000-4000-8000-000000000003";
const campaignTwo = "eeeeeeee-0000-4000-8000-000000000004";
const sharedKey = "eeeeeeee-0000-4000-8000-000000000005";
const differentKeys = [
  "eeeeeeee-0000-4000-8000-000000000006",
  "eeeeeeee-0000-4000-8000-000000000007",
];

async function cleanup(sql: Sql) {
  await sql.begin(async (transaction) => {
    await transaction`delete from public.campaign_send_recipients where send_id in (
      select id from public.campaign_sends where campaign_id in (${campaignOne}, ${campaignTwo})
    )`;
    await transaction`delete from public.campaign_sends where campaign_id in (${campaignOne}, ${campaignTwo})`;
    await transaction`delete from public.campaigns where id in (${campaignOne}, ${campaignTwo})`;
    await transaction`delete from public.contacts where id = ${contactId}`;
    await transaction`delete from public.brand_memberships where user_id = ${userId}`;
    await transaction`delete from auth.users where id = ${userId}`;
  });
}

async function approve(databaseUrl: string, campaignId: string, confirmationKey: string) {
  const connection = postgres(databaseUrl, { max: 1 });
  try {
    return await connection.begin(async (transaction) => {
      await transaction`set local role authenticated`;
      await transaction`select set_config('request.jwt.claim.role', 'authenticated', true)`;
      await transaction`select set_config('request.jwt.claim.sub', ${userId}, true)`;
      const [result] = await transaction<{ send_id: string }[]>`
        select send_id from public.approve_campaign_send(${campaignId}, ${confirmationKey})
      `;
      return result.send_id;
    });
  } finally {
    await connection.end();
  }
}

async function main() {
  const databaseUrl =
    process.env.DATABASE_URL ?? "postgresql://postgres:postgres@127.0.0.1:54322/postgres";
  const sql = postgres(databaseUrl, { max: 1 });
  try {
    await cleanup(sql);
    await sql.begin(async (transaction) => {
      await transaction`insert into auth.users (id, email) values (${userId}, 'concurrency@example.test')`;
      await transaction`insert into public.brand_memberships (brand_id, user_id, role)
        values (${brandId}, ${userId}, 'owner')`;
      await transaction`insert into public.contacts (
        id, brand_id, external_id, full_name, email, country_code, signup_at,
        lifecycle_status, marketing_consent, email_status, sms_status
      ) values (
        ${contactId}, ${brandId}, 'CT-999998', 'Concurrency Contact',
        'concurrency@example.test', 'AQ', now(), 'active', true, 'active', 'unavailable'
      )`;
      await transaction`insert into public.campaigns (
        id, brand_id, external_id, name, channel, target_country_code, sent_at
      ) values
        (${campaignOne}, ${brandId}, 'KIL-CONCURRENCY-1', 'Concurrency One', 'email', 'AQ', now()),
        (${campaignTwo}, ${brandId}, 'KIL-CONCURRENCY-2', 'Concurrency Two', 'email', 'AQ', now())`;
    });

    const sameKeyResults = await Promise.all([
      approve(databaseUrl, campaignOne, sharedKey),
      approve(databaseUrl, campaignOne, sharedKey),
    ]);
    assert.equal(sameKeyResults[0], sameKeyResults[1], "double click must return one logical send");

    const competingResults = await Promise.allSettled([
      approve(databaseUrl, campaignTwo, differentKeys[0]),
      approve(databaseUrl, campaignTwo, differentKeys[1]),
    ]);
    assert.equal(
      competingResults.filter((result) => result.status === "fulfilled").length,
      1,
      "only one competing confirmation may succeed",
    );
    assert.equal(
      competingResults.filter((result) => result.status === "rejected").length,
      1,
      "the competing confirmation must fail visibly",
    );

    const [counts] = await sql<{ sends: number; recipients: number }[]>`
      select
        (select count(*)::integer from public.campaign_sends where campaign_id in (${campaignOne}, ${campaignTwo})) sends,
        (select count(*)::integer from public.campaign_send_recipients where send_id in (
          select id from public.campaign_sends where campaign_id in (${campaignOne}, ${campaignTwo})
        )) recipients
    `;
    assert.deepEqual(counts, { sends: 2, recipients: 2 });
    console.log("Concurrent confirmation verification passed: one send and snapshot per campaign.");
  } finally {
    await cleanup(sql);
    await sql.end();
  }
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : "Concurrency verification failed");
  process.exitCode = 1;
});
