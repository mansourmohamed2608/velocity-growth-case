# Velocity Growth Case - Setup Checkpoint

Date: 15 Sep 2026

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

- Reboot completed.
- WSL 2 and Docker Desktop are working.
- Docker Engine and required local Supabase services are healthy.
- GitHub CLI is authenticated and `origin` targets the existing public repository.
- Vercel and hosted Supabase/Google provider setup are reported complete; production integration remains to be verified.
- Assignment, seed data, and provider discovery completed. See `TASKS.md` and `DATA_NOTES.md`.

## Guardrails

- Do not run npx supabase db push.
- Do not manually create database tables.
- Do not expose or commit secrets.
- Do not create six portal users manually yet.
- Do not make real provider sends during automated tests.

## Next implementation phase

Application scaffold, followed by authoritative migrations and local database tests.
