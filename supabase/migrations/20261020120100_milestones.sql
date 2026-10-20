-- Milestones: account achievements a member earns by using Checkpoint (their
-- first game, 100 games, a 7-day streak, a year as a member...), and the flair
-- they unlock: an avatar frame, a title under the name and up to three badges
-- showcased on the profile. Not to be confused with Steam achievements, which
-- are per game and come from Steam.
--
--   milestones                 the catalog: what each milestone counts
--                              (`metric`), how many it takes (`threshold`), and
--                              the frame or title it unlocks, if any. Seeded
--                              below; must match `milestones` in
--                              lib/models/milestone.dart, which adds the names,
--                              descriptions, icons and points (a test compares
--                              the two).
--   user_milestones            one row per milestone a member has earned, with
--                              when. Kept forever: removing games or unfollowing
--                              never takes one away.
--   award_milestones(offset)   what the app calls: works out everything the
--                              caller has done from their own rows, records each
--                              milestone newly reached and returns those.
--   award_milestones_for       the same for any member; internal (the backfill
--                              below, and award_milestones).
--
--   profiles.avatar_frame          the frame drawn around the photo (a frame id
--                                  of `milestones.frame`); NULL: none
--   profiles.title_milestone       the milestone whose title shows under the
--                                  name; NULL: none
--   profiles.showcased_milestones  up to three milestones shown on the profile
--
-- History counts. Every metric is read from what is already in the database
-- (library, sessions, completions, ratings, lists, follows, completion times,
-- Steam achievement counts, two-factor and the join date), so nothing starts
-- from zero, and the migration ends by awarding every existing member what they
-- have already earned. Unlock dates are the real ones where the data has them:
-- the 10th game's `date_added` for "10 games", the first session's `logged_at`,
-- the join date plus a year for "member for a year". Amounts with no date of
-- their own (hours, ratings, genres...) are dated when they are awarded.
--
-- Time of day: streaks and Night Owl go by the member's own days, so the app
-- sends its UTC offset. The backfill doesn't know it and uses UTC; the app's
-- next call adds anything that only counts in local time.
--
-- Who sees what: any signed-in member reads anyone's milestones (they are on
-- the profile, like the rest of it). Nobody writes them but the functions. A
-- member sets their own frame, title and showcase, and a trigger refuses
-- anything they have not unlocked.
--
-- Deploy order: apply this migration, then ship the app build that uses it.
-- Older builds don't read the new columns or call the function, so nothing
-- changes for them; their members' milestones are awarded by the backfill and
-- on their first launch of a new build.

-- 1. The catalog ----------------------------------------------------------------

create table if not exists public.milestones (
  id        text primary key,
  metric    text not null,
  threshold numeric not null check (threshold > 0),
  -- An id the app knows (AvatarFrame in lib/models/milestone.dart).
  frame     text unique,
  title     text unique
);

comment on table public.milestones is
  'The milestones members can earn: what each counts, how many it takes, and the frame or title it unlocks. Must match lib/models/milestone.dart.';

alter table public.milestones enable row level security;

drop policy if exists milestones_select on public.milestones;
create policy milestones_select
  on public.milestones
  for select
  to authenticated
  using (true);

revoke all on public.milestones from public, anon, authenticated;
grant select on public.milestones to authenticated;

