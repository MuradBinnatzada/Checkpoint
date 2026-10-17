-- Row ownership: no signed-in member can write or delete another member's rows.
--
-- profiles, user_games, log_entries and social_follows hold per-member data. They
-- were created in the dashboard rather than in a migration, so the write policies
-- on them are not in this repository: the only policies the migrations pin down
-- are the read rules on `profiles`. Whether a stray `using (true)` or a policy
-- for the wrong role is sitting on one of these tables cannot be told from here.
--
-- This migration makes the ownership rule explicit and independent of what is
-- already there. For each table, and for each of INSERT, UPDATE and DELETE:
--
--   1. A RESTRICTIVE policy (`<table>_<op>_own_only`): the row's owner column must
--      equal auth.uid(). Restrictive policies are AND-ed with every permissive
--      one, so even an old broad policy cannot let a member touch someone else's
--      row, or hand a row of their own to someone else (UPDATE/INSERT check the
--      new row too). Same technique as profiles_select_own_only
--      (20261013130000_...). It applies to anon as well, which has no auth.uid().
--
--   2. A PERMISSIVE own-row policy (`<table>_<op>_own`) for the operations the
--      app actually performs, so the app keeps working even if the dashboard
--      policies are later removed. Operations the app never does get no
--      permissive policy: the restrictive one alone grants nothing.
--
--        table           owner column   the app inserts  updates  deletes
--        profiles        id             yes (upsert)      yes      no
--        user_games      user_id        yes (upsert)      yes      yes
--        log_entries     user_id        yes               no       yes
--        social_follows  follower_id    yes               no       yes
--
-- (The user_profile / log_entry records in the review notes are `profiles` and
-- `log_entries`; user_games and social_follows are the same kind of table.)
--
-- Also revoked: anon's access to these tables altogether, and authenticated's
-- TRUNCATE / REFERENCES / TRIGGER. TRUNCATE ignores RLS, so a table-wide grant of
-- it is a way around every policy above. Supabase grants all of them by default.
--
-- Not affected: the service role (Edge Functions) and the owner of SECURITY
-- DEFINER functions (merge_game_into, link_steam_apps) bypass RLS, so sync-steam,
-- delete-account and the like work as before. SELECT policies are not touched, and
-- the rules above rely on them being there: Postgres only lets UPDATE/DELETE ...
-- WHERE (and anything with RETURNING, which the app's upserts use) act on rows the
-- member can also SELECT. The app reads all four tables, so those policies exist.
--
-- Not covered: `games`, the shared catalog. Members may add rows, so ownership
-- there is `created_by`, and its policies are a separate decision. See
-- 20261014120000_harden_for_open_signups.sql.
--
-- The last block fails the migration if any table ends up without RLS or without
-- the three restrictive policies, so a bad deploy cannot pass silently. To look
-- at what is in place:
--
--   select tablename, policyname, permissive, roles, cmd, qual, with_check
--   from pg_policies
--   where schemaname = 'public'
--     and tablename in ('profiles', 'user_games', 'log_entries', 'social_follows')
--   order by tablename, cmd, permissive, policyname;

do $$
declare
  t record;
  op text;
  owned text;
  clause text;
begin
  for t in
    select * from (values
      ('profiles',       'id',          array['insert', 'update']),
      ('user_games',     'user_id',     array['insert', 'update', 'delete']),
      ('log_entries',    'user_id',     array['insert', 'delete']),
      ('social_follows', 'follower_id', array['insert', 'delete'])
    ) as v(tbl, owner, app_ops)
  loop
    execute format('alter table public.%I enable row level security', t.tbl);

    owned := format('%I = (select auth.uid())', t.owner);

    foreach op in array array['insert', 'update', 'delete'] loop
      -- INSERT has only a WITH CHECK, DELETE only a USING, UPDATE both.
      clause := case op
        when 'insert' then format('with check (%s)', owned)
        when 'update' then format('using (%s) with check (%s)', owned, owned)
        else format('using (%s)', owned)
      end;

      execute format('drop policy if exists %I on public.%I', t.tbl || '_' || op || '_own_only', t.tbl);
      execute format(
        'create policy %I on public.%I as restrictive for %s to public %s',
        t.tbl || '_' || op || '_own_only', t.tbl, op, clause
      );

      execute format('drop policy if exists %I on public.%I', t.tbl || '_' || op || '_own', t.tbl);
      if op = any (t.app_ops) then
        execute format(
          'create policy %I on public.%I as permissive for %s to authenticated %s',
          t.tbl || '_' || op || '_own', t.tbl, op, clause
        );
      end if;
    end loop;

    execute format('revoke all on public.%I from anon', t.tbl);
    execute format('revoke truncate, references, trigger on public.%I from authenticated', t.tbl);
  end loop;
end;
$$;

-- Fail loudly if the result is not what this file promises.
do $$
declare
  tbl text;
  op text;
begin
  foreach tbl in array array['profiles', 'user_games', 'log_entries', 'social_follows'] loop
    if not exists (
      select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public' and c.relname = tbl and c.relrowsecurity
    ) then
      raise exception 'Row level security is not enabled on public.%', tbl;
    end if;

    foreach op in array array['INSERT', 'UPDATE', 'DELETE'] loop
      if not exists (
        select 1 from pg_policies
        where schemaname = 'public' and tablename = tbl
          and cmd = op and permissive = 'RESTRICTIVE'
      ) then
        raise exception 'public.% has no restrictive % policy', tbl, op;
      end if;
    end loop;
  end loop;
end;
$$;
