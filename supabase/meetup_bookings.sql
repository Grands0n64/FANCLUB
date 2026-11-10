-- FANCLUB meetup booking setup
create table if not exists public.meetup_booking_profiles (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  rate_30_min numeric(12,2) not null check (rate_30_min > 0),
  rate_hour numeric(12,2) not null check (rate_hour > 0),
  rate_half_day numeric(12,2) not null check (rate_half_day > 0),
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
  duration_minutes integer not null check (duration_minutes >= 30 and duration_minutes <= 480 and duration_minutes % 30 = 0),
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
