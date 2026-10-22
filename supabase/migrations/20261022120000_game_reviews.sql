-- Game reviews: everyone's reviews on a game's screen, a community rating, and a
-- way to report a review.
--
-- Until now a review (user_games.review, 500 characters) only showed up on the
-- game's screen for the members you follow, inside the Friends panel. This adds:
--
--   user_games.reviewed_at       when the member last wrote or changed the review,
--                                to order reviews and say how old one is. Kept by
--                                a trigger; the app never sends it. Reviews
--                                written before this migration are dated by when
--                                the member completed or added the game.
--   review length                raised from 500 to 2000 characters: 500 is a
--                                comment, not a review.
--   game_reviews(game, ...)      one page of the reviews of a game, from every
--                                member: the author's public profile fields,
--                                their status, rating and hours, and the text.
--                                Filtered to the members the caller follows, or
--                                not, and ordered friends first, newest, highest
--                                or lowest rated.
--   game_review_stats(game)      how many members rated the game and wrote a
--                                review, the average rating, and how many gave
--                                each half star (the community rating).
--   review_reports               a member's report of another's review. Write
--                                only: nothing in the app reads it back, the
--                                reports are for whoever moderates (the Supabase
--                                dashboard). game_reviews leaves a review out for
--                                the member who reported it.
--
-- Nothing private is exposed: a review, a rating, the status and the hours are
-- already readable by every signed-in member through public_user_games, and the
-- profile fields come from public_profiles' own list. The functions run as their
-- owner (SECURITY DEFINER) and name every column they return: never add
-- purchase_price, achievements, email or steam_id. Like the other member-facing
-- functions they answer signed-in members who passed two-factor only
-- (20261019135155_require_mfa.sql).
--
-- Deploy order: apply this migration before shipping the app build that uses it.
-- Until then the game screen leaves the Reviews panel out (the requests fail
-- quietly), and a review is still cut to 500 characters by the old constraint.

-- 1. When a review was written --------------------------------------------------

alter table public.user_games
  add column if not exists reviewed_at timestamptz;

comment on column public.user_games.reviewed_at is
  'When the member last wrote or changed the review. Kept by the user_games_track_review trigger; NULL when there is no review.';

-- Reviews that exist already: dated by when the game was completed, or added. This
-- runs before the trigger below exists, which would otherwise keep the old NULL.
update public.user_games
   set reviewed_at = coalesce(completed_at, date_added, now())
 where btrim(review) <> ''
   and reviewed_at is null;

create or replace function public.user_games_track_review()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if btrim(coalesce(new.review, '')) = '' then
    new.reviewed_at := null;
  elsif tg_op = 'INSERT' or new.review is distinct from old.review then
    new.reviewed_at := now();
  else
    -- Not the member's to set: the date stays what it was.
    new.reviewed_at := old.reviewed_at;
  end if;
  return new;
end;
$$;

drop trigger if exists user_games_track_review on public.user_games;
create trigger user_games_track_review
  before insert or update on public.user_games
  for each row execute function public.user_games_track_review();

-- Reviews of a game are read newest first, and counted, so a game with many has
-- them in one index. (Only rows with a review are in it.)
create index if not exists user_games_game_reviews_idx
  on public.user_games (game_id, reviewed_at desc)
  where btrim(review) <> '';

-- 2. A review may be longer -----------------------------------------------------

alter table public.user_games
  drop constraint if exists user_games_review_length,
  add constraint user_games_review_length
    check (char_length(review) <= 2000);

comment on column public.user_games.review is
  'The member''s review of the game, at most 2000 characters; empty: none. Public to signed-in members, like the rating.';

-- 3. Reports --------------------------------------------------------------------

create table if not exists public.review_reports (
  reporter_id    uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  review_user_id uuid not null,
  game_id        uuid not null,
  reason         text not null
    constraint review_reports_reason_check
    check (reason in ('spam', 'abuse', 'other')),
  created_at     timestamptz not null default now(),
  -- One report per member and review: reporting again changes nothing.
  primary key (reporter_id, review_user_id, game_id),
  constraint review_reports_not_own
    check (reporter_id <> review_user_id),
  -- The review the report is about. A report goes with it when the member
  -- takes the game out of their library, or deletes their account.
  constraint review_reports_review_fkey
    foreign key (review_user_id, game_id)
    references public.user_games (user_id, game_id)
    on update cascade
    on delete cascade
);

