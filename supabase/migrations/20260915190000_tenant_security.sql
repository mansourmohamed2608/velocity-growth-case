-- Central tenant-isolation boundary. Keep policies brand-scoped through these helpers.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated;

create function private.is_brand_member(target_brand_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.brand_memberships membership
    where membership.brand_id = target_brand_id
      and membership.user_id = (select auth.uid())
  );
$$;

create function private.is_brand_owner(target_brand_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.brand_memberships membership
    where membership.brand_id = target_brand_id
      and membership.user_id = (select auth.uid())
      and membership.role = 'owner'
  );
$$;

revoke all on function private.is_brand_member(uuid) from public, anon;
revoke all on function private.is_brand_owner(uuid) from public, anon;
grant execute on function private.is_brand_member(uuid) to authenticated;
grant execute on function private.is_brand_owner(uuid) to authenticated;

create function public.current_portal_context()
returns table (
  brand_id uuid,
  brand_code text,
  brand_name text,
  role public.portal_role
)
language sql
stable
security invoker
set search_path = ''
as $$
  select brand.id, brand.code, brand.name, membership.role
  from public.brand_memberships membership
  join public.brands brand on brand.id = membership.brand_id
  where membership.user_id = (select auth.uid());
$$;

create function public.assert_brand_owner(target_brand_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.is_brand_owner(target_brand_id) then
    raise exception 'owner role required' using errcode = '42501';
  end if;
end;
$$;

revoke all on function public.current_portal_context() from public, anon;
revoke all on function public.assert_brand_owner(uuid) from public, anon;
grant execute on function public.current_portal_context() to authenticated;
grant execute on function public.assert_brand_owner(uuid) to authenticated;

alter table public.brands enable row level security;
alter table public.brands force row level security;
alter table public.brand_memberships enable row level security;
alter table public.brand_memberships force row level security;
alter table public.import_runs enable row level security;
alter table public.import_runs force row level security;
alter table public.import_errors enable row level security;
alter table public.import_errors force row level security;
alter table public.contacts enable row level security;
alter table public.contacts force row level security;
alter table public.campaigns enable row level security;
alter table public.campaigns force row level security;
alter table public.campaign_sends enable row level security;
alter table public.campaign_sends force row level security;
alter table public.campaign_send_recipients enable row level security;
alter table public.campaign_send_recipients force row level security;
alter table public.provider_events enable row level security;
alter table public.provider_events force row level security;
alter table public.published_reports enable row level security;
alter table public.published_reports force row level security;
alter table public.report_sessions enable row level security;
alter table public.report_sessions force row level security;

create policy brands_member_select
on public.brands for select to authenticated
using ((select private.is_brand_member(id)));

create policy memberships_self_select
on public.brand_memberships for select to authenticated
using (user_id = (select auth.uid()));

create policy import_runs_member_select
on public.import_runs for select to authenticated
using ((select private.is_brand_member(brand_id)));

create policy import_errors_member_select
on public.import_errors for select to authenticated
using ((select private.is_brand_member(brand_id)));

create policy contacts_member_select
on public.contacts for select to authenticated
using ((select private.is_brand_member(brand_id)));

create policy campaigns_member_select
on public.campaigns for select to authenticated
using ((select private.is_brand_member(brand_id)));

create policy campaign_sends_member_select
on public.campaign_sends for select to authenticated
using ((select private.is_brand_member(brand_id)));

create policy campaign_send_recipients_member_select
on public.campaign_send_recipients for select to authenticated
using ((select private.is_brand_member(brand_id)));

create policy provider_events_member_select
on public.provider_events for select to authenticated
using ((select private.is_brand_member(brand_id)));

create policy published_reports_member_select
on public.published_reports for select to authenticated
using ((select private.is_brand_member(brand_id)));

revoke all on table public.brands from anon, authenticated;
revoke all on table public.brand_memberships from anon, authenticated;
revoke all on table public.import_runs from anon, authenticated;
revoke all on table public.import_errors from anon, authenticated;
revoke all on table public.contacts from anon, authenticated;
revoke all on table public.campaigns from anon, authenticated;
revoke all on table public.campaign_sends from anon, authenticated;
revoke all on table public.campaign_send_recipients from anon, authenticated;
revoke all on table public.provider_events from anon, authenticated;
revoke all on table public.published_reports from anon, authenticated;
revoke all on table public.report_sessions from anon, authenticated;

grant select on table public.brands to authenticated;
grant select on table public.brand_memberships to authenticated;
grant select on table public.import_runs to authenticated;
grant select on table public.import_errors to authenticated;
grant select on table public.contacts to authenticated;
grant select on table public.campaigns to authenticated;
grant select on table public.campaign_sends to authenticated;
grant select on table public.campaign_send_recipients to authenticated;
grant select on table public.provider_events to authenticated;
grant select on table public.published_reports to authenticated;

