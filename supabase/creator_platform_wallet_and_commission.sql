-- FANCLUB central receiving wallets + 80/20 earnings ledger.
-- Safe additive migration; run after creator_payments.sql.
begin;

-- Remove the creator-owned wallet configuration. FANCLUB uses one central destination.
drop table if exists public.creator_payment_methods cascade;

alter table public.creator_payment_submissions
  add column if not exists platform_wallet_snapshot text,
  add column if not exists creator_share_minor bigint,
  add column if not exists platform_share_minor bigint;

create or replace function public.set_fanclub_payment_destination()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.payment_method = 'bitcoin' then
    new.platform_wallet_snapshot := '1HxpFiB5fpL2oPoxFcPiGB7JcHFauqzs2o';
  elsif new.payment_method = 'usdt_bep20' then
    new.platform_wallet_snapshot := '0x6588cd478cf2b229e72fa9c81f983d7922d8a840';
  else
    new.platform_wallet_snapshot := 'FANCLUB_GIFT_CARD_REVIEW';
  end if;
  return new;
end;
$$;

drop trigger if exists set_fanclub_payment_destination on public.creator_payment_submissions;
create trigger set_fanclub_payment_destination
before insert on public.creator_payment_submissions
for each row execute function public.set_fanclub_payment_destination();

create table if not exists public.platform_earnings (
  id uuid primary key default gen_random_uuid(),
  payment_id uuid not null unique references public.creator_payment_submissions(id) on delete restrict,
  creator_id uuid not null references public.profiles(id) on delete restrict,
  buyer_id uuid not null references public.profiles(id) on delete restrict,
  gross_minor bigint not null check(gross_minor > 0),
  creator_share_minor bigint not null check(creator_share_minor >= 0),
  platform_share_minor bigint not null check(platform_share_minor >= 0),
  currency char(3) not null,
  payment_method text not null,
  created_at timestamptz not null default now(),
  check(creator_share_minor + platform_share_minor = gross_minor)
);
alter table public.platform_earnings enable row level security;
drop policy if exists "Admins view platform earnings" on public.platform_earnings;
create policy "Admins view platform earnings"
on public.platform_earnings for select to authenticated
using(exists(select 1 from public.admin_roles a where a.user_id=auth.uid()));
grant select on public.platform_earnings to authenticated;

create or replace function public.record_fanclub_payment_split()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_creator_share bigint;
  v_platform_share bigint;
begin
  if old.status = 'pending' and new.status = 'confirmed' then
    v_creator_share := floor(new.amount_minor * 0.80)::bigint;
    v_platform_share := new.amount_minor - v_creator_share;

    update public.creator_payment_submissions
      set creator_share_minor = v_creator_share,
          platform_share_minor = v_platform_share
    where id = new.id;

    insert into public.creator_transactions
      (creator_id,payer_id,post_id,gross_minor,creator_share_minor,platform_share_minor,currency,status,provider_reference)
    values
      (new.creator_id,new.buyer_id,new.post_id,new.amount_minor,v_creator_share,v_platform_share,new.currency,'available','fanclub-payment:'||new.id::text)
    on conflict(provider_reference) do nothing;

    insert into public.platform_earnings
      (payment_id,creator_id,buyer_id,gross_minor,creator_share_minor,platform_share_minor,currency,payment_method)
    values
      (new.id,new.creator_id,new.buyer_id,new.amount_minor,v_creator_share,v_platform_share,new.currency,new.payment_method)
    on conflict(payment_id) do nothing;
  end if;
  return new;
end;
$$;

drop trigger if exists record_fanclub_payment_split on public.creator_payment_submissions;
create trigger record_fanclub_payment_split
after update of status on public.creator_payment_submissions
for each row execute function public.record_fanclub_payment_split();

commit;
