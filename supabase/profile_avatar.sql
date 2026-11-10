-- Run this in Supabase SQL Editor to enable member profile photos.
alter table public.profiles
add column if not exists avatar_url text;

-- The existing fanclub-media storage bucket is used by the app for profile photo files.
