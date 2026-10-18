-- Move Steam apps that were matched to the wrong IGDB game.
--
-- Problem: sync-steam used to resolve a Steam app to an IGDB game by its title
-- alone. A title can name several games: Steam's "Tomb Raider" (the 2013 reboot)
-- was linked to the 1996 "Tomb Raider", Valve's "Deadlock" to an unrelated 2021
-- "DeadLock". Once linked, `games.steam_app_id` made every later sync trust it.
--
-- Fix: sync-steam now reads IGDB's own Steam links (`external_games`), which name
-- the game by app id. When a known app's game is not the one IGDB links it to,
-- the sync calls `relink_steam_apps` below, which
--   * records the move in `steam_app_relinks`,
--   * moves `games.steam_app_id` from the wrong game to the right one, and
--   * folds the syncing member's library row and play sessions on the wrong game
--     into the right one.
-- Only that member's rows move: someone else may have added the other game on
-- purpose (the 1996 Tomb Raider is a real game). Every other owner of the app has
-- theirs moved on their own next sync, which finds the recorded move by app id.
--
-- Deploy order: apply this migration, then deploy sync-steam. A sync-steam that
-- runs without it still syncs; it leaves wrongly matched games where they are.

-- 1. Recorded moves ------------------------------------------------------------
create table if not exists public.steam_app_relinks (
  app_id     bigint not null,
  from_id    uuid not null, -- the wrongly linked game (may be gone from games later)
  into_id    uuid not null references public.games (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (app_id, from_id)
);

comment on table public.steam_app_relinks is
  'Steam apps sync-steam moved off a game an old title match linked them to. Read by sync-steam to move each owner''s library row; service role only.';

-- Only the service role (sync-steam) reads or writes it.
alter table public.steam_app_relinks enable row level security;
revoke all on public.steam_app_relinks from public, anon, authenticated;
grant select, insert, update, delete on public.steam_app_relinks to service_role;

-- 2. Fold one member's row on a game into their row on another -------------------
-- The per-member twin of merge_game_into (20261016120000_unify_game_ids_on_igdb_id.sql),
-- with the same rules when the member has both rows: hours are the larger, status
-- and platform come from the row with more hours (ties: the target row), rating
-- and price fall back to the other row when empty, favorite is "either",
-- date_added the earlier, and stored achievements and their counts are kept if
-- either row has them. A moved row loses its chosen backdrop, which was art of the
-- other game. Returns whether a row was moved or folded.
create or replace function public.merge_user_game_into(target_user uuid, from_id uuid, into_id uuid)
returns boolean
language plpgsql
set search_path = public
as $$
begin
  if target_user is null or from_id is null or into_id is null or from_id = into_id then
    return false;
  end if;
  if not exists (select 1 from user_games where user_id = target_user and game_id = from_id) then
    return false;
  end if;

  if exists (select 1 from user_games where user_id = target_user and game_id = into_id) then
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
           achievements   = coalesce(t.achievements, f.achievements),
           achievements_unlocked  = coalesce(t.achievements_unlocked, f.achievements_unlocked),
           achievements_total     = coalesce(t.achievements_total, f.achievements_total),
           achievements_playtime  = coalesce(t.achievements_playtime, f.achievements_playtime),
           achievements_synced_at = coalesce(t.achievements_synced_at, f.achievements_synced_at)
      from user_games f
     where t.user_id = target_user and t.game_id = into_id
       and f.user_id = target_user and f.game_id = from_id;
    delete from user_games where user_id = target_user and game_id = from_id;
  else
    update user_games
       set game_id = into_id,
           custom_backdrop_url = null
     where user_id = target_user and game_id = from_id;
  end if;

  update log_entries set game_id = into_id where user_id = target_user and game_id = from_id;
  return true;
end;
$$;

-- 3. Called by sync-steam -----------------------------------------------------------
-- links: [{ "app_id": 203160, "from_id": "<wrong games.id>", "into_id": "<right games.id>" }, ...]
-- For each link: record it, take the app id off the wrong game, put it on the
-- right one (unless that game is already another app's), and fold target_user's
-- row on the wrong game into the right one. Idempotent. Returns { "moved": n }.
create or replace function public.relink_steam_apps(target_user uuid, links jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  l record;
  n_moved integer := 0;
begin
  for l in
    select * from jsonb_to_recordset(links) as x(app_id bigint, from_id uuid, into_id uuid)
  loop
    if l.app_id is null or l.from_id is null or l.into_id is null or l.from_id = l.into_id then
      continue;
    end if;
    if not exists (select 1 from games where id = l.into_id) then
      continue;
    end if;

    insert into steam_app_relinks (app_id, from_id, into_id)
    values (l.app_id, l.from_id, l.into_id)
    on conflict (app_id, from_id) do update set into_id = excluded.into_id;

    update games set steam_app_id = null where id = l.from_id and steam_app_id = l.app_id;
    update games set steam_app_id = l.app_id where id = l.into_id and steam_app_id is null;

    if merge_user_game_into(target_user, l.from_id, l.into_id) then
      n_moved := n_moved + 1;
    end if;
  end loop;

  return jsonb_build_object('moved', n_moved);
end;
$$;

-- These rewrite a member's library, so only the service role (Edge Functions) may
-- call them; Supabase grants new functions to anon and authenticated by default.
revoke all on function public.merge_user_game_into(uuid, uuid, uuid) from public, anon, authenticated;
revoke all on function public.relink_steam_apps(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.merge_user_game_into(uuid, uuid, uuid) to service_role;
grant execute on function public.relink_steam_apps(uuid, jsonb) to service_role;

notify pgrst, 'reload schema';
