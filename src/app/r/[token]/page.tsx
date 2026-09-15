import { cookies } from "next/headers";

import { SubmitButton } from "@/components/submit-button";
import {
  createPublicClient,
  digestForPostgres,
  type PublicCampaignReport,
  reportCookieName,
  reportTokenPattern,
} from "@/lib/public-report";

import { unlockReport } from "./actions";

const integer = new Intl.NumberFormat("en", { maximumFractionDigits: 0 });
const date = new Intl.DateTimeFormat("en", { dateStyle: "long", timeZone: "UTC" });

export default async function PublicReportPage({
  params,
  searchParams,
}: {
  params: Promise<{ token: string }>;
  searchParams: Promise<{ error?: string }>;
}) {
  const { token } = await params;
  const query = await searchParams;
  const validToken = reportTokenPattern.test(token);
  const cookieStore = await cookies();
  const sessionToken = validToken ? cookieStore.get(reportCookieName(token))?.value : null;
  let report: PublicCampaignReport | null = null;

  if (sessionToken) {
    const result = await createPublicClient()
      .rpc("public_campaign_report", { target_session_digest: digestForPostgres(sessionToken) })
      .maybeSingle();
    if (result.error) throw new Error("The campaign report could not be loaded.");
    report = result.data as PublicCampaignReport | null;
  }

  if (!report) {
    return (
      <main className="report-lock-shell">
        <section className="report-lock-card">
          <span className="wordmark-mark" aria-hidden="true">
            R
          </span>
          <p className="eyebrow">Protected campaign results</p>
          <h1>Enter the report password.</h1>
          <p>
            The link and password are both required. This access does not sign you into the client
            portal.
          </p>
          {query.error ? <div className="form-alert">The link or password is invalid.</div> : null}
          <form action={unlockReport} className="publish-form">
            <input name="token" type="hidden" value={token} />
            <label htmlFor="public-report-password">Password</label>
            <input
              autoComplete="current-password"
              id="public-report-password"
              name="password"
              required
              type="password"
            />
            <SubmitButton className="button button-dark" pendingLabel="Checking access…">
              View campaign results
            </SubmitButton>
          </form>
        </section>
      </main>
    );
  }

  return (
    <main className="public-report-shell">
      <header className="public-report-header">
        <div className="wordmark">
          <span className="wordmark-mark" aria-hidden="true">
            R
          </span>
          <span>Relay results</span>
        </div>
        <span>Limited campaign view</span>
      </header>
      <section className="public-report-hero">
        <p className="eyebrow">{report.brand_name}</p>
        <h1>{report.campaign_name}</h1>
        <p>
          {report.campaign_external_id} · {report.channel} · sent{" "}
          {date.format(new Date(report.sent_at))}
        </p>
      </section>
      <section className="report-metric-grid" aria-label="Campaign results">
        <article>
          <span>Reported sent</span>
          <strong>{integer.format(report.reported_sent)}</strong>
        </article>
        <article>
          <span>Event delivered</span>
          <strong>{integer.format(report.event_delivered)}</strong>
        </article>
        <article>
          <span>Unique opens</span>
          <strong>{integer.format(report.event_opened)}</strong>
        </article>
        <article>
          <span>Bounces</span>
          <strong>{integer.format(report.event_bounced)}</strong>
        </article>
      </section>
      <section className="report-detail-grid">
        <div>
          <span>Reported delivered</span>
          <strong>{integer.format(report.reported_delivered)}</strong>
        </div>
        <div>
          <span>Reported opens</span>
          <strong>{integer.format(report.reported_opens)}</strong>
        </div>
        <div>
          <span>Reported clicks</span>
          <strong>{integer.format(report.reported_clicks)}</strong>
        </div>
        <div>
          <span>Event clicks</span>
          <strong>{integer.format(report.event_clicked)}</strong>
        </div>
        <div>
          <span>Unsubscribed</span>
          <strong>{integer.format(report.event_unsubscribed)}</strong>
        </div>
        <div>
          <span>Complaints</span>
          <strong>{integer.format(report.event_complained)}</strong>
        </div>
      </section>
      <p className="report-definition">
        Reported values come from the campaign export. Event values count unique customers from
        validated, deduplicated delivery facts. This page is bound to this campaign only.
      </p>
    </main>
  );
}
