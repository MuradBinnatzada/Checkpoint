-- Two-factor authentication: an account that has it on only counts as signed in
-- once the session entered its code.
--
-- Settings > Security turns on a code from an authenticator app (Supabase Auth
-- MFA, TOTP). After the password, Google or Apple, the app asks for the code
-- before anything else, and a right one makes the session aal2 (the `aal` claim
-- of its access token). The app's prompt alone could be stepped around: the
-- session from the password alone (aal1) is a valid token for the API. So the
-- server applies the same rule:
--
-- 1. public.mfa_satisfied(): true when the caller's token is aal2, or when the
--    caller has no verified factor in auth.mfa_factors (two-factor is off, so
--    aal1 is all there is). SECURITY DEFINER because the client roles can't read
--    auth.mfa_factors. Without a session (anon, service role) there is no
--    factor, so it is true.
--
-- 2. A RESTRICTIVE policy `<table>_aal2_if_mfa`, for all commands, on the
--    member-owned tables: profiles, user_games, log_entries, social_follows,
--    game_lists and game_list_items. Restrictive policies are AND-ed with every
--    permissive one, so an aal1 session of an account with two-factor on reads
--    and writes nothing there, its own rows included, until it enters the code.
--    The same for avatar uploads (storage.objects in the `avatars` bucket).
--    Accounts without two-factor see no change; the service role bypasses RLS.
--
-- 3. The SECURITY DEFINER functions members call run as their owner, past those
--    policies, so each gets the same check next to its "signed in" one:
--    public_profile_stats, public_achievement_summary, public_achievement_totals,
--    public_game_achievements, following_game_activity, following_recent_activity.
--    Otherwise the bodies, signatures and grants are those of 20261017140000,
--    20261018210000 and 20261019015200 (one added line each). The other
--    SECURITY DEFINER functions (steam_sync_due, invoke_steam_background_sync)
--    are for the service role and cron only.
--
-- 4. The Edge Functions apply the rule themselves (they use the service role):
--    sync-steam, sync-achievements, delete-account and igdb-handler read the
--    caller's factors from getUser() and the token's `aal` claim, and answer
--    MFA_REQUIRED (403). See supabase/functions/_shared/mfa.ts.
--
-- Not changed: the public_* views also run as their owner, but they show only
-- what every signed-in member may see of anyone, so an aal1 session learns
-- nothing there that a brand-new account couldn't.
--
-- Supabase itself ends the account's aal1 sessions on other devices when the
-- first code is verified, and only lets an aal2 session remove the factor.
--
-- Setup: Authentication > Multi-Factor in the dashboard must have Authenticator
-- app (TOTP) turned on (the default); supabase/config.toml turns it on for
-- `supabase start`. Deploy this migration with the Edge Functions
-- (deploy-supabase.yml does both), then ship the app. An account that turns
-- two-factor on can't use app builds from before this change: they never ask
-- for the code, and the server refuses their aal1 session.

-- 1. The rule ------------------------------------------------------------------

create or replace function public.mfa_satisfied()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(auth.jwt() ->> 'aal', '') = 'aal2'
      or not exists (
        select 1 from auth.mfa_factors f
        where f.user_id = (select auth.uid())
          and f.status = 'verified'
      )
$$;

comment on function public.mfa_satisfied() is
  'Whether the caller''s session passed two-factor authentication: aal2, or no verified factor (20261019135155_require_mfa.sql).';

-- The policies run it as the member.
revoke all on function public.mfa_satisfied() from public, anon, authenticated;
grant execute on function public.mfa_satisfied() to authenticated;

-- 2. Member-owned tables ---------------------------------------------------------

-- (select ...) makes Postgres work it out once per statement, not once per row.
do $$
declare
  tbl text;
begin
  foreach tbl in array array[
    'profiles', 'user_games', 'log_entries', 'social_follows', 'game_lists', 'game_list_items'
  ] loop
    execute format('drop policy if exists %I on public.%I', tbl || '_aal2_if_mfa', tbl);
    execute format(
      'create policy %I on public.%I as restrictive for all to authenticated '
      'using ((select public.mfa_satisfied())) with check ((select public.mfa_satisfied()))',
      tbl || '_aal2_if_mfa', tbl
    );
  end loop;
end;
$$;

drop policy if exists "Avatar uploads need the two-factor code when it is on." on storage.objects;
create policy "Avatar uploads need the two-factor code when it is on."
  on storage.objects
  as restrictive
  for all
  to authenticated
  using (bucket_id <> 'avatars' or (select public.mfa_satisfied()))
  with check (bucket_id <> 'avatars' or (select public.mfa_satisfied()));

-- 3. SECURITY DEFINER functions ----------------------------------------------------

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
    and (select public.mfa_satisfied())
