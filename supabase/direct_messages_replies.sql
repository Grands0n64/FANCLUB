-- FANCLUB DM reply support
-- Run once in Supabase SQL Editor before using swipe-to-reply.
alter table public.messages
  add column if not exists reply_to_message_id uuid null
  references public.messages(id) on delete set null;

create index if not exists messages_reply_to_message_id_idx
  on public.messages(reply_to_message_id);
