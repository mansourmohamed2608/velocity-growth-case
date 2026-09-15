import Link from "next/link";

import { getDashboardData } from "@/lib/portal-data";
import { requirePortalContext } from "@/lib/portal-context";

export const metadata = { title: "Dashboard" };

const integer = new Intl.NumberFormat("en", { maximumFractionDigits: 0 });
const compact = new Intl.NumberFormat("en", { notation: "compact", maximumFractionDigits: 1 });
const shortDate = new Intl.DateTimeFormat("en", {
  day: "numeric",
  month: "short",
  timeZone: "UTC",
});

function SignupChart({
  points,
}: {
  points: Awaited<ReturnType<typeof getDashboardData>>["signups"];
}) {
  if (!points.length) return <p className="empty-state">No signup history is available yet.</p>;
  const maximum = Math.max(...points.map((point) => point.signup_count), 1);

  return (
    <figure className="signup-figure">
      <div
        aria-label="Daily customer signups over the latest 30-day data window"
        className="signup-chart"
        role="img"
      >
        {points.map((point) => (
          <div
            className="signup-bar"
            key={point.signup_date}
            style={{ height: `${Math.max((point.signup_count / maximum) * 100, 2)}%` }}
            title={`${point.signup_date}: ${integer.format(point.signup_count)} signups`}
          />
        ))}
      </div>
      <figcaption>
        <span>{shortDate.format(new Date(`${points[0].signup_date}T00:00:00Z`))}</span>
        <strong>Peak {integer.format(maximum)}</strong>
        <span>{shortDate.format(new Date(`${points.at(-1)!.signup_date}T00:00:00Z`))}</span>
      </figcaption>
    </figure>
  );
}

export default async function PortalPage() {
  const [context, data] = await Promise.all([requirePortalContext(), getDashboardData()]);
  const contactableRate = data.summary.total_customers
    ? Math.round((data.summary.contactable_customers / data.summary.total_customers) * 100)
    : 0;

  return (
    <main className="portal-main dashboard-main">
      <section className="page-heading">
        <div>
          <p className="eyebrow">{context.brandCode} workspace</p>
          <h1>Growth at a glance.</h1>
        </div>
        <p>
          A tenant-safe view of customer reach, recent acquisition, campaign outcomes, and source
          data health.
        </p>
      </section>

      <section aria-label="Customer overview" className="metric-grid">
        <article className="metric-card metric-card-primary">
          <span>Total customers</span>
          <strong>{integer.format(data.summary.total_customers)}</strong>
          <p>Valid, deduplicated contact records</p>
        </article>
        <article className="metric-card">
          <span>Contactable now</span>
          <strong>{integer.format(data.summary.contactable_customers)}</strong>
          <p>{contactableRate}% of the customer base</p>
        </article>
        <article className="metric-card">
          <span>Latest data date</span>
          <strong className="metric-date">
            {data.summary.latest_signup_date
              ? shortDate.format(new Date(`${data.summary.latest_signup_date}T00:00:00Z`))
              : "No data"}
          </strong>
          <p>The chart anchors to source data, not today</p>
        </article>
      </section>

      <section className="dashboard-grid">
        <article className="panel chart-panel">
          <div className="panel-heading">
            <div>
              <p className="section-kicker">Customer acquisition</p>
              <h2>Daily signups</h2>
            </div>
            <span className="soft-pill">30 data days</span>
          </div>
          <SignupChart points={data.signups} />
          <p className="definition">
            Window: the 30 calendar days ending on the newest valid signup date in this tenant’s
            imported data. Days with no signups remain visible as zero.
          </p>
        </article>

        <article className="panel health-panel">
          <div className="panel-heading">
            <div>
              <p className="section-kicker">Source health</p>
              <h2>Recent imports</h2>
            </div>
          </div>
          {data.runs.length ? (
            <ul className="health-list">
              {data.runs.map((run) => (
                <li key={run.id}>
                  <div>
                    <strong>{run.source_filename}</strong>
                    <span>
                      {integer.format(run.accepted_rows)} accepted ·{" "}
                      {integer.format(run.rejected_rows)} rejected
                    </span>
                  </div>
                  <span className={`status-label status-${run.status}`}>
                    {run.status.replaceAll("_", " ")}
                  </span>
                </li>
              ))}
            </ul>
          ) : (
            <p className="empty-state">No imports have run for this brand.</p>
          )}
          {data.issues.length ? (
            <details className="issue-details">
              <summary>Review latest validation issues</summary>
              <ul>
                {data.issues.map((issue) => (
                  <li key={issue.id}>
                    <strong>Row {integer.format(issue.row_number)}</strong>
                    <span>{issue.reason}</span>
                  </li>
                ))}
              </ul>
            </details>
          ) : null}
        </article>
      </section>

      <section className="panel campaign-panel">
        <div className="panel-heading">
          <div>
            <p className="section-kicker">Campaign performance</p>
            <h2>Latest campaigns</h2>
          </div>
          <Link className="text-link" href="/portal/campaigns">
            View all campaigns →
          </Link>
        </div>
        {data.campaigns.length ? (
          <div className="table-scroll">
            <table>
              <thead>
                <tr>
                  <th>Campaign</th>
                  <th>Channel</th>
                  <th>Reported sent</th>
                  <th>Event delivered</th>
                  <th>Unique opens</th>
                  <th>Bounces</th>
                </tr>
              </thead>
              <tbody>
                {data.campaigns.map((campaign) => (
                  <tr key={campaign.id}>
                    <td>
                      <strong>{campaign.name}</strong>
                      <span>{campaign.external_id}</span>
                    </td>
                    <td>
                      <span className="channel-pill">{campaign.channel}</span>
                    </td>
                    <td>{compact.format(campaign.reported_sent)}</td>
                    <td>{compact.format(campaign.event_delivered)}</td>
                    <td>{compact.format(campaign.event_opened)}</td>
                    <td>{compact.format(campaign.event_bounced)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <p className="empty-state">No campaigns have been imported for this brand.</p>
        )}
        <p className="definition">
          “Reported” metrics are preserved from campaign exports and may be internally inconsistent.
          “Event” metrics count unique customers in valid, deduplicated event facts. They are shown
          separately and never silently substituted for each other.
        </p>
      </section>
    </main>
  );
}
