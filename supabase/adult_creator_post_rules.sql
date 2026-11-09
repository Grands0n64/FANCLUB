-- FANCLUB: adult posts are Creator Studio only and never appear in the normal public feed.
-- Run once in Supabase SQL Editor.

-- Normal public feed and its social interactions are strictly non-adult.
drop policy if exists "Approved public posts readable" on public.posts;
create policy "Approved non adult public posts readable"
on public.posts for select to anon, authenticated
using (moderation_status='approved' and visibility='public' and is_adult=false);

-- A creator may view their own posts in Creator Studio/profile.
drop policy if exists "Creators view own posts" on public.posts;
create policy "Creators view own posts"
on public.posts for select to authenticated
using (auth.uid()=creator_id);

-- Only a verified creator can create adult posts. Ordinary posts must be non-adult.
drop policy if exists "Creators publish own posts" on public.posts;
create policy "Verified creators publish permitted posts"
on public.posts for insert to authenticated
with check (
  auth.uid()=creator_id
  and moderation_status='approved'
  and (
    is_adult=false
    or exists (
      select 1 from public.profiles p
      where p.id=auth.uid()
        and p.is_creator=true
        and p.verification is not null
        and p.verification not in ('none','unverified','pending')
    )
  )
);

-- Social interactions are only available on approved non-adult public posts.
drop policy if exists "Likes readable on approved public posts" on public.post_likes;
drop policy if exists "Members like as themselves" on public.post_likes;
drop policy if exists "Comments readable on approved public posts" on public.post_comments;
drop policy if exists "Members comment as themselves" on public.post_comments;
create policy "Likes readable on non adult public posts" on public.post_likes
for select to authenticated using (exists(select 1 from public.posts p where p.id=post_id and p.visibility='public' and p.is_adult=false and p.moderation_status='approved'));
create policy "Members like non adult public posts" on public.post_likes
for insert to authenticated with check (auth.uid()=user_id and exists(select 1 from public.posts p where p.id=post_id and p.visibility='public' and p.is_adult=false and p.moderation_status='approved'));
create policy "Comments readable on non adult public posts" on public.post_comments
for select to authenticated using (exists(select 1 from public.posts p where p.id=post_id and p.visibility='public' and p.is_adult=false and p.moderation_status='approved'));
create policy "Members comment on non adult public posts" on public.post_comments
for insert to authenticated with check (auth.uid()=user_id and exists(select 1 from public.posts p where p.id=post_id and p.visibility='public' and p.is_adult=false and p.moderation_status='approved'));
