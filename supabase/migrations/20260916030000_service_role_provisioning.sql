-- Server-only account provisioning needs to resolve brands and maintain the
-- explicit user-to-brand role mapping. No tenant data-table access is granted.

grant select on table public.brands to service_role;
grant select, insert, update, delete on table public.brand_memberships to service_role;
