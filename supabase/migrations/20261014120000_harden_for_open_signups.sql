-- Hardening before Google sign-in is opened to every account.
--
-- 1. profiles: drop the old "profiles are public readable" SELECT policy.
--    It is `using (true)` and applies to anon too. Reads were only kept private
--    by the restrictive policy `profiles_select_own_only`; with this gone, nothing
--    depends on that one. Safe: it is SELECT-only, own-row reads are covered by
--    `profiles_select_own`, and other members are read through `public_profiles`.
--
-- 2. games: any signed-in user may insert catalog rows (created_by = auth.uid())
--    and edit the ones they created, so the free-text columns need limits.
--    The cover URL is loaded by every user's app, so it may only point at IGDB's
--    image host (both the app and sync-steam already produce
--    https://images.igdb.com/...). Length limits are deliberately generous: one
--    oversized row would fail a whole sync-steam batch upsert.
--
--    NOT VALID = new rows and updated rows are checked; existing rows are not.
--    To see whether old rows would fail, run this first:
--
--      select id, title, cover_url from public.games
--      where cover_url is not null and cover_url !~ '^https://images\.igdb\.com/';
--
--    Once that returns nothing (or you've fixed those rows), enforce on old rows too:
--
--      alter table public.games validate constraint games_cover_url_igdb;
--      (and likewise for the other games_* constraints below)
--
-- This does NOT stop someone from inserting a fake game under an unused id.
-- That needs catalog writes moved to an Edge Function (service role).
--
-- Not changed on purpose: the Security Advisor flags `public.public_profiles` as
-- SECURITY DEFINER. That is intentional (see 20261013130000_...): it exposes only
-- id, handle, display_name and avatar_url, and only to `authenticated`.

drop policy if exists "profiles are public readable" on public.profiles;

alter table public.games
  add constraint games_cover_url_igdb
    check (cover_url is null or cover_url ~ '^https://images\.igdb\.com/') not valid,
  add constraint games_title_length
    check (char_length(title) between 1 and 300) not valid,
  add constraint games_publisher_length
    check (publisher is null or char_length(publisher) <= 300) not valid,
  add constraint games_developer_length
    check (developer is null or char_length(developer) <= 300) not valid,
  add constraint games_summary_length
    check (char_length(summary) <= 10000) not valid,
  add constraint games_platforms_size
    check (cardinality(platforms) <= 50) not valid,
  add constraint games_genres_size
    check (cardinality(genres) <= 50) not valid;
