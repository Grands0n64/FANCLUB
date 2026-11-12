-- FANCLUB CREATOR PAYMENTS SETUP
-- Run this complete file once in Supabase SQL Editor after the original FANCLUB schema and meetup_bookings.sql.

-- ===== supabase/creator_payments.sql =====
-- FANCLUB creator payments: BTC, USDT (BEP20), gift cards and manual approval.
-- Run this migration once in Supabase SQL Editor.
begin;

create table if not exists public.creator_payment_methods (
  creator_id uuid primary key references public.profiles(id) on delete cascade,
  btc_wallet text,
  usdt_bep20_wallet text,
  gift_cards_enabled boolean not null default true,
  updated_at timestamptz not null default now(),
  check (btc_wallet is null or length(btrim(btc_wallet)) between 20 and 120),
  check (usdt_bep20_wallet is null or usdt_bep20_wallet ~ '^0x[a-fA-F0-9]{40}$')
);
alter table public.creator_payment_methods enable row level security;
drop policy if exists "Payment methods are visible" on public.creator_payment_methods;
create policy "Payment methods are visible" on public.creator_payment_methods for select to authenticated using (true);
drop policy if exists "Creators manage own payment methods" on public.creator_payment_methods;
create policy "Creators manage own payment methods" on public.creator_payment_methods for insert to authenticated with check (auth.uid()=creator_id);
create policy "Creators update own payment methods" on public.creator_payment_methods for update to authenticated using (auth.uid()=creator_id) with check (auth.uid()=creator_id);
grant select,insert,update on public.creator_payment_methods to authenticated;

create table if not exists public.creator_payment_submissions (
  id uuid primary key default gen_random_uuid(),
  buyer_id uuid not null references public.profiles(id) on delete restrict,
  creator_id uuid not null references public.profiles(id) on delete restrict,
  creator_username text not null,
  item_type text not null check(item_type in ('paid_post','meetup')),
  post_id uuid references public.posts(id) on delete set null,
  meetup_booking_id uuid references public.meetup_bookings(id) on delete set null,
  item_title text not null,
  amount_minor bigint not null check(amount_minor > 0),
  currency text not null check(currency in ('USD','NGN','GBP','EUR')),
  payment_method text not null check(payment_method in ('bitcoin','usdt_bep20','gift_card')),
  transaction_reference text,
  gift_card_provider text,
  gift_card_code text,
  evidence_paths text[] not null default '{}',
  status text not null default 'pending' check(status in ('pending','confirmed','rejected')),
  admin_notes text,
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  check (creator_id <> buyer_id),
  check ((item_type='paid_post' and post_id is not null and meetup_booking_id is null)
      or (item_type='meetup' and meetup_booking_id is not null and post_id is null)),
  check ((payment_method='gift_card' and gift_card_provider is not null and gift_card_code is not null)
      or (payment_method<>'gift_card' and transaction_reference is not null))
);
create index if not exists creator_payment_submissions_creator_created_idx on public.creator_payment_submissions(creator_id,created_at desc);
create index if not exists creator_payment_submissions_status_created_idx on public.creator_payment_submissions(status,created_at desc);
alter table public.creator_payment_submissions enable row level security;

create or replace function public.validate_creator_payment_submission()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_post public.posts%rowtype; v_booking public.meetup_bookings%rowtype; v_username text;
begin
  if auth.uid() is null or new.buyer_id <> auth.uid() then raise exception 'Sign in to submit a payment.'; end if;
  if new.status <> 'pending' then raise exception 'New payments must start pending.'; end if;
  select username into v_username from public.profiles where id=new.creator_id;
  if v_username is null then raise exception 'Creator account not found.'; end if;
  new.creator_username := v_username;
  if new.item_type='paid_post' then
    select * into v_post from public.posts where id=new.post_id;
    if not found or v_post.creator_id<>new.creator_id or v_post.visibility<>'paid' or v_post.moderation_status<>'approved' then
      raise exception 'This paid post is not available for purchase.';
    end if;
    if new.amount_minor<>v_post.price_minor or new.currency<>'USD' then raise exception 'The post price has changed. Refresh and try again.'; end if;
    new.item_title := coalesce(nullif(left(btrim(v_post.caption),120),''),'Exclusive creator content');
  else
    select * into v_booking from public.meetup_bookings where id=new.meetup_booking_id;
    if not found or v_booking.creator_id<>new.creator_id or v_booking.customer_id<>new.buyer_id or v_booking.status<>'awaiting_payment' then
      raise exception 'This meetup booking is not awaiting payment.';
    end if;
    if new.amount_minor<>round(v_booking.total_amount*100)::bigint or new.currency<>v_booking.currency then
      raise exception 'The meetup amount does not match the booking.';
    end if;
    new.item_title := v_booking.meetup_option || ' · ' || v_booking.booking_code;
  end if;
  return new;
end; $$;
drop trigger if exists validate_creator_payment_submission on public.creator_payment_submissions;
create trigger validate_creator_payment_submission before insert on public.creator_payment_submissions
for each row execute function public.validate_creator_payment_submission();

