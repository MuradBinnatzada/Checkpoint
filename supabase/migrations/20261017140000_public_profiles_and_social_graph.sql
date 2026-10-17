-- Public profiles and the social graph.
--
-- What the app can now do, and what each part of this file gives it:
--
--   * Open another member's profile: name, @handle, avatar, whether they connected
--     Steam, their follower / following counts and their games (favorites, rated,
--     library).                     -> public_profiles, public_user_games, public_profile_stats
--   * Read who follows whom, for any member.   -> social_follows SELECT policy,
--                                                public_followers, public_following
--   * Read another member's achievements, ON REQUEST ONLY.
--                                   -> public_achievement_summary, public_game_achievements
--
-- Design rule: other members' rows are never readable through the tables
-- themselves. `profiles` and `user_games` stay own-row-only, and everything the
-- app may show about someone else goes through a view or a function that lists its
-- columns explicitly, the same technique as `public_profiles`
-- (20261013130000_restrict_profiles_read_add_public_profiles.sql).
--
--   exposed to other members            never exposed
--   ----------------------------------  -------------------------------------------
--   handle, display name, avatar        email, steam_id (only "has one" is shown)
--   follow edges                        bio
--   status, rating, hours, played_on,   purchase_price, achievements (the JSONB is
--   date_added, favorite, catalog data  large and personal: see "Achievements" below)
--
-- Views and functions here run as their owner (SECURITY DEFINER semantics), which
-- is what lets them read rows the caller's own policies hide. They are safe only
-- because of the explicit column lists: when you add a column to the underlying
-- table, nothing appears here until you add it on purpose. Supabase's linter flags
-- them as "security definer view"; that is intentional.
--
-- Deploy order: apply this migration before shipping the app build that uses it.
-- Reads of the new views / functions fail until it exists.

