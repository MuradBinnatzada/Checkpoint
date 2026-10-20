-- Milestones that don't need Steam: PSN, Xbox and Nintendo players can earn
-- every one of them too.
--
-- 1. user_games.perfected: the member marks a game they got everything out of.
--    The app names it after where they played it (a Platinum trophy on PS3,
--    PS4, PS5 and Vita, every achievement on PC and Xbox, 100% anywhere else),
--    but it is the same flag everywhere. Self-reported, like hours and
--    completions: nothing checks it with Sony, Microsoft or Nintendo.
--    Other members see it (public_user_games), like the rating.
--
-- 2. Perfectionist (perfect_game) counts a game that is perfected, as well as
--    one with every Steam achievement unlocked, as before.
--
-- 3. The steam_connected milestone is now for connecting any game account:
--    Steam, or PSN, Xbox or Nintendo (profiles.connected_services). Its id stays
--    the same, so the members who earned it keep it, and keep showing it.
--
-- The backfill at the end awards it to the members who have only connected
-- PSN, Xbox or Nintendo. Nobody has a perfected game yet, so nothing else is
-- new.
--
-- Deploy order: apply this migration before shipping the app build that uses
-- it. That build reads and writes the column with the library, which fails
-- until it exists.

-- 1. The flag --------------------------------------------------------------------

alter table public.user_games
  add column if not exists perfected boolean not null default false;

comment on column public.user_games.perfected is
  'The member got everything out of the game: a Platinum trophy, every achievement or 100%, by where they played it. Self-reported. Public to signed-in members, like the rating.';

-- The view as in 20261019015200_completion_dates_reviews_release_dates.sql, with
-- perfected at the end: columns can only be added at the end of a view.
create or replace view public.public_user_games
  with (security_invoker = false) as
  select ug.user_id,
         ug.game_id,
         ug.status,
         ug.rating,
         ug.hours_played,
         ug.played_on,
         ug.date_added,
         ug.is_favorite,
         g.igdb_id,
         g.steam_app_id,
         g.title,
         g.publisher,
         g.developer,
         g.release_year,
         g.platforms,
         g.genres,
         g.summary,
         g.cover_url,
         ug.custom_backdrop_url,
         ug.review,
         ug.completed_at,
         ug.perfected
  from public.user_games ug
  join public.games g on g.id = ug.game_id;

-- 2. The catalog -------------------------------------------------------------------
-- In the same form as the rows of 20261020120100_milestones.sql (the catalog test
-- in test/milestones_test.dart reads both).

insert into public.milestones (id, metric, threshold, frame, title) values
  ('steam_connected', 'game_account', 1, null, null)
on conflict (id) do update
  set metric = excluded.metric,
      threshold = excluded.threshold,
      frame = excluded.frame,
      title = excluded.title;

-- 3. Awarding ------------------------------------------------------------------------
-- As in 20261020120100_milestones.sql, but for perfect_games and game_account.

