-- Instagram and Twitch on the profile.
--
-- The Connected accounts box on a profile now lists Game profiles (Steam, PSN, Xbox,
-- Nintendo) and Social media (Discord, Instagram, Twitch). Discord was already
-- stored; this adds the two new services the same way:
--
--   * their NAMES in `profiles.connected_services` ('instagram', 'twitch'), so a
--     member who connected one is told apart from one who did not;
--   * the username the member typed, in `profiles.instagram_id` and
--     `profiles.twitch_id`, which is what the link on the profile opens
--     (instagram.com/<name>, twitch.tv/<name>).
--
-- Like the PSN / Xbox / Discord names (20261018120000_public_profile_details.sql)
-- they are public to other SIGNED-IN members only: anon has no access to the view.
-- Update the privacy policy page together with this migration (docs/privacy.html).
--
-- Deploy order: apply this migration before shipping the app build that uses it.
-- The profile page selects the new columns from public_profiles, and the app writes
-- them to `profiles`, so both fail until they exist.

-- 1. Account names ------------------------------------------------------------
alter table public.profiles
  add column if not exists instagram_id text,
  add column if not exists twitch_id text;

-- A client can write anything to its own row, so the names are bounded the same way
-- as the others. Real ones are far shorter (Instagram 30, Twitch 25).
alter table public.profiles drop constraint if exists profiles_account_names_length;
alter table public.profiles
  add constraint profiles_account_names_length
  check (
    char_length(psn_id) <= 64
    and char_length(xbox_id) <= 64
    and char_length(discord_id) <= 64
    and char_length(instagram_id) <= 64
    and char_length(twitch_id) <= 64
  );

comment on column public.profiles.instagram_id is
  'Instagram username the member entered, without "@". Public to signed-in members (the profile link opens it).';
comment on column public.profiles.twitch_id is
  'Twitch username the member entered. Public to signed-in members (the profile link opens it).';

-- 2. The list of connected services -------------------------------------------
-- The constraint from 20261017150000_public_connected_services.sql knew four
-- names; it now knows six. Existing rows hold a subset of the old four, so they
-- still pass.
alter table public.profiles drop constraint if exists profiles_connected_services_known;
alter table public.profiles
  add constraint profiles_connected_services_known
  check (
    connected_services <@ array['discord', 'instagram', 'nintendo', 'psn', 'twitch', 'xbox']
    and cardinality(connected_services) <= 6
  );

comment on column public.profiles.connected_services is
  'Names of the services the member connected: discord, instagram, nintendo, psn, twitch, xbox. Steam is derived from steam_id. Public (shown on the profile).';

-- 3. Public profile header ----------------------------------------------------
-- Columns can only be added at the END of an existing view. The first twelve are
-- those of 20261018120000_public_profile_details.sql.
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
         created_at as joined_at,
         instagram_id,
         twitch_id
  from public.profiles;

comment on view public.public_profiles is
  'Public fields of every profile, readable by any signed-in user: name, handle, avatar, bio, linked services and their account names, member since. Never add email.';

revoke all on public.public_profiles from public, anon, authenticated;
grant select on public.public_profiles to authenticated;

notify pgrst, 'reload schema';

-- Fail loudly if the result is not what this file promises.
do $$
begin
  if (
    select count(*) from information_schema.columns
    where table_schema = 'public' and table_name = 'public_profiles'
      and column_name in ('instagram_id', 'twitch_id')
  ) <> 2 then
    raise exception 'public.public_profiles is missing instagram_id or twitch_id';
  end if;

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
  ) or not exists (
    select 1 from pg_constraint
    where conrelid = 'public.profiles'::regclass
      and conname = 'profiles_connected_services_known'
  ) then
    raise exception 'A profiles constraint is missing';
  end if;

  -- Signed-in members read it, anonymous callers do not.
  if has_table_privilege('anon', 'public.public_profiles', 'select')
     or not has_table_privilege('authenticated', 'public.public_profiles', 'select') then
    raise exception 'public.public_profiles has the wrong grants';
  end if;
end;
$$;
