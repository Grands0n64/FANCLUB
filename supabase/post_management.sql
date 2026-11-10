-- FANCLUB post management: pinning, editing and deleting own posts.
-- Run this once in Supabase SQL Editor.
alter table public.posts add column if not exists is_pinned boolean not null default false;

drop policy if exists "Creators update own posts" on public.posts;
drop policy if exists "Creators update own pending posts" on public.posts;
drop policy if exists "Creators manage own posts" on public.posts;

create policy "Creators manage own posts"
on public.posts
for update to authenticated
using (auth.uid() = creator_id)
with check (auth.uid() = creator_id);

create policy "Creators delete own posts"
on public.posts
for delete to authenticated
using (auth.uid() = creator_id);

grant update (caption, media_path, media_type, is_pinned) on public.posts to authenticated;
grant delete on public.posts to authenticated;
