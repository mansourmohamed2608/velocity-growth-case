import assert from "node:assert/strict";

import postgres from "postgres";

const expected = {
  KAROO: { contacts: 12_406, campaigns: 19, events: 69_100, sends: 0 },
  KILELE: { contacts: 79_778, campaigns: 44, events: 294_736, sends: 7 },
  MARRAKECH: { contacts: 918, campaigns: 6, events: 307, sends: 0 },
};

async function main() {
  const databaseUrl =
    process.env.DATABASE_URL ?? "postgresql://postgres:postgres@127.0.0.1:54322/postgres";
  const sql = postgres(databaseUrl);
  try {
    const totals = await sql<
      {
        code: keyof typeof expected;
        contacts: number;
        campaigns: number;
        events: number;
        sends: number;
      }[]
    >`
      select brand.code,
        (select count(*)::integer from public.contacts where brand_id = brand.id) contacts,
        (select count(*)::integer from public.campaigns where brand_id = brand.id) campaigns,
        (select count(*)::integer from public.provider_events where brand_id = brand.id) events,
        (select count(*)::integer from public.campaign_sends where brand_id = brand.id) sends
      from public.brands brand
      order by brand.code
    `;
    assert.equal(totals.length, 3, "all three brands must exist");
    for (const total of totals)
      assert.deepEqual(
        {
          contacts: total.contacts,
          campaigns: total.campaigns,
          events: total.events,
          sends: total.sends,
        },
        expected[total.code],
        `${total.code} logical totals changed`,
      );

    const [duplicates] = await sql<
      {
        contact_duplicate_keys: number;
        campaign_duplicate_keys: number;
        event_duplicate_keys: number;
      }[]
    >`
      select
        (select count(*)::integer from (select brand_id, external_id from public.contacts group by 1, 2 having count(*) > 1) duplicate) contact_duplicate_keys,
        (select count(*)::integer from (select brand_id, external_id from public.campaigns group by 1, 2 having count(*) > 1) duplicate) campaign_duplicate_keys,
        (select count(*)::integer from (select brand_id, source, provider_event_id from public.provider_events group by 1, 2, 3 having count(*) > 1) duplicate) event_duplicate_keys
    `;
    assert.deepEqual(duplicates, {
      contact_duplicate_keys: 0,
      campaign_duplicate_keys: 0,
      event_duplicate_keys: 0,
    });

    const [audit] = await sql<{ running: number; latest_files: number }[]>`
      select count(*) filter (where status = 'running')::integer running,
        count(distinct source_filename) filter (where status in ('completed', 'completed_with_errors'))::integer latest_files
      from public.import_runs
    `;
    assert.equal(audit.running, 0, "no import run may remain running");
    assert.equal(audit.latest_files, 11, "every source file needs a completed audit run");

    const [delta] = await sql<{ source_precedence: number; email: string }[]>`
      select source_precedence, email from public.contacts
      where brand_id = '11111111-1111-4111-8111-111111111111' and external_id = 'CT-070368'
    `;
    assert.deepEqual(delta, { source_precedence: 10, email: "brian.zahra.delta2170@vg-eval.test" });
    console.log(
      "Import verification passed: counts, uniqueness, audit completion, and delta precedence are stable.",
    );
  } finally {
    await sql.end();
  }
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : "Import verification failed");
  process.exitCode = 1;
});
