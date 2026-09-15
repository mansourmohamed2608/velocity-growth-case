import { getCampaigns } from "@/lib/portal-data";
import { requirePortalContext } from "@/lib/portal-context";

export const metadata = { title: "Campaigns" };

const integer = new Intl.NumberFormat("en", { maximumFractionDigits: 0 });
const money = new Intl.NumberFormat("en", { style: "currency", currency: "USD" });
const date = new Intl.DateTimeFormat("en", {
  day: "numeric",
  month: "short",
  year: "numeric",
  timeZone: "UTC",
});

export default async function CampaignsPage() {
  const [context, campaigns] = await Promise.all([requirePortalContext(), getCampaigns()]);

  return (
    <main className="portal-main list-main">
      <section className="page-heading compact-heading">
        <div>
          <p className="eyebrow">Campaign archive</p>
          <h1>Campaigns</h1>
        </div>
        <p>Imported history, event-derived outcomes, and role-aware delivery controls.</p>
      </section>

      <section className="panel list-panel">
        <div className="list-toolbar">
          <div>
            <p className="section-kicker">History and results</p>
            <h2>{integer.format(campaigns.length)} campaigns</h2>
          </div>
          <span className="role-note">
            {context.role === "owner"
              ? "Owner · sending requires an exact audience preview"
              : "Analyst · read-only access"}
          </span>
        </div>

        {campaigns.length ? (
          <div className="table-scroll">
            <table className="campaigns-table">
              <thead>
                <tr>
                  <th>Campaign</th>
                  <th>Sent</th>
                  <th>Reported</th>
                  <th>Event-derived customers</th>
                  <th>Spend</th>
                  <th>Action</th>
                </tr>
              </thead>
              <tbody>
                {campaigns.map((campaign) => (
                  <tr key={campaign.id}>
                    <td>
                      <strong>{campaign.name}</strong>
                      <span>
                        {campaign.external_id} · {campaign.channel}
                      </span>
                    </td>
                    <td>{date.format(new Date(campaign.sent_at))}</td>
                    <td className="stacked-metrics">
                      <span>{integer.format(campaign.reported_sent)} sent</span>
                      <span>{integer.format(campaign.reported_delivered)} delivered</span>
                      <span>{integer.format(campaign.reported_opens)} opens</span>
                    </td>
                    <td className="stacked-metrics">
                      <span>{integer.format(campaign.event_delivered)} delivered</span>
                      <span>{integer.format(campaign.event_opened)} opened</span>
                      <span>{integer.format(campaign.event_bounced)} bounced</span>
                    </td>
                    <td>{money.format(Number(campaign.spend))}</td>
                    <td>
                      {campaign.send_status ? (
                        <span className={`status-label status-${campaign.send_status}`}>
                          {campaign.send_status}
                        </span>
                      ) : context.role === "owner" ? (
                        <button
                          className="button button-dark"
                          disabled
                          title="Audience approval is added in the safe-send phase"
                          type="button"
                        >
                          Prepare send
                        </button>
                      ) : (
                        <span className="read-only-label">Read only</span>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <p className="empty-state">No campaigns have been imported for this brand.</p>
        )}
        <p className="definition">
          Export-reported totals are preserved exactly, including known inconsistencies.
          Event-derived figures count unique customers from valid deduplicated facts. Sending
          remains unavailable until the owner reviews and confirms a frozen eligible audience.
        </p>
      </section>
    </main>
  );
}
