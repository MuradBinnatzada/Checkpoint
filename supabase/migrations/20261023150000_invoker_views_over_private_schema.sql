-- The public_* views: the definer part moves out of the API's schema.
--
-- public_profiles, public_followers, public_following, public_user_games and
-- public_recent_activity have to run as their owner: `profiles`, `user_games` and
-- `log_entries` are own-row only (20261013130000, 20261017120000), so another
-- member's row, and the columns that stay private (email, notes ...), cannot be
-- read through them by the member asking. The advisor lists each one as a
-- "Security Definer View" (ERROR) for as long as it is a definer view that
-- `authenticated` can select from in a schema the API exposes.
--
-- Making them plain security_invoker views would mean opening those three tables
-- to every member's SELECT, with the private columns guarded only by column
-- privileges the app's own `select *` reads would trip over. That is a weaker
-- design, so it is not done here. This is what is done:
--
--   private.public_*   the existing definer views, unchanged, moved here by
--                      ALTER VIEW ... SET SCHEMA. `private` is not in
--                      supabase/config.toml's [api] schemas (and must never be
--                      added to the Exposed schemas in the dashboard), so the API
--                      cannot reach them.
--   public.public_*    one thin SECURITY INVOKER view each, `select * from
--                      private.public_*`, same name and columns, which is what
--                      the app asks for (/rest/v1/public_profiles ...).
--
-- What a member can read does not change: the same columns of the same rows, from
-- the same definer view, only one step further in. Nothing is made more or less
-- private by this; it moves where the definer view lives so that the advisor lists
-- only what is exposed. `anon` has no access to any of them, as before.
--
-- From now on, change a view's columns with `create or replace view
-- private.public_*` (columns can only be added at the end), and then repeat the
-- wrapper so it picks them up (`select *` is expanded when the wrapper is made):
--
--   create or replace view public.public_profiles
--     with (security_invoker = true) as select * from private.public_profiles;
--
-- A migration that redefines `public.public_*` as a definer view brings the
-- advisor's error back; the last block of this file is the check to repeat in it.

create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

do $$
declare
  v text;
begin
  foreach v in array array[
    'public_profiles', 'public_followers', 'public_following',
    'public_user_games', 'public_recent_activity'
  ] loop
    -- Moved once: a second run finds the definer view already in `private`.
    if to_regclass(format('private.%I', v)) is null then
      execute format('alter view public.%I set schema private', v);
    end if;

    execute format('revoke all on private.%I from public, anon, authenticated', v);
    execute format('grant select on private.%I to authenticated', v);

    execute format(
      'create or replace view public.%I with (security_invoker = true) as select * from private.%I',
      v, v
    );
    execute format('comment on view public.%I is %L', v,
      coalesce(obj_description(to_regclass(format('private.%I', v)), 'pg_class'),
               'Read through private.' || v || ', which is the SECURITY DEFINER view.'));

    execute format('revoke all on public.%I from public, anon, authenticated', v);
    execute format('grant select on public.%I to authenticated', v);
  end loop;
end;
$$;

notify pgrst, 'reload schema';

-- Fail loudly if the result is not what this file promises.
do $$
declare
  v text;
  leftover text;
begin
  foreach v in array array[
    'public_profiles', 'public_followers', 'public_following',
    'public_user_games', 'public_recent_activity'
  ] loop
    -- The wrapper is an invoker view; the view behind it still runs as its owner.
    if not (select coalesce(c.reloptions @> array['security_invoker=true'], false)
            from pg_class c where c.oid = to_regclass(format('public.%I', v))) then
      raise exception 'public.% must be a security_invoker view', v;
    end if;
    if (select coalesce(c.reloptions @> array['security_invoker=true'], false)
        from pg_class c where c.oid = to_regclass(format('private.%I', v))) then
      raise exception 'private.% must stay the definer view', v;
    end if;

    -- Signed-in members read both; anon reads neither.
    if not has_table_privilege('authenticated', format('public.%I', v), 'select')
       or not has_table_privilege('authenticated', format('private.%I', v), 'select')
       or has_table_privilege('anon', format('public.%I', v), 'select')
       or has_table_privilege('anon', format('private.%I', v), 'select') then
      raise exception '% has the wrong grants', v;
    end if;

    -- Same columns on both sides.
    if (select array_agg(attname order by attnum) from pg_attribute
        where attrelid = to_regclass(format('public.%I', v)) and attnum > 0 and not attisdropped)
       is distinct from
       (select array_agg(attname order by attnum) from pg_attribute
        where attrelid = to_regclass(format('private.%I', v)) and attnum > 0 and not attisdropped) then
      raise exception 'public.% and private.% have different columns', v, v;
    end if;
  end loop;

  if has_schema_privilege('anon', 'private', 'usage')
     or not has_schema_privilege('authenticated', 'private', 'usage') then
    raise exception 'The private schema has the wrong grants';
  end if;

  -- The advisor's rule: a view in `public` that members can select and that is not
  -- security_invoker.
  select string_agg(c.relname, ', ') into leftover
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relkind = 'v'
    and (has_table_privilege('anon', c.oid, 'select')
         or has_table_privilege('authenticated', c.oid, 'select'))
    and not coalesce(c.reloptions @> array['security_invoker=true'], false);
  if leftover is not null then
    raise exception 'Definer views are still readable through the API: %', leftover;
  end if;
end;
$$;
