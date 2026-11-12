-- FANCLUB likes/comments promotional order queue
begin;
create table if not exists public.engagement_promotion_orders (
 id uuid primary key default gen_random_uuid(),
 buyer_id uuid not null references public.profiles(id) on delete cascade,
 engagement_type text not null check (engagement_type in ('likes','comments')),
 package_quantity integer not null default 2000 check (package_quantity=2000),
 target_mode text not null check (target_mode in ('post','all_posts')),
 target_post_url text,
 payment_method text not null check (payment_method in ('bitcoin','usdt_bep20')),
 transaction_hash text not null check (length(btrim(transaction_hash)) between 8 and 200),
 wallet_snapshot text not null,
 amount_minor integer not null check (amount_minor in (100,200)),
 status text not null default 'pending' check (status in ('pending','confirmed','rejected')),
 admin_notes text,
 reviewed_by uuid references auth.users(id),
 reviewed_at timestamptz,
 created_at timestamptz not null default now(),
 check ((target_mode='post' and target_post_url like 'http%/home?post=%') or (target_mode='all_posts' and target_post_url is null)),
 check ((engagement_type='likes' and amount_minor=100) or (engagement_type='comments' and amount_minor=200))
);
create index if not exists engagement_promotion_orders_status_created_idx on public.engagement_promotion_orders(status,created_at);
alter table public.engagement_promotion_orders enable row level security;
drop policy if exists "Buyers and admins view engagement orders" on public.engagement_promotion_orders;
create policy "Buyers and admins view engagement orders" on public.engagement_promotion_orders for select to authenticated using (auth.uid()=buyer_id or exists(select 1 from public.admin_roles a where a.user_id=auth.uid()));
drop policy if exists "Members submit own engagement orders" on public.engagement_promotion_orders;
create policy "Members submit own engagement orders" on public.engagement_promotion_orders for insert to authenticated with check (auth.uid()=buyer_id and status='pending' and reviewed_by is null and reviewed_at is null);
drop policy if exists "Admins review engagement orders" on public.engagement_promotion_orders;
create policy "Admins review engagement orders" on public.engagement_promotion_orders for update to authenticated using (exists(select 1 from public.admin_roles a where a.user_id=auth.uid())) with check (exists(select 1 from public.admin_roles a where a.user_id=auth.uid()));
grant select,insert on public.engagement_promotion_orders to authenticated;
grant update(status,admin_notes,reviewed_by,reviewed_at) on public.engagement_promotion_orders to authenticated;
create or replace function public.guard_engagement_promotion_order()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or new.buyer_id<>auth.uid() then raise exception 'Sign in to submit your own order.'; end if;
 if new.engagement_type='likes' then new.amount_minor:=100; else new.amount_minor:=200; end if;
 if new.package_quantity<>2000 then raise exception 'Only the 2,000 engagement package is available.'; end if;
 if new.payment_method='bitcoin' then new.wallet_snapshot:='1HxpFiB5fpL2oPoxFcPiGB7JcHFauqzs2o'; else new.wallet_snapshot:='0x6588cd478cf2b229e72fa9c81f983d7922d8a840'; end if;
 new.status:='pending';
 return new;
end; $$;
drop trigger if exists guard_engagement_promotion_order on public.engagement_promotion_orders;
create trigger guard_engagement_promotion_order before insert on public.engagement_promotion_orders for each row execute function public.guard_engagement_promotion_order();
commit;
