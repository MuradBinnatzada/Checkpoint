-- Unify game identity on IGDB.
--
-- Problem: the same game could be saved twice. Steam sync keyed a game by its
-- Steam app id (57e40000-0000-0000-0000-<appid>); in-app search keyed it by its
-- IGDB id (00000000-0000-4000-8000-<igdbid>). The copies split hours, ratings
-- and achievements between two `games` rows.
--
-- Fix: `igdb_id` is the identity of a game.
--   * `games.igdb_id` is UNIQUE.
--   * `games.id` stays a uuid (user_games / log_entries point at it), but a CHECK
--     makes it a pure function of igdb_id:  id = igdb_game_uuid(igdb_id).
--     Steam sync, the in-app search and this database all compute the same id.
--   * `games.steam_app_id` records which Steam app a game is, so achievements no
--     longer decode the Steam app id out of the game's uuid.
--   * New rows must have an igdb_id (constraint added NOT VALID, see below).
--
-- What this migration can NOT do: merge the existing Steam-keyed duplicates.
-- Those rows have no igdb_id (sync-steam never wrote one), so there is nothing
-- in the database to match them on. They are merged by sync-steam: on a user's
-- next sync it re-matches their legacy Steam games against IGDB and calls
-- `link_steam_apps`, which folds each legacy row into the IGDB-keyed row for
-- every user at once. Until then a legacy row keeps working as before.
--
-- Deploy order (the new app build and Edge Functions need this schema):
--   1. apply this migration            (supabase db push)
--   2. deploy sync-steam and sync-achievements
--   3. ship the app build
-- Between 1 and 2, the OLD sync-steam fails on purpose: it inserts rows without
-- an igdb_id, which games_igdb_id_required rejects.
--
-- The migration aborts (changing nothing) if it finds games rows it can't
-- classify; see the check in step 3.

-- 1. The canonical id for an IGDB game --------------------------------------
-- Must stay identical to igdbGameUuid() in sync-steam and gameIdForIgdb() in
-- lib/models/game.dart. IGDB ids are far below 10^12, so 12 digits is plenty.
create or replace function public.igdb_game_uuid(igdb bigint)
returns uuid
language sql
immutable
strict
parallel safe
set search_path = ''
as $$
  select ('00000000-0000-4000-8000-' || lpad(igdb::text, 12, '0'))::uuid
$$;

-- 2. Columns -----------------------------------------------------------------
-- igdb_id already exists (the app has always selected it); normalise it to
-- bigint. Only when it isn't one yet: ALTER ... TYPE refuses to run on a column
-- that a trigger or view depends on (games_fill_igdb_id, below) even when the
-- type would not change, so an unconditional ALTER makes this file fail when it
-- is applied a second time.
alter table public.games add column if not exists igdb_id bigint;
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'games'
      and column_name = 'igdb_id' and data_type <> 'bigint'
  ) then
    alter table public.games alter column igdb_id type bigint using igdb_id::bigint;
  end if;
end;
$$;

alter table public.games add column if not exists steam_app_id bigint;

-- user_games.achievements is read by the app and written by sync-achievements,
-- but 20261012120000_add_achievements_to_user_games.sql contains the steam_id
-- migration by mistake, so a fresh database never got this column. merge_game_into
-- below uses it. No-op on a database that already has it.
alter table public.user_games add column if not exists achievements jsonb;

-- 3. Refuse to continue on data we can't classify ---------------------------
do $$
declare
  bad integer;
begin
  select count(*) into bad
  from public.games
  where igdb_id is not null
    and (igdb_id not between 1 and 999999999999
         or id <> public.igdb_game_uuid(igdb_id));

  if bad > 0 then
    raise exception
      'Found % games row(s) whose igdb_id is set but whose id is not the id derived from it. They need a decision from you before ids can be unified. List them with: select id, igdb_id, title from public.games where igdb_id is not null and id::text <> ''00000000-0000-4000-8000-'' || lpad(igdb_id::text, 12, ''0''); If they are stale data, clear the value (update public.games set igdb_id = null where <same condition>) and run this migration again.',
      bad;
  end if;
