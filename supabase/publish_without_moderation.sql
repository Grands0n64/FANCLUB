-- FANCLUB: allow signed-in creators to publish posts directly.
-- Run once in Supabase SQL Editor.
-- This does not add automated content scanning.

drop policy if exists "Approved safe public posts readable" on public.posts;
drop policy if exists "Creators create own pending posts" on public.posts;
drop policy if exists "Creators update own pending posts" on public.posts;

create policy "Approved public posts readable"
on public.posts for select
to anon, authenticated
using (moderation_status = 'approved' and visibility = 'public');

create policy "Creators publish own posts"
on public.posts for insert
to authenticated
with check (auth.uid() = creator_id and moderation_status = 'approved');

create policy "Creators update own posts"
on public.posts for update
to authenticated
using (auth.uid() = creator_id)
with check (auth.uid() = creator_id);

-- Ensure the public media bucket accepts creator-owned image/video uploads.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'fanclub-media',
  'fanclub-media',
  true,
  52428800,
  array['image/jpeg','image/png','image/webp','image/gif','video/mp4','video/webm']
)
on conflict (id) do update
set public = true,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Authenticated users upload own safe media" on storage.objects;
create policy "Authenticated users upload own fanclub media"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'fanclub-media'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists "Public read approved fanclub media" on storage.objects;
create policy "Public read fanclub media"
on storage.objects for select
to public
using (bucket_id = 'fanclub-media');
