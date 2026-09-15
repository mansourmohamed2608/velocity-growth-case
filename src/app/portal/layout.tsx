import Link from "next/link";

import { requirePortalContext } from "@/lib/portal-context";

import { signOut } from "./actions";

export default async function PortalLayout({ children }: { children: React.ReactNode }) {
  const context = await requirePortalContext();

  return (
    <div className="portal-shell">
      <header className="portal-header">
        <Link className="wordmark" href="/portal">
          <span aria-hidden="true" className="wordmark-mark">
            R
          </span>
          <span>Relay</span>
        </Link>
        <nav aria-label="Portal navigation" className="portal-nav">
          <Link href="/portal">Dashboard</Link>
          <span aria-disabled="true">Contacts</span>
          <span aria-disabled="true">Campaigns</span>
        </nav>
        <form action={signOut}>
          <button className="button button-quiet" type="submit">
            Sign out
          </button>
        </form>
      </header>
      <div className="portal-meta">
        <div>
          <span className="status-dot" aria-hidden="true" />
          {context.brandName}
        </div>
        <div>
          <span className="role-pill">{context.role}</span>
          <span>{context.userEmail}</span>
        </div>
      </div>
      {children}
    </div>
  );
}
