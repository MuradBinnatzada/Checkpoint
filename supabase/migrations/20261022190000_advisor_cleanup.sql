-- Clean-up from the Supabase security and performance advisors.
--
-- 1. Trigger functions are not an API.
--    `handle_new_user()` and `set_updated_at()` were made in the dashboard before
--    this folder existed (no file here creates them). A trigger does not check
--    EXECUTE when it fires, so nobody needs the grant on `handle_new_user()`;
--    `public` (and so `anon` and every signed-in member) still had it, which the
--    advisor reports as a SECURITY DEFINER function anyone can call. Revoked.
--    `set_updated_at()` gets a fixed search_path (the "function search path
--    mutable" warning), but only when its body is the plain
--    `new.<column> := now()` kind: its source is not in the repository, and an
--    empty search_path would break one that names a table without its schema.
--
-- 2. citext moves out of `public`.
--    20261011000000 creates it in `extensions`, but the live database got it in
--    `public` when profiles was made in the dashboard. ALTER EXTENSION moves the
--    type, its operators and its index support; profiles.handle and everything
--    built on it follow by OID. Nothing in this folder names the type outside
--    that column, and no function with a `public` search_path compares a handle.
--
-- 3. Indexes for the foreign keys the advisor lists (and two it will list for
--    discussion_reports once 20261022165000 is applied). Each is what an
--    `on delete cascade` / `set null` (an account or a library row going away)
--    scans to find the rows that depend on it.
--
-- 4. game_list_items had one policy for SELECT and a FOR ALL policy that also
--    covers SELECT, so every read ran both. The FOR ALL is split into the three
--    writes it was for; who can read and who can write is unchanged.
--
-- 5. profiles, user_games, log_entries and social_follows: the live database
--    still had the policies made by hand in the dashboard next to the ones
--    20261017120000 defines, i.e. two permissive policies for the same command.
--    The hand-made ones are dropped; see section 5 for log_entries, whose SELECT
--    policy is created first.
--
-- Not changed on purpose (the advisor lists them; the files named say why):
--   * "Security Definer View" on public_profiles, public_followers,
--     public_following, public_user_games, public_recent_activity
--     (20261013130000, 20261017140000): `profiles` is readable by its owner only,
--     so the views must run as their owner to show other members' public fields.
--   * "Signed-in users can execute SECURITY DEFINER function" on the functions
--     the app calls (award_milestones, game_reviews, public_profile_stats ...):
--     that is the app's API. Each names its columns, checks auth.uid() and
--     mfa_satisfied(), and has no grant for anon. mfa_satisfied() is also called
--     by the policies, as the member, so it needs the grant.
--   * "RLS enabled, no policy" on edge_rate_limits, mfa_recovery_codes,
--     steam_app_relinks, steam_sync_state, text_translations: service-role tables.
--     Their privileges are revoked from every client role as well, so RLS with no
--     policy is the second lock.
--   * "Unused index": the database is young; an index nobody has needed yet is
--     not one nobody needs.

-- 1. Trigger functions ----------------------------------------------------------

do $$
declare
  fn regprocedure;
  body text;
begin
  fn := to_regprocedure('public.handle_new_user()');
  if fn is not null then
    revoke all on function public.handle_new_user() from public, anon, authenticated;
  end if;

  fn := to_regprocedure('public.set_updated_at()');
  if fn is not null then
    select prosrc into body from pg_proc where oid = fn;
    if body !~* '\m(select|from|join|insert|update|delete|perform|execute)\M' then
      alter function public.set_updated_at() set search_path = '';
    else
      raise notice 'public.set_updated_at() left alone: its body reads tables, set its search_path by hand';
    end if;
  end if;
end;
$$;

-- 2. citext ---------------------------------------------------------------------

create schema if not exists extensions;

do $$
begin
  if exists (
    select 1 from pg_extension e join pg_namespace n on n.oid = e.extnamespace
    where e.extname = 'citext' and n.nspname = 'public'
  ) then
    alter extension citext set schema extensions;
  end if;
end;
$$;

-- 3. Foreign key indexes ---------------------------------------------------------

create index if not exists games_created_by_idx
  on public.games (created_by);

create index if not exists review_reports_review_idx
  on public.review_reports (review_user_id, game_id);

create index if not exists steam_app_relinks_into_idx
  on public.steam_app_relinks (into_id);

create index if not exists user_milestones_milestone_idx
  on public.user_milestones (milestone_id);

-- discussion_reports (20261022165000) would be listed next: its once-per-member
-- indexes are partial and lead with reporter_id, so the thread and the reply a
-- report points at are not covered.
create index if not exists discussion_reports_thread_idx
  on public.discussion_reports (thread_id);

create index if not exists discussion_reports_post_idx
  on public.discussion_reports (post_id);

-- 4. game_list_items: one policy per command ---------------------------------------

drop policy if exists game_list_items_write_own on public.game_list_items;

drop policy if exists game_list_items_insert_own on public.game_list_items;
create policy game_list_items_insert_own
  on public.game_list_items
  for insert
  to authenticated
  with check (exists (
    select 1 from public.game_lists l
    where l.id = list_id and l.user_id = (select auth.uid())
  ));

drop policy if exists game_list_items_update_own on public.game_list_items;
create policy game_list_items_update_own
  on public.game_list_items
  for update
  to authenticated
  using (exists (
    select 1 from public.game_lists l
    where l.id = list_id and l.user_id = (select auth.uid())
  ))
  with check (exists (
    select 1 from public.game_lists l
    where l.id = list_id and l.user_id = (select auth.uid())
  ));

drop policy if exists game_list_items_delete_own on public.game_list_items;
create policy game_list_items_delete_own
  on public.game_list_items
  for delete
  to authenticated
  using (exists (
    select 1 from public.game_lists l
    where l.id = list_id and l.user_id = (select auth.uid())
  ));

-- 5. Policies from the dashboard that 20261017120000 made redundant ----------------
-- The live database still has the permissive policies that were made by hand on
-- these four tables next to the ones this folder defines, so every command ran
-- both. (Names and definitions as listed from pg_policies on 2026-10-22; each
-- does what the repo's policy beside it does.) The restrictive `*_own_only`
-- guards are not touched.
--
-- log_entries is the one to be careful with: the live database has no
-- log_entries_select_own (20261011000000 is recorded as applied, not run), so
-- its only SELECT policy is the FOR ALL one dropped below. The repo's is created
-- first.

drop policy if exists log_entries_select_own on public.log_entries;
create policy log_entries_select_own
  on public.log_entries
  for select
  to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists "users own log_entries" on public.log_entries;
drop policy if exists "users insert own profile" on public.profiles;
drop policy if exists "users update own profile" on public.profiles;
drop policy if exists "users delete own follows" on public.social_follows;
drop policy if exists "users create own follows" on public.social_follows;
drop policy if exists "authenticated users read follows" on public.social_follows;
drop policy if exists "users own user_games" on public.user_games;

notify pgrst, 'reload schema';

-- Fail loudly if the result is not what this file promises.
do $$
declare
  guarded record;
  op text;
  policy_count integer;
begin
  -- One permissive policy per command on these tables, and one for each command
  -- the app uses (the table in 20261017120000 lists them).
  for guarded in
    select * from (values
      ('profiles',       array['select', 'insert', 'update']),
      ('user_games',     array['select', 'insert', 'update', 'delete']),
      ('log_entries',    array['select', 'insert', 'update', 'delete']),
      ('social_follows', array['select', 'insert', 'delete'])
    ) as v(tbl, app_ops)
  loop
    foreach op in array array['select', 'insert', 'update', 'delete'] loop
      select count(*) into policy_count from pg_policies
      where schemaname = 'public' and tablename = guarded.tbl and permissive = 'PERMISSIVE'
        and lower(cmd) in (op, 'all');
      if policy_count > 1 or (policy_count = 0 and op = any (guarded.app_ops)) then
        raise exception 'public.% has % permissive % policies', guarded.tbl, policy_count, upper(op);
      end if;
    end loop;
  end loop;

  if to_regprocedure('public.handle_new_user()') is not null
     and (has_function_privilege('anon', 'public.handle_new_user()', 'execute')
          or has_function_privilege('authenticated', 'public.handle_new_user()', 'execute')) then
    raise exception 'public.handle_new_user() is still callable by members';
  end if;

  if exists (
    select 1 from pg_extension e join pg_namespace n on n.oid = e.extnamespace
    where e.extname = 'citext' and n.nspname = 'public'
  ) then
    raise exception 'citext is still in public';
  end if;

  if not exists (
    select 1
    from pg_attribute a
    join pg_type t on t.oid = a.atttypid
    join pg_namespace n on n.oid = t.typnamespace
    where a.attrelid = 'public.profiles'::regclass and a.attname = 'handle'
      and t.typname = 'citext' and n.nspname = 'extensions'
  ) then
    raise exception 'profiles.handle is no longer an extensions.citext';
  end if;

  if (select count(*) from pg_policies
      where schemaname = 'public' and tablename = 'game_list_items'
        and permissive = 'PERMISSIVE' and cmd in ('SELECT', 'ALL')) <> 1 then
    raise exception 'game_list_items has overlapping permissive policies';
  end if;

  if (select count(*) from pg_policies
      where schemaname = 'public' and tablename = 'game_list_items'
        and permissive = 'PERMISSIVE' and cmd in ('INSERT', 'UPDATE', 'DELETE')) <> 3 then
    raise exception 'game_list_items needs one write policy per command';
  end if;
end;
$$;
