-- Connected services on public profiles.
--
-- Until now another member's profile could only show Steam as connected, because
-- `profiles.steam_id` is the only service data the server holds. PSN, Xbox and
-- Discord names are kept on the owner's device, and Nintendo has no stored id at
-- all, so nothing else could be told apart from "not connected".
--
-- This adds one column, `profiles.connected_services`: the NAMES of the services
-- the member has connected, written by the app from the member's own session
-- (the own-row UPDATE policies from 20261017120000_enforce_row_ownership.sql
-- already allow it, the same way display_name or steam_id are written).
--
--   stored in connected_services        never stored, never exposed
--   ----------------------------------  -------------------------------------------
--   'psn', 'xbox', 'discord',           the PSN / Xbox / Discord usernames (they stay
--   'nintendo'                          on the device), the Steam ID
--
-- Steam is not in the list: it stays derived from `steam_id`, so the two can never
-- disagree (`steam_connected` on public_profiles, from the previous migration).
--
-- Deploy order: apply this migration before shipping the app build that uses it.
-- The app selects `connected_services` from public_profiles, so a profile fails to
-- load until the column is in the view.

-- 1. The column --------------------------------------------------------------
-- Existing rows get the empty list, which is also the right answer for a member
-- who has not connected anything. The constraint keeps the list to the names
-- above (and short, because the value is copied into every read of the view): the
-- app only ever writes those, and a client can write anything to its own row.
alter table public.profiles
  add column if not exists connected_services text[] not null default '{}';

alter table public.profiles drop constraint if exists profiles_connected_services_known;
alter table public.profiles
  add constraint profiles_connected_services_known
  check (
    connected_services <@ array['discord', 'nintendo', 'psn', 'xbox']
    and cardinality(connected_services) <= 4
  );

comment on column public.profiles.connected_services is
  'Names of the gaming services the member connected: discord, nintendo, psn, xbox. Steam is derived from steam_id. Public (shown on the profile); the account names behind them are never stored.';

-- 2. Public profile header ---------------------------------------------------
-- A column can only be added at the END of an existing view, so it goes last. The
-- columns before it are exactly those of 20261017140000_public_profiles_and_social_graph.sql.
create or replace view public.public_profiles
  with (security_invoker = false) as
  select id,
         handle,
         display_name,
         avatar_url,
         (nullif(btrim(steam_id), '') is not null) as steam_connected,
         connected_services
  from public.profiles;

comment on view public.public_profiles is
  'Public fields of every profile. Safe for any signed-in user to read. Never add email, steam_id, bio or the PSN / Xbox / Discord account names; steam_connected is a yes/no only and connected_services holds service names, nothing else.';

revoke all on public.public_profiles from public, anon, authenticated;
grant select on public.public_profiles to authenticated;

notify pgrst, 'reload schema';

-- Fail loudly if the result is not what this file promises.
do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'public_profiles'
      and column_name = 'connected_services'
  ) then
    raise exception 'public.public_profiles has no connected_services column';
  end if;

  -- Still none of the private columns, nor any column that would hold an account name.
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name in ('public_profiles', 'public_followers', 'public_following', 'public_user_games')
      and column_name in (
        'email', 'steam_id', 'bio', 'purchase_price', 'achievements',
        'psn_id', 'xbox_id', 'discord_id'
      )
  ) then
    raise exception 'A public view exposes a column that must stay private';
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.profiles'::regclass
      and conname = 'profiles_connected_services_known'
  ) then
    raise exception 'profiles_connected_services_known is missing';
  end if;

  -- Signed-in members read it, anonymous callers do not.
  if has_table_privilege('anon', 'public.public_profiles', 'select')
     or not has_table_privilege('authenticated', 'public.public_profiles', 'select') then
    raise exception 'public.public_profiles has the wrong grants';
  end if;
end;
$$;
