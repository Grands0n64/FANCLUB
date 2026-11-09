-- FANCLUB starter schema. Review before running in your own Supabase project.
create extension if not exists pgcrypto;
create type public.verification_level as enum ('none','noble','royal','sovereign','imperial_elite');
create type public.post_visibility as enum ('public','followers','subscribers','paid');
create type public.transaction_status as enum ('pending','available','paid','refunded','disputed','failed');
create table public.profiles(id uuid primary key references auth.users(id) on delete cascade,username text unique not null check(char_length(username) between 3 and 30),display_name text not null check(char_length(display_name) between 1 and 60),bio text not null default '' check(char_length(bio)<=500),avatar_path text,is_creator boolean not null default false,verification public.verification_level not null default 'none',created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create table public.follows(follower_id uuid not null references public.profiles(id) on delete cascade,followed_id uuid not null references public.profiles(id) on delete cascade,created_at timestamptz not null default now(),primary key(follower_id,followed_id),check(follower_id<>followed_id));
create table public.posts(id uuid primary key default gen_random_uuid(),creator_id uuid not null references public.profiles(id) on delete cascade,caption text not null default '' check(char_length(caption)<=5000),media_path text,visibility public.post_visibility not null default 'public',price_minor bigint check(price_minor is null or price_minor>=0),is_adult boolean not null default false,moderation_status text not null default 'pending' check(moderation_status in ('pending','approved','rejected','removed')),created_at timestamptz not null default now(),check(visibility<>'paid' or price_minor>0));
create table public.subscriptions(id uuid primary key default gen_random_uuid(),creator_id uuid not null references public.profiles(id) on delete cascade,subscriber_id uuid not null references public.profiles(id) on delete cascade,status text not null default 'pending' check(status in ('pending','active','cancelled','expired','refunded')),price_minor bigint not null check(price_minor>0),currency char(3) not null,started_at timestamptz,ends_at timestamptz,provider_reference text unique,created_at timestamptz not null default now(),check(creator_id<>subscriber_id));
create table public.creator_transactions(id uuid primary key default gen_random_uuid(),creator_id uuid not null references public.profiles(id) on delete restrict,payer_id uuid references public.profiles(id) on delete set null,post_id uuid references public.posts(id) on delete set null,gross_minor bigint not null check(gross_minor>0),creator_share_minor bigint not null check(creator_share_minor>=0),platform_share_minor bigint not null check(platform_share_minor>=0),currency char(3) not null,status public.transaction_status not null default 'pending',provider_reference text unique,created_at timestamptz not null default now(),check(creator_share_minor+platform_share_minor<=gross_minor));
create table public.reports(id uuid primary key default gen_random_uuid(),reporter_id uuid not null references public.profiles(id) on delete cascade,reported_user_id uuid references public.profiles(id) on delete cascade,post_id uuid references public.posts(id) on delete cascade,reason text not null check(char_length(reason) between 3 and 1000),status text not null default 'open' check(status in ('open','reviewing','resolved','dismissed')),created_at timestamptz not null default now(),check(reported_user_id is not null or post_id is not null));
alter table public.profiles enable row level security; alter table public.follows enable row level security; alter table public.posts enable row level security; alter table public.subscriptions enable row level security; alter table public.creator_transactions enable row level security; alter table public.reports enable row level security;
create policy "Profiles are viewable" on public.profiles for select using(true);
create policy "Users create own profile" on public.profiles for insert with check(auth.uid()=id);
create policy "Users update own profile" on public.profiles for update using(auth.uid()=id) with check(auth.uid()=id);
create policy "Follows visible to signed-in users" on public.follows for select to authenticated using(true);
create policy "Users follow as themselves" on public.follows for insert to authenticated with check(auth.uid()=follower_id);
create policy "Users unfollow themselves" on public.follows for delete to authenticated using(auth.uid()=follower_id);
-- Only safe, approved public posts are exposed by this starter policy.
-- Paid, subscriber-only and adult media need private storage and server-side authorization before release.
create policy "Approved safe public posts readable" on public.posts for select using(moderation_status='approved' and visibility='public' and is_adult=false);
create policy "Creators create own pending posts" on public.posts for insert to authenticated with check(auth.uid()=creator_id and moderation_status='pending');
create policy "Creators update own pending posts" on public.posts for update to authenticated using(auth.uid()=creator_id and moderation_status='pending') with check(auth.uid()=creator_id and moderation_status='pending');
create policy "Users view own subscriptions" on public.subscriptions for select to authenticated using(auth.uid()=subscriber_id or auth.uid()=creator_id);
-- Financial writes are intentionally server-only: no client insert/update policies are granted.


-- Create a profile automatically after a user confirms/creates an auth account.
create or replace function public.handle_new_fanclub_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  chosen_username text;
  chosen_name text;
begin
  chosen_username := lower(coalesce(new.raw_user_meta_data->>'username', 'member_' || substr(new.id::text,1,8)));
  chosen_name := coalesce(nullif(trim(new.raw_user_meta_data->>'display_name'),''), 'Fanclub member');
  insert into public.profiles (id, username, display_name)
  values (new.id, chosen_username, chosen_name)
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_fanclub_auth_user_created on auth.users;
create trigger on_fanclub_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_fanclub_user();

-- Members may edit profile presentation, but cannot grant themselves creator or verification privileges.
revoke insert, update on public.profiles from authenticated;
grant insert (id, username, display_name, bio, avatar_path) on public.profiles to authenticated;
grant update (username, display_name, bio, avatar_path) on public.profiles to authenticated;

create policy "Signed-in members can submit reports" on public.reports
for insert to authenticated
with check (auth.uid() = reporter_id);


-- Social interactions
create table if not exists public.post_likes (
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(post_id,user_id)
);
create table if not exists public.post_comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check(char_length(body) between 1 and 2000),
  created_at timestamptz not null default now()
);
alter table public.post_likes enable row level security;
alter table public.post_comments enable row level security;
create policy "Likes readable on approved public posts" on public.post_likes for select using (exists(select 1 from public.posts p where p.id=post_id and p.visibility='public' and p.is_adult=false and p.moderation_status='approved'));
create policy "Members like as themselves" on public.post_likes for insert to authenticated with check(auth.uid()=user_id and exists(select 1 from public.posts p where p.id=post_id and p.visibility='public' and p.is_adult=false and p.moderation_status='approved'));
create policy "Members remove own likes" on public.post_likes for delete to authenticated using(auth.uid()=user_id);
create policy "Comments readable on approved public posts" on public.post_comments for select using(exists(select 1 from public.posts p where p.id=post_id and p.visibility='public' and p.is_adult=false and p.moderation_status='approved'));
create policy "Members comment as themselves" on public.post_comments for insert to authenticated with check(auth.uid()=user_id and exists(select 1 from public.posts p where p.id=post_id and p.visibility='public' and p.is_adult=false and p.moderation_status='approved'));
create policy "Members delete own comments" on public.post_comments for delete to authenticated using(auth.uid()=user_id);


-- Owner/admin moderation access. Add the owner's account using the SQL snippet in README.
create table if not exists public.admin_roles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.admin_roles enable row level security;
create policy "Admins can view their own role" on public.admin_roles
for select to authenticated using (auth.uid() = user_id);
create policy "Admins can review posts" on public.posts
for select to authenticated using (exists(select 1 from public.admin_roles a where a.user_id = auth.uid()));
create policy "Admins can moderate posts" on public.posts
for update to authenticated
using (exists(select 1 from public.admin_roles a where a.user_id = auth.uid()))
with check (exists(select 1 from public.admin_roles a where a.user_id = auth.uid()));
