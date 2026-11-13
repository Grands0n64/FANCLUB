-- FANCLUB direct-message controls
-- Run this file in Supabase SQL Editor after social_features.sql and direct_messages_media.sql.

create table if not exists public.dm_conversation_preferences (
  user_id uuid not null references public.profiles(id) on delete cascade,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  pinned_at timestamptz,
  cleared_at timestamptz,
  primary key(user_id, conversation_id)
);
alter table public.dm_conversation_preferences enable row level security;
drop policy if exists "Users manage own DM preferences" on public.dm_conversation_preferences;
create policy "Users manage own DM preferences" on public.dm_conversation_preferences
 for all to authenticated
 using (auth.uid()=user_id and public.is_fanclub_conversation_member(conversation_id))
 with check (auth.uid()=user_id and public.is_fanclub_conversation_member(conversation_id));
grant select,insert,update,delete on public.dm_conversation_preferences to authenticated;

create table if not exists public.dm_blocks (
 blocker_id uuid not null references public.profiles(id) on delete cascade,
 blocked_id uuid not null references public.profiles(id) on delete cascade,
 created_at timestamptz not null default now(),
 primary key(blocker_id,blocked_id),
 check(blocker_id<>blocked_id)
);
alter table public.dm_blocks enable row level security;
drop policy if exists "Users view own DM blocks" on public.dm_blocks;
create policy "Users view own DM blocks" on public.dm_blocks for select to authenticated
 using(auth.uid()=blocker_id or auth.uid()=blocked_id);
drop policy if exists "Users block others" on public.dm_blocks;
create policy "Users block others" on public.dm_blocks for insert to authenticated
 with check(auth.uid()=blocker_id);
drop policy if exists "Users unblock others" on public.dm_blocks;
create policy "Users unblock others" on public.dm_blocks for delete to authenticated
 using(auth.uid()=blocker_id);
grant select,insert,delete on public.dm_blocks to authenticated;

create or replace function public.fanclub_dm_is_blocked(user_a uuid,user_b uuid)
returns boolean language sql stable security definer set search_path=''
as $$
 select exists(select 1 from public.dm_blocks b
 where (b.blocker_id=user_a and b.blocked_id=user_b)
    or (b.blocker_id=user_b and b.blocked_id=user_a));
$$;
revoke all on function public.fanclub_dm_is_blocked(uuid,uuid) from public;
grant execute on function public.fanclub_dm_is_blocked(uuid,uuid) to authenticated;

-- Reuse a prior one-to-one thread. A transaction lock prevents duplicate threads on simultaneous starts.
create or replace function public.start_fanclub_conversation(other_user uuid)
returns uuid language plpgsql security definer set search_path=''
as $$
declare me uuid:=auth.uid(); found_id uuid; created_id uuid; lock_key bigint;
begin
 if me is null or other_user is null or other_user=me then raise exception 'A different signed-in member is required'; end if;
 if not exists(select 1 from public.profiles p where p.id=other_user) then raise exception 'Member not found'; end if;
 if public.fanclub_dm_is_blocked(me,other_user) then raise exception 'This conversation is unavailable'; end if;
 lock_key:=hashtextextended(least(me::text,other_user::text)||':'||greatest(me::text,other_user::text),0);
 perform pg_advisory_xact_lock(lock_key);
 select c.id into found_id from public.conversations c
 where exists(select 1 from public.conversation_members a where a.conversation_id=c.id and a.user_id=me)
 and exists(select 1 from public.conversation_members b where b.conversation_id=c.id and b.user_id=other_user)
 and (select count(*) from public.conversation_members cm where cm.conversation_id=c.id)=2
 order by c.created_at desc limit 1;
 if found_id is not null then return found_id; end if;
 insert into public.conversations default values returning id into created_id;
 insert into public.conversation_members(conversation_id,user_id) values(created_id,me),(created_id,other_user);
 return created_id;
end;
$$;
revoke all on function public.start_fanclub_conversation(uuid) from public;
grant execute on function public.start_fanclub_conversation(uuid) to authenticated;

-- Per-user clearing: do not erase the other participant's message history.
-- A sender may remove their own messages.
grant delete on public.messages to authenticated;
drop policy if exists "Senders delete own messages" on public.messages;
create policy "Senders delete own messages" on public.messages for delete to authenticated
 using(auth.uid()=sender_id and public.is_fanclub_conversation_member(conversation_id));

-- Blocked pairs cannot read or send messages or open the conversation through the normal client.
drop policy if exists "Conversation members read messages" on public.messages;
create policy "Conversation members read messages" on public.messages for select to authenticated
 using(public.is_fanclub_conversation_member(conversation_id) and not exists(
  select 1 from public.conversation_members peer where peer.conversation_id=messages.conversation_id
   and peer.user_id<>auth.uid() and public.fanclub_dm_is_blocked(auth.uid(),peer.user_id)
 ));
drop policy if exists "Conversation members send messages" on public.messages;
create policy "Conversation members send messages" on public.messages for insert to authenticated
 with check(auth.uid()=sender_id and public.is_fanclub_conversation_member(conversation_id) and not exists(
  select 1 from public.conversation_members peer where peer.conversation_id=messages.conversation_id
   and peer.user_id<>auth.uid() and public.fanclub_dm_is_blocked(auth.uid(),peer.user_id)
 ));
drop policy if exists "Members view their conversations" on public.conversations;
create policy "Members view their conversations" on public.conversations for select to authenticated
 using(public.is_fanclub_conversation_member(id) and not exists(
  select 1 from public.conversation_members peer where peer.conversation_id=conversations.id
   and peer.user_id<>auth.uid() and public.fanclub_dm_is_blocked(auth.uid(),peer.user_id)
 ));

drop policy if exists "Conversation members read message media" on storage.objects;
create policy "Conversation members read message media" on storage.objects for select to authenticated
 using(bucket_id='fanclub-dm-media' and exists(
  select 1 from public.messages m
  join public.conversation_members peer on peer.conversation_id=m.conversation_id and peer.user_id<>auth.uid()
  where m.media_path=name and public.is_fanclub_conversation_member(m.conversation_id)
   and not public.fanclub_dm_is_blocked(auth.uid(),peer.user_id)
 ));