create or replace function public.award_milestones_for(target uuid, utc_offset_minutes integer)
returns table (milestone_id text, unlocked_at timestamptz)
language sql
set search_path = ''
as $$
  with
  shift as (
    select make_interval(
      mins => greatest(-840, least(840, coalesce(utc_offset_minutes, 0)))
    ) as local_offset
  ),
  library as (
    select ug.status, ug.rating, ug.hours_played, ug.played_on, ug.date_added,
           ug.completed_at, ug.review, ug.is_favorite,
           ug.achievements_unlocked, ug.achievements_total, ug.perfected,
           g.genres, g.release_year
    from public.user_games ug
    join public.games g on g.id = ug.game_id
    where ug.user_id = target
  ),
  -- The games actually played, for the variety milestones.
  played as (
    select * from library
    where status in ('playing', 'completed', 'dropped') or hours_played > 0
  ),
  -- Sessions the member logged; the Steam sync's are its own bookkeeping.
  sessions as (
    select le.logged_at,
           le.platform,
           (le.logged_at at time zone 'UTC') + (select local_offset from shift) as local_at
    from public.log_entries le
    where le.user_id = target
      and le.source is distinct from 'steam'
  ),

  -- a. Dated events: "N of them" was reached when the Nth happened. Completions
  --    from before completed_at was kept have no date: they go after the dated
  --    ones (which "N completed" can't have come later than), and one of them
  --    that is the Nth is dated now.
  events (metric, reached_at) as (
    select 'library_games', date_added from library
    union all select 'wishlist', date_added from library where status = 'wishlist'
    union all select 'completed', completed_at from library where status = 'completed'
    union all select 'sessions', logged_at from sessions
    union all select 'night_sessions', logged_at from sessions
      where extract(hour from local_at) < 4
    union all select 'completion_times', ct.created_at
      from public.completion_times ct where ct.user_id = target
    union all select 'lists', gl.created_at
      from public.game_lists gl where gl.user_id = target
    union all select 'public_lists', gl.updated_at
      from public.game_lists gl where gl.user_id = target and gl.is_public
    union all select 'following', f.created_at
      from public.social_follows f where f.follower_id = target
    union all select 'followers', f.created_at
      from public.social_follows f where f.followee_id = target
  ),
  event_unlocks as (
    select m.id,
           (array_agg(e.reached_at order by e.reached_at nulls last))[m.threshold::integer]
             as reached_at
    from public.milestones m
    join events e on e.metric = m.metric
    group by m.id, m.threshold
    having count(*) >= m.threshold
  ),

  -- b. Amounts with no date of their own: reached now.
  amounts (metric, amount) as (
    select 'hours', coalesce(sum(hours_played), 0)::numeric from library
    union all select 'game_hours', coalesce(max(hours_played), 0)::numeric from library
    union all select 'rated', count(*) filter (where rating > 0) from library
    union all select 'reviews', count(*) filter (where btrim(review) <> '') from library
    union all select 'favorites', count(*) filter (where is_favorite) from library
    union all select 'dropped', count(*) filter (where status = 'dropped') from library
    -- Marked by the member (not on a wishlisted game, which they don't have),
    -- or every Steam achievement unlocked.
    union all select 'perfect_games', count(*) filter (
        where (perfected and status <> 'wishlist')
           or (achievements_total > 0 and achievements_unlocked >= achievements_total)
      ) from library
    union all select 'genres', count(distinct genre)
      from played cross join lateral unnest(played.genres) as genre
    union all select 'retro_games', count(*) filter (where release_year < 1995) from played
    union all select 'decades', count(distinct release_year / 10) from played
    union all select 'platforms', count(distinct platform) from (
        select played_on as platform from library where played_on is not null
        union
        select platform from sessions where platform is not null
      ) as used
    union all select 'list_size', coalesce(max(items), 0) from (
        select count(*) as items
        from public.game_list_items i
        join public.game_lists gl on gl.id = i.list_id
        where gl.user_id = target
        group by i.list_id
      ) as sizes
    union all select 'profile_complete', count(*) from public.profiles p
      where p.id = target
        and nullif(btrim(p.avatar_url), '') is not null
        and btrim(p.bio) <> ''
    union all select 'game_account', count(*) from public.profiles p
      where p.id = target
        and (nullif(btrim(p.steam_id), '') is not null
             or p.connected_services && array['psn', 'xbox', 'nintendo'])
    union all select 'two_factor', count(*) from auth.mfa_factors f
      where f.user_id = target and f.status = 'verified'
  ),
  amount_unlocks as (
    select m.id, now() as reached_at
    from public.milestones m
    join amounts a on a.metric = m.metric
    where a.amount >= m.threshold
  ),

  -- c. Days in a row with a session, in the member's own days: reached on the
  --    Nth day of the first run that long, at that day's first session.
  session_days as (
    select local_at::date as local_day, min(logged_at) as first_at
    from sessions
    group by local_at::date
  ),
  runs as (
    select local_day,
           local_day - (row_number() over (order by local_day))::integer as run_id
    from session_days
  ),
  run_lengths as (
    select run_id, min(local_day) as first_day, count(*) as run_days
    from runs
    group by run_id
  ),
  streak_unlocks as (
    select m.id, sd.first_at as reached_at
    from public.milestones m
    cross join lateral (
      select min(r.first_day) + (m.threshold::integer - 1) as local_day
      from run_lengths r
      where r.run_days >= m.threshold
    ) as reached
    join session_days sd on sd.local_day = reached.local_day
    where m.metric = 'streak_days'
  ),

  -- d. Membership: on the anniversary itself. Founding members joined before
  --    2027.
  member_unlocks as (
    select m.id, p.created_at + make_interval(months => m.threshold::integer) as reached_at
    from public.milestones m
    join public.profiles p on p.id = target
    where m.metric = 'member_months'
      and p.created_at + make_interval(months => m.threshold::integer) <= now()
    union all
    select m.id, p.created_at
    from public.milestones m
    join public.profiles p on p.id = target
    where m.metric = 'founding_member'
      and p.created_at < timestamptz '2027-01-01 00:00:00+00'
  ),

  earned as (
    select id, reached_at from event_unlocks
    union all select id, reached_at from amount_unlocks
    union all select id, reached_at from streak_unlocks
    union all select id, reached_at from member_unlocks
  )
  insert into public.user_milestones as um (user_id, milestone_id, unlocked_at)
  select target, e.id, least(coalesce(e.reached_at, now()), now())
  from earned e
  where target is not null
  on conflict (user_id, milestone_id) do nothing
  returning um.milestone_id, um.unlocked_at;
$$;

comment on function public.award_milestones_for(uuid, integer) is
  'Records every milestone the member has reached and returns the new ones. Internal: the app calls award_milestones.';

revoke all on function public.award_milestones_for(uuid, integer) from public, anon, authenticated;

-- 4. Backfill -------------------------------------------------------------------------
-- The members who connected a game account other than Steam earn the connected
-- milestone now.

select count(*)
from (
  select p.id
  from public.profiles p
  where p.connected_services && array['psn', 'xbox', 'nintendo']
) as members
cross join lateral public.award_milestones_for(members.id, 0) as awarded;

notify pgrst, 'reload schema';
