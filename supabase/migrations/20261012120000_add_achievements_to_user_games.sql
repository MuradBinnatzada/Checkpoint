-- Steam ID64, stored per user on their profile.
--
-- Previously the Flutter app kept this in local SharedPreferences and sent it to
-- the `sync-steam` Edge Function in the request body. It now lives here, and
-- `sync-steam` reads it with the service role, keyed by the verified caller's
-- user id (profiles.id = auth.users.id), so a client can't pass someone else's.
--
-- NULL = the user has not connected Steam.
-- The app writes it with `update profiles set steam_id = ... where id = auth.uid()`,
-- which the existing own-row update policy on profiles already has to allow
-- (the profile editor uses the same path for display_name / handle / bio).

alter table public.profiles
  add column if not exists steam_id text default null;

comment on column public.profiles.steam_id is
  'Steam ID64 the user connected. Private: the app never selects it for other members.';
