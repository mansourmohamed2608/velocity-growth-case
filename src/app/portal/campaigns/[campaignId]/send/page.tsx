import { randomUUID } from "node:crypto";

import Link from "next/link";
import { redirect } from "next/navigation";

import { SubmitButton } from "@/components/submit-button";
import { getSendPreparation, type FrozenRecipient, type SendAudienceRow } from "@/lib/portal-data";
import { requirePortalContext } from "@/lib/portal-context";

import { approveSend, dispatchSend, reconcileSend } from "./actions";

const integer = new Intl.NumberFormat("en", { maximumFractionDigits: 0 });

function pageHref(campaignId: string, page: number) {
  return `/portal/campaigns/${campaignId}/send${page > 1 ? `?page=${page}` : ""}`;
}

function isFrozenRecipient(
  recipient: FrozenRecipient | SendAudienceRow,
): recipient is FrozenRecipient {
  return "approved_snapshot" in recipient;
}

export default async function SendPage({
  params,
  searchParams,
}: {
  params: Promise<{ campaignId: string }>;
  searchParams: Promise<{ page?: string }>;
}) {
  const context = await requirePortalContext();
  if (context.role !== "owner") {
    return (
      <main className="portal-main list-main">
        <section className="permission-panel">
          <p className="eyebrow">Read-only account</p>
          <h1>Owner approval is required.</h1>
          <p>
            Analysts can inspect campaign results, but cannot preview recipients or approve
            delivery.
          </p>
          <Link className="button button-quiet" href="/portal/campaigns">
            Back to campaigns
          </Link>
        </section>
      </main>
    );
  }

  const { campaignId } = await params;
  const query = await searchParams;
  const requestedPage = Number.parseInt(query.page ?? "1", 10);
  const page = Number.isSafeInteger(requestedPage) && requestedPage > 0 ? requestedPage : 1;
  const data = await getSendPreparation(campaignId, page);
  const pageCount = Math.max(1, Math.ceil(data.total / data.pageSize));
  if (page > pageCount) redirect(pageHref(campaignId, pageCount));

  return (
    <main className="portal-main send-main">
      <Link className="back-link" href="/portal/campaigns">
        ← Campaigns
      </Link>
      <section className="page-heading compact-heading send-heading">
        <div>
          <p className="eyebrow">{data.send ? "Approved send" : "Audience approval"}</p>
          <h1>{data.campaign.name}</h1>
        </div>
        <p>
          {data.campaign.external_id} · {data.campaign.channel} ·{" "}
          {data.campaign.target_country_code ?? "All countries"}
        </p>
      </section>

      {data.send ? (
        <>
          <section aria-label="Send progress" className="metric-grid send-metrics">
            <article className="metric-card metric-card-primary">
              <span>Frozen recipients</span>
              <strong>{integer.format(data.send.recipient_count)}</strong>
              <p>Immutable at approval</p>
            </article>
            <article className="metric-card">
              <span>Send state</span>
              <strong className="metric-date">{data.send.status}</strong>
              <p>
                {data.send.provider_batch_id
                  ? `Batch ${data.send.provider_batch_id}`
                  : "Awaiting provider dispatch"}
              </p>
            </article>
            <article className="metric-card">
              <span>Provider accepted</span>
              <strong>{integer.format(data.send.accepted_count)}</strong>
              <p>
                {integer.format(data.send.rejected_count)} rejected ·{" "}
                {integer.format(data.send.delivered_count)} delivered
              </p>
            </article>
          </section>
          {data.send.source === "portal" &&
          ["approved", "dispatching", "failed"].includes(data.send.status) ? (
            <section className="dispatch-callout">
              <div>
                <p className="section-kicker">Irreversible provider action</p>
                <h2>
                  {data.send.status === "approved" ? "Ready to dispatch" : "Recover this dispatch"}
                </h2>
                <p>
                  This sends <strong>{integer.format(data.send.recipient_count)}</strong>{" "}
                  {data.campaign.channel} messages for <strong>{data.campaign.name}</strong>. The
                  frozen send ID is reused on every retry, so provider acceptance or a lost response
                  cannot create a second delivery.
                </p>
                {data.send.last_error ? (
                  <p className="dispatch-error">{data.send.last_error}</p>
                ) : null}
              </div>
              <form action={dispatchSend}>
                <input name="campaignId" type="hidden" value={data.campaign.id} />
                <input name="sendId" type="hidden" value={data.send.id} />
                <SubmitButton className="button button-primary" pendingLabel="Dispatching safely…">
                  {data.send.status === "approved"
                    ? "Dispatch approved audience"
                    : "Retry same provider batch"}
                </SubmitButton>
              </form>
            </section>
          ) : null}
          {data.send.provider_batch_id ? (
            <section className="reconcile-strip">
              <div>
                <strong>Delivery results</strong>
                <span>
                  {integer.format(data.send.delivered_count)} delivered ·{" "}
                  {integer.format(data.send.opened_count)} opened ·{" "}
                  {integer.format(data.send.bounced_count)} bounced ·{" "}
                  {integer.format(data.send.unsubscribed_count)} unsubscribed
                </span>
              </div>
              <form action={reconcileSend}>
                <input name="campaignId" type="hidden" value={data.campaign.id} />
                <input name="sendId" type="hidden" value={data.send.id} />
                <SubmitButton className="button button-quiet" pendingLabel="Refreshing results…">
                  Refresh provider results
                </SubmitButton>
              </form>
            </section>
          ) : null}
        </>
      ) : (
        <section className="approval-callout">
          <div>
            <p className="section-kicker">Exact eligible audience</p>
            <strong>{integer.format(data.total)}</strong>
            <span>{data.campaign.channel} recipients</span>
          </div>
          <form action={approveSend}>
            <input name="campaignId" type="hidden" value={data.campaign.id} />
            <input name="confirmationKey" type="hidden" value={randomUUID()} />
            <p>
              Approval freezes the exact recipients and destinations shown by these rules. It does
              not contact the provider yet; dispatch is a separate recoverable step.
            </p>
            <SubmitButton
              className="button button-primary"
              disabled={data.total === 0}
              pendingLabel="Freezing audience…"
            >
              Approve {integer.format(data.total)} recipients
            </SubmitButton>
          </form>
        </section>
      )}

      <section className="panel list-panel recipient-panel">
        <div className="list-toolbar">
          <div>
            <p className="section-kicker">{data.send ? "Immutable snapshot" : "Current preview"}</p>
            <h2>{data.send ? "Approved recipients" : "Eligible recipients"}</h2>
          </div>
          <span className="soft-pill">{integer.format(data.total)} exact records</span>
        </div>
        {data.recipients.length ? (
          <div
            aria-label="Campaign recipient table"
            className="table-scroll"
            role="region"
            tabIndex={0}
          >
            <table>
              <thead>
                <tr>
                  <th>Customer</th>
                  <th>Destination</th>
                  <th>Country</th>
                  <th>State</th>
                </tr>
              </thead>
              <tbody>
                {data.recipients.map((recipient) => {
                  const frozen = isFrozenRecipient(recipient);
                  return (
                    <tr key={frozen ? recipient.id : recipient.contact_id}>
                      <td>
                        <strong>
                          {frozen
                            ? (recipient.approved_snapshot.full_name ?? "Customer")
                            : recipient.full_name}
                        </strong>
                        <span>
                          {frozen ? recipient.contact_external_id : recipient.external_id}
                        </span>
                      </td>
                      <td>{recipient.destination}</td>
                      <td>
                        {frozen
                          ? (recipient.approved_snapshot.country_code ?? "—")
                          : (recipient.country_code ?? "—")}
                      </td>
                      <td>
                        <span
                          className={`status-label status-${frozen ? recipient.status : "completed"}`}
                        >
                          {frozen ? recipient.status : "eligible"}
                        </span>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        ) : (
          <p className="empty-state">
            No eligible recipients match this campaign’s channel and country.
          </p>
        )}
        <nav aria-label="Recipient pages" className="pagination">
          {page > 1 ? (
            <Link className="button button-quiet" href={pageHref(campaignId, page - 1)}>
              ← Previous
            </Link>
          ) : (
            <span />
          )}
          <span>
            Page {page} of {pageCount}
          </span>
          {page < pageCount ? (
            <Link className="button button-quiet" href={pageHref(campaignId, page + 1)}>
              Next →
            </Link>
          ) : (
            <span />
          )}
        </nav>
      </section>

      <p className="definition standalone-definition">
        Eligibility is evaluated for this campaign’s channel and target country: active lifecycle,
        explicit marketing consent, no deletion or current suppression, and an active destination.
        Confirmation re-evaluates these rules inside the same transaction that creates the immutable
        snapshot.
      </p>
    </main>
  );
}
