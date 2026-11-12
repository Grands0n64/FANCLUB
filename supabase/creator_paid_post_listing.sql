-- Allow signed-in members to discover approved paid-post metadata.
-- Media remains in private storage and must only be delivered after payment approval.
drop policy if exists "Approved paid post listings readable" on public.posts;
create policy "Approved paid post listings readable"
on public.posts for select to authenticated
using (visibility='paid' and moderation_status='approved' and is_adult=false);
