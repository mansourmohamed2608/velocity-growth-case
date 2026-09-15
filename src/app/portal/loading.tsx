export default function PortalLoading() {
  return (
    <main aria-busy="true" aria-live="polite" className="portal-main list-main">
      <p className="eyebrow">Loading workspace</p>
      <div className="skeleton skeleton-title" />
      <div className="skeleton-grid">
        <div className="skeleton skeleton-card" />
        <div className="skeleton skeleton-card" />
        <div className="skeleton skeleton-card" />
      </div>
      <span className="sr-only">Loading portal data</span>
    </main>
  );
}
