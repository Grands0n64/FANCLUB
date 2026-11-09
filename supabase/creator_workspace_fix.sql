-- FANCLUB profile signup repair and creator workspace support
-- Safe to run in Supabase SQL Editor.

-- Repair any legacy blank/whitespace display names before tightening the constraint.
update public.profiles
set display_name = 'Fanclub member'
where display_name is null or char_length(btrim(display_name)) = 0;

alter table public.profiles drop constraint if exists profiles_display_name_check;
alter table public.profiles
  add constraint profiles_display_name_check
  check (char_length(btrim(display_name)) between 1 and 60);

-- Normalize signup metadata before inserting a profile.
create or replace function public.handle_new_fanclub_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  chosen_username text;
  chosen_name text;
begin
  chosen_username := lower(coalesce(nullif(btrim(new.raw_user_meta_data->>'username'), ''), 'member_' || substr(new.id::text,1,8)));
  chosen_name := left(coalesce(nullif(btrim(new.raw_user_meta_data->>'display_name'), ''), 'Fanclub member'), 60);
  insert into public.profiles (id, username, display_name)
  values (new.id, chosen_username, chosen_name)
  on conflict (id) do nothing;
  return new;
end;
$$;

-- Creators may see their own pending/rejected posts in Creator Studio.
drop policy if exists "Creators view own posts" on public.posts;
create policy "Creators view own posts"
on public.posts for select to authenticated
using (auth.uid() = creator_id);

-- Paid media must not use the public fanclub-media bucket.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('fanclub-paid-media','fanclub-paid-media',false,52428800,
       array['image/jpeg','image/png','image/webp','image/gif','video/mp4','video/webm'])
on conflict(id) do update
set public=false,
    file_size_limit=excluded.file_size_limit,
    allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists "Creators upload own paid media" on storage.objects;
create policy "Creators upload own paid media"
on storage.objects for insert to authenticated
with check (
  bucket_id='fanclub-paid-media'
  and (storage.foldername(name))[1]=(select auth.uid())::text
);

drop policy if exists "Creators view own paid media" on storage.objects;
create policy "Creators view own paid media"
on storage.objects for select to authenticated
using (
  bucket_id='fanclub-paid-media'
  and (storage.foldername(name))[1]=(select auth.uid())::text
);
