-- Security hardening: the catalog is written by the server only, the library
-- columns that come from Steam can't be set by hand, profile fields are checked,
-- and the Edge Functions get a per-member rate limit.
--
-- 1. games: members can no longer write the shared catalog.
--    Until now any signed-in member could INSERT a `games` row (with any free
--    IGDB id, title, summary and cover) and UPDATE the rows they created,
--    `igdb_synced_at` included. A row is shared by everyone who adds that game
--    and Home's "Recently Added" lists the newest rows to every visitor, so one
--    account could put its own text on a real game before anyone else added it,
--    or fill Home with made-up games, and stamp them as filled in from IGDB so
--    nothing ever corrected them.
--    Now only the service role writes the catalog: igdb-handler's `add` mode
--    builds a missing row from IGDB's own answer (title, cover, summary,
--    platforms...), and sync-steam does the same for Steam games. The app sends
--    IGDB ids only. Reading the catalog is unchanged.
--
-- 2. user_games: achievements and Steam playtime are the server's.
--    `achievements`, its counts and `steam_playtime_minutes` are written by
--    sync-steam and sync-achievements from Steam. A member could write their own
--    row's, and other members see the counts on their profile. Now a member's
--    insert leaves them empty and a member's update keeps what the row had, the
--    same way log_entries_keep_source (20261019014800) treats `source`. The
--    service role is not affected. The app never sends these columns.
--
-- 3. profiles: limits on what other members are shown.
--    Name, handle, bio, avatar and Steam ID had no limits in the database (only
--    the app's own form checked them), and every member's app loads the avatar
--    URL, so it could point at a server that logs who looks at the profile.
--    A trigger checks a value when it is set or changed, so rows saved before
--    this migration never fail an unrelated edit:
--      display_name  control and text-direction characters removed, trimmed,
--                    cut to 100 characters (an account name from Google or
--                    Apple is never refused at sign-in); empty becomes 'Player'
--      handle        a-z, 0-9 and _, 3 to 30 characters (the app allows 24)
--      bio           at most 500 characters (the app allows 160)
--      avatar_url    a photo in the member's own folder of this project's
--                    `avatars` bucket, or a Google account photo. On the first
--                    insert (sign-in) anything else is dropped, so sign-in never
--                    fails on it; on an edit it is refused.
--      steam_id      a 17-digit Steam ID64
--    The service role (Edge Functions) is not checked.
--    A project behind a Supabase custom domain serves its storage from that
--    domain: add it to profiles_avatar_url_ok() below before using one.
--
-- 4. Rate limits for the Edge Functions.
--    `consume_rate_limit(user, bucket, max_hits, window_seconds)` counts a
--    member's calls in a fixed window and answers 0 (go ahead) or the seconds
--    until the window ends. The functions call it with the service role before
--    any work (see supabase/functions/_shared/rate_limit.ts for the limits) and
--    answer RATE_LIMITED (429) when it says wait. One row per member and bucket,
--    gone with the account.
--
-- Deploy order: deploy igdb-handler (its `add` mode) together with or before
-- this migration (deploy-supabase.yml does both), then ship the app. App builds
-- from before this change insert catalog rows themselves, so adding a game that
-- nobody has added yet fails on them until they are updated; games already in
-- the catalog, and everything else, keep working.

-- 1. Catalog -------------------------------------------------------------------

drop policy if exists games_insert_own on public.games;
drop policy if exists games_update_own on public.games;

-- Privileges come before policies: without INSERT/UPDATE/DELETE no policy, old or
-- new, can let a member write. TRUNCATE, REFERENCES and TRIGGER go too
-- (Supabase grants them by default, and TRUNCATE ignores RLS).
revoke insert, update, delete, truncate, references, trigger
  on public.games from public, anon, authenticated;
grant select on public.games to anon, authenticated;

comment on table public.games is
  'The shared game catalog, one row per IGDB game. Everyone reads it; only the service role writes it (igdb-handler mode add / details / backfill, sync-steam).';

-- 2. Library columns that come from Steam ---------------------------------------

create or replace function public.user_games_keep_server_columns()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user in ('authenticated', 'anon') then
    if tg_op = 'INSERT' then
      new.achievements := null;
      new.achievements_unlocked := null;
      new.achievements_total := null;
      new.achievements_playtime := null;
      new.achievements_synced_at := null;
      new.steam_playtime_minutes := null;
    else
      new.achievements := old.achievements;
      new.achievements_unlocked := old.achievements_unlocked;
      new.achievements_total := old.achievements_total;
      new.achievements_playtime := old.achievements_playtime;
      new.achievements_synced_at := old.achievements_synced_at;
      new.steam_playtime_minutes := old.steam_playtime_minutes;
    end if;
  end if;
  return new;
end;
$$;

-- BEFORE triggers run in name order: this one runs after
-- user_games_count_achievements, so a member's list can't leave its counts behind.
drop trigger if exists user_games_server_columns on public.user_games;
create trigger user_games_server_columns
  before insert or update on public.user_games
  for each row execute function public.user_games_keep_server_columns();

-- 3. Profile fields ---------------------------------------------------------------

-- Whether [url] may be member_id's avatar: a file in their own folder of the
-- `avatars` bucket of a Supabase project (or of `supabase start` on this machine),
-- or a Google account photo, which Google sign-in fills in.
create or replace function public.profiles_avatar_url_ok(url text, member_id uuid)
returns boolean
language sql
immutable
set search_path = ''
as $$
  -- (A regular expression can't count past 255, so the length is checked apart.)
  select char_length(url) <= 2000
     and (url ~ ('^https://[a-z0-9]{20}\.supabase\.co/storage/v1/object/public/avatars/'
                 || member_id::text || '/[A-Za-z0-9._-]{1,100}$')
       or url ~ ('^http://(127\.0\.0\.1|localhost):54321/storage/v1/object/public/avatars/'
                 || member_id::text || '/[A-Za-z0-9._-]{1,100}$')
       or url ~ '^https://lh[0-9]\.googleusercontent\.com/[A-Za-z0-9/_=.~+-]+$')
$$;

create or replace function public.profiles_check_values()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  is_new constant boolean := tg_op = 'INSERT';
begin
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;

  if new.display_name is not null
     and (is_new or new.display_name is distinct from old.display_name) then
    new.display_name := left(
      btrim(regexp_replace(new.display_name, '[\x01-\x1f\x7f‎‏‪-‮⁦-⁩]', '', 'g')),
      100
    );
    if new.display_name = '' then
      new.display_name := 'Player';
    end if;
  end if;

  if is_new or new.handle is distinct from old.handle then
    -- citext compares case-insensitively, regular expressions included: test the text.
    if new.handle is not null and new.handle::text !~ '^[a-z0-9_]{3,30}$' then
      raise exception 'A handle is 3 to 30 characters: a-z, 0-9 and _.'
        using errcode = 'check_violation';
    end if;
  end if;

  if (is_new or new.bio is distinct from old.bio) and char_length(new.bio) > 500 then
    raise exception 'A bio is at most 500 characters.' using errcode = 'check_violation';
  end if;

  if (is_new or new.avatar_url is distinct from old.avatar_url)
     and new.avatar_url is not null
     and not public.profiles_avatar_url_ok(new.avatar_url, new.id) then
    if is_new then
      new.avatar_url := null;
    else
      raise exception 'A profile photo must be uploaded to Checkpoint.' using errcode = 'check_violation';
    end if;
  end if;

  if (is_new or new.steam_id is distinct from old.steam_id)
     and nullif(btrim(new.steam_id), '') is not null
     and btrim(new.steam_id) !~ '^[0-9]{17}$' then
    raise exception 'A Steam ID64 is 17 digits.' using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

drop trigger if exists profiles_check_values on public.profiles;
create trigger profiles_check_values
  before insert or update on public.profiles
  for each row execute function public.profiles_check_values();

-- 4. Rate limits for the Edge Functions ---------------------------------------------

create table if not exists public.edge_rate_limits (
  user_id      uuid not null references auth.users (id) on delete cascade,
  bucket       text not null,
  window_start timestamptz not null,
  hits         integer not null,
  primary key (user_id, bucket)
);

comment on table public.edge_rate_limits is
  'Calls per member and Edge Function in the current window (consume_rate_limit). Service role only.';

alter table public.edge_rate_limits enable row level security;
revoke all on public.edge_rate_limits from public, anon, authenticated;
grant select, insert, update, delete on public.edge_rate_limits to service_role;

-- Counts one call of target_user to bucket_name. Answers 0 while the window
-- (window_seconds long, starting at the first call) has room for max_hits calls,
-- otherwise the whole seconds until it ends.
create or replace function public.consume_rate_limit(
  target_user uuid,
  bucket_name text,
  max_hits integer,
  window_seconds integer
)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  span constant interval := make_interval(secs => greatest(window_seconds, 1));
  counted public.edge_rate_limits;
begin
  insert into public.edge_rate_limits as r (user_id, bucket, window_start, hits)
  values (target_user, bucket_name, now(), 1)
  on conflict (user_id, bucket) do update
    set window_start = case when r.window_start <= now() - span then now() else r.window_start end,
        hits = case when r.window_start <= now() - span then 1 else r.hits + 1 end
  returning * into counted;

  if counted.hits <= max_hits then
    return 0;
  end if;
  return greatest(1, ceil(extract(epoch from counted.window_start + span - now()))::integer);
end;
$$;

revoke all on function public.consume_rate_limit(uuid, text, integer, integer) from public, anon, authenticated;
grant execute on function public.consume_rate_limit(uuid, text, integer, integer) to service_role;

notify pgrst, 'reload schema';

-- Fail loudly if the result is not what this file promises.
do $$
declare
  op text;
begin
  foreach op in array array['insert', 'update', 'delete', 'truncate'] loop
    if has_table_privilege('authenticated', 'public.games', op)
       or has_table_privilege('anon', 'public.games', op) then
      raise exception 'Members can still % public.games', op;
    end if;
  end loop;
  if not has_table_privilege('authenticated', 'public.games', 'select')
     or not has_table_privilege('anon', 'public.games', 'select') then
    raise exception 'public.games must stay readable';
  end if;
  if not has_table_privilege('service_role', 'public.games', 'insert') then
    raise exception 'The service role must still write public.games';
  end if;

  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.user_games'::regclass and tgname = 'user_games_server_columns'
  ) or not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.profiles'::regclass and tgname = 'profiles_check_values'
  ) then
    raise exception 'A hardening trigger is missing';
  end if;

  if has_table_privilege('authenticated', 'public.edge_rate_limits', 'select')
     or has_function_privilege('authenticated', 'public.consume_rate_limit(uuid, text, integer, integer)', 'execute')
     or has_function_privilege('anon', 'public.consume_rate_limit(uuid, text, integer, integer)', 'execute') then
    raise exception 'The rate limits must be for the service role only';
  end if;

  if not public.profiles_avatar_url_ok(
           'https://abcdefghijklmnopqrst.supabase.co/storage/v1/object/public/avatars/00000000-0000-4000-8000-000000000001/1760000000000.jpg',
           '00000000-0000-4000-8000-000000000001')
     or public.profiles_avatar_url_ok(
           'https://abcdefghijklmnopqrst.supabase.co/storage/v1/object/public/avatars/00000000-0000-4000-8000-000000000002/1760000000000.jpg',
           '00000000-0000-4000-8000-000000000001')
     or public.profiles_avatar_url_ok('https://example.com/pixel.gif', '00000000-0000-4000-8000-000000000001')
     or not public.profiles_avatar_url_ok(
           'https://lh3.googleusercontent.com/a/ACg8ocJx-abc_DEF=s96-c',
           '00000000-0000-4000-8000-000000000001') then
    raise exception 'profiles_avatar_url_ok does not accept what it should';
  end if;
end;
$$;
