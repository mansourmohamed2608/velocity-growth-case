# Velocity Growth Case - Setup Checkpoint

Date: 16 Sep 2026

## Completed

- Project root:
  C:\Users\manso\Downloads\velocity-growth-case

- Git initialized on main.

- .task folder created.

- Velocity seed ZIP present and SHA-256 verified:
  4961A25B151CA13AC56089CA46B94DEF6074C315445EC193C7BF87060683D35C

- .gitignore created.

- .env.example created.

- .env.local created and gitignored.

- Velocity provider API key stored locally in .env.local.
  NEVER COMMIT OR SHARE IT.

- SUBMISSION_PRIVATE.md created and gitignored.

- Supabase account and organization created.

- Supabase hosted project created:
  velocity-growth-case

- Supabase region:
  CentralEU (Frankfurt)

- Supabase project ref:
  phtafctxyabkvqlcsulz

- Supabase CLI installed locally.

- Supabase CLI authenticated.

- Local project linked successfully to hosted Supabase project.

- WSL 2.7.14 installed.

- Windows VirtualMachinePlatform enabled successfully.

## Current checkpoint

- Full application, migrations, seed import, RLS, role accounts, provider adapter, reconciliation, and secure reports are implemented.
- Local clean reset, 77 database/RLS assertions, two stable imports, concurrency checks, build, and browser suites pass.
- Hosted Supabase migrations/data and six role accounts are deployed and verified.
- Production is live at `https://velocity-growth-case.vercel.app`.
- Supabase Site URL and redirect allow-list target production; Google OAuth consent and the permitted Kilele owner login pass in production.
- Production email/password role matrix, largest-tenant queries/send preview, phone layout, direct unknown-user isolation, and public report password checks pass.
- Git history is pushed to the existing public repository.

## Guardrails

- Do not manually create database tables.
- Do not expose or commit secrets.
- Do not make real provider sends during automated tests.

## Human-gated final actions

- Explicitly approve or decline one real provider dispatch; no sandbox is documented.
- Confirm earliest start date and notice period for the submission email.
