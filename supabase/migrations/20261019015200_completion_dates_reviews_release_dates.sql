-- Completion dates, short reviews and exact release dates.
--
-- 1. user_games.completed_at: when the member last marked the game completed, for
--    the Year in Review. A trigger keeps it: set when the status becomes
--    completed, kept while it stays so, cleared when it changes. The app never
--    sends it. Games completed before this migration have none (the date was
--    never recorded); the app counts those in the year they were last played.
--
-- 2. user_games.review: a short review next to the rating, at most 500
--    characters ('' = none). Other signed-in members see it like the rating:
--    public_user_games and following_game_activity (the Friends panel on a game's
--    screen) now return it.
--
-- 3. games.release_date: the day IGDB says the game first came out, written by
--    igdb-handler and sync-steam with the rest of the catalog row, and by the app
--    when it adds a game from search. Wishlist release alerts read it.
--
-- 4. following_recent_activity (Home's "From people you follow"): a completion is
--    dated by completed_at when there is one, instead of when the game was added.
--
-- Nothing private is exposed: completed_at and review join the public columns of
-- public_user_games; purchase_price, achievements and the session notes stay out.
--
-- Deploy order: apply this migration, then deploy igdb-handler and sync-steam,
-- then ship the app build (its library read asks for the new columns).

-- 1. Completion dates ----------------------------------------------------------

alter table public.user_games
  add column if not exists completed_at timestamptz;

comment on column public.user_games.completed_at is
  'When the member last marked the game completed. Kept by the user_games_track_completion trigger; NULL when not completed, or completed before the date was recorded.';

create or replace function public.user_games_track_completion()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.status = 'completed' then
    new.completed_at := case
      when tg_op = 'INSERT' or old.status is distinct from 'completed' then now()
      else old.completed_at
    end;
  else
    new.completed_at := null;
  end if;
  return new;
end;
$$;

drop trigger if exists user_games_track_completion on public.user_games;
create trigger user_games_track_completion
  before insert or update on public.user_games
  for each row execute function public.user_games_track_completion();

-- 2. Reviews -------------------------------------------------------------------

alter table public.user_games
  add column if not exists review text not null default '';

alter table public.user_games
  drop constraint if exists user_games_review_length,
  add constraint user_games_review_length
    check (char_length(review) <= 500);

comment on column public.user_games.review is
  'The member''s short review of the game, at most 500 characters; empty: none. Public to signed-in members, like the rating.';

-- 3. Release dates -------------------------------------------------------------

alter table public.games
  add column if not exists release_date date;

comment on column public.games.release_date is
  'The day the game first came out, from IGDB (first_release_date). NULL: IGDB has no exact date yet.';

-- 4. What other members see ---------------------------------------------------

-- The same view as in 20261018190000_custom_game_backdrop.sql, with review and
-- completed_at at the end. Dropped and made again rather than replaced: the live
-- view was changed outside the migrations (its 19th column is custom_cover_url),
-- and `create or replace view` can only add columns after the existing ones, so
-- it can't line up with every copy. Nothing depends on the view, and its grants
-- are set again below.
drop view if exists public.public_user_games;
create view public.public_user_games
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
         ug.completed_at
  from public.user_games ug
  join public.games g on g.id = ug.game_id;

comment on view public.public_user_games is
  'What other members may see of a library. Never add purchase_price, achievements or steam_playtime_minutes.';

revoke all on public.public_user_games from public, anon, authenticated;
grant select on public.public_user_games to authenticated;

-- The Friends panel shows reviews too. Its result gains a column, which
-- `create or replace` can't do, so the function is made again with the same
-- body as in 20261018170000_friends_on_game_screen.sql plus `review`.
drop function if exists public.following_game_activity(uuid, integer);
create function public.following_game_activity(
  target_game uuid,
  per_status integer default 20
)
returns table (
  id uuid,
  handle text,
  display_name text,
  avatar_url text,
  status text,
  rating double precision,
  date_added timestamptz,
  status_total integer,
  review text
)
language sql
stable
security definer
set search_path = ''
as $$
  select r.id, r.handle, r.display_name, r.avatar_url,
         r.status, r.rating, r.date_added, r.status_total, r.review
  from (
    select p.id,
           p.handle::text as handle,
           p.display_name::text as display_name,
           p.avatar_url::text as avatar_url,
           ug.status::text as status,
           coalesce(ug.rating, 0)::double precision as rating,
           ug.date_added::timestamptz as date_added,
           count(*) over (partition by ug.status)::integer as status_total,
           coalesce(ug.review, '')::text as review,
           row_number() over (
             partition by ug.status
             order by (coalesce(ug.rating, 0) > 0) desc,
                      ug.date_added desc nulls last,
                      p.id
           ) as position
    from public.social_follows f
    join public.user_games ug
      on ug.user_id = f.followee_id and ug.game_id = target_game
    join public.profiles p on p.id = f.followee_id
    where f.follower_id = (select auth.uid())
      and ug.status is not null
  ) r
  where r.position <= least(greatest(coalesce(per_status, 20), 1), 50)
  order by r.status, r.position
$$;

comment on function public.following_game_activity(uuid, integer) is
  'Members the caller follows who have target_game: public profile fields, status, rating, date_added, review. Never add purchase_price, achievements, email or steam_id.';

revoke all on function public.following_game_activity(uuid, integer) from public, anon, authenticated;
grant execute on function public.following_game_activity(uuid, integer) to authenticated;

-- Home's friends feed: the same function as in
-- 20261018220000_following_recent_activity.sql, with completions dated by
-- completed_at when there is one.
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
  library as (
    select u.user_id,
           u.game_id,
           case when u.status::text = 'completed' then 'completed' else 'rated' end
             as kind,
           0::double precision as hours,
           coalesce(u.rating, 0)::double precision as rating,
           u.occurred_at
    from followed fo
    cross join cap
    cross join lateral (
      select ug.user_id, ug.game_id, ug.status, ug.rating,
             (case when ug.status::text = 'completed'
                   then coalesce(ug.completed_at, ug.date_added)
                   else ug.date_added end)::timestamptz as occurred_at
      from public.user_games ug
      where ug.user_id = fo.user_id
        and ug.date_added is not null
        and (ug.status::text = 'completed' or coalesce(ug.rating, 0) > 0)
      order by 5 desc
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

notify pgrst, 'reload schema';

-- Fail loudly if the result is not what this file promises.
do $$
declare
  feed constant regprocedure := 'public.following_recent_activity(integer)'::regprocedure;
  friends constant regprocedure := 'public.following_game_activity(uuid, integer)'::regprocedure;
begin
  if not (select prosecdef from pg_proc where oid = friends)
     or not (select prosecdef from pg_proc where oid = feed) then
    raise exception 'The friends functions must be SECURITY DEFINER';
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name in (
        'public_profiles', 'public_followers', 'public_following',
        'public_user_games', 'public_recent_activity'
      )
      and column_name in ('email', 'purchase_price', 'achievements', 'note', 'steam_playtime_minutes')
  ) then
    raise exception 'A public view exposes a column that must stay private';
  end if;

  if has_function_privilege('anon', friends, 'execute')
     or not has_function_privilege('authenticated', friends, 'execute')
     or has_table_privilege('anon', 'public.public_user_games', 'select')
     or not has_table_privilege('authenticated', 'public.public_user_games', 'select') then
    raise exception 'The friends function or public_user_games has the wrong grants';
  end if;
end;
$$;
