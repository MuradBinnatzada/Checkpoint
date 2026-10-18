-- IGDB game details on the shared catalog, and exact platforms.
--
-- 1. games: the stable part of what IGDB says about a game, kept once per game for
--    everyone instead of being fetched again by every member:
--      developers / publishers   the main ones (IGDB's own page lists them like that)
--      themes, game_modes, player_perspectives, game_engines
--      igdb_synced_at            when the `igdb-handler` Edge Function (mode
--                                `details` or `backfill`) last filled the row in. It
--                                refreshes a row at most once a week. NULL: never; the
--                                app reads only that (which of its library's games
--                                are NULL) to send them to `backfill` in the
--                                background.
--    `platforms` and `genres` already existed. `platforms` now holds exact consoles
--    ('ps3', 'xbox360', 'wiiU'...: the GamePlatform enum names in
--    lib/models/game.dart) instead of brand families; rows that still hold the old
--    families ('playstation', 'xbox'...) are read as before and replaced as each
--    game's details are opened, or as the app's background backfill reaches it.
--
--    The columns are not part of the library query (the payload would grow for every
--    row of every library, and of the copy saved on the device). The app reads them
--    in a query of its own, when the Library's filter sheet opens (user_games joined
--    to the games with igdb_synced_at set, these columns only), to filter by theme,
--    mode, perspective, engine, developer and publisher.
--
--    Storyline, similar games and time to beat are NOT stored: the storyline is only
--    read on the details screen, similar games and time to beat change with IGDB's
--    ratings and votes, and none of them is something to filter on. The app asks
--    `igdb-handler` for them and keeps them in memory.
--
--    Who writes these columns: the Edge Function, with the service role, from IGDB's
--    own answer. RLS lets a member edit only the catalog rows they created, so no
--    member could (or needs to) write them. The size limits below are for the
--    members who can: like the other `games_*` constraints they are NOT VALID, so
--    new and updated rows are checked and existing rows are not.
--
-- 2. user_games.played_on and log_entries.platform: the platform a game is played on
--    is now as exact as the catalog's ('ps3', 'xbox360'...), so a constraint that
--    lists the old values would refuse it. Every CHECK that mentions either column is
--    dropped and replaced by one that only requires a short plain word, which is
--    what the app writes (GamePlatform names, and 'retro' for Emulator).
--
-- Deploy order: apply this migration, then deploy `igdb-handler` (it writes the new
-- columns), then ship the app build.

-- 1. Catalog ------------------------------------------------------------------
alter table public.games
  add column if not exists developers          text[] not null default '{}',
  add column if not exists publishers          text[] not null default '{}',
  add column if not exists themes              text[] not null default '{}',
  add column if not exists game_modes          text[] not null default '{}',
  add column if not exists player_perspectives text[] not null default '{}',
  add column if not exists game_engines        text[] not null default '{}',
  add column if not exists igdb_synced_at      timestamptz;

alter table public.games
  drop constraint if exists games_igdb_lists_size,
  add constraint games_igdb_lists_size
    check (
      cardinality(developers) <= 50
      and cardinality(publishers) <= 50
      and cardinality(themes) <= 50
      and cardinality(game_modes) <= 50
      and cardinality(player_perspectives) <= 50
      and cardinality(game_engines) <= 50
    ) not valid;

comment on column public.games.igdb_synced_at is
  'When igdb-handler (mode details or backfill) last filled in platforms, genres, themes, game modes, perspectives, engines, developers and publishers from IGDB. NULL: never.';

-- 2. Exact "played on" platforms ------------------------------------------------
do $$
declare
  c record;
begin
  for c in
    select con.conrelid::regclass as tbl, con.conname
    from pg_constraint con
    where con.contype = 'c'
      and (
        (con.conrelid = 'public.user_games'::regclass
          and pg_get_constraintdef(con.oid) ~* '\mplayed_on\M')
        or (con.conrelid = 'public.log_entries'::regclass
          and pg_get_constraintdef(con.oid) ~* '\mplatform\M')
      )
  loop
    execute format('alter table %s drop constraint %I', c.tbl, c.conname);
  end loop;
end
$$;

alter table public.user_games
  add constraint user_games_played_on_format
    check (played_on is null or played_on ~ '^[A-Za-z0-9]{1,24}$') not valid;

alter table public.log_entries
  add constraint log_entries_platform_format
    check (platform is null or platform ~ '^[A-Za-z0-9]{1,24}$') not valid;
