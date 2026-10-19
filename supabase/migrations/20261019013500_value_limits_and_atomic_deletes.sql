-- Limits on the numbers members type in, and game removal in one request.
--
-- 1. Limits. Nothing stopped a client from saving negative hours, a rating of 40
--    or a session dated next year: the app checks its own input, but anyone with a
--    session can call the API directly. The ranges are generous on purpose:
--
--      user_games.hours_played     0 - 100 000 (Steam's longest playtimes are far below)
--      user_games.rating           0 - 5 (0 = not rated; the app rates in halves)
--      user_games.purchase_price   0 - 100 000
--      log_entries.hours           more than 0, at most 100 000 (a "set total
--                                  hours" edit logs the difference as one session)
--      log_entries.logged_at       not more than a day ahead (clock skew); any
--                                  time in the past, so sessions can be backdated
--      log_entries.note            at most 1 000 characters
--
--    The library values already saved are moved into range first (a
--    negative becomes 0, anything above the top becomes the top), so the
--    constraints hold for every row and editing an old row never fails on a value
--    the member can't see. Sessions are not changed: the constraint is NOT VALID,
--    which checks new and edited sessions only. To check old ones too, once this
--    returns nothing:
--      select id, hours from public.log_entries
--      where hours <= 0 or hours > 100000 or char_length(note) > 1000;
--    run:
--      alter table public.log_entries validate constraint log_entries_hours_range;
--      alter table public.log_entries validate constraint log_entries_note_length;
--
-- 2. Removing a game from the library took two requests, sessions and then the
--    library row, so a failure in between lost the sessions and kept the game.
--    remove_library_game does both in one transaction, and clear_library the
--    same for the whole library. They run as the caller (SECURITY INVOKER), so
--    the row ownership policies (20261017120000) still decide what they may
--    delete, and they only ever look at the caller's own rows.
--
-- Deploy order: apply this migration before shipping the app build that calls
-- the two functions.

-- 1. Limits -----------------------------------------------------------------

update public.user_games set hours_played = 0 where hours_played < 0;
update public.user_games set hours_played = 100000 where hours_played > 100000;
update public.user_games set rating = 0 where rating < 0;
update public.user_games set rating = 5 where rating > 5;
update public.user_games set purchase_price = 0 where purchase_price < 0;
update public.user_games set purchase_price = 100000 where purchase_price > 100000;

alter table public.user_games
  drop constraint if exists user_games_hours_played_range,
  add constraint user_games_hours_played_range
    check (hours_played is null or hours_played between 0 and 100000),
  drop constraint if exists user_games_rating_range,
  add constraint user_games_rating_range
    check (rating is null or rating between 0 and 5),
  drop constraint if exists user_games_purchase_price_range,
  add constraint user_games_purchase_price_range
    check (purchase_price is null or purchase_price between 0 and 100000);

alter table public.log_entries
  drop constraint if exists log_entries_hours_range,
  add constraint log_entries_hours_range
    check (hours > 0 and hours <= 100000) not valid,
  drop constraint if exists log_entries_note_length,
  add constraint log_entries_note_length
    check (char_length(note) <= 1000) not valid;

-- A CHECK can't compare with now() (it must give the same answer forever), so the
-- date is checked when a session is written.
create or replace function public.log_entries_not_in_future()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.logged_at > now() + interval '1 day' then
    raise exception 'A play session can''t be dated in the future (%).', new.logged_at
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

drop trigger if exists log_entries_not_in_future on public.log_entries;
create trigger log_entries_not_in_future
  before insert or update of logged_at on public.log_entries
  for each row execute function public.log_entries_not_in_future();

-- 2. Removing games -----------------------------------------------------------

-- Takes target_game out of the caller's library together with its play sessions:
-- both or neither. Removing a game that isn't there does nothing.
create or replace function public.remove_library_game(target_game uuid)
returns void
language sql
security invoker
set search_path = ''
as $$
  delete from public.log_entries
   where user_id = (select auth.uid()) and game_id = target_game;
  delete from public.user_games
   where user_id = (select auth.uid()) and game_id = target_game;
$$;

-- Empties the caller's library: every play session and every game, in one
-- transaction. The shared catalog is untouched.
create or replace function public.clear_library()
returns void
language sql
security invoker
set search_path = ''
as $$
  delete from public.log_entries where user_id = (select auth.uid());
  delete from public.user_games where user_id = (select auth.uid());
$$;

revoke all on function public.remove_library_game(uuid) from public, anon, authenticated;
revoke all on function public.clear_library() from public, anon, authenticated;
grant execute on function public.remove_library_game(uuid) to authenticated;
grant execute on function public.clear_library() to authenticated;

notify pgrst, 'reload schema';

-- Fail loudly if the result is not what this file promises.
do $$
begin
  if (
    select count(*) from pg_constraint
    where conname in (
      'user_games_hours_played_range', 'user_games_rating_range',
      'user_games_purchase_price_range', 'log_entries_hours_range',
      'log_entries_note_length'
    )
  ) <> 5 then
    raise exception 'A value limit is missing';
  end if;

  if has_function_privilege('anon', 'public.remove_library_game(uuid)', 'execute')
     or has_function_privilege('anon', 'public.clear_library()', 'execute')
     or not has_function_privilege('authenticated', 'public.remove_library_game(uuid)', 'execute')
     or not has_function_privilege('authenticated', 'public.clear_library()', 'execute') then
    raise exception 'The library functions have the wrong grants';
  end if;
end;
$$;
