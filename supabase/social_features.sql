-- FANCLUB social features migration
-- Safe, non-adult public media only. Adult/paid media must use private storage and server authorization.
create table if not exists public.stories (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references public.profiles(id) on delete cascade,
 media_path text not null,
 media_type text not null check(media_type in ('image','video')),
 created_at timestamptz not null default now(),
 expires_at timestamptz not null default (now()+interval '24 hours')
);
create table if not exists public.conversations (
 id uuid primary key default gen_random_uuid(),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create table if not exists public.conversation_members (
 conversation_id uuid not null references public.conversations(id) on delete cascade,
 user_id uuid not null references public.profiles(id) on delete cascade,
 joined_at timestamptz not null default now(),
 primary key(conversation_id,user_id)
);
create table if not exists public.messages (
 id uuid primary key default gen_random_uuid(),
 conversation_id uuid not null references public.conversations(id) on delete cascade,
 sender_id uuid not null references public.profiles(id) on delete cascade,
 body text not null check(char_length(body) between 1 and 5000),
 created_at timestamptz not null default now(),
 read_at timestamptz
);
create table if not exists public.notifications (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references public.profiles(id) on delete cascade,
 actor_id uuid references public.profiles(id) on delete set null,
 kind text not null check(kind in ('follow','like','comment','message')),
 post_id uuid references public.posts(id) on delete cascade,
 message text not null check(char_length(message) between 1 and 500),
 created_at timestamptz not null default now(),
 read_at timestamptz
);
alter table public.stories enable row level security;
alter table public.conversations enable row level security;
alter table public.conversation_members enable row level security;
alter table public.messages enable row level security;
alter table public.notifications enable row level security;

drop policy if exists "Active stories are public" on public.stories;
create policy "Active stories are public" on public.stories for select to authenticated using(expires_at>now());
drop policy if exists "Members create own stories" on public.stories;
create policy "Members create own stories" on public.stories for insert to authenticated with check(auth.uid()=user_id and expires_at<=now()+interval '25 hours' and expires_at>now());

drop policy if exists "Members view their conversations" on public.conversations;
create policy "Members view their conversations" on public.conversations for select to authenticated using(exists(select 1 from public.conversation_members m where m.conversation_id=id and m.user_id=auth.uid()));
drop policy if exists "Members view conversation membership" on public.conversation_members;
create policy "Members view conversation membership" on public.conversation_members for select to authenticated using(exists(select 1 from public.conversation_members m where m.conversation_id=conversation_id and m.user_id=auth.uid()));
drop policy if exists "Conversation members read messages" on public.messages;
create policy "Conversation members read messages" on public.messages for select to authenticated using(exists(select 1 from public.conversation_members m where m.conversation_id=messages.conversation_id and m.user_id=auth.uid()));
drop policy if exists "Conversation members send messages" on public.messages;
create policy "Conversation members send messages" on public.messages for insert to authenticated with check(auth.uid()=sender_id and exists(select 1 from public.conversation_members m where m.conversation_id=messages.conversation_id and m.user_id=auth.uid()));
drop policy if exists "Users read own notifications" on public.notifications;
create policy "Users read own notifications" on public.notifications for select to authenticated using(auth.uid()=user_id);
drop policy if exists "Users update own notifications" on public.notifications;
create policy "Users update own notifications" on public.notifications for update to authenticated using(auth.uid()=user_id) with check(auth.uid()=user_id);

grant select,insert on public.stories to authenticated;
grant select on public.conversations to authenticated;
grant select on public.conversation_members to authenticated;
grant select,insert on public.messages to authenticated;
grant select,update on public.notifications to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('fanclub-media','fanclub-media',true,52428800,array['image/jpeg','image/png','image/webp','image/gif','video/mp4','video/webm'])
on conflict(id) do update set file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
drop policy if exists "Authenticated users upload own safe media" on storage.objects;
create policy "Authenticated users upload own safe media" on storage.objects for insert to authenticated with check(bucket_id='fanclub-media' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists "Public read approved fanclub media" on storage.objects;
create policy "Public read approved fanclub media" on storage.objects for select to public using(bucket_id='fanclub-media');

-- Create a two-person conversation atomically; clients cannot add themselves to arbitrary threads.
create or replace function public.start_fanclub_conversation(other_user uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare new_id uuid;
begin
 if auth.uid() is null or other_user is null or other_user=auth.uid() then
   raise exception 'A different signed-in member is required';
 end if;
 if not exists(select 1 from public.profiles where id=other_user) then
   raise exception 'Member not found';
 end if;
 insert into public.conversations default values returning id into new_id;
 insert into public.conversation_members(conversation_id,user_id)
 values(new_id,auth.uid()),(new_id,other_user);
 return new_id;
end;
$$;
revoke all on function public.start_fanclub_conversation(uuid) from public;
grant execute on function public.start_fanclub_conversation(uuid) to authenticated;
