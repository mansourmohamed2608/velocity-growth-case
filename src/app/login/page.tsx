import Link from "next/link";

import { signInWithGoogle, signInWithPassword } from "./actions";

export const metadata = { title: "Sign in" };

const messages: Record<string, string> = {
  "invalid-input": "Enter a valid email address and password.",
  credentials: "Those credentials were not accepted.",
  oauth: "Google sign-in could not be started. Please try again.",
  callback: "The sign-in response could not be verified. Please try again.",
  configuration: "Sign-in is temporarily unavailable because the app is not configured.",
};

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  const errorCode = (await searchParams).error;
  const errorMessage = errorCode ? messages[errorCode] : undefined;

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
          <p className="muted">Use one of the six approved client-portal accounts.</p>
          {errorMessage ? (
            <p className="form-alert" role="alert">
              {errorMessage}
            </p>
          ) : null}
          <form action={signInWithGoogle}>
            <button className="button button-primary button-wide" type="submit">
              <span className="google-g" aria-hidden="true">
                G
              </span>
              Continue with Google
            </button>
          </form>
          <div className="divider">
            <span>or</span>
          </div>
          <form action={signInWithPassword} className="auth-fields">
            <label>
              Email address
              <input
                autoComplete="email"
                name="email"
                type="email"
                placeholder="you@company.com"
                required
              />
            </label>
            <label>
              Password
              <input
                autoComplete="current-password"
                name="password"
                type="password"
                placeholder="••••••••"
                required
              />
            </label>
            <button className="button button-dark button-wide" type="submit">
              Sign in
            </button>
          </form>
        </div>
      </section>
    </main>
  );
}