end;
$$;

-- 4. Backfill -----------------------------------------------------------------
-- Search-added games already carry their IGDB id inside their uuid.
update public.games
   set igdb_id = right(id::text, 12)::bigint
 where igdb_id is null
   and id::text ~ '^00000000-0000-4000-8000-[0-9]{12}$'
   and right(id::text, 12)::bigint > 0;

-- Steam-synced games carry their Steam app id inside their uuid.
update public.games
   set steam_app_id = right(id::text, 12)::bigint
 where steam_app_id is null
   and id::text ~ '^57e40000-0000-0000-0000-[0-9]{12}$';

-- 5. Constraints, index, trigger ---------------------------------------------
-- One row per IGDB game. A plain (non-partial) unique index, so the clients can
-- use `on conflict (igdb_id)`; NULLs (legacy rows) don't collide with each other.
create unique index if not exists games_igdb_id_key on public.games (igdb_id);

-- Fast "which games are these Steam apps?" lookups for sync-steam.
create index if not exists games_steam_app_id_idx
  on public.games (steam_app_id)
  where steam_app_id is not null;

-- id is a pure function of igdb_id. Validated now: step 3 proved existing rows pass.
alter table public.games drop constraint if exists games_id_matches_igdb_id;
alter table public.games
  add constraint games_id_matches_igdb_id
  check (
    igdb_id is null
    or (igdb_id between 1 and 999999999999 and id = public.igdb_game_uuid(igdb_id))
  );

-- Every NEW or UPDATED row needs an igdb_id. NOT VALID because the legacy
-- Steam-keyed rows don't have one yet, and a constraint can't be validated
-- while they exist. When this returns 0:
--     select count(*) from public.games where igdb_id is null;
-- run:
--     alter table public.games validate constraint games_igdb_id_required;
alter table public.games drop constraint if exists games_igdb_id_required;
alter table public.games
  add constraint games_igdb_id_required
  check (igdb_id is not null) not valid;

-- Safety net for app builds that predate this change: they insert search-added
-- games with the IGDB-derived id but without igdb_id. Fill it in from the id, so
-- those rows still end up well-formed. Runs before the constraints above.
create or replace function public.games_fill_igdb_id()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.igdb_id is null
     and new.id::text ~ '^00000000-0000-4000-8000-[0-9]{12}$'
     and right(new.id::text, 12)::bigint > 0 then
    new.igdb_id := right(new.id::text, 12)::bigint;
  end if;
  return new;
end;
$$;

drop trigger if exists games_fill_igdb_id on public.games;
create trigger games_fill_igdb_id
  before insert or update of id, igdb_id on public.games
  for each row execute function public.games_fill_igdb_id();

-- 6. Folding a duplicate into the IGDB-keyed row ------------------------------
-- Moves everything that points at game `from_id` over to `into_id` for ALL users,
-- then deletes `from_id`. Idempotent: if `from_id` is already gone it does nothing.
--
-- A user who tracks BOTH rows ends up with one. Their hours are the larger of the
-- two; status and platform come from the row with more hours (ties: the target
-- row); rating, price and platform fall back to the other row when empty; favorite
-- is "either"; date_added is the earlier; stored achievements are kept if either
-- row has them. Other users' rows are simply re-pointed.
--
-- The delete at the end fails (and the whole call rolls back) if some other table
-- still references `from_id` through a foreign key, rather than orphaning data.
create or replace function public.merge_game_into(from_id uuid, into_id uuid)
returns void
language plpgsql
set search_path = public
as $$
declare
  from_steam bigint;
