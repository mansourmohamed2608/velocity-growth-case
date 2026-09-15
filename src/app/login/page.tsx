import Link from "next/link";

export const metadata = { title: "Sign in" };

export default function LoginPage() {
  return (
    <main className="auth-shell">
      <section className="auth-story">
        <Link className="wordmark wordmark-light" href="/">
          <span aria-hidden="true" className="wordmark-mark">
            R
          </span>
          <span>Relay</span>
        </Link>
        <div>
          <p className="eyebrow eyebrow-light">Built for considered growth</p>
          <h1>Your campaign truth, kept close.</h1>
          <p>Secure access for Kilele Rides, Karoo Coaches, and Marrakech Express.</p>
        </div>
        <small>Velocity Growth · Client portal</small>
      </section>
      <section className="auth-panel" aria-labelledby="login-heading">
        <div className="auth-card">
          <p className="eyebrow">Welcome back</p>
          <h2 id="login-heading">Sign in to your workspace</h2>
          <p className="muted">
            Authentication will be connected in the next implementation phase.
          </p>
          <button className="button button-primary button-wide" type="button" disabled>
            Continue with Google
          </button>
          <div className="divider">
            <span>or</span>
          </div>
          <fieldset disabled className="auth-fields">
            <label>
              Email address
              <input autoComplete="email" name="email" type="email" placeholder="you@company.com" />
            </label>
            <label>
              Password
              <input
                autoComplete="current-password"
                name="password"
                type="password"
                placeholder="••••••••"
              />
            </label>
            <button className="button button-dark button-wide" type="submit">
              Sign in
            </button>
          </fieldset>
        </div>
      </section>
    </main>
  );
}
