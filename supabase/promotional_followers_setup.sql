-- FANCLUB promotional follower counter
-- Run this once in Supabase SQL Editor after promotions_setup.sql.
-- Promotional quantities are added only when a campaign becomes active
-- (manual payment approval or an authorised free campaign).
begin;

alter table public.profiles
  add column if not exists promotional_followers bigint not null default 0
  check (promotional_followers >= 0);

alter table public.promotion_campaigns
  add column if not exists followers_credited_at timestamptz;

create or replace function public.credit_promotional_followers()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_creator_id uuid;
  v_quantity integer;
begin
  if new.status <> 'active' then
    return new;
  end if;

  update public.promotion_campaigns
     set followers_credited_at = now()
   where id = new.id
     and followers_credited_at is null
  returning creator_id, target_reach
       into v_creator_id, v_quantity;

  if v_creator_id is not null then
    update public.profiles
       set promotional_followers = promotional_followers + v_quantity,
           updated_at = now()
     where id = v_creator_id;
  end if;

  return new;
end;
$$;

drop trigger if exists credit_promotional_followers on public.promotion_campaigns;
create trigger credit_promotional_followers
after insert or update of status on public.promotion_campaigns
for each row
execute function public.credit_promotional_followers();

revoke all on function public.credit_promotional_followers() from public, anon, authenticated;

-- Keep the promotional counter read-only for members.
revoke update on public.profiles from authenticated;
grant update (username, display_name, bio, avatar_path) on public.profiles to authenticated;

commit;