drop policy if exists "Payment parties and admins view submissions" on public.creator_payment_submissions;
create policy "Payment parties and admins view submissions" on public.creator_payment_submissions for select to authenticated
using (
  auth.uid()=buyer_id or auth.uid()=creator_id
  or exists(select 1 from public.admin_roles a where a.user_id=auth.uid())
);
drop policy if exists "Buyers submit their own pending payments" on public.creator_payment_submissions;
create policy "Buyers submit their own pending payments" on public.creator_payment_submissions for insert to authenticated
with check(auth.uid()=buyer_id and status='pending' and reviewed_by is null and reviewed_at is null);
drop policy if exists "Admins review payment submissions" on public.creator_payment_submissions;
create policy "Admins review payment submissions" on public.creator_payment_submissions for update to authenticated
using(exists(select 1 from public.admin_roles a where a.user_id=auth.uid()))
with check(exists(select 1 from public.admin_roles a where a.user_id=auth.uid()));
grant select,insert on public.creator_payment_submissions to authenticated;
grant update(status,admin_notes,reviewed_by,reviewed_at) on public.creator_payment_submissions to authenticated;

-- Dedicated admin alert queue; every new payment creates a pending alert.
create table if not exists public.admin_payment_notifications (
  id uuid primary key default gen_random_uuid(),
  payment_id uuid not null unique references public.creator_payment_submissions(id) on delete cascade,
  message text not null,
  created_at timestamptz not null default now(),
  read_at timestamptz
);
alter table public.admin_payment_notifications enable row level security;
drop policy if exists "Admins view payment alerts" on public.admin_payment_notifications;
create policy "Admins view payment alerts" on public.admin_payment_notifications for select to authenticated
using(exists(select 1 from public.admin_roles a where a.user_id=auth.uid()));
drop policy if exists "Admins update payment alerts" on public.admin_payment_notifications;
create policy "Admins update payment alerts" on public.admin_payment_notifications for update to authenticated
using(exists(select 1 from public.admin_roles a where a.user_id=auth.uid()))
with check(exists(select 1 from public.admin_roles a where a.user_id=auth.uid()));
grant select,update on public.admin_payment_notifications to authenticated;

create or replace function public.create_admin_payment_alert()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.admin_payment_notifications(payment_id,message)
  values(new.id,'Payment pending approval for @'||new.creator_username)
  on conflict(payment_id) do nothing;
  return new;
end; $$;
drop trigger if exists create_admin_payment_alert on public.creator_payment_submissions;
create trigger create_admin_payment_alert after insert on public.creator_payment_submissions
for each row execute function public.create_admin_payment_alert();

create or replace function public.sync_confirmed_meetup_payment()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.item_type='meetup' and new.meetup_booking_id is not null then
    update public.meetup_bookings
      set status=case when new.status='confirmed' then 'paid' when new.status='rejected' then 'awaiting_payment' else status end,
          payment_reference=case when new.status='confirmed' then new.id::text else payment_reference end
    where id=new.meetup_booking_id;
  end if;
  return new;
end; $$;
drop trigger if exists sync_confirmed_meetup_payment on public.creator_payment_submissions;
create trigger sync_confirmed_meetup_payment after update of status on public.creator_payment_submissions
for each row execute function public.sync_confirmed_meetup_payment();

-- Private evidence bucket. Upload path must start with the buyer's auth UUID.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('fanclub-payment-evidence','fanclub-payment-evidence',false,10485760,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
drop policy if exists "Buyers upload own payment evidence" on storage.objects;
create policy "Buyers upload own payment evidence" on storage.objects for insert to authenticated
with check(bucket_id='fanclub-payment-evidence' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists "Payment parties and admins read payment evidence" on storage.objects;
create policy "Payment parties and admins read payment evidence" on storage.objects for select to authenticated
using(bucket_id='fanclub-payment-evidence' and (
  (storage.foldername(name))[1]=auth.uid()::text
  or exists(select 1 from public.creator_payment_submissions p
    where p.evidence_paths @> array[name] and (p.creator_id=auth.uid() or p.buyer_id=auth.uid()))
  or exists(select 1 from public.admin_roles a where a.user_id=auth.uid())
));

commit;


-- ===== supabase/creator_paid_post_listing.sql =====
-- Allow signed-in members to discover approved paid-post metadata.
-- Media remains in private storage and must only be delivered after payment approval.
drop policy if exists "Approved paid post listings readable" on public.posts;
create policy "Approved paid post listings readable"
on public.posts for select to authenticated
using (visibility='paid' and moderation_status='approved' and is_adult=false);


-- ===== supabase/creator_paid_media_access.sql =====
-- Allow a buyer to read a paid media object only after admin confirms
-- a payment for that exact post. The bucket stays private.
drop policy if exists "Buyers read paid post media after approval" on storage.objects;
create policy "Buyers read paid post media after approval"
on storage.objects for select to authenticated
using (
  bucket_id='fanclub-paid-media'
  and exists (
    select 1
    from public.posts p
    join public.creator_payment_submissions s on s.post_id=p.id
    where p.media_path=storage.objects.name
      and p.creator_id=s.creator_id
      and s.buyer_id=auth.uid()
      and s.status='confirmed'
  )
);


-- ===== Central platform wallets and 80/20 commission =====
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
