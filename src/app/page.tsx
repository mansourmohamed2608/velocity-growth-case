import Link from "next/link";

export default function Home() {
  return (
    <main className="landing-shell">
      <nav className="landing-nav" aria-label="Primary navigation">
        <Link className="wordmark" href="/" aria-label="Relay home">
          <span aria-hidden="true" className="wordmark-mark">
            R
          </span>
          <span>Relay</span>
        </Link>
        <Link className="button button-quiet" href="/login">
          Sign in
        </Link>
      </nav>

      <section className="hero">
        <div className="eyebrow">Client campaign portal</div>
        <h1>Growth data, with the guardrails built in.</h1>
        <p>
          Understand who you can reach, see how every campaign performed, and approve the next send
          with confidence.
        </p>
        <Link className="button button-primary" href="/login">
          Open your workspace <span aria-hidden="true">→</span>
        </Link>
      </section>

      <section className="proof-grid" aria-label="Product principles">
        <article>
          <span className="proof-number">01</span>
          <h2>One clear picture</h2>
          <p>Contacts, signups, and campaign outcomes in one focused workspace.</p>
        </article>
        <article>
          <span className="proof-number">02</span>
          <h2>Approval you can trust</h2>
          <p>See the exact audience before a message leaves the building.</p>
        </article>
        <article>
          <span className="proof-number">03</span>
          <h2>Private by design</h2>
          <p>Every brand is isolated in the database, not merely filtered on screen.</p>
        </article>
      </section>
    </main>
  );
}