comment on table public.review_reports is
  'A member''s report of another member''s review of a game. Write only for members: moderators read it in the dashboard.';

alter table public.review_reports enable row level security;

-- A member reports as themselves, and reads back only their own reports (an
-- INSERT ... ON CONFLICT needs to see the row it would conflict with).
drop policy if exists review_reports_select_own on public.review_reports;
create policy review_reports_select_own
  on public.review_reports
  for select
  to authenticated
  using (reporter_id = (select auth.uid()));

drop policy if exists review_reports_insert_own on public.review_reports;
create policy review_reports_insert_own
  on public.review_reports
  for insert
  to authenticated
  with check (reporter_id = (select auth.uid()));

drop policy if exists review_reports_aal2_if_mfa on public.review_reports;
create policy review_reports_aal2_if_mfa
  on public.review_reports
  as restrictive
  for all
  to authenticated
  using ((select public.mfa_satisfied()))
  with check ((select public.mfa_satisfied()));

revoke all on public.review_reports from public, anon, authenticated;
grant select, insert on public.review_reports to authenticated;

-- 4. What the game's screen shows -----------------------------------------------

-- The community rating of a game. `half_stars` has ten entries: how many members
-- gave 0.5, 1, 1.5 ... 5 stars. `average` is 0 when nobody rated it.
create or replace function public.game_review_stats(target_game uuid)
returns table (
  ratings integer,
  average double precision,
  reviews integer,
  half_stars integer[]
)
language sql
stable
security definer
set search_path = ''
as $$
  with allowed as (
    select (select auth.uid()) is not null and (select public.mfa_satisfied()) as ok
  ),
  buckets as (
    select round(ug.rating * 2)::integer as bucket, count(*)::integer as n
    from public.user_games ug, allowed
    where allowed.ok
      and ug.game_id = target_game
      and ug.rating > 0
    group by 1
  )
  select coalesce(sum(b.n), 0)::integer as ratings,
         coalesce(sum(b.n * b.bucket)::double precision / nullif(sum(b.n) * 2, 0), 0)
           as average,
         (select count(*)::integer
          from public.user_games ug, allowed
          where allowed.ok
            and ug.game_id = target_game
            and btrim(ug.review) <> '') as reviews,
         array(
           select coalesce((select b2.n from buckets b2 where b2.bucket = k), 0)
           from generate_series(1, 10) k
           order by k
         ) as half_stars
  from buckets b
$$;

comment on function public.game_review_stats(uuid) is
  'How many members rated target_game and reviewed it, the average rating, and how many gave each half star. Never return a user id or a single member''s row.';

