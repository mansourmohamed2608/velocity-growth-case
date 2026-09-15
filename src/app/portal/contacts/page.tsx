import Link from "next/link";
import { redirect } from "next/navigation";

import { getContactsPage } from "@/lib/portal-data";

export const metadata = { title: "Contacts" };

const integer = new Intl.NumberFormat("en", { maximumFractionDigits: 0 });
const date = new Intl.DateTimeFormat("en", {
  day: "numeric",
  month: "short",
  year: "numeric",
  timeZone: "UTC",
});

function pageHref(page: number, search: string) {
  const params = new URLSearchParams();
  if (search) params.set("q", search);
  if (page > 1) params.set("page", String(page));
  const query = params.toString();
  return `/portal/contacts${query ? `?${query}` : ""}`;
}

export default async function ContactsPage({
  searchParams,
}: {
  searchParams: Promise<{ page?: string; q?: string }>;
}) {
  const params = await searchParams;
  const search = (params.q ?? "").trim().slice(0, 120);
  const requestedPage = Number.parseInt(params.page ?? "1", 10);
  const page = Number.isSafeInteger(requestedPage) && requestedPage > 0 ? requestedPage : 1;
  const { rows, total, pageSize } = await getContactsPage(search, page);
  const pageCount = Math.max(1, Math.ceil(total / pageSize));
  if (page > pageCount) redirect(pageHref(pageCount, search));

  return (
    <main className="portal-main list-main">
      <section className="page-heading compact-heading">
        <div>
          <p className="eyebrow">Customer directory</p>
          <h1>Contacts</h1>
        </div>
        <p>Server-paginated records with current consent and channel contactability.</p>
      </section>

      <section className="panel list-panel">
        <div className="list-toolbar">
          <form action="/portal/contacts" className="search-form" role="search">
            <label className="sr-only" htmlFor="contact-search">
              Search contacts
            </label>
            <input
              defaultValue={search}
              id="contact-search"
              maxLength={120}
              name="q"
              placeholder="Search name, ID, or email"
              type="search"
            />
            <button className="button button-dark" type="submit">
              Search
            </button>
            {search ? (
              <Link className="button button-quiet" href="/portal/contacts">
                Clear
              </Link>
            ) : null}
          </form>
          <p>
            {integer.format(total)} {search ? "matches" : "contacts"}
          </p>
        </div>

        {rows.length ? (
          <div aria-label="Contacts table" className="table-scroll" role="region" tabIndex={0}>
            <table>
              <thead>
                <tr>
                  <th>Customer</th>
                  <th>Location</th>
                  <th>Lifecycle</th>
                  <th>Channels</th>
                  <th>Contactability</th>
                  <th>Signed up</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((contact) => (
                  <tr key={contact.id}>
                    <td>
                      <strong>{contact.full_name}</strong>
                      <span>
                        {contact.external_id} · {contact.email ?? contact.phone ?? "No destination"}
                      </span>
                    </td>
                    <td>
                      {[contact.city, contact.country_code].filter(Boolean).join(", ") || "—"}
                    </td>
                    <td>
                      <span className="soft-pill">{contact.lifecycle_status}</span>
                    </td>
                    <td className="channel-statuses">
                      <span>Email: {contact.email_status}</span>
                      <span>SMS: {contact.sms_status}</span>
                    </td>
                    <td>
                      <span
                        className={`contactability ${contact.is_contactable ? "is-ready" : "is-blocked"}`}
                      >
                        {contact.contactability_reason}
                      </span>
                    </td>
                    <td>{date.format(new Date(contact.signup_at))}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <div className="empty-state">
            <strong>No contacts found.</strong>
            <span>
              {search
                ? "Try a broader name, ID, or email."
                : "Import valid contacts to populate this page."}
            </span>
          </div>
        )}

        <nav aria-label="Contact pages" className="pagination">
          {page > 1 ? (
            <Link className="button button-quiet" href={pageHref(page - 1, search)}>
              ← Previous
            </Link>
          ) : (
            <span />
          )}
          <span>
            Page {integer.format(page)} of {integer.format(pageCount)}
          </span>
          {page < pageCount ? (
            <Link className="button button-quiet" href={pageHref(page + 1, search)}>
              Next →
            </Link>
          ) : (
            <span />
          )}
        </nav>
      </section>

      <p className="definition standalone-definition">
        Contactable means: explicit marketing consent, active lifecycle, not deleted or currently
        suppressed, and at least one active destination. Email and SMS status remain visible so a
        marketer can understand why a record is excluded.
      </p>
    </main>
  );
}
