"use client";

export default function PortalError({
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  return (
    <main className="portal-main list-main">
      <section className="error-panel" role="alert">
        <p className="eyebrow">Data unavailable</p>
        <h1>This workspace could not be loaded.</h1>
        <p>
          The request failed, so no totals or empty results have been inferred. Retry the query; if
          it persists, check the database and session health.
        </p>
        <button className="button button-dark" onClick={reset} type="button">
          Try again
        </button>
      </section>
    </main>
  );
}