-- One page of the reviews of a game, by every member. `sort_by` is:
--   friends   the members the caller follows first, then newest (the default)
--   newest    latest review first
--   highest   best rating first, unrated last
--   lowest    worst rating first, unrated last
-- `only_following` keeps just the members the caller follows. A review the caller
-- reported is left out. The caller's own review is in the list (`is_own`).
create or replace function public.game_reviews(
  target_game uuid,
  only_following boolean default false,
  sort_by text default 'friends',
  page_size integer default 20,
  page_offset integer default 0
)
returns table (
  id uuid,
  handle text,
  display_name text,
  avatar_url text,
  avatar_frame text,
  showcased_milestones text[],
  status text,
  rating double precision,
  hours_played double precision,
  review text,
  reviewed_at timestamptz,
  is_following boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select r.id, r.handle, r.display_name, r.avatar_url, r.avatar_frame,
         r.showcased_milestones, r.status, r.rating, r.hours_played, r.review,
         r.reviewed_at, r.is_following
  from (
    select p.id,
           p.handle::text as handle,
           p.display_name::text as display_name,
           p.avatar_url::text as avatar_url,
           p.avatar_frame::text as avatar_frame,
           p.showcased_milestones as showcased_milestones,
           ug.status::text as status,
           coalesce(ug.rating, 0)::double precision as rating,
           coalesce(ug.hours_played, 0)::double precision as hours_played,
           ug.review::text as review,
           coalesce(ug.reviewed_at, ug.date_added)::timestamptz as reviewed_at,
           exists (
             select 1 from public.social_follows f
             where f.follower_id = (select auth.uid()) and f.followee_id = ug.user_id
           ) as is_following
    from public.user_games ug
    join public.profiles p on p.id = ug.user_id
    where ug.game_id = target_game
      and btrim(ug.review) <> ''
      and (select auth.uid()) is not null
      and (select public.mfa_satisfied())
      and not exists (
        select 1 from public.review_reports rr
        where rr.reporter_id = (select auth.uid())
          and rr.review_user_id = ug.user_id
          and rr.game_id = ug.game_id
      )
  ) r
  where not coalesce(only_following, false) or r.is_following
  order by
    case when coalesce(sort_by, 'friends') = 'friends' then r.is_following end desc nulls last,
    case when sort_by = 'highest' then (r.rating > 0) end desc nulls last,
    case when sort_by = 'highest' then r.rating end desc nulls last,
    case when sort_by = 'lowest' then (r.rating > 0) end desc nulls last,
    case when sort_by = 'lowest' then r.rating end asc nulls last,
    r.reviewed_at desc nulls last,
    r.id
  limit least(greatest(coalesce(page_size, 20), 1), 50)
  offset greatest(coalesce(page_offset, 0), 0)
$$;

comment on function public.game_reviews(uuid, boolean, text, integer, integer) is
  'A page of the reviews of target_game by every member: public profile fields, status, rating, hours, review text and date. Never add purchase_price, achievements, email or steam_id.';

-- Functions are executable by PUBLIC unless revoked.
revoke all on function public.game_review_stats(uuid) from public, anon, authenticated;
revoke all on function public.game_reviews(uuid, boolean, text, integer, integer) from public, anon, authenticated;
grant execute on function public.game_review_stats(uuid) to authenticated;
grant execute on function public.game_reviews(uuid, boolean, text, integer, integer) to authenticated;

notify pgrst, 'reload schema';

-- Fail loudly if the result is not what this file promises.
do $$
declare
  stats constant regprocedure := 'public.game_review_stats(uuid)'::regprocedure;
  page constant regprocedure :=
    'public.game_reviews(uuid, boolean, text, integer, integer)'::regprocedure;
begin
  if not (select prosecdef from pg_proc where oid = stats)
     or not (select prosecdef from pg_proc where oid = page) then
    raise exception 'The review functions must be SECURITY DEFINER';
  end if;

  if has_function_privilege('anon', stats, 'execute')
     or has_function_privilege('anon', page, 'execute')
     or not has_function_privilege('authenticated', stats, 'execute')
     or not has_function_privilege('authenticated', page, 'execute') then
    raise exception 'The review functions have the wrong grants';
  end if;

  if not exists (
    select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'review_reports' and c.relrowsecurity
  ) then
    raise exception 'Row level security is not enabled on public.review_reports';
  end if;
  if has_table_privilege('anon', 'public.review_reports', 'select')
     or has_table_privilege('authenticated', 'public.review_reports', 'update')
     or has_table_privilege('authenticated', 'public.review_reports', 'delete') then
    raise exception 'public.review_reports has the wrong grants';
  end if;
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'review_reports'
      and policyname = 'review_reports_aal2_if_mfa'
      and permissive = 'RESTRICTIVE' and cmd = 'ALL'
  ) then
    raise exception 'public.review_reports has no restrictive two-factor policy';
  end if;
  if exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'review_reports'
      and permissive = 'PERMISSIVE'
      and coalesce(qual, '') not like '%auth.uid()%'
      and coalesce(with_check, '') not like '%auth.uid()%'
  ) then
    raise exception 'public.review_reports has a policy that is not limited to the member''s own reports';
  end if;
end;
$$;
