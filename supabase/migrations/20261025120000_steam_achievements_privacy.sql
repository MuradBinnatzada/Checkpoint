-- "Show Steam Achievements" in Settings > Privacy.
--
-- A member can now keep their Steam achievements to themselves. The choice is
-- `profiles.show_steam_achievements` (default true, so nothing changes for anyone
-- until they turn it off), written by the member on their own row like the rest of
-- their profile.
--
-- Turned off, other members get none of their achievements, whatever they call:
--
--   public_achievement_totals    returns no row
--   public_achievement_summary   returns no rows
--   public_game_achievements     returns NULL
--   sync-achievements            answers ACHIEVEMENTS_HIDDEN (403) for another
--                                member's game, before reading the stored list or
--                                asking Steam
--
-- The member themselves still gets everything: their own profile always shows
-- their achievements. The flag is also on `public_profiles`, so the app knows to
-- leave the Achievements card off the page instead of showing it empty.
--
-- Deploy order: apply this migration, then deploy `sync-achievements` (it reads the
-- new column), then ship the app (the profile page selects the column from
-- public_profiles and fails to load until it exists).

-- 1. The setting -------------------------------------------------------------
alter table public.profiles
  add column if not exists show_steam_achievements boolean not null default true;

comment on column public.profiles.show_steam_achievements is
  'Whether other members may see this member''s Steam achievements (Settings > Privacy). The member always sees their own.';

-- 2. Public profile header ----------------------------------------------------
-- Columns can only be added at the END of an existing view. The first seventeen
-- are those of 20261023120000_member_list_counts.sql.
create or replace view public.public_profiles
  with (security_invoker = false) as
  select p.id,
         p.handle,
         p.display_name,
         p.avatar_url,
         (nullif(btrim(p.steam_id), '') is not null) as steam_connected,
         p.connected_services,
         p.bio,
         p.steam_id,
         p.psn_id,
         p.xbox_id,
         p.discord_id,
         p.created_at as joined_at,
         p.instagram_id,
         p.twitch_id,
         (select count(*)::integer from public.user_games ug
          where ug.user_id = p.id) as games_count,
         (select count(*)::integer from public.social_follows f
          where f.followee_id = p.id) as followers_count,
         exists (
           select 1 from public.social_follows f
           where f.follower_id = (select auth.uid()) and f.followee_id = p.id
         ) as viewer_follows,
         p.show_steam_achievements
  from public.profiles p;

comment on view public.public_profiles is
  'Public fields of every profile, readable by any signed-in user: name, handle, avatar, bio, linked services and their account names, member since, game and follower counts, whether the caller follows them, and whether they share their Steam achievements. Never add email.';

revoke all on public.public_profiles from public, anon, authenticated;
grant select on public.public_profiles to authenticated;

-- 3. Achievements, only for the member or when they share them ------------------
-- Same signatures, grants and rules as before (20261017140000, 20261021120000), plus
-- the condition at the end of each WHERE: the caller is the member, or the member
-- shares their achievements. SECURITY DEFINER, so `profiles` is read whatever its
-- row policies say.
create or replace function public.public_achievement_summary(target_user uuid)
returns table (game_id uuid, title text, cover_url text, unlocked integer, total integer)
language sql
stable
security definer
set search_path = ''
as $$
  select ug.game_id, g.title, g.cover_url, ug.achievements_unlocked, ug.achievements_total
  from public.user_games ug
  join public.games g on g.id = ug.game_id
  where ug.user_id = target_user
    and (select auth.uid()) is not null
    and ug.achievements_unlocked > 0
    and ug.achievements_total > 0
    and (
      target_user = (select auth.uid())
      or exists (
        select 1 from public.profiles p
        where p.id = target_user and p.show_steam_achievements
      )
    )
  order by ug.achievements_unlocked::numeric / ug.achievements_total desc,
           ug.achievements_unlocked desc,
           g.title,
           ug.game_id
  limit 500
$$;

-- An aggregate always returns a row, so the check is a HAVING: a member who hides
-- their achievements gets no row at all rather than zeros, which the app reads as
-- "none".
create or replace function public.public_achievement_totals(target_user uuid)
returns table (unlocked integer, total integer, games integer, completed_games integer)
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(sum(ug.achievements_unlocked), 0)::integer,
         coalesce(sum(ug.achievements_total), 0)::integer,
         count(*)::integer,
         (count(*) filter (where ug.achievements_unlocked >= ug.achievements_total))::integer
  from public.user_games ug
  where ug.user_id = target_user
    and (select auth.uid()) is not null
    and ug.achievements_unlocked > 0
    and ug.achievements_total > 0
  having target_user = (select auth.uid())
      or exists (
        select 1 from public.profiles p
        where p.id = target_user and p.show_steam_achievements
      )
$$;

create or replace function public.public_game_achievements(target_user uuid, target_game uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select ug.achievements
  from public.user_games ug
  where ug.user_id = target_user
    and ug.game_id = target_game
    and (select auth.uid()) is not null
    and jsonb_typeof(ug.achievements) = 'array'
    and (
      target_user = (select auth.uid())
      or exists (
        select 1 from public.profiles p
        where p.id = target_user and p.show_steam_achievements
      )
    )
$$;

-- Functions are executable by PUBLIC unless revoked.
revoke all on function public.public_achievement_summary(uuid) from public, anon, authenticated;
revoke all on function public.public_achievement_totals(uuid) from public, anon, authenticated;
revoke all on function public.public_game_achievements(uuid, uuid) from public, anon, authenticated;
grant execute on function public.public_achievement_summary(uuid) to authenticated;
grant execute on function public.public_achievement_totals(uuid) to authenticated;
grant execute on function public.public_game_achievements(uuid, uuid) to authenticated;

notify pgrst, 'reload schema';

-- Fail loudly if the result is not what this file promises.
do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'profiles'
      and column_name = 'show_steam_achievements'
      and data_type = 'boolean' and is_nullable = 'NO'
      and column_default = 'true'
  ) then
    raise exception 'profiles.show_steam_achievements is not a non-null boolean defaulting to true';
  end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'public_profiles'
      and column_name = 'show_steam_achievements'
  ) then
    raise exception 'public.public_profiles has no show_steam_achievements column';
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

  if has_table_privilege('anon', 'public.public_profiles', 'select')
     or not has_table_privilege('authenticated', 'public.public_profiles', 'select') then
    raise exception 'public.public_profiles has the wrong grants';
  end if;

  if has_function_privilege('anon', 'public.public_achievement_summary(uuid)', 'execute')
     or has_function_privilege('anon', 'public.public_achievement_totals(uuid)', 'execute')
     or has_function_privilege('anon', 'public.public_game_achievements(uuid, uuid)', 'execute')
     or not has_function_privilege('authenticated', 'public.public_achievement_summary(uuid)', 'execute')
     or not has_function_privilege('authenticated', 'public.public_achievement_totals(uuid)', 'execute')
     or not has_function_privilege('authenticated', 'public.public_game_achievements(uuid, uuid)', 'execute') then
    raise exception 'the public achievement functions have the wrong grants';
  end if;
end;
$$;
