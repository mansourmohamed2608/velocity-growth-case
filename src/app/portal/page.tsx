import { requirePortalContext } from "@/lib/portal-context";

export const metadata = { title: "Dashboard" };

export default async function PortalPage() {
  const context = await requirePortalContext();

  return (
    <main className="portal-main">
      <p className="eyebrow">{context.brandCode} workspace</p>
      <h1>Good to have you here.</h1>
      <p className="portal-intro">
        Your authenticated workspace is connected. Dashboard, contacts, and campaign data are added
        after the idempotent source import.
      </p>
      <section className="placeholder-grid" aria-label="Workspace sections">
        {[
          ["Dashboard", "Clear totals and campaign outcomes"],
          ["Contacts", "Bounded, searchable customer pages"],
          ["Campaigns", "History, approval, and delivery progress"],
        ].map(([title, description], index) => (
          <article key={title}>
            <span>0{index + 1}</span>
            <h2>{title}</h2>
            <p>{description}</p>
          </article>
        ))}
      </section>
    </main>
  );
}
