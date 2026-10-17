-- Background Steam sync: pg_cron calls the `sync-steam` Edge Function every 15
-- minutes, and the function refreshes the libraries of the members whose turn it is.
--
-- Who is synced (see `steam_sync_due`):
--   * has a Steam ID on their profile,
--   * has synced by hand at least once. Recording that first sync is what enrolls
--     a member (sync-steam writes `steam_sync_state`), so nobody's library is
--     imported unasked. Members who synced before this migration join at their next
--     manual sync,
--   * used the app in the last 30 days (their session was refreshed or they signed in),
--   * is due: `next_attempt_at` has passed. A good sync schedules the next one in 12
--     hours; failures back off (functions/_shared/sync_schedule.ts).
-- The 10 most overdue members are synced per run, one after the other, with a small
-- IGDB budget. That is about 960 member-syncs a day, enough for ~480 members at the
-- 12-hour interval. Past that, raise BACKGROUND_BATCH_SIZE in sync-steam or run the
-- job more often. Steam's key allows 100 000 calls a day and a sync is one call.
--
-- ONE-TIME SETUP. These are secrets, so they cannot live in a migration. Until all
-- three exist, the job runs and does nothing (it logs a warning).
--
--   -- SQL editor:
--   select vault.create_secret('https://<project-ref>.supabase.co', 'project_url');
--   select vault.create_secret('<the anon key the app uses>',       'anon_key');
--   select vault.create_secret('<a long random string>',            'cron_secret');
--
--   -- shell, with the SAME random string (e.g. from `openssl rand -hex 32`):
--   supabase secrets set CRON_SECRET=<the same string>
--
-- `anon_key` only gets the request past the Edge Functions gateway (JWT check); the
-- function itself accepts the call because of `cron_secret`. If the project moves to
-- publishable keys only, set `verify_jwt = false` for sync-steam in config.toml.
--
-- Pause it:   select cron.unschedule('sync-steam-background');
-- Resume it:  re-run the `cron.schedule` call at the bottom of this file.
-- Look at it: select * from cron.job_run_details order by start_time desc limit 20;
--             select id, status_code, content::text from net._http_response order by created desc limit 5;

create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;

-- 1. Sync state ---------------------------------------------------------------
-- One row per enrolled member. Written only by sync-steam (service role): RLS is on
-- and there is no policy, and the client roles have no grants at all.
-- Rows go with the account (on delete cascade), so delete-account needs no change.
create table if not exists public.steam_sync_state (
  user_id              uuid primary key references auth.users (id) on delete cascade,
  last_synced_at       timestamptz not null,
  last_attempt_at      timestamptz,
  next_attempt_at      timestamptz not null default now(),
  consecutive_failures integer not null default 0,
  last_error_code      text
);

alter table public.steam_sync_state enable row level security;
revoke all on public.steam_sync_state from public, anon, authenticated;

comment on table public.steam_sync_state is
  'Background Steam sync bookkeeping, one row per member who has synced. Service role only.';

-- 2. Who is due ---------------------------------------------------------------
-- SECURITY DEFINER because "recently active" is read from auth.sessions, which the
-- service role is not guaranteed to be able to select from. Only the service role
-- may call it.
create or replace function public.steam_sync_due(batch_size integer, active_days integer)
returns table (user_id uuid, steam_id text, consecutive_failures integer)
language sql
stable
security definer
set search_path = ''
set timezone = 'UTC'
as $$
  select s.user_id, btrim(p.steam_id), s.consecutive_failures
  from public.steam_sync_state s
  join public.profiles p on p.id = s.user_id
  join auth.users u on u.id = s.user_id
  where s.next_attempt_at <= now()
    and nullif(btrim(p.steam_id), '') is not null
    and coalesce(
          (select max(coalesce(x.refreshed_at, x.created_at))
             from auth.sessions x
            where x.user_id = s.user_id),
          u.last_sign_in_at
        ) > now() - make_interval(days => active_days)
  order by s.last_synced_at, s.user_id
  limit greatest(batch_size, 0)
$$;

revoke all on function public.steam_sync_due(integer, integer) from public, anon, authenticated;
grant execute on function public.steam_sync_due(integer, integer) to service_role;

-- 3. The call that cron makes --------------------------------------------------
-- Reads the three Vault secrets and posts to sync-steam. pg_net is asynchronous: the
-- job does not wait for the sync, and the answer lands in net._http_response.
-- Returns the request id, or null when the secrets are not set up yet.
create or replace function public.invoke_steam_background_sync()
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  project_url text;
  anon_key    text;
  cron_secret text;
begin
  select decrypted_secret into project_url from vault.decrypted_secrets where name = 'project_url';
  select decrypted_secret into anon_key    from vault.decrypted_secrets where name = 'anon_key';
  select decrypted_secret into cron_secret from vault.decrypted_secrets where name = 'cron_secret';

  if coalesce(project_url, '') = '' or coalesce(anon_key, '') = '' or coalesce(cron_secret, '') = '' then
    raise warning 'invoke_steam_background_sync: Vault secrets project_url, anon_key and cron_secret must all be set; skipping this run';
    return null;
  end if;

  return net.http_post(
    url := rtrim(project_url, '/') || '/functions/v1/sync-steam',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', anon_key,
      'Authorization', 'Bearer ' || anon_key,
      'x-cron-secret', cron_secret
    ),
    body := '{}'::jsonb,
    -- sync-steam stops starting members after 90 s; the edge function limit is 150 s.
    timeout_milliseconds := 150000
  );
end;
$$;

revoke all on function public.invoke_steam_background_sync() from public, anon, authenticated;

-- 4. The schedule ---------------------------------------------------------------
do $$
begin
  if exists (select 1 from cron.job where jobname = 'sync-steam-background') then
    perform cron.unschedule('sync-steam-background');
  end if;
  perform cron.schedule(
    'sync-steam-background',
    '*/15 * * * *',
    'select public.invoke_steam_background_sync()'
  );
end;
$$;
