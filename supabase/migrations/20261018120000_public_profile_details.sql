-- Public profile details: bio, linked accounts and recent activity.
--
-- A member's profile page now shows what their own profile page shows: the bio,
-- the services they linked as icons that open their account (Steam, Xbox and PSN
-- profile pages; Discord copies the username), and their latest play sessions.
--
-- This REVERSES three rules the earlier public-profile migrations set, on purpose:
--
--   rule in 20261013130000 / 20261017140000 / 20261017150000    now
--   ---------------------------------------------------------   -----------------------
--   "never expose bio"                                           bio is public
--   "never expose steam_id" (only a yes/no)                      steam_id is public
--   PSN / Xbox / Discord names stay on the member's device       stored, and public
--
-- They are public to other SIGNED-IN members only (anon has no access to any of
-- this), the same audience that already sees the name, handle, avatar, follows and
-- library. They are what makes the icons tappable. A Steam ID64 is the number in
-- steamcommunity.com/profiles/<id>, which Steam itself shows publicly; the game
-- details of the Steam profile stay governed by the member's Steam privacy setting.
-- Update the privacy policy page together with this migration (docs/privacy.html).
--
-- Still never exposed: email, purchase_price, achievements (only through the
-- on-request functions) and the NOTE of a play session.
--
-- Deploy order: apply this migration before shipping the app build that uses it.
-- The profile page reads the new columns from public_profiles.

-- 1. Account names ------------------------------------------------------------
-- What the member typed when linking the service: PSN id, Xbox gamertag, Discord
-- username. NULL = not linked (or linked before this version: the app uploads the
-- name the next time it runs). Written by the app from the member's own session,
-- like display_name or steam_id. Nintendo has no name; it is only a flag in
-- connected_services.
alter table public.profiles
  add column if not exists psn_id text,
  add column if not exists xbox_id text,
  add column if not exists discord_id text;

-- A client can write anything to its own row, so the names are bounded. Real ones
-- are far shorter (PSN 16, Xbox 15, Discord 32).
alter table public.profiles drop constraint if exists profiles_account_names_length;
alter table public.profiles
  add constraint profiles_account_names_length
  check (
    char_length(psn_id) <= 64
    and char_length(xbox_id) <= 64
    and char_length(discord_id) <= 64
  );

comment on column public.profiles.psn_id is
  'PSN id the member entered. Public to signed-in members (the profile icon links to it).';
comment on column public.profiles.xbox_id is
  'Xbox gamertag the member entered. Public to signed-in members (the profile icon links to it).';
comment on column public.profiles.discord_id is
  'Discord username the member entered. Public to signed-in members (the profile icon copies it).';

-- 2. Public profile header ----------------------------------------------------
-- Columns can only be added at the END of an existing view. The first six are
-- those of 20261017150000_public_connected_services.sql.
create or replace view public.public_profiles
  with (security_invoker = false) as
  select id,
         handle,
         display_name,
         avatar_url,
         (nullif(btrim(steam_id), '') is not null) as steam_connected,
         connected_services,
         bio,
         steam_id,
         psn_id,
         xbox_id,
         discord_id,
         created_at as joined_at
  from public.profiles;

comment on view public.public_profiles is
  'Public fields of every profile, readable by any signed-in user: name, handle, avatar, bio, linked services and their account names, member since. Never add email.';

revoke all on public.public_profiles from public, anon, authenticated;
grant select on public.public_profiles to authenticated;

-- 3. Recent play sessions -----------------------------------------------------
-- One row per logged session with the catalog data to draw it. The NOTE is left out:
-- it is free text the member wrote for themselves.
create or replace view public.public_recent_activity
  with (security_invoker = false) as
  select l.id,
         l.user_id,
         l.game_id,
         l.hours,
         l.platform,
         l.logged_at,
         g.igdb_id,
         g.steam_app_id,
         g.title,
         g.publisher,
         g.developer,
         g.release_year,
         g.platforms,
         g.genres,
         g.summary,
         g.cover_url
  from public.log_entries l
  join public.games g on g.id = l.game_id;

comment on view public.public_recent_activity is
  'Play sessions of any member (game, hours, platform, when) for the profile page. Never add note.';

revoke all on public.public_recent_activity from public, anon, authenticated;
grant select on public.public_recent_activity to authenticated;

-- "Latest sessions of this member".
create index if not exists log_entries_user_logged_idx
  on public.log_entries (user_id, logged_at desc);

notify pgrst, 'reload schema';

-- Fail loudly if the result is not what this file promises.
do $$
begin
  -- Still none of the columns that stay private.
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name in (
        'public_profiles', 'public_followers', 'public_following',
        'public_user_games', 'public_recent_activity'
      )
      and column_name in ('email', 'purchase_price', 'achievements', 'note')
  ) then
    raise exception 'A public view exposes a column that must stay private';
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.profiles'::regclass
      and conname = 'profiles_account_names_length'
  ) then
    raise exception 'profiles_account_names_length is missing';
  end if;

  -- Signed-in members read them, anonymous callers do not.
  if has_table_privilege('anon', 'public.public_profiles', 'select')
     or has_table_privilege('anon', 'public.public_recent_activity', 'select')
     or not has_table_privilege('authenticated', 'public.public_profiles', 'select')
     or not has_table_privilege('authenticated', 'public.public_recent_activity', 'select') then
    raise exception 'The public views have the wrong grants';
  end if;
end;
$$;
