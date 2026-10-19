-- "From people you follow" on Home.
--
-- Home now shows what the members you follow did lately: the sessions they
-- logged, the games they completed and the ratings they gave, newest first, each
-- with their photo and the game's cover.
--
--   following_recent_activity(max_rows)   the newest events of the members the
--                                         caller follows, at most `max_rows`
--                                         (default 30, never more than 100)
--
-- One row per event:
--
--   kind         occurred_at   hours / rating
--   ----------   -----------   ----------------------------------------------
--   session      logged_at     hours of the session (rating 0)
--   completed    date_added    rating they gave, 0 if none (hours 0)
--   rated        date_added    rating they gave (hours 0); a rated game that is
--                              not completed, so a completed game shows once
--
-- Sessions count once per game and member: the latest one. A completion or a
-- rating is dated by `date_added`, because that is the only date
-- `public_user_games` has; a game completed or rated long after it was added
-- comes in at the date it was added, and the app shows no time for those two
-- kinds.
--
-- Nothing new is exposed. Every column is one the public views already give any
-- signed-in member: the profile fields of `public_profiles`, the sessions of
-- `public_recent_activity` (never the note) and the status, rating and
-- date_added of `public_user_games` (never purchase_price or achievements). Like
-- `following_game_activity` (20261018170000_friends_on_game_screen.sql) it runs as
-- its owner (SECURITY DEFINER) and names every column it returns: never add note,
-- purchase_price, achievements, email or steam_id. It saves the app from listing
-- everyone it follows and then each one's sessions and library.
--
-- Without a signed-in caller there is nobody to follow, so it returns no rows
-- (and anon may not call it at all).
--
-- Deploy order: apply this migration before shipping the app build that uses it.
-- Until then Home leaves the section out (the request fails quietly).

-- "Latest completed or rated games of this member". Sessions already have
-- log_entries_user_logged_idx (20261018120000_public_profile_details.sql).
create index if not exists user_games_user_added_idx
  on public.user_games (user_id, date_added desc);

create or replace function public.following_recent_activity(
  max_rows integer default 30
)
returns table (
  user_id uuid,
  handle text,
  display_name text,
  avatar_url text,
  game_id uuid,
  igdb_id public.games.igdb_id%type,
  steam_app_id public.games.steam_app_id%type,
  title public.games.title%type,
  publisher public.games.publisher%type,
  developer public.games.developer%type,
  release_year public.games.release_year%type,
  platforms public.games.platforms%type,
  genres public.games.genres%type,
  summary public.games.summary%type,
  cover_url public.games.cover_url%type,
  kind text,
  hours double precision,
  rating double precision,
  occurred_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  with cap as (
    select least(greatest(coalesce(max_rows, 30), 1), 100) as n
  ),
  followed as (
    select f.followee_id as user_id
    from public.social_follows f
    where f.follower_id = (select auth.uid())
      and f.followee_id <> (select auth.uid())
  ),
  -- Each member's newest sessions (no more than the feed can show), then the
  -- latest of each game.
  sessions as (
    select distinct on (s.user_id, s.game_id)
           s.user_id,
           s.game_id,
           'session'::text as kind,
           s.hours::double precision as hours,
           0::double precision as rating,
           s.logged_at::timestamptz as occurred_at
    from followed fo
    cross join cap
    cross join lateral (
      select l.user_id, l.game_id, l.hours, l.logged_at
      from public.log_entries l
      where l.user_id = fo.user_id
        and l.logged_at is not null
        and l.hours > 0
      order by l.logged_at desc
      limit cap.n
    ) s
    order by s.user_id, s.game_id, s.logged_at desc
  ),
  -- Each member's newest completed or rated games.
  library as (
    select u.user_id,
           u.game_id,
           case when u.status::text = 'completed' then 'completed' else 'rated' end
             as kind,
           0::double precision as hours,
           coalesce(u.rating, 0)::double precision as rating,
           u.date_added::timestamptz as occurred_at
    from followed fo
    cross join cap
    cross join lateral (
      select ug.user_id, ug.game_id, ug.status, ug.rating, ug.date_added
      from public.user_games ug
      where ug.user_id = fo.user_id
        and ug.date_added is not null
        and (ug.status::text = 'completed' or coalesce(ug.rating, 0) > 0)
      order by ug.date_added desc
      limit cap.n
    ) u
  ),
  events as (
    select * from sessions
    union all
    select * from library
  )
  select e.user_id,
         p.handle::text,
         p.display_name::text,
         p.avatar_url::text,
         e.game_id,
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
         e.kind,
         e.hours,
         e.rating,
         e.occurred_at
  from events e
  join public.profiles p on p.id = e.user_id
  join public.games g on g.id = e.game_id
  order by e.occurred_at desc, e.user_id, e.game_id, e.kind
  limit least(greatest(coalesce(max_rows, 30), 1), 100)
$$;

comment on function public.following_recent_activity(integer) is
  'Newest sessions, completions and ratings of the members the caller follows, with their public profile fields and the catalog game. Never add note, purchase_price, achievements, email or steam_id.';

-- Functions are executable by PUBLIC unless revoked.
revoke all on function public.following_recent_activity(integer) from public, anon, authenticated;
grant execute on function public.following_recent_activity(integer) to authenticated;

notify pgrst, 'reload schema';

-- Fail loudly if the result is not what this file promises.
do $$
declare
  fn constant regprocedure := 'public.following_recent_activity(integer)'::regprocedure;
begin
  if not (select prosecdef from pg_proc where oid = fn) then
    raise exception 'following_recent_activity must be SECURITY DEFINER';
  end if;

  -- None of the columns that stay private.
  if exists (
    select 1
    from pg_proc, unnest(proargnames) as arg(n)
    where oid = fn
      and arg.n in ('note', 'purchase_price', 'achievements', 'email', 'steam_id')
  ) then
    raise exception 'following_recent_activity returns a column that must stay private';
  end if;

  -- Signed-in members call it, anonymous callers do not.
  if has_function_privilege('anon', fn, 'execute')
     or not has_function_privilege('authenticated', fn, 'execute') then
    raise exception 'following_recent_activity has the wrong grants';
  end if;
end;
$$;
