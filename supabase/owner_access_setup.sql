-- FANCLUB owner access and complimentary owner benefits
-- Run after schema.sql and promotions_setup.sql in Supabase SQL Editor.
begin;

do $$
declare v_owner_id uuid;
begin
  select id into v_owner_id from auth.users where lower(email)=lower('Riayoung280@gmail.com') limit 1;
  if v_owner_id is null then
    raise exception 'Create/sign in to FANCLUB once with Riayoung280@gmail.com, then run this SQL again.';
  end if;
  insert into public.admin_roles(user_id) values(v_owner_id) on conflict(user_id) do nothing;
  update public.profiles set verification='imperial_elite',updated_at=now() where id=v_owner_id;
end $$;

-- Allow the owner/admin to read every RLS-protected public application table.
do $$
declare t record;
begin
  for t in
    select c.relname
    from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relkind='r' and c.relrowsecurity=true
      and c.relname<>'admin_roles'
  loop
    execute format('drop policy if exists "FANCLUB owner full read" on public.%I',t.relname);
    execute format(
      'create policy "FANCLUB owner full read" on public.%I for select to authenticated using (exists (select 1 from public.admin_roles a where a.user_id=auth.uid()))',
      t.relname
    );
    execute format('grant select on public.%I to authenticated',t.relname);
  end loop;
end $$;

-- A verified owner may create free campaigns; ordinary members still pay the published rate.
alter table public.promotion_campaigns drop constraint if exists promotion_campaigns_amount_minor_check;
alter table public.promotion_campaigns add constraint promotion_campaigns_amount_minor_check check(amount_minor>=0);

create or replace function public.guard_promotion_campaign()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_verification public.verification_level; v_gender text; v_is_admin boolean;
begin
  if auth.uid() is null or new.creator_id<>auth.uid() then
    raise exception 'Sign in to create your own promotion campaign.';
  end if;
  select exists(select 1 from public.admin_roles a where a.user_id=auth.uid()) into v_is_admin;
  if v_is_admin then
    new.amount_minor:=0;
    new.delivered_reach:=0;
    new.status:='active';
    new.starts_at:=now();
    new.activated_at:=now();
    new.ends_at:=now()+interval '30 days';
    return new;
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

commit;