insert into public.milestones (id, metric, threshold, frame, title) values
  -- Library: games in it, any status.
  ('library_1', 'library_games', 1, null, null),
  ('library_10', 'library_games', 10, 'bronze', null),
  ('library_50', 'library_games', 50, 'silver', null),
  ('library_100', 'library_games', 100, 'gold', 'Collector'),
  ('library_200', 'library_games', 200, 'prism', null),
  ('library_500', 'library_games', 500, 'platinum', 'Hoarder'),
  ('library_1000', 'library_games', 1000, null, null),
  -- Logbook: sessions the member logged (the Steam sync's don't count).
  ('sessions_1', 'sessions', 1, null, null),
  ('sessions_10', 'sessions', 10, null, null),
  ('sessions_50', 'sessions', 50, null, null),
  ('sessions_100', 'sessions', 100, null, null),
  ('sessions_500', 'sessions', 500, null, 'Chronicler'),
  -- Playtime: hours over the whole library, and in a single game.
  ('hours_10', 'hours', 10, null, null),
  ('hours_100', 'hours', 100, null, null),
  ('hours_500', 'hours', 500, 'neon', null),
  ('hours_1000', 'hours', 1000, null, 'Touch Grass'),
  ('game_hours_100', 'game_hours', 100, null, 'Devoted'),
  -- Finisher: completed games, and completion times added.
  ('completed_1', 'completed', 1, null, null),
  ('completed_10', 'completed', 10, null, null),
  ('completed_25', 'completed', 25, 'laurel', 'Finisher'),
  ('completed_50', 'completed', 50, null, null),
  ('completed_100', 'completed', 100, null, 'Completionist'),
  ('completion_time_1', 'completion_times', 1, null, null),
  -- Streaks: days in a row with a session; a session between midnight and 4.
  ('streak_3', 'streak_days', 3, null, null),
  ('streak_7', 'streak_days', 7, null, null),
  ('streak_30', 'streak_days', 30, 'ember', 'Marathoner'),
  ('night_owl', 'night_sessions', 1, null, 'Night Owl'),
  -- Critic: games rated, reviews written.
  ('rated_1', 'rated', 1, null, null),
  ('rated_25', 'rated', 25, null, null),
  ('rated_100', 'rated', 100, null, null),
  ('reviews_1', 'reviews', 1, null, null),
  ('reviews_10', 'reviews', 10, null, 'Critic'),
  ('reviews_50', 'reviews', 50, null, null),
  -- Curator: lists.
  ('lists_1', 'lists', 1, null, 'Curator'),
  ('public_list', 'public_lists', 1, null, null),
  ('list_size_25', 'list_size', 25, null, null),
  -- Variety, over the games actually played.
  ('platforms_3', 'platforms', 3, null, null),
  ('platforms_5', 'platforms', 5, null, null),
  ('genres_10', 'genres', 10, null, null),
  ('retro_1', 'retro_games', 1, null, null),
  ('decades_4', 'decades', 4, null, 'Time Traveler'),
  -- Social.
  ('following_1', 'following', 1, null, null),
  ('followers_1', 'followers', 1, null, null),
  ('followers_10', 'followers', 10, null, null),
  ('followers_50', 'followers', 50, null, 'Socialite'),
  -- Membership: calendar months since joining, and joining in the first year.
  ('member_1m', 'member_months', 1, null, null),
  ('member_3m', 'member_months', 3, null, null),
  ('member_6m', 'member_months', 6, null, null),
  ('member_1y', 'member_months', 12, 'veteran', 'Veteran'),
  ('member_2y', 'member_months', 24, null, null),
  ('member_3y', 'member_months', 36, null, 'Old Guard'),
  ('member_5y', 'member_months', 60, null, 'Legend'),
  ('founding_member', 'founding_member', 1, 'founder', 'Founder'),
  -- Account.
  ('profile_complete', 'profile_complete', 1, null, null),
  ('favorites_4', 'favorites', 4, null, null),
  ('wishlist_10', 'wishlist', 10, null, null),
  ('dropped_1', 'dropped', 1, null, null),
  ('steam_connected', 'steam_connected', 1, null, null),
  ('two_factor', 'two_factor', 1, 'shield', null),
  ('perfect_game', 'perfect_games', 1, null, 'Perfectionist')
on conflict (id) do update
  set metric = excluded.metric,
      threshold = excluded.threshold,
      frame = excluded.frame,
      title = excluded.title;

-- 2. What members earned -----------------------------------------------------------

create table if not exists public.user_milestones (
  user_id      uuid not null references auth.users (id) on delete cascade,
  milestone_id text not null references public.milestones (id) on delete cascade,
  unlocked_at  timestamptz not null default now(),
  primary key (user_id, milestone_id)
);

comment on table public.user_milestones is
  'The milestones each member has earned, and when. Readable by signed-in members; written only by award_milestones.';

alter table public.user_milestones enable row level security;

drop policy if exists user_milestones_select on public.user_milestones;
create policy user_milestones_select
  on public.user_milestones
  for select
  to authenticated
  using (true);

-- The two-factor rule of 20261019135155_require_mfa.sql, like the other member data.
drop policy if exists user_milestones_aal2_if_mfa on public.user_milestones;
create policy user_milestones_aal2_if_mfa
  on public.user_milestones
  as restrictive
  for all
  to authenticated
  using ((select public.mfa_satisfied()))
  with check ((select public.mfa_satisfied()));

revoke all on public.user_milestones from public, anon, authenticated;
grant select on public.user_milestones to authenticated;

-- 3. Awarding ------------------------------------------------------------------------

