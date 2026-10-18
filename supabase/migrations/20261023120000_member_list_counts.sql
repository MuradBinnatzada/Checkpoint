-- Game and follower counts in the member list.
--
-- The Users tab of Discover shows "N games · N followers" under every member, but
-- the app had no way to read those numbers for a whole page of members, so it
-- showed 0 for everyone. `public_profiles` now carries them:
--
--   games_count      how many games the member has in their library (any status),
--                    the same number as `games` from public_profile_stats.
--   followers_count  how many members follow them.
--   viewer_follows   whether the caller follows them, so the app can move the
--                    follower count as soon as the Follow button is tapped.
--
-- Nothing new is exposed: both counts are already readable by every signed-in
-- member through public_profile_stats, one member at a time
-- (20261017140000_public_profiles_and_social_graph.sql).
--
-- Cost: the counts are subqueries, and a view is flattened into the query that
-- reads it, so only requests that select these columns pay for them (the profile
-- header, the handle check and the follow lists do not). With a LIMIT, Postgres
-- also computes them after the page is cut, so a page of 30 members is 60 index
-- lookups: social_follows_followee_created_idx and the (user_id, game_id) key of
-- user_games.
--
-- Deploy order: apply this migration before shipping the app build that uses it.
-- Until then the Users tab fails to load (the new columns don't exist).

-- Columns can only be added at the END of an existing view. The first fourteen
-- are those of 20261019120000_instagram_twitch_accounts.sql.
create or replace view public.public_profiles
  with (security_invoker = false) as
  select p.id,
         p.handle,
         p.display_name,
         p.avatar_url,
         (nullif(btrim(p.steam_id), '') is not null) as steam_connected,
         p.connected_services,
         p.bio,
         p.steam_id,
         p.psn_id,
         p.xbox_id,
         p.discord_id,
         p.created_at as joined_at,
         p.instagram_id,
         p.twitch_id,
         (select count(*)::integer from public.user_games ug
          where ug.user_id = p.id) as games_count,
         (select count(*)::integer from public.social_follows f
          where f.followee_id = p.id) as followers_count,
         exists (
           select 1 from public.social_follows f
           where f.follower_id = (select auth.uid()) and f.followee_id = p.id
         ) as viewer_follows
  from public.profiles p;

comment on view public.public_profiles is
  'Public fields of every profile, readable by any signed-in user: name, handle, avatar, bio, linked services and their account names, member since, game and follower counts, and whether the caller follows them. Never add email.';

revoke all on public.public_profiles from public, anon, authenticated;
grant select on public.public_profiles to authenticated;

notify pgrst, 'reload schema';

-- Fail loudly if the result is not what this file promises.
do $$
begin
  if (
    select count(*) from information_schema.columns
    where table_schema = 'public' and table_name = 'public_profiles'
      and column_name in ('games_count', 'followers_count', 'viewer_follows')
  ) <> 3 then
    raise exception 'public.public_profiles is missing a count column';
  end if;

  -- Still none of the columns that stay private.
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name in (
        'public_profiles', 'public_followers', 'public_following',
        'public_user_games', 'public_recent_activity'
      )
      and column_name in ('email', 'purchase_price', 'achievements', 'note')
  ) then
    raise exception 'A public view exposes a column that must stay private';
  end if;

  -- Signed-in members read it, anonymous callers do not.
  if has_table_privilege('anon', 'public.public_profiles', 'select')
     or not has_table_privilege('authenticated', 'public.public_profiles', 'select') then
    raise exception 'public.public_profiles has the wrong grants';
  end if;
end;
$$;
