-- FANCLUB verification payment submissions
begin;
create table if not exists public.verification_payment_submissions (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references public.profiles(id) on delete restrict,
 verification_level text not null check (verification_level in ('noble','royal','sovereign')),
 amount_usd numeric(10,2) not null check (amount_usd in (5,15,30)),
 payment_method text not null check (payment_method in ('bitcoin','usdt_bep20')),
 transaction_reference text not null,
 status text not null default 'pending' check (status in ('pending','confirmed','rejected')),
 admin_notes text,
 reviewed_by uuid references auth.users(id) on delete set null,
 reviewed_at timestamptz,
 created_at timestamptz not null default now(),
 constraint verification_payment_amount_matches_level check (
  (verification_level='noble' and amount_usd=5) or
  (verification_level='royal' and amount_usd=15) or
  (verification_level='sovereign' and amount_usd=30)
 )
);
create index if not exists verification_payment_submissions_user_created_idx
 on public.verification_payment_submissions(user_id,created_at desc);
create index if not exists verification_payment_submissions_status_created_idx
 on public.verification_payment_submissions(status,created_at desc);
alter table public.verification_payment_submissions enable row level security;
drop policy if exists "Users submit own verification payments" on public.verification_payment_submissions;
create policy "Users submit own verification payments"
 on public.verification_payment_submissions for insert to authenticated
 with check(auth.uid()=user_id and status='pending' and reviewed_by is null and reviewed_at is null);
drop policy if exists "Users and admins view verification payments" on public.verification_payment_submissions;
create policy "Users and admins view verification payments"
 on public.verification_payment_submissions for select to authenticated
 using(auth.uid()=user_id or exists(select 1 from public.admin_roles a where a.user_id=auth.uid()));
drop policy if exists "Admins review verification payments" on public.verification_payment_submissions;
create policy "Admins review verification payments"
 on public.verification_payment_submissions for update to authenticated
 using(exists(select 1 from public.admin_roles a where a.user_id=auth.uid()))
 with check(exists(select 1 from public.admin_roles a where a.user_id=auth.uid()));
grant select,insert on public.verification_payment_submissions to authenticated;
grant update(status,admin_notes,reviewed_by,reviewed_at) on public.verification_payment_submissions to authenticated;
commit;