$$;

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
    and (select public.mfa_satisfied())
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
    and (select public.mfa_satisfied())
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
    and (select public.mfa_satisfied())
    and jsonb_typeof(ug.achievements) = 'array'
    and (
      target_user = (select auth.uid())
      or exists (
        select 1 from public.profiles p
        where p.id = target_user and p.show_steam_achievements
      )
    )
$$;

create or replace function public.following_game_activity(
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
      and (select public.mfa_satisfied())
  ) r
  where r.position <= least(greatest(coalesce(per_status, 20), 1), 50)
  order by r.status, r.position
$$;

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
      and (select public.mfa_satisfied())
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

comment on function public.following_game_activity(uuid, integer) is
  'Members the caller follows who have target_game: public profile fields, status, rating, date_added, review. Never add purchase_price, achievements, email or steam_id.';

-- Unchanged, restated: executable by signed-in members only.
revoke all on function public.public_profile_stats(uuid) from public, anon, authenticated;
revoke all on function public.public_achievement_summary(uuid) from public, anon, authenticated;
revoke all on function public.public_achievement_totals(uuid) from public, anon, authenticated;
revoke all on function public.public_game_achievements(uuid, uuid) from public, anon, authenticated;
revoke all on function public.following_game_activity(uuid, integer) from public, anon, authenticated;
revoke all on function public.following_recent_activity(integer) from public, anon, authenticated;
grant execute on function public.public_profile_stats(uuid) to authenticated;
grant execute on function public.public_achievement_summary(uuid) to authenticated;
grant execute on function public.public_achievement_totals(uuid) to authenticated;
grant execute on function public.public_game_achievements(uuid, uuid) to authenticated;
grant execute on function public.following_game_activity(uuid, integer) to authenticated;
grant execute on function public.following_recent_activity(integer) to authenticated;

notify pgrst, 'reload schema';

-- Fail loudly if the result is not what this file promises.
do $$
declare
  tbl text;
  fn regprocedure;
begin
  foreach tbl in array array[
    'profiles', 'user_games', 'log_entries', 'social_follows', 'game_lists', 'game_list_items'
  ] loop
    if not exists (
      select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public' and c.relname = tbl and c.relrowsecurity
    ) then
      raise exception 'Row level security is not enabled on public.%', tbl;
    end if;
    if not exists (
      select 1 from pg_policies
      where schemaname = 'public' and tablename = tbl
        and policyname = tbl || '_aal2_if_mfa'
        and permissive = 'RESTRICTIVE' and cmd = 'ALL'
    ) then
      raise exception 'public.% has no restrictive two-factor policy', tbl;
    end if;
  end loop;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and policyname = 'Avatar uploads need the two-factor code when it is on.'
      and permissive = 'RESTRICTIVE'
  ) then
    raise exception 'storage.objects has no restrictive two-factor policy';
  end if;

  foreach fn in array array[
    'public.public_profile_stats(uuid)',
    'public.public_achievement_summary(uuid)',
    'public.public_achievement_totals(uuid)',
    'public.public_game_achievements(uuid, uuid)',
    'public.following_game_activity(uuid, integer)',
    'public.following_recent_activity(integer)'
  ]::regprocedure[] loop
    if not (select prosecdef from pg_proc where oid = fn) then
      raise exception '% must stay SECURITY DEFINER', fn;
    end if;
    if (select prosrc from pg_proc where oid = fn) not like '%public.mfa_satisfied()%' then
      raise exception '% does not check two-factor authentication', fn;
    end if;
    if has_function_privilege('anon', fn, 'execute')
       or not has_function_privilege('authenticated', fn, 'execute') then
      raise exception '% has the wrong grants', fn;
    end if;
  end loop;

  if not (select prosecdef from pg_proc where oid = 'public.mfa_satisfied()'::regprocedure)
     or has_function_privilege('anon', 'public.mfa_satisfied()', 'execute')
     or not has_function_privilege('authenticated', 'public.mfa_satisfied()', 'execute') then
    raise exception 'public.mfa_satisfied() must be SECURITY DEFINER and for signed-in members only';
  end if;

  -- It can read auth.mfa_factors, and lets through what it should: no session,
  -- and a member without a verified factor at aal1 or aal2.
  if not public.mfa_satisfied() then
    raise exception 'public.mfa_satisfied() refuses a caller without a session';
  end if;
  perform set_config('request.jwt.claims',
    '{"sub": "00000000-0000-4000-8000-0000000000f0", "role": "authenticated", "aal": "aal1"}', true);
  if not public.mfa_satisfied() then
    raise exception 'public.mfa_satisfied() refuses a member without two-factor';
  end if;
  perform set_config('request.jwt.claims', '', true);
end;
$$;
