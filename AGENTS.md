# Working Agreement

The employer brief in `.task/Growth Engineer Case Study.pdf` is the source of truth. Keep employer files, secrets, and private submission credentials untracked.

Before changing behavior, read the relevant project document:

- `TASKS.md` — requirements and acceptance status
- `DECISIONS.md` — security, data, and architecture decisions
- `ARCHITECTURE.md` — boundaries and data flows
- `DATA_NOTES.md` — source-data and provider-contract facts
- `README.md` — operator and contributor instructions

Non-negotiable rules:

- PostgreSQL RLS is the tenant security boundary. Every exposed tenant table must enable and force RLS.
- Authentication is not authorization; access requires an explicit membership.
- Provider credentials and privileged Supabase credentials are server-only.
- Imports, send confirmation, dispatch retries, and event reconciliation must be idempotent.
- Never make a real provider send during tests. Use dependency injection and recorded fixtures.
- Update `TASKS.md` and `DECISIONS.md` when acceptance status or a material decision changes.
