import { signOut } from "@/app/portal/actions";

export const metadata = { title: "No portal access" };

export default function UnauthorizedPage() {
  return (
    <main className="state-page">
      <p className="eyebrow">Access protected</p>
      <h1>This account has no workspace.</h1>
      <p>
        Signing in proves your identity. Portal access also requires one of the six approved brand
        memberships.
      </p>
      <form action={signOut}>
        <button className="button button-primary" type="submit">
          Sign out and try another account
        </button>
      </form>
    </main>
  );
}