-- 1. social_follows ----------------------------------------------------------
-- The table was created in the dashboard, so this is a no-op where it exists. On a
-- fresh database it creates what the app expects: one row per (follower, followee),
-- gone with either account. 20261017120000_enforce_row_ownership.sql already
-- limits INSERT and DELETE to the follower's own rows.
create table if not exists public.social_follows (
  follower_id uuid not null references auth.users (id) on delete cascade,
  followee_id uuid not null references auth.users (id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (follower_id, followee_id)
);

-- Lists are shown newest follow first, so the table needs to know when each one
-- happened. Existing rows get the time of this migration.
alter table public.social_follows
  add column if not exists created_at timestamptz not null default now();

-- Nobody follows themselves. NOT VALID: new and updated rows are checked, rows that
-- already exist are not (so a stray old row can't fail the deploy). To enforce on
-- old rows too, once this returns nothing:
--   select * from public.social_follows where follower_id = followee_id;
-- run:
--   alter table public.social_follows validate constraint social_follows_no_self_follow;
alter table public.social_follows drop constraint if exists social_follows_no_self_follow;
alter table public.social_follows
  add constraint social_follows_no_self_follow
  check (follower_id <> followee_id) not valid;

-- "Who follows X" and "who does X follow", newest first, one index each. (The
-- primary key already answers "does A follow B".)
create index if not exists social_follows_followee_created_idx
  on public.social_follows (followee_id, created_at desc);
create index if not exists social_follows_follower_created_idx
  on public.social_follows (follower_id, created_at desc);

alter table public.social_follows enable row level security;

-- Any signed-in member can read the follow graph: follower and following lists are
-- public inside the app. Writes stay limited to your own edges by the restrictive
-- policies from 20261017120000_enforce_row_ownership.sql; they are not repeated here.
-- (anon has no grant on the table, see that migration.)
drop policy if exists social_follows_select_authenticated on public.social_follows;
create policy social_follows_select_authenticated
  on public.social_follows
  for select
  to authenticated
  using (true);

grant select, insert, delete on public.social_follows to authenticated;

-- 2. Public profile header ---------------------------------------------------
-- `steam_connected` says whether the member linked a Steam account, without the ID.
-- A column can only be added at the END of an existing view, so it goes last.
create or replace view public.public_profiles
  with (security_invoker = false) as
  select id,
         handle,
         display_name,
         avatar_url,
         (nullif(btrim(steam_id), '') is not null) as steam_connected
  from public.profiles;

comment on view public.public_profiles is
  'Public fields of every profile. Safe for any signed-in user to read. Never add email, steam_id or bio; steam_connected is a yes/no only.';

revoke all on public.public_profiles from public, anon, authenticated;
grant select on public.public_profiles to authenticated;

-- 3. Follower / following lists ----------------------------------------------
-- One row per edge, already joined to the other member's public fields, so a list
-- is a single request (PostgREST can't join through to `public_profiles`).
--   public_followers: the members who follow user_id.
--   public_following: the members user_id follows.
-- `id` is the OTHER member, like public_profiles.id.
create or replace view public.public_followers
  with (security_invoker = false) as
  select f.followee_id as user_id,
         p.id,
         p.handle,
         p.display_name,
         p.avatar_url,
         f.created_at as followed_at
  from public.social_follows f
  join public.profiles p on p.id = f.follower_id;

create or replace view public.public_following
  with (security_invoker = false) as
  select f.follower_id as user_id,
         p.id,
         p.handle,
         p.display_name,
         p.avatar_url,
         f.created_at as followed_at
  from public.social_follows f
  join public.profiles p on p.id = f.followee_id;

comment on view public.public_followers is
  'Members who follow user_id, with their public profile fields. Never add email or steam_id.';
comment on view public.public_following is
  'Members user_id follows, with their public profile fields. Never add email or steam_id.';

revoke all on public.public_followers, public.public_following from public, anon, authenticated;
grant select on public.public_followers, public.public_following to authenticated;

-- 4. Games of another member -------------------------------------------------
-- A member's library as other members see it: their tracking fields plus the
-- catalog data to draw a poster, flattened into one row (a view can't be
-- embedded like `games!inner(...)`). No purchase_price, no achievements.
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
         g.cover_url
  from public.user_games ug
  join public.games g on g.id = ug.game_id;

comment on view public.public_user_games is
  'What other members may see of a library. Never add purchase_price or achievements.';

revoke all on public.public_user_games from public, anon, authenticated;
grant select on public.public_user_games to authenticated;

-- "user_games" itself: your own rows only, whatever other policies exist. The view
-- above is the only way to see someone else's, and it leaves `achievements` out.
-- Without this, a broad SELECT policy created in the dashboard would let any member
-- run  GET /rest/v1/user_games?select=achievements  for everybody. Same technique as
-- profiles_select_own_only: a RESTRICTIVE policy is AND-ed with every permissive
-- one. The app only ever reads user_games with user_id = auth.uid() (library,
-- achievements, realtime), so nothing it does is affected. The service role
-- (Edge Functions) and the SECURITY DEFINER functions bypass RLS.
alter table public.user_games enable row level security;

drop policy if exists user_games_select_own on public.user_games;
create policy user_games_select_own
  on public.user_games
  as permissive
  for select
  to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists user_games_select_own_only on public.user_games;
create policy user_games_select_own_only
  on public.user_games
  as restrictive
  for select
  to public
  using (user_id = (select auth.uid()));

-- Faster "this member's favorites / best rated" reads for a profile page.
create index if not exists user_games_user_favorite_idx
  on public.user_games (user_id) where is_favorite;
create index if not exists user_games_user_rating_idx
  on public.user_games (user_id, rating desc) where rating > 0;

-- 5. Counts for a profile page -----------------------------------------------
-- Followers, following, whether the caller follows this member, and how many games
-- they have: one request for four numbers, none of them sensitive. Returns no row
-- when called without a session.
create or replace function public.public_profile_stats(target_user uuid)
returns table (followers integer, following integer, viewer_follows boolean, games integer)
language sql
stable
security definer
set search_path = ''
as $$
  select
    (select count(*)::integer from public.social_follows where followee_id = target_user),
    (select count(*)::integer from public.social_follows where follower_id = target_user),
    exists (
      select 1 from public.social_follows
      where follower_id = (select auth.uid()) and followee_id = target_user
    ),
    (select count(*)::integer from public.user_games where user_id = target_user)
  where (select auth.uid()) is not null
$$;

-- 6. Achievements, on request ------------------------------------------------
-- Achievements are not part of any payload above. A viewer asks for them
-- explicitly, in two steps so that nothing large is sent unasked:
--
--   public_achievement_summary(member)          one row per game that has any:
--                                               title, cover, unlocked / total.
--                                               Counted in SQL; no achievement
--                                               rows leave the database.
--   public_game_achievements(member, game)      the full list for ONE game.
--
-- A function rather than a policy because RLS works on rows, not columns: letting
-- members read each other's user_games rows would hand over `achievements` along
-- with them. Both need a signed-in caller (the grants below also keep anon out) and
-- return nothing for a member or game that has none.
create or replace function public.public_achievement_summary(target_user uuid)
returns table (game_id uuid, title text, cover_url text, unlocked integer, total integer)
language sql
stable
security definer
set search_path = ''
as $$
  select ug.game_id, g.title, g.cover_url, s.unlocked, s.total
  from public.user_games ug
  join public.games g on g.id = ug.game_id
  cross join lateral (
    select count(*) filter (where a ->> 'unlocked' = 'true')::integer as unlocked,
           count(*)::integer as total
    from jsonb_array_elements(
      case when jsonb_typeof(ug.achievements) = 'array' then ug.achievements else '[]'::jsonb end
    ) as a
  ) s
  where ug.user_id = target_user
    and (select auth.uid()) is not null
    and s.total > 0
  order by s.unlocked desc, s.total desc, g.title, ug.game_id
  limit 100
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
$$;

-- Functions are executable by PUBLIC unless revoked.
revoke all on function public.public_profile_stats(uuid) from public, anon, authenticated;
revoke all on function public.public_achievement_summary(uuid) from public, anon, authenticated;
revoke all on function public.public_game_achievements(uuid, uuid) from public, anon, authenticated;
grant execute on function public.public_profile_stats(uuid) to authenticated;
grant execute on function public.public_achievement_summary(uuid) to authenticated;
grant execute on function public.public_game_achievements(uuid, uuid) to authenticated;

notify pgrst, 'reload schema';

-- Fail loudly if the result is not what this file promises.
do $$
declare
  rel text;
begin
  foreach rel in array array['social_follows', 'user_games'] loop
    if not exists (
      select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public' and c.relname = rel and c.relrowsecurity
    ) then
      raise exception 'Row level security is not enabled on public.%', rel;
    end if;
  end loop;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'user_games'
      and cmd = 'SELECT' and permissive = 'RESTRICTIVE'
  ) then
    raise exception 'public.user_games has no restrictive SELECT policy';
  end if;

  -- The columns this file promises never to expose.
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name in ('public_profiles', 'public_followers', 'public_following', 'public_user_games')
      and column_name in ('email', 'steam_id', 'bio', 'purchase_price', 'achievements')
  ) then
    raise exception 'A public view exposes a column that must stay private';
  end if;
end;
$$;
