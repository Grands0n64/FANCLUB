-- FANCLUB permissions repair (safe to run after the starter schema)
-- Grants table-level access; existing RLS policies continue to control which rows/actions are allowed.

grant usage on schema public to anon, authenticated;

grant select on table public.profiles to anon, authenticated;
grant insert (id, username, display_name, bio, avatar_path) on table public.profiles to authenticated;
grant update (username, display_name, bio, avatar_path) on table public.profiles to authenticated;

grant select on table public.posts to anon, authenticated;
grant insert on table public.posts to authenticated;
grant update on table public.posts to authenticated;

grant select, insert, delete on table public.follows to authenticated;
grant select, insert, delete on table public.post_likes to authenticated;
grant select, insert, delete on table public.post_comments to authenticated;
grant select on table public.subscriptions to authenticated;
grant select, insert on table public.reports to authenticated;
grant select on table public.admin_roles to authenticated;

-- Do not grant direct client writes to subscriptions or creator_transactions.
