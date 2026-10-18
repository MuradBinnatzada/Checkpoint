-- Each member's own backdrop for a game.
--
-- Behind a game's header and its Home card the app draws the game's cover,
-- blurred. On a game's screen a member can now pick one of the game's IGDB
-- artworks or screenshots (igdb-handler's `media` mode) to show there instead,
-- sharp. The cover itself stays IGDB's. The pick is theirs, so it lives on their
-- library row:
--
--   user_games.custom_backdrop_url   the backdrop, NULL: the blurred cover
--
-- It is shown wherever the member's library is, including to other members
-- (public_user_games), so it may only ever be an IGDB image URL: no other host,
-- nothing that could track who looks at the profile.
--
-- Deploy order: apply this migration before shipping the app build that uses it.
-- The new build reads the columns with the library, so it fails to load one
-- until they exist.

-- 1. Columns ---------------------------------------------------------------------
alter table public.user_games
  add column if not exists custom_backdrop_url text;

comment on column public.user_games.custom_backdrop_url is
  'The member''s chosen backdrop for the game, an IGDB image URL. NULL: the blurred cover.';

alter table public.user_games
  drop constraint if exists user_games_custom_backdrop_igdb,
  add constraint user_games_custom_backdrop_igdb
    check (
      custom_backdrop_url is null
      or custom_backdrop_url ~ '^https://images\.igdb\.com/igdb/image/upload/t_[a-z0-9_]{1,24}/[A-Za-z0-9]{1,32}\.(jpg|png|webp)$'
    );

-- 2. Other members see it too -----------------------------------------------------
-- Columns can only be added at the END of an existing view; the first eighteen are
-- the ones 20261017140000_public_profiles_and_social_graph.sql defined.
create or replace view public.public_user_games
  with (security_invoker = false) as
  select ug.user_id,
         ug.game_id,
         ug.status,
         ug.rating,
         ug.hours_played,
         ug.played_on,
         ug.date_added,
         ug.is_favorite,
         g.igdb_id,
         g.steam_app_id,
         g.title,
         g.publisher,
         g.developer,
         g.release_year,
         g.platforms,
         g.genres,
         g.summary,
         g.cover_url,
         ug.custom_backdrop_url
  from public.user_games ug
  join public.games g on g.id = ug.game_id;

comment on view public.public_user_games is
  'What other members may see of a library. Never add purchase_price or achievements.';

revoke all on public.public_user_games from public, anon, authenticated;
grant select on public.public_user_games to authenticated;

notify pgrst, 'reload schema';

-- Fail loudly if the result is not what this file promises.
do $$
begin
  if (
    select count(*) from information_schema.columns
    where table_schema = 'public' and table_name = 'public_user_games'
      and column_name = 'custom_backdrop_url'
  ) <> 1 then
    raise exception 'public.public_user_games is missing custom_backdrop_url';
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'public_user_games'
      and column_name in ('purchase_price', 'achievements')
  ) then
    raise exception 'public.public_user_games exposes a column that must stay private';
  end if;

  if has_table_privilege('anon', 'public.public_user_games', 'select')
     or not has_table_privilege('authenticated', 'public.public_user_games', 'select') then
    raise exception 'public.public_user_games has the wrong grants';
  end if;
end;
$$;
