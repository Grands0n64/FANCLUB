-- FANCLUB profile promotion campaigns
-- Run once in Supabase SQL Editor after schema.sql and creator_payments_setup.sql.

begin;

create table if not exists public.promotion_eligibility (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  gender_identity text not null default 'prefer_not_to_say'
    check (gender_identity in ('female','male','non_binary','prefer_not_to_say')),
  updated_at timestamptz not null default now()
);
alter table public.promotion_eligibility enable row level security;
drop policy if exists "Members read own promotion eligibility" on public.promotion_eligibility;
create policy "Members read own promotion eligibility" on public.promotion_eligibility
for select to authenticated using (auth.uid()=user_id);
drop policy if exists "Members set own promotion eligibility" on public.promotion_eligibility;
create policy "Members set own promotion eligibility" on public.promotion_eligibility
for insert to authenticated with check (auth.uid()=user_id);
drop policy if exists "Members update own promotion eligibility" on public.promotion_eligibility;
create policy "Members update own promotion eligibility" on public.promotion_eligibility
for update to authenticated using (auth.uid()=user_id) with check (auth.uid()=user_id);
grant select,insert,update on public.promotion_eligibility to authenticated;

create table if not exists public.promotion_campaigns (
  id uuid primary key default gen_random_uuid(),
  creator_id uuid not null references public.profiles(id) on delete cascade,
  target_reach integer not null check (target_reach between 1000 and 10000000),
  delivered_reach integer not null default 0 check (delivered_reach >= 0),
  amount_minor bigint not null check (amount_minor > 0),
  status text not null default 'awaiting_payment'
    check (status in ('awaiting_payment','pending_review','active','completed','rejected','expired')),
  created_at timestamptz not null default now(),
  starts_at timestamptz,
  ends_at timestamptz not null default (now() + interval '30 days'),
  activated_at timestamptz,
  completed_at timestamptz,
  check (delivered_reach <= target_reach)
);
create index if not exists promotion_campaigns_active_idx
on public.promotion_campaigns(status,created_at) where status='active';
create index if not exists promotion_campaigns_creator_idx
on public.promotion_campaigns(creator_id,created_at desc);
alter table public.promotion_campaigns enable row level security;
drop policy if exists "Creators view own promotion campaigns" on public.promotion_campaigns;
create policy "Creators view own promotion campaigns" on public.promotion_campaigns
for select to authenticated using (auth.uid()=creator_id);
grant select on public.promotion_campaigns to authenticated;

