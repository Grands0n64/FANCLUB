-- FANCLUB: enforce a seven-day cooldown on display-name and username changes.
begin;

alter table public.profiles
  add column if not exists identity_changed_at timestamptz;

create or replace function public.enforce_fanclub_identity_change_cooldown()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.username is distinct from old.username
     or new.display_name is distinct from old.display_name then
    if old.identity_changed_at is not null
       and old.identity_changed_at > now() - interval '7 days' then
      raise exception 'You can change your name or username once every 7 days. Try again after %.',
        (old.identity_changed_at + interval '7 days');
    end if;
    new.identity_changed_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists fanclub_identity_change_cooldown on public.profiles;
create trigger fanclub_identity_change_cooldown
before update of username, display_name on public.profiles
for each row
execute function public.enforce_fanclub_identity_change_cooldown();

commit;
