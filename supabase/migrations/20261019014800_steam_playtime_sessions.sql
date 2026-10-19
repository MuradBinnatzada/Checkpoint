-- Play sessions from Steam playtime.
--
-- Steam only reports how long a game has been played in all. sync-steam now keeps
-- the playtime it saw on the library row, and when a later sync (by hand or the
-- background one, every 12 hours) sees more, it logs the difference as a play
-- session, dated when Steam says the game was last played. The first playtime
-- seen for a game is its whole history, so it is only kept, not logged. See
-- supabase/functions/_shared/steam_sessions.ts for the rules.
--
-- Deploy order: apply this migration, then deploy sync-steam (it writes both
-- columns), then ship the app build that shows where a session came from.

alter table public.user_games
  add column if not exists steam_playtime_minutes integer;

alter table public.user_games
  drop constraint if exists user_games_steam_playtime_minutes_range,
  add constraint user_games_steam_playtime_minutes_range
    check (steam_playtime_minutes is null or steam_playtime_minutes >= 0);

comment on column public.user_games.steam_playtime_minutes is
  'Steam playtime_forever (minutes) at the last sync that logged a session or set the baseline. NULL: not seen yet. Written by sync-steam only; never shown to other members.';

-- Where a session came from: NULL is logged by the member, 'steam' by sync-steam.
alter table public.log_entries
  add column if not exists source text;

alter table public.log_entries
  drop constraint if exists log_entries_source_known,
  add constraint log_entries_source_known
    check (source is null or source = 'steam');

comment on column public.log_entries.source is
  'NULL: logged by the member. steam: logged by sync-steam from a rise in Steam playtime.';

-- A member logs their own sessions, never Steam ones: only the service role
-- (sync-steam) sets a source. A member's insert has none, and a member's edit
-- keeps the one the session has.
create or replace function public.log_entries_keep_source()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user in ('authenticated', 'anon') then
    new.source := case when tg_op = 'UPDATE' then old.source else null end;
  end if;
  return new;
end;
$$;

drop trigger if exists log_entries_keep_source on public.log_entries;
create trigger log_entries_keep_source
  before insert or update on public.log_entries
  for each row execute function public.log_entries_keep_source();

notify pgrst, 'reload schema';

-- The public views list their columns, so neither column is exposed. Check.
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name in ('public_user_games', 'public_recent_activity')
      and column_name = 'steam_playtime_minutes'
  ) then
    raise exception 'A public view exposes steam_playtime_minutes';
  end if;
end;
$$;