-- Everything [target] has reached, recorded with when it was reached; returns the
-- milestones that were new. Runs as its owner: only award_milestones and this
-- migration call it.
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
           ug.achievements_unlocked, ug.achievements_total,
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
    union all select 'perfect_games', count(*) filter (
        where achievements_total > 0 and achievements_unlocked >= achievements_total
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
    union all select 'steam_connected', count(*) from public.profiles p
      where p.id = target and nullif(btrim(p.steam_id), '') is not null
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

-- The signed-in member's new milestones. [utc_offset_minutes] is the device's
-- offset from UTC (CET in winter: 60), for streaks and Night Owl.
create or replace function public.award_milestones(utc_offset_minutes integer default 0)
returns table (milestone_id text, unlocked_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null or not (select public.mfa_satisfied()) then
    return;
  end if;
  return query
    select a.milestone_id, a.unlocked_at
    from public.award_milestones_for((select auth.uid()), utc_offset_minutes) as a;
end;
$$;

comment on function public.award_milestones(integer) is
  'Awards the signed-in member every milestone they have reached and returns the new ones (20261020120100_milestones.sql).';

revoke all on function public.award_milestones(integer) from public, anon, authenticated;
grant execute on function public.award_milestones(integer) to authenticated;

-- 4. Flair on the profile ---------------------------------------------------------------

alter table public.profiles
  add column if not exists avatar_frame text,
  add column if not exists title_milestone text,
  add column if not exists showcased_milestones text[] not null default '{}';

comment on column public.profiles.avatar_frame is
  'The frame around the member''s photo: a milestones.frame they have unlocked. NULL: none.';
comment on column public.profiles.title_milestone is
  'The milestone whose title shows under the member''s name; one with a title that they have unlocked. NULL: none.';
comment on column public.profiles.showcased_milestones is
  'Up to three milestones the member has unlocked, shown on their profile.';

-- Members only wear what they earned. The service role is not checked.
create or replace function public.profiles_check_flair()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  is_new constant boolean := tg_op = 'INSERT';
begin
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;

  if new.avatar_frame is not null
     and (is_new or new.avatar_frame is distinct from old.avatar_frame)
     and not exists (
       select 1
       from public.user_milestones um
       join public.milestones m on m.id = um.milestone_id
       where um.user_id = new.id and m.frame = new.avatar_frame
     ) then
    raise exception 'That frame is not unlocked yet.' using errcode = 'check_violation';
  end if;

  if new.title_milestone is not null
     and (is_new or new.title_milestone is distinct from old.title_milestone)
     and not exists (
       select 1
       from public.user_milestones um
       join public.milestones m on m.id = um.milestone_id
       where um.user_id = new.id
         and m.id = new.title_milestone
         and m.title is not null
     ) then
    raise exception 'That title is not unlocked yet.' using errcode = 'check_violation';
  end if;

  if is_new or new.showcased_milestones is distinct from old.showcased_milestones then
    if cardinality(new.showcased_milestones) > 3
       or cardinality(new.showcased_milestones)
          <> (select count(distinct x) from unnest(new.showcased_milestones) as x)
       or exists (
         select 1
         from unnest(new.showcased_milestones) as x
         where not exists (
           select 1 from public.user_milestones um
           where um.user_id = new.id and um.milestone_id = x
         )
       ) then
      raise exception 'Showcase up to three different milestones you have unlocked.'
        using errcode = 'check_violation';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists profiles_check_flair on public.profiles;
create trigger profiles_check_flair
  before insert or update on public.profiles
  for each row execute function public.profiles_check_flair();

-- 5. Public views -------------------------------------------------------------------
-- Columns can only be added at the END of an existing view. public_profiles is as
-- in 20261018210000_steam_achievements_privacy.sql, public_followers and
-- public_following as in 20261017140000_public_profiles_and_social_graph.sql.

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
         p.show_steam_achievements,
         p.avatar_frame,
         p.title_milestone,
         p.showcased_milestones
  from public.profiles p;

create or replace view public.public_followers
  with (security_invoker = false) as
  select f.followee_id as user_id,
         p.id,
         p.handle,
         p.display_name,
         p.avatar_url,
         f.created_at as followed_at,
         p.avatar_frame,
         p.showcased_milestones
  from public.social_follows f
  join public.profiles p on p.id = f.follower_id;

create or replace view public.public_following
  with (security_invoker = false) as
  select f.follower_id as user_id,
         p.id,
         p.handle,
         p.display_name,
         p.avatar_url,
         f.created_at as followed_at,
         p.avatar_frame,
         p.showcased_milestones
  from public.social_follows f
  join public.profiles p on p.id = f.followee_id;

-- 6. Backfill -------------------------------------------------------------------------
-- Every member gets what they have already earned, dated when they earned it.

select count(*)
from public.profiles p
cross join lateral public.award_milestones_for(p.id, 0) as awarded;
