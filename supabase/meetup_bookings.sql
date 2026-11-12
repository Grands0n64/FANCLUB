-- FANCLUB meetup booking setup
create table if not exists public.meetup_booking_profiles (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  rate_30_min numeric(12,2) not null check (rate_30_min > 0),
  rate_hour numeric(12,2) not null check (rate_hour > 0),
  rate_half_day numeric(12,2) not null check (rate_half_day > 0),
  rate_overnight numeric(12,2) not null default 200 check (rate_overnight > 0),
  currency text not null default 'USD' check (currency in ('USD','NGN','GBP','EUR')),
  meetup_options text[] not null default array['Coffee meetup','Lunch or dinner','Public event','Creator meet-and-greet','Video call','Photography session'],
  enabled boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.meetup_bookings (
  id uuid primary key default gen_random_uuid(),
  booking_code text not null unique,
  creator_id uuid not null references public.profiles(id) on delete cascade,
  customer_id uuid not null references public.profiles(id) on delete cascade,
  starts_at timestamptz not null,
  duration_minutes integer not null check (duration_minutes >= 30 and duration_minutes <= 1440 and duration_minutes % 30 = 0),
  meetup_option text not null,
  total_amount numeric(12,2) not null check (total_amount > 0),
  currency text not null check (currency in ('USD','NGN','GBP','EUR')),
  status text not null default 'awaiting_payment' check (status in ('awaiting_payment','paid','confirmed','cancelled','refunded')),
  payment_reference text unique,
  created_at timestamptz not null default now(),
  check (creator_id <> customer_id)
);
alter table public.meetup_booking_profiles enable row level security;
alter table public.meetup_bookings enable row level security;
drop policy if exists "Meetup listings are public" on public.meetup_booking_profiles;
create policy "Meetup listings are public" on public.meetup_booking_profiles for select using (enabled = true or auth.uid() = user_id);
drop policy if exists "Creators manage own meetup listing" on public.meetup_booking_profiles;
create policy "Creators manage own meetup listing" on public.meetup_booking_profiles for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "Customers create meetup requests" on public.meetup_bookings;
create policy "Customers create meetup requests" on public.meetup_bookings for insert with check (auth.uid() = customer_id and status = 'awaiting_payment' and payment_reference is null);
drop policy if exists "Booking parties can view requests" on public.meetup_bookings;
create policy "Booking parties can view requests" on public.meetup_bookings for select using (auth.uid() = customer_id or auth.uid() = creator_id);
-- Do not add client-side policies allowing users to mark a booking paid.
-- Payment confirmation must be performed by a trusted server webhook after provider verification.


-- Create booking requests through a trusted database function so the client
-- cannot choose an arbitrary price or mark a request as paid.
drop policy if exists "Customers create meetup requests" on public.meetup_bookings;
create or replace function public.create_meetup_booking(
  p_creator_id uuid,
  p_starts_at timestamptz,
  p_duration_minutes integer,
  p_meetup_option text
)
returns setof public.meetup_bookings
language plpgsql
security definer
set search_path = public
as $$
declare
  v_customer_id uuid := auth.uid();
  v_listing public.meetup_booking_profiles%rowtype;
  v_amount numeric(12,2);
  v_code text;
begin
  if v_customer_id is null then
    raise exception 'Sign in to request a meetup booking.';
  end if;
  if p_creator_id = v_customer_id then
    raise exception 'You cannot book your own meetup.';
  end if;
  if p_starts_at <= now() then
    raise exception 'Choose a future date and time.';
  end if;
  if p_duration_minutes < 30 or p_duration_minutes > 1440 or p_duration_minutes % 30 <> 0 then
    raise exception 'Choose a duration between 30 minutes and 24 hours.';
  end if;
  select * into v_listing
  from public.meetup_booking_profiles
  where user_id = p_creator_id and enabled = true;
  if not found then
    raise exception 'This creator is not accepting meetup bookings.';
  end if;
  if not (p_meetup_option = any(v_listing.meetup_options)) then
    raise exception 'Choose one of the meetup options offered by this creator.';
  end if;
  if p_duration_minutes = 240 then
    v_amount := v_listing.rate_half_day;
  elsif p_duration_minutes = 720 then
    v_amount := v_listing.rate_overnight;
  elsif p_duration_minutes < 240 then
    v_amount := floor(p_duration_minutes / 60.0) * v_listing.rate_hour
      + ((p_duration_minutes % 60) / 30) * v_listing.rate_30_min;
  elsif p_duration_minutes < 720 then
    v_amount := v_listing.rate_half_day
      + ceil((p_duration_minutes - 240) / 60.0) * v_listing.rate_hour;
  else
    v_amount := v_listing.rate_overnight
      + ceil((p_duration_minutes - 720) / 60.0) * v_listing.rate_hour;
  end if;
  v_code := 'FC-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));
  return query
  insert into public.meetup_bookings(
    booking_code, creator_id, customer_id, starts_at, duration_minutes,
    meetup_option, total_amount, currency, status
  ) values (
    v_code, p_creator_id, v_customer_id, p_starts_at, p_duration_minutes,
    p_meetup_option, v_amount, v_listing.currency, 'awaiting_payment'
  )
  returning *;
end;
$$;
revoke all on function public.create_meetup_booking(uuid,timestamptz,integer,text) from public;
grant execute on function public.create_meetup_booking(uuid,timestamptz,integer,text) to authenticated;