create table if not exists public.promotion_payments (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null unique references public.promotion_campaigns(id) on delete restrict,
  buyer_id uuid not null references public.profiles(id) on delete restrict,
  amount_minor bigint not null check (amount_minor > 0),
  payment_method text not null check(payment_method in ('bitcoin','usdt_bep20')),
  transaction_hash text not null check(length(btrim(transaction_hash)) between 8 and 200),
  wallet_snapshot text not null,
  status text not null default 'pending' check(status in ('pending','confirmed','rejected')),
  admin_notes text,
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists promotion_payments_status_created_idx
on public.promotion_payments(status,created_at);
alter table public.promotion_payments enable row level security;
drop policy if exists "Buyers and admins view promotion payments" on public.promotion_payments;
create policy "Buyers and admins view promotion payments" on public.promotion_payments
for select to authenticated using (
  auth.uid()=buyer_id or exists(select 1 from public.admin_roles a where a.user_id=auth.uid())
);
drop policy if exists "Eligible buyers submit promotion payments" on public.promotion_payments;
create policy "Eligible buyers submit promotion payments" on public.promotion_payments
for insert to authenticated with check (
  auth.uid()=buyer_id and status='pending' and reviewed_by is null and reviewed_at is null
);
drop policy if exists "Admins review promotion payments" on public.promotion_payments;
create policy "Admins review promotion payments" on public.promotion_payments
for update to authenticated
using(exists(select 1 from public.admin_roles a where a.user_id=auth.uid()))
with check(exists(select 1 from public.admin_roles a where a.user_id=auth.uid()));
grant select,insert on public.promotion_payments to authenticated;
grant update(status,admin_notes,reviewed_by,reviewed_at) on public.promotion_payments to authenticated;

create or replace function public.guard_promotion_campaign()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_verification public.verification_level; v_gender text;
begin
  if auth.uid() is null or new.creator_id<>auth.uid() then
    raise exception 'Sign in to create your own promotion campaign.';
  end if;
  select p.verification,e.gender_identity into v_verification,v_gender
  from public.profiles p join public.promotion_eligibility e on e.user_id=p.id
  where p.id=new.creator_id;
  if not found or v_gender<>'female' or v_verification not in ('royal','sovereign','imperial_elite') then
    raise exception 'Promote is available only to female members with Royal verification or higher.';
  end if;
  if new.amount_minor<>round(new.target_reach*0.2)::bigint then
    raise exception 'Promotion price does not match the $2 per 1,000 reach rate.';
  end if;
  new.delivered_reach:=0;
  new.status:='awaiting_payment';
  new.ends_at:=now()+interval '30 days';
  return new;
end; $$;
drop trigger if exists guard_promotion_campaign on public.promotion_campaigns;
create trigger guard_promotion_campaign before insert on public.promotion_campaigns
for each row execute function public.guard_promotion_campaign();

create or replace function public.guard_promotion_payment()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_campaign public.promotion_campaigns%rowtype;
begin
  if auth.uid() is null or new.buyer_id<>auth.uid() then raise exception 'Sign in to submit payment.'; end if;
  select * into v_campaign from public.promotion_campaigns where id=new.campaign_id for update;
  if not found or v_campaign.creator_id<>new.buyer_id or v_campaign.status<>'awaiting_payment' then
    raise exception 'This promotion campaign is not awaiting payment.';
  end if;
  if new.amount_minor<>v_campaign.amount_minor then raise exception 'Promotion amount has changed. Refresh and try again.'; end if;
  if new.payment_method='bitcoin' then
    new.wallet_snapshot:='1HxpFiB5fpL2oPoxFcPiGB7JcHFauqzs2o';
  else
    new.wallet_snapshot:='0x6588cd478cf2b229e72fa9c81f983d7922d8a840';
  end if;
  return new;
end; $$;
drop trigger if exists guard_promotion_payment on public.promotion_payments;
create trigger guard_promotion_payment before insert on public.promotion_payments
for each row execute function public.guard_promotion_payment();

create or replace function public.set_promotion_pending_review()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  update public.promotion_campaigns set status='pending_review' where id=new.campaign_id and status='awaiting_payment';
  return new;
end; $$;
drop trigger if exists set_promotion_pending_review on public.promotion_payments;
create trigger set_promotion_pending_review after insert on public.promotion_payments
for each row execute function public.set_promotion_pending_review();

create or replace function public.apply_promotion_payment_review()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if old.status='pending' and new.status in ('confirmed','rejected') then
    update public.promotion_campaigns
      set status=case when new.status='confirmed' then 'active' else 'rejected' end,
          starts_at=case when new.status='confirmed' then now() else starts_at end,
          activated_at=case when new.status='confirmed' then now() else activated_at end
    where id=new.campaign_id and status='pending_review';
  end if;
  return new;
end; $$;
drop trigger if exists apply_promotion_payment_review on public.promotion_payments;
create trigger apply_promotion_payment_review after update of status on public.promotion_payments
for each row execute function public.apply_promotion_payment_review();

create table if not exists public.promotion_impressions (
  campaign_id uuid not null references public.promotion_campaigns(id) on delete cascade,
  viewer_id uuid not null references public.profiles(id) on delete cascade,
  seen_at timestamptz not null default now(),
  primary key(campaign_id,viewer_id)
);
alter table public.promotion_impressions enable row level security;
revoke all on public.promotion_impressions from anon,authenticated;

create or replace function public.get_active_promotions()
returns table(
  id uuid, creator_id uuid, target_reach integer, delivered_reach integer,
  username text, display_name text, avatar_url text, verification text
)
language sql stable security definer set search_path='' as $$
  select c.id,c.creator_id,c.target_reach,c.delivered_reach,
         p.username,p.display_name,p.avatar_path::text,p.verification::text
  from public.promotion_campaigns c
  join public.profiles p on p.id=c.creator_id
  where auth.uid() is not null and c.status='active'
    and c.delivered_reach<c.target_reach
    and c.ends_at>now()
    and c.creator_id<>auth.uid()
  order by c.created_at asc
  limit 5;
$$;
grant execute on function public.get_active_promotions() to authenticated;

create or replace function public.record_promotion_impression(p_campaign_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
declare v_inserted integer;
begin
  if auth.uid() is null then raise exception 'Sign in to record a promotion impression.'; end if;
  insert into public.promotion_impressions(campaign_id,viewer_id)
  select c.id,auth.uid() from public.promotion_campaigns c
  where c.id=p_campaign_id and c.status='active'
    and c.ends_at>now() and c.delivered_reach<c.target_reach
    and c.creator_id<>auth.uid()
  on conflict do nothing;
  get diagnostics v_inserted = row_count;
  if v_inserted=1 then
    update public.promotion_campaigns
      set delivered_reach=delivered_reach+1,
          status=case when delivered_reach+1>=target_reach then 'completed' else 'active' end,
          completed_at=case when delivered_reach+1>=target_reach then now() else completed_at end
    where id=p_campaign_id and status='active';
    return true;
  end if;
  return false;
end; $$;
grant execute on function public.record_promotion_impression(uuid) to authenticated;

create or replace function public.expire_promotion_campaigns()
returns integer language plpgsql security definer set search_path='' as $$
declare v_count integer;
begin
  update public.promotion_campaigns set status='expired'
  where status='active' and ends_at<=now();
  get diagnostics v_count=row_count;
  return v_count;
end; $$;
revoke all on function public.expire_promotion_campaigns() from public,anon,authenticated;

commit;
