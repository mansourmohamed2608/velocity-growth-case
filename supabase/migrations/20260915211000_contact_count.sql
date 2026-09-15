create function public.portal_contacts_count(search_text text default null)
returns bigint
language sql
stable
security invoker
set search_path = ''
as $$
  select count(*)::bigint
  from public.contacts contact
  where nullif(btrim(search_text), '') is null
    or contact.external_id ilike '%' || btrim(search_text) || '%'
    or contact.full_name ilike '%' || btrim(search_text) || '%'
    or coalesce(contact.email, '') ilike '%' || btrim(search_text) || '%';
$$;

revoke all on function public.portal_contacts_count(text) from public, anon;
grant execute on function public.portal_contacts_count(text) to authenticated;
