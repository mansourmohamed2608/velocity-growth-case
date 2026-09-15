-- Audience preview already binds the selected campaign to the caller through
-- assert_brand_owner and explicitly filters contacts by that campaign's brand.
-- Definer execution avoids one RLS membership function call per contact for the
-- largest tenant while preserving the same owner-only authorization boundary.

alter function public.portal_send_audience_count(uuid) security definer;
alter function public.portal_send_audience(uuid, integer, integer) security definer;
