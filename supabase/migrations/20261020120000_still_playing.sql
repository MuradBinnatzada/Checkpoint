-- "Still playing" for completed games: a game the member finished but plays on
-- (online, post-game, DLC) stays Completed and is listed under Playing too, in
-- the library's Playing tab and on Home.
--
-- user_games.still_playing: false unless the member turns it on, on the game's
-- screen. Only a completed game can be still played: user_games_track_completion
-- (20261019015200_completion_dates_reviews_release_dates.sql) now clears it with
-- completed_at whenever the status is anything else, and a check backs that up.
--
-- It stays private for now: public_user_games doesn't return it, so other
-- members see the game as Completed only.
--
-- Deploy order: apply this migration before shipping the app build that uses
-- it. That build reads and writes the column with the library, which fails
-- until it exists.

alter table public.user_games
  add column if not exists still_playing boolean not null default false;

comment on column public.user_games.still_playing is
  'A completed game the member still plays (online, post-game...), listed under Playing too. Cleared by user_games_track_completion whenever the status is not completed.';

create or replace function public.user_games_track_completion()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.status = 'completed' then
    new.completed_at := case
      when tg_op = 'INSERT' or old.status is distinct from 'completed' then now()
      else old.completed_at
    end;
  else
    new.completed_at := null;
    new.still_playing := false;
  end if;
  return new;
end;
$$;

-- The trigger runs first, so this only ever stops a write that bypasses it.
alter table public.user_games
  drop constraint if exists user_games_still_playing_completed,
  add constraint user_games_still_playing_completed
    check (not still_playing or status = 'completed');

notify pgrst, 'reload schema';
