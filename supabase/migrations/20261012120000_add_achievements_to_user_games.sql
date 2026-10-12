-- On-demand Steam achievements, stored per user per game.
--
-- One JSONB array on the existing user_games row instead of a child table:
-- achievements are only ever read and written as a whole list for a single
-- (user, game), so a relational table would just add thousands of tiny rows
-- and joins for no query benefit.
--
-- NULL      = achievements have never been loaded for this game
-- '[]'      = loaded; the game has no Steam achievements
-- '[{...}]' = loaded. Each element:
--             { "name": text, "description": text, "icon_url": text,
--               "unlocked": boolean, "unlocked_at": ISO-8601 text | null }
--
-- Written by the `sync-achievements` Edge Function (service role). Existing
-- row-level policies on user_games already cover the new column.

alter table public.user_games
  add column if not exists achievements jsonb default null
  constraint user_games_achievements_is_array
    check (achievements is null or jsonb_typeof(achievements) = 'array');

comment on column public.user_games.achievements is
  'Merged Steam achievement schema + player unlock state. NULL = not loaded yet.';