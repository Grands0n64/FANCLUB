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
     set followers_credited_at = now(),
         status = 'completed',
         completed_at = now()
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

-- Make follower purchases available to every signed-in member.
-- Admin/owner purchases are always free and activate immediately.
alter table public.promotion_campaigns
  drop constraint if exists promotion_campaigns_amount_minor_check;
alter table public.promotion_campaigns
  add constraint promotion_campaigns_amount_minor_check check (amount_minor >= 0);

create or replace function public.guard_promotion_campaign()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_is_admin boolean;
begin
  if auth.uid() is null or new.creator_id <> auth.uid() then
    raise exception 'Sign in to create your own follower purchase.';
  end if;

  select exists(
    select 1 from public.admin_roles a where a.user_id = auth.uid()
  ) into v_is_admin;

  if v_is_admin then
    new.amount_minor := 0;
    new.delivered_reach := 0;
    new.status := 'active';
    new.starts_at := now();
    new.activated_at := now();
    new.ends_at := now() + interval '30 days';
    return new;
  end if;

  if new.target_reach < 1000 or new.target_reach > 10000000 then
    raise exception 'Choose between 1,000 and 10,000,000 promotional followers.';
  end if;
  if new.amount_minor <> round(new.target_reach * 0.2)::bigint then
    raise exception 'Follower purchase price does not match the published rate.';
  end if;

  new.delivered_reach := 0;
  new.status := 'awaiting_payment';
  new.ends_at := now() + interval '30 days';
  return new;
end;
$$;

drop trigger if exists guard_promotion_campaign on public.promotion_campaigns;
create trigger guard_promotion_campaign
before insert on public.promotion_campaigns
for each row execute function public.guard_promotion_campaign();

-- Keep the promotional counter read-only for members.
revoke update on public.profiles from authenticated;
grant update (username, display_name, bio, avatar_path) on public.profiles to authenticated;

commit;
