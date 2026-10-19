-- Community completion times: how long members took to finish a game, and the
-- middle of those times on the game's screen.
--
-- A member who marks a game Completed can say how long it took them, in one of
-- three categories (HowLongToBeat's, which are also IGDB's hastily / normally /
-- completely):
--
--   main            Main Story
--   main_extra      Main + Extras
--   completionist   Completionist
--
--   completion_times              one row per member and game: the category and
--                                 the time in minutes. The app upserts on
--                                 (user_id, game_id), so a member has at most one
--                                 time per game, which they change or delete.
--   completion_time_stats(game)   one row per category of the game that has
--                                 times: their median, in minutes, and how many
--                                 there are.
--
-- Who sees what: a member reads, writes and deletes their own rows only; nobody
-- reads another member's. The function runs as its owner (SECURITY DEFINER) to
-- see every member's time, and returns only the median and the count of each
-- category, never a user id. The app shows a category's median once it has 5
-- times (`minCommunityTimes` in lib/models/completion_time.dart), and IGDB's
-- figure until then.
--
-- Outliers: times under 10 minutes or over 1 000 hours are left out of the
-- median and the count (a typo, or a game left running), though the table keeps
-- them. The median is what keeps the remaining extremes from pulling the figure,
-- so the fastest and slowest 10% are not trimmed as well: taking the same number
-- of times off both ends never moves a median.
--
-- A time belongs to the member's library row for the game (a foreign key on
-- (user_id, game_id), cascading deletes and updates): removing the game
-- (remove_library_game, clear_library) or the account removes it, and when
-- merge_game_into or merge_user_game_into move a library row to another game the
-- time moves with it (folding it into a row the member already has there keeps
-- that row's time). It stays when the game moves away from Completed.
--
-- The two-factor rule of 20261019135155_require_mfa.sql covers the table and the
-- function like the other member-owned data.
--
-- Deploy order: apply this migration before shipping the app build that uses it.
-- That build reads the member's own times with the library (`completion_times`
-- embedded in the user_games query), which fails until the table exists.

create table if not exists public.completion_times (
  user_id    uuid not null default auth.uid(),
  game_id    uuid not null,
  category   text not null
    constraint completion_times_category_check
    check (category in ('main', 'main_extra', 'completionist')),
  -- Up to 100 000 hours, the limit on a game's total (20261019013500).
  minutes    integer not null
    constraint completion_times_minutes_range
    check (minutes between 1 and 6000000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, game_id),
  constraint completion_times_user_game_fkey
    foreign key (user_id, game_id)
    references public.user_games (user_id, game_id)
    on update cascade
    on delete cascade
);

-- completion_time_stats reads a game's times by category, minutes in order.
create index if not exists completion_times_game_idx
  on public.completion_times (game_id, category, minutes);

comment on table public.completion_times is
  'How long a member took to finish a game in their library, in one category. Own rows only; everyone''s are summed up by completion_time_stats.';

-- 1. Row level security -------------------------------------------------------

alter table public.completion_times enable row level security;

drop policy if exists completion_times_select_own on public.completion_times;
create policy completion_times_select_own
  on public.completion_times
  for select
  to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists completion_times_insert_own on public.completion_times;
create policy completion_times_insert_own
  on public.completion_times
  for insert
  to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists completion_times_update_own on public.completion_times;
create policy completion_times_update_own
  on public.completion_times
  for update
  to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop policy if exists completion_times_delete_own on public.completion_times;
create policy completion_times_delete_own
  on public.completion_times
  for delete
  to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists completion_times_aal2_if_mfa on public.completion_times;
create policy completion_times_aal2_if_mfa
  on public.completion_times
  as restrictive
  for all
  to authenticated
  using ((select public.mfa_satisfied()))
  with check ((select public.mfa_satisfied()));

revoke all on public.completion_times from anon;
revoke truncate, references, trigger on public.completion_times from authenticated;
grant select, insert, update, delete on public.completion_times to authenticated;

-- 2. Bookkeeping ----------------------------------------------------------------

create or replace function public.completion_times_touch()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists completion_times_touch on public.completion_times;
create trigger completion_times_touch
  before update on public.completion_times
  for each row execute function public.completion_times_touch();

-- 3. What the game's screen shows ----------------------------------------------

create or replace function public.completion_time_stats(target_game uuid)
returns table (category text, median_minutes integer, submissions integer)
language sql
stable
security definer
set search_path = ''
as $$
  select ct.category,
         round(percentile_cont(0.5) within group (order by ct.minutes))::integer,
         count(*)::integer
  from public.completion_times ct
  where ct.game_id = target_game
    and ct.minutes between 10 and 60000
    and (select auth.uid()) is not null
    and (select public.mfa_satisfied())
  group by ct.category
  order by ct.category
$$;

comment on function public.completion_time_stats(uuid) is
  'Per category of target_game: the median of the members'' completion times (10 minutes to 1000 hours) and how many there are. Never return a user id or a single member''s row.';

-- Functions are executable by PUBLIC unless revoked.
revoke all on function public.completion_time_stats(uuid) from public, anon, authenticated;
grant execute on function public.completion_time_stats(uuid) to authenticated;

notify pgrst, 'reload schema';

-- Fail loudly if the result is not what this file promises.
do $$
declare
  fn regprocedure := 'public.completion_time_stats(uuid)'::regprocedure;
begin
  if not exists (
    select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'completion_times' and c.relrowsecurity
  ) then
    raise exception 'Row level security is not enabled on public.completion_times';
  end if;
  if has_table_privilege('anon', 'public.completion_times', 'select') then
    raise exception 'anon can read public.completion_times';
  end if;
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'completion_times'
      and policyname = 'completion_times_aal2_if_mfa'
      and permissive = 'RESTRICTIVE' and cmd = 'ALL'
  ) then
    raise exception 'public.completion_times has no restrictive two-factor policy';
  end if;
  if exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'completion_times'
      and permissive = 'PERMISSIVE'
      and coalesce(qual, '') not like '%auth.uid()%'
      and coalesce(with_check, '') not like '%auth.uid()%'
  ) then
    raise exception 'public.completion_times has a policy that is not limited to the member''s own rows';
  end if;

  if not (select prosecdef from pg_proc where oid = fn) then
    raise exception '% must be SECURITY DEFINER', fn;
  end if;
  if (select prosrc from pg_proc where oid = fn) not like '%public.mfa_satisfied()%' then
    raise exception '% does not check two-factor authentication', fn;
  end if;
  if has_function_privilege('anon', fn, 'execute')
     or not has_function_privilege('authenticated', fn, 'execute') then
    raise exception '% has the wrong grants', fn;
  end if;
end;
$$;
