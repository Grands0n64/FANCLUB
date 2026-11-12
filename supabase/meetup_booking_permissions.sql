-- FANCLUB meetup booking profile permissions
-- Fixes "permission denied for table meetup_booking_profiles".
-- Run once in Supabase SQL Editor.

begin;

alter table public.meetup_booking_profiles enable row level security;

grant select, insert, update on table public.meetup_booking_profiles to authenticated;

drop policy if exists "Members view enabled meetup listings or own rates" on public.meetup_booking_profiles;
create policy "Members view enabled meetup listings or own rates"
on public.meetup_booking_profiles
for select
to authenticated
using (enabled = true or user_id = auth.uid());

drop policy if exists "Members create own meetup rates" on public.meetup_booking_profiles;
create policy "Members create own meetup rates"
on public.meetup_booking_profiles
for insert
to authenticated
with check (user_id = auth.uid());

drop policy if exists "Members update own meetup rates" on public.meetup_booking_profiles;
create policy "Members update own meetup rates"
on public.meetup_booking_profiles
for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

commit;
