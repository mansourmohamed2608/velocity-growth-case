import Link from "next/link";

import { PortalNav } from "@/components/portal-nav";
import { SubmitButton } from "@/components/submit-button";
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
        <PortalNav />
        <form action={signOut}>
          <SubmitButton className="button button-quiet" pendingLabel="Signing out…">
            Sign out
          </SubmitButton>
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
