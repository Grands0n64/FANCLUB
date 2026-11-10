-- Run this in Supabase SQL Editor to enable member profile photos.
alter table public.profiles
add column if not exists avatar_url text;

-- The existing fanclub-media storage bucket is used by the app for profile photo files.


-- Allow signed-in members to edit only their own profile.
grant update (display_name, bio, avatar_url) on public.profiles to authenticated;

drop policy if exists "Members can update their own profile" on public.profiles;
create policy "Members can update their own profile"
on public.profiles
for update
to authenticated
using (auth.uid() = id)
with check (auth.uid() = id);

