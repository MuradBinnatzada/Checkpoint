-- Profiles privacy: other members must not be able to read `email` or `steam_id`.
--
-- Problem: the app (fetchSocialUsers) needs to list other members, so the
-- `profiles` SELECT policy lets every signed-in user read every row. Selecting
-- only four columns in Dart doesn't help: anyone can call
--   GET /rest/v1/profiles?select=email,steam_id
-- with their own session token.
--
-- Fix:
--   1. `profiles` can only be read for your OWN row (id = auth.uid()).
--   2. Other members are read through `public_profiles`, a view that exposes
--      only id, handle, display_name and avatar_url.
--
-- The existing SELECT policy on `profiles` isn't defined in any migration, so I
-- can't know its name. Instead of guessing, step 1 adds a RESTRICTIVE policy.
-- Restrictive policies are AND-ed with every permissive policy, so even if an
-- old "viewable by everyone" policy is still there, reads stay limited to the
-- caller's own row. See the cleanup note at the bottom.
--
-- App changes that go with this (already made in Dart):
--   - fetchSocialUsers   reads public_profiles
--   - isHandleAvailable  reads public_profiles (it has to see OTHER users'
--                        handles, which `profiles` no longer allows)
-- Ship the new app build only after this migration is applied: before it, the
-- view doesn't exist and both queries fail.

alter table public.profiles enable row level security;

-- 1a. Permissive: you can read your own row (so this works even if the old
--     broad policy is later dropped).
drop policy if exists profiles_select_own on public.profiles;
create policy profiles_select_own
  on public.profiles
  for select
  to authenticated
  using (id = (select auth.uid()));

-- 1b. Restrictive: the guard. No other permissive policy can widen this.
--     Applies to `anon` too, which also gets no rows (auth.uid() is null).
drop policy if exists profiles_select_own_only on public.profiles;
create policy profiles_select_own_only
  on public.profiles
  as restrictive
  for select
  to public
  using (id = (select auth.uid()));

-- 2. Public view of other members.
--
-- Deliberately NOT security_invoker: it runs as its owner, so it can read every
-- row of `profiles` despite the policies above. That is safe only because the
-- view lists four non-sensitive columns. Do not add email, steam_id, bio, etc.
-- (Supabase's linter flags this as "security definer view"; here it's
-- intentional.)
create or replace view public.public_profiles
  with (security_invoker = false) as
  select id, handle, display_name, avatar_url
  from public.profiles;

comment on view public.public_profiles is
  'Public fields of every profile. Safe for any signed-in user to read. Never add email or steam_id.';

-- Supabase grants new relations in `public` to anon/authenticated by default.
-- This view is auto-updatable and runs as its owner, so leaving INSERT/UPDATE/
-- DELETE granted would let clients write to `profiles` through it, bypassing RLS.
revoke all on public.public_profiles from public, anon, authenticated;
grant select on public.public_profiles to authenticated;

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------------
-- Cleanup (optional, do by hand): find the old broad SELECT policy.
--
--   select policyname, permissive, roles, cmd, qual
--   from pg_policies
--   where schemaname = 'public' and tablename = 'profiles';
--
-- A permissive SELECT (or ALL) policy with qual = true is the one this
-- migration neutralises. It does nothing now, so you can drop it so the rules
-- are readable in one place:
--   drop policy "<name>" on public.profiles;
-- Only drop it if cmd = SELECT. If cmd = ALL, it also grants writes; replace
-- it with explicit own-row INSERT/UPDATE policies first.
-- ---------------------------------------------------------------------------
