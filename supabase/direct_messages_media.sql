-- FANCLUB direct-message media support
-- Run after social_features.sql in Supabase SQL Editor.
alter table public.messages
  add column if not exists kind text not null default 'text'
    check (kind in ('text','image','video','voice')),
  add column if not exists media_path text,
  add column if not exists media_mime text,
  add column if not exists duration_seconds integer;

alter table public.messages drop constraint if exists messages_body_check;
alter table public.messages add constraint messages_body_check
  check (char_length(body) between 0 and 5000);

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('fanclub-dm-media','fanclub-dm-media',false,104857600,
  array['image/jpeg','image/png','image/webp','image/gif','video/mp4','video/webm','audio/webm','audio/mp4','audio/mpeg','audio/ogg'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists "Conversation members upload message media" on storage.objects;
create policy "Conversation members upload message media"
on storage.objects for insert to authenticated
with check (
  bucket_id='fanclub-dm-media'
  and (storage.foldername(name))[1]=auth.uid()::text
);

drop policy if exists "Conversation members read message media" on storage.objects;
create policy "Conversation members read message media"
on storage.objects for select to authenticated
using (
  bucket_id='fanclub-dm-media'
  and exists (
    select 1
    from public.messages m
    where m.media_path=name
      and public.is_fanclub_conversation_member(m.conversation_id)
  )
);

grant update on public.messages to authenticated;
drop policy if exists "Members mark messages read" on public.messages;
create policy "Members mark messages read"
on public.messages for update to authenticated
using (public.is_fanclub_conversation_member(conversation_id))
with check (public.is_fanclub_conversation_member(conversation_id));
