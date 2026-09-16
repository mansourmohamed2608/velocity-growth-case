import Link from "next/link";

import { CopyButton } from "@/components/client-actions";
import { SubmitButton } from "@/components/submit-button";
import { requirePortalContext } from "@/lib/portal-context";
import { reportTokenPattern } from "@/lib/public-report";
import { createClient } from "@/lib/supabase/server";

import { publishReport } from "./actions";

export default async function PublishReportPage({
  params,
  searchParams,
}: {
  params: Promise<{ campaignId: string }>;
  searchParams: Promise<{ token?: string }>;
}) {
  const context = await requirePortalContext();
  const { campaignId } = await params;
  if (context.role !== "owner") {
    return (
      <main className="portal-main list-main">
        <section className="permission-panel">
          <p className="eyebrow">Read-only account</p>
          <h1>Owner publication is required.</h1>
          <p>
            Analysts can review campaign results but cannot create or rotate public report access.
          </p>
          <Link className="button button-quiet" href="/portal/campaigns">
            Back to campaigns
          </Link>
        </section>
      </main>
    );
  }

  const supabase = await createClient();
  const [campaignResult, publishedResult, query] = await Promise.all([
    supabase.from("campaigns").select("id,name,external_id").eq("id", campaignId).single(),
    supabase
      .from("published_reports")
      .select("id,created_at,updated_at")
      .eq("campaign_id", campaignId)
      .maybeSingle(),
    searchParams,
  ]);
  if (campaignResult.error || !campaignResult.data)
    throw new Error("Campaign could not be loaded.");
  if (publishedResult.error) throw new Error("Publication status could not be loaded.");

  const token = query.token && reportTokenPattern.test(query.token) ? query.token : null;
  const appUrl = process.env.NEXT_PUBLIC_APP_URL ?? "http://localhost:3000";
  const shareUrl = token ? new URL(`/r/${token}`, appUrl).toString() : null;

  return (
    <main className="portal-main send-main">
      <Link className="back-link" href="/portal/campaigns">
        ← Campaigns
      </Link>
      <section className="page-heading compact-heading">
        <div>
          <p className="eyebrow">Secure public results</p>
          <h1>{campaignResult.data.name}</h1>
        </div>
        <p>
          {campaignResult.data.external_id} · one campaign, one opaque link, one limited session
        </p>
      </section>

      {shareUrl ? (
        <section className="share-success">
          <p className="section-kicker">New report link</p>
          <h2>Copy this link now.</h2>
          <p>
            Relay stores only its SHA-256 digest, so the raw link cannot be recovered after you
            leave this page. Share the password separately.
          </p>
          <div className="share-link-control">
            <input aria-label="Public report URL" readOnly value={shareUrl} />
            <CopyButton value={shareUrl} />
          </div>
          <a
            className="button button-quiet share-open-link"
            href={shareUrl}
            rel="noreferrer"
            target="_blank"
          >
            Open report in new tab
          </a>
        </section>
      ) : null}

      <section className="panel publish-panel">
        <div>
          <p className="section-kicker">
            {publishedResult.data ? "Rotate access" : "Publish results"}
          </p>
          <h2>
            {publishedResult.data
              ? "Create a new link and password"
              : "Protect this campaign report"}
          </h2>
          <p>
            {publishedResult.data
              ? "The prior token and all sessions stop working as soon as you rotate access."
              : "The public page exposes only this campaign’s summary—never contacts, tenant tables, or portal access."}
          </p>
        </div>
        <form action={publishReport} className="publish-form">
          <input name="campaignId" type="hidden" value={campaignId} />
          <label htmlFor="report-password">Report password</label>
          <input
            autoComplete="new-password"
            id="report-password"
            minLength={12}
            name="password"
            required
            type="password"
          />
          <small>12–128 characters. Send it through a different channel than the URL.</small>
          <SubmitButton className="button button-dark" pendingLabel="Securing report…">
            {publishedResult.data ? "Rotate secure report" : "Publish secure report"}
          </SubmitButton>
        </form>
      </section>
    </main>
  );
}