begin
  if from_id is null or into_id is null or from_id = into_id then
    return;
  end if;
  if not exists (select 1 from games where id = from_id) then
    return;
  end if;
  if not exists (select 1 from games where id = into_id) then
    raise exception 'merge_game_into: target game % does not exist', into_id;
  end if;

  select steam_app_id into from_steam from games where id = from_id;

  -- Users with a row on both games: fold the duplicate into the target's row.
  update user_games t
     set hours_played   = greatest(coalesce(t.hours_played, 0), coalesce(f.hours_played, 0)),
         status         = case when coalesce(f.hours_played, 0) > coalesce(t.hours_played, 0)
                               then f.status else t.status end,
         played_on      = case when coalesce(f.hours_played, 0) > coalesce(t.hours_played, 0)
                               then coalesce(f.played_on, t.played_on)
                               else coalesce(t.played_on, f.played_on) end,
         rating         = coalesce(nullif(t.rating, 0), f.rating, t.rating),
         purchase_price = coalesce(nullif(t.purchase_price, 0), f.purchase_price, t.purchase_price),
         is_favorite    = coalesce(t.is_favorite, false) or coalesce(f.is_favorite, false),
         date_added     = least(t.date_added, f.date_added),
         achievements   = coalesce(t.achievements, f.achievements)
    from user_games f
   where t.game_id = into_id
     and f.game_id = from_id
     and f.user_id = t.user_id;

  delete from user_games f
   using user_games t
   where f.game_id = from_id
     and t.game_id = into_id
     and t.user_id = f.user_id;

  -- Everyone else: re-point.
  update user_games set game_id = into_id where game_id = from_id;
  update log_entries set game_id = into_id where game_id = from_id;

  delete from games where id = from_id;

  -- Don't lose which Steam app the folded row was.
  if from_steam is not null then
    update games set steam_app_id = from_steam
     where id = into_id and steam_app_id is null;
  end if;
end;
$$;

-- Called by sync-steam after it matches Steam apps to IGDB games.
-- links: [{ "app_id": 1086, "game_id": "<igdb-keyed games.id>", "legacy_id": "<57e4... games.id>" | null }, ...]
-- For each link: record the Steam app on the game (first one wins when two Steam
-- apps resolve to the same IGDB game), then fold the legacy row, if any, into it.
-- Returns { "linked": n, "merged": m }.
create or replace function public.link_steam_apps(links jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  l record;
  n_linked integer := 0;
  n_merged integer := 0;
begin
  for l in
    select * from jsonb_to_recordset(links) as x(app_id bigint, game_id uuid, legacy_id uuid)
  loop
    update games set steam_app_id = l.app_id
     where id = l.game_id and steam_app_id is null;
    if found then
      n_linked := n_linked + 1;
    end if;

    if l.legacy_id is not null
       and l.legacy_id <> l.game_id
       and exists (select 1 from games where id = l.legacy_id) then
      perform merge_game_into(l.legacy_id, l.game_id);
      n_merged := n_merged + 1;
    end if;
  end loop;

  return jsonb_build_object('linked', n_linked, 'merged', n_merged);
end;
$$;

-- These rewrite every user's library, so only the service role (Edge Functions)
-- may call them. Supabase grants new functions to anon and authenticated by
-- default, which would expose them as /rest/v1/rpc/... to any signed-in user.
revoke all on function public.merge_game_into(uuid, uuid) from public, anon, authenticated;
revoke all on function public.link_steam_apps(jsonb) from public, anon, authenticated;
grant execute on function public.merge_game_into(uuid, uuid) to service_role;
grant execute on function public.link_steam_apps(jsonb) to service_role;

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------------
-- Follow-ups, by hand, whenever you like:
--
--   -- Legacy rows still waiting for a sync to adopt them:
--   select count(*) from public.games where igdb_id is null;
--
--   -- ...of which are not Steam games (no app id), so no sync will ever adopt
--   -- them; they stay as they are unless you merge them yourself:
--   select id, title from public.games where igdb_id is null and steam_app_id is null;
--
--   -- Merge one by hand (the target row must already exist):
--   select public.merge_game_into('<legacy id>', public.igdb_game_uuid(<igdb id>));
-- ---------------------------------------------------------------------------
