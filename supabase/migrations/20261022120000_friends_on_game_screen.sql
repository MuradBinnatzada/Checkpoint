-- Friends on a game's screen.
--
-- A game's screen now shows which of the members you follow have the game, by
-- status: completed it, are playing it, want to play it (To Play or Wishlist),
-- each with their photo and the rating they gave, like Letterboxd's "Watched by".
--
--   following_game_activity(game)    one row per member the caller follows who
--                                    has the game in their library: their public
--                                    profile fields, status, rating and when they
--                                    added it, plus how many followed members
--                                    have that status in all.
--
-- Nothing new is exposed: status, rating and date_added are already readable by
-- every signed-in member through `public_user_games`
-- (20261017140000_public_profiles_and_social_graph.sql). The function only saves
-- the app from listing everyone it follows and then their games, two requests
-- with an `in (...)` list that grows with the follow list. Like the functions in
-- that file it runs as its owner (SECURITY DEFINER), so it names every column it
-- returns: never add purchase_price, achievements, email or steam_id.
--
-- At most `per_status` members are returned per status (rated first, then the
-- most recently added), so a popular game is still a small payload; `status_total`
-- is the full count either way.
--
-- Deploy order: apply this migration before shipping the app build that uses it.
-- Until then the game screen leaves the section out (the request fails quietly).

create or replace function public.following_game_activity(
  target_game uuid,
  per_status integer default 20
)
returns table (
  id uuid,
  handle text,
  display_name text,
  avatar_url text,
  status text,
  rating double precision,
  date_added timestamptz,
  status_total integer
)
language sql
stable
security definer
set search_path = ''
as $$
  select r.id, r.handle, r.display_name, r.avatar_url,
         r.status, r.rating, r.date_added, r.status_total
  from (
    select p.id,
           p.handle::text as handle,
           p.display_name::text as display_name,
           p.avatar_url::text as avatar_url,
           ug.status::text as status,
           coalesce(ug.rating, 0)::double precision as rating,
           ug.date_added::timestamptz as date_added,
           count(*) over (partition by ug.status)::integer as status_total,
           row_number() over (
             partition by ug.status
             order by (coalesce(ug.rating, 0) > 0) desc,
                      ug.date_added desc nulls last,
                      p.id
           ) as position
    from public.social_follows f
    join public.user_games ug
      on ug.user_id = f.followee_id and ug.game_id = target_game
    join public.profiles p on p.id = f.followee_id
    where f.follower_id = (select auth.uid())
      and ug.status is not null
  ) r
  where r.position <= least(greatest(coalesce(per_status, 20), 1), 50)
  order by r.status, r.position
$$;

comment on function public.following_game_activity(uuid, integer) is
  'Members the caller follows who have target_game: public profile fields, status, rating, date_added. Never add purchase_price, achievements, email or steam_id.';

-- Functions are executable by PUBLIC unless revoked.
revoke all on function public.following_game_activity(uuid, integer) from public, anon, authenticated;
grant execute on function public.following_game_activity(uuid, integer) to authenticated;

notify pgrst, 'reload schema';
