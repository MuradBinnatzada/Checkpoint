-- Achievement counts for every Steam game, not only the ones opened.
--
-- Until now a game's achievements existed only once its owner had pressed "Load
-- Steam Achievements" on its screen (the whole list, in user_games.achievements),
-- so a profile listed just those few games. The counts are now kept on their own,
-- for every Steam game of a library:
--
--   achievements_unlocked / achievements_total
--       How many the member has unlocked, out of how many the game has. Written by
--       the `sync-steam` Edge Function for every game played since it last counted
--       (one small Steam request per game, see achievements_playtime), and kept in
--       step with the full list by the trigger below whenever that list is written.
--       NULL: never counted. 0 / 0: the game has no achievements.
--   achievements_playtime
--       The Steam playtime (minutes) of the game when sync-steam counted it. A game
--       not played since then cannot have unlocked anything new, so it is not asked
--       about again. NULL: never counted by sync-steam.
--   achievements_synced_at
--       When the full list (user_games.achievements) was last fetched from Steam.
--       Set by the trigger. `sync-achievements` uses it to answer other members
--       from the stored list instead of asking Steam again within a few minutes.
--
-- The profile reads the counts (public_achievement_summary, public_achievement_totals,
-- both redefined below to read the columns rather than count the JSONB), and a game's
-- full list is fetched when it is opened: from the database when it is up to date
-- with the counts, otherwise from Steam through `sync-achievements`, which may now do
-- that for another member's game too (the Steam data is theirs and public, see the
-- function's header). Only games with at least one achievement unlocked are listed and
-- counted on a profile, like Steam's own completion rate.
--
-- Who writes the columns: the Edge Functions, with the service role. Like
-- `achievements`, a member could write their own row's; that only changes what their
-- own profile shows.
--
-- Deploy order: apply this migration, then deploy `sync-steam` and `sync-achievements`,
-- then ship the app. The old functions keep working against it (the trigger keeps the
-- counts of the lists they write).

alter table public.user_games
  add column if not exists achievements_unlocked integer,
  add column if not exists achievements_total integer,
  add column if not exists achievements_playtime integer,
  add column if not exists achievements_synced_at timestamptz;

comment on column public.user_games.achievements_unlocked is
  'Steam achievements unlocked in this game. Written by sync-steam and by the trigger on achievements. NULL: never counted.';
comment on column public.user_games.achievements_total is
  'Steam achievements the game has (0: none). Written with achievements_unlocked.';
comment on column public.user_games.achievements_playtime is
  'Steam playtime in minutes when sync-steam last counted the achievements; not counted again until it changes.';
comment on column public.user_games.achievements_synced_at is
  'When the full achievement list (achievements) was last fetched from Steam. Set by the trigger.';

-- The counts of a full list, kept in step whatever writes the list. --------------
create or replace function public.user_games_count_achievements()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if jsonb_typeof(new.achievements) = 'array' then
    select count(*) filter (where a ->> 'unlocked' = 'true')::integer,
           count(*)::integer
      into new.achievements_unlocked, new.achievements_total
      from jsonb_array_elements(new.achievements) as a;
    new.achievements_synced_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists user_games_count_achievements on public.user_games;
create trigger user_games_count_achievements
  before insert or update of achievements on public.user_games
  for each row execute function public.user_games_count_achievements();

-- The lists stored before this migration. Their fetch time is unknown, so
-- achievements_synced_at stays NULL ("long ago").
update public.user_games ug
set achievements_total = jsonb_array_length(ug.achievements),
    achievements_unlocked = (
      select count(*)::integer
      from jsonb_array_elements(ug.achievements) as a
      where a ->> 'unlocked' = 'true'
    )
where jsonb_typeof(ug.achievements) = 'array'
  and ug.achievements_total is null;

create index if not exists user_games_achievements_unlocked_idx
  on public.user_games (user_id) where achievements_unlocked > 0;

-- Counts from sync-steam, many games in one call. ---------------------------------
-- `counts` is a JSON array of {game_id, unlocked, total, playtime}. Updates only:
-- a game no longer in the library is skipped, never added back. Service role only.
create or replace function public.set_achievement_counts(target_user uuid, counts jsonb)
returns integer
language sql
set search_path = ''
as $$
  with c as (
    select *
    from jsonb_to_recordset(counts) as x(game_id uuid, unlocked integer, total integer, playtime integer)
  ), updated as (
    update public.user_games ug
    set achievements_unlocked = c.unlocked,
        achievements_total = c.total,
        achievements_playtime = c.playtime
    from c
    where ug.user_id = target_user
      and ug.game_id = c.game_id
    returning 1
  )
  select count(*)::integer from updated
$$;

revoke all on function public.set_achievement_counts(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.set_achievement_counts(uuid, jsonb) to service_role;

-- What a profile shows, now from the columns. -------------------------------------
-- Same signatures, grants and rules as before (20261017140000, 20261018130000): a
-- signed-in caller only, SECURITY DEFINER because RLS works on rows and would hand
-- over the `achievements` JSONB with them, and nothing but counts in the result.
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
  order by ug.achievements_unlocked::numeric / ug.achievements_total desc,
           ug.achievements_unlocked desc,
           g.title,
           ug.game_id
  limit 500
$$;

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
$$;

revoke all on function public.public_achievement_summary(uuid) from public, anon, authenticated;
revoke all on function public.public_achievement_totals(uuid) from public, anon, authenticated;
grant execute on function public.public_achievement_summary(uuid) to authenticated;
grant execute on function public.public_achievement_totals(uuid) to authenticated;

notify pgrst, 'reload schema';

-- Fail loudly if the result is not what this file promises.
do $$
begin
  if has_function_privilege('anon', 'public.public_achievement_summary(uuid)', 'execute')
     or has_function_privilege('anon', 'public.public_achievement_totals(uuid)', 'execute')
     or not has_function_privilege('authenticated', 'public.public_achievement_summary(uuid)', 'execute')
     or not has_function_privilege('authenticated', 'public.public_achievement_totals(uuid)', 'execute') then
    raise exception 'the public achievement functions have the wrong grants';
  end if;
  if has_function_privilege('authenticated', 'public.set_achievement_counts(uuid, jsonb)', 'execute')
     or has_function_privilege('anon', 'public.set_achievement_counts(uuid, jsonb)', 'execute') then
    raise exception 'set_achievement_counts must be for the service role only';
  end if;
end;
$$;
