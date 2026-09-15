import Link from "next/link";

export default function NotFound() {
  return (
    <main className="state-page">
      <p className="eyebrow">404</p>
      <h1>That page isn&apos;t here.</h1>
      <p>The link may be incomplete or no longer available.</p>
      <Link className="button button-primary" href="/">
        Return home
      </Link>
    </main>
  );
}
