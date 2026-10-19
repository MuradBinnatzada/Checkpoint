-- Base schema: the tables every later migration builds on.
--
-- profiles, games, user_games and log_entries (and the avatars bucket) were made
-- in the Supabase dashboard before this folder existed, so no migration created
-- them and a new database could not be built from the repository: the first
-- `alter table public.profiles` failed. This file creates them as the later
-- migrations, the app (lib/data/db_schema.dart) and the Edge Functions use them.
-- It sorts first, so `supabase db reset` and a new project apply everything in
-- order.
--
-- Only the columns the tables started with are here. Later migrations add the
-- rest with `add column if not exists` (steam_id, achievements, steam_app_id,
-- connected_services...), and constraints with names they own, so the history
-- reads the same on a new database as it did on the live one.
--
-- THE LIVE DATABASE ALREADY HAS ALL OF THIS. Don't run it there; record it as
-- applied (README > Database migrations):
--   supabase migration repair --status applied 20261011000000
-- Every statement is `if not exists` / `on conflict do nothing` all the same, so
-- running it by mistake changes nothing that exists.

create extension if not exists citext with schema extensions;

-- 1. profiles ---------------------------------------------------------------
-- One row per account, made by the app on first sign-in
-- (CheckpointRepository.ensureProfile). Readable only for your own row
-- (20261013130000); other members are read through public_profiles.
create table if not exists public.profiles (
  id                uuid primary key references auth.users (id) on delete cascade,
  email             text,
  display_name      text,
  -- Stored lowercase, without the "@" the app shows in front of it.
  handle            extensions.citext unique,
  bio               text not null default '',
  avatar_url        text,
  created_at        timestamptz not null default now()
);

-- 2. games ------------------------------------------------------------------
-- The shared catalog. Any signed-in member may add a game (search, Steam sync
-- does it with the service role) and edit the rows they added; everyone reads it,
-- including signed-out visitors (Home's "Recently Added").
create table if not exists public.games (
  id           uuid primary key,
  igdb_id      bigint,
  slug         text,
  title        text not null,
  publisher    text,
  developer    text,
  release_year integer
    constraint games_release_year_check
    check (release_year is null or release_year between 1950 and 2100),
  platforms    text[] not null default '{}',
  genres       text[] not null default '{}',
  summary      text default '',
  cover_url    text,
  -- The app doesn't send it: a member's insert is stamped with their id.
  created_by   uuid default auth.uid() references auth.users (id) on delete set null,
  created_at   timestamptz not null default now()
);

-- Home's "Recently Added" reads the newest rows.
create index if not exists games_created_at_idx on public.games (created_at desc);

alter table public.games enable row level security;

drop policy if exists games_select_all on public.games;
create policy games_select_all
  on public.games
  for select
  to anon, authenticated
  using (true);

drop policy if exists games_insert_own on public.games;
create policy games_insert_own
  on public.games
  for insert
  to authenticated
  with check (created_by = (select auth.uid()));

drop policy if exists games_update_own on public.games;
create policy games_update_own
  on public.games
  for update
  to authenticated
  using (created_by = (select auth.uid()))
  with check (created_by = (select auth.uid()));

-- 3. user_games ---------------------------------------------------------------
-- A member's library: one row per game they track. The SELECT policies (own rows
-- only) are in 20261017140000, the write policies in 20261017120000.
create table if not exists public.user_games (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users (id) on delete cascade,
  -- No cascade: merge_game_into (20261016120000) relies on a delete of a game
  -- that something still points at failing.
  game_id        uuid not null references public.games (id),
  status         text not null
    constraint user_games_status_check
    check (status in ('playing', 'to_play', 'completed', 'dropped', 'wishlist')),
  rating         real not null default 0,
  hours_played   double precision not null default 0,
  played_on      text,
  purchase_price numeric not null default 0,
  date_added     timestamptz not null default now(),
  is_favorite    boolean not null default false,
  created_at     timestamptz not null default now(),
  -- The app and sync-steam upsert on (user_id, game_id).
  constraint user_games_user_game_key unique (user_id, game_id)
);

create index if not exists user_games_game_id_idx on public.user_games (game_id);

-- 4. log_entries ----------------------------------------------------------------
-- Play sessions. Readable only for your own rows; other members see them through
-- public_recent_activity (20261018120000), without the note.
create table if not exists public.log_entries (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users (id) on delete cascade,
  game_id    uuid not null references public.games (id),
  hours      double precision not null,
  platform   text,
  note       text not null default '',
  -- The app sends it for a session logged offline; otherwise the time it arrives.
  logged_at  timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create index if not exists log_entries_user_game_idx on public.log_entries (user_id, game_id);

alter table public.log_entries enable row level security;

-- 20261017120000 says the app's reads rely on a SELECT policy being there; on the
-- live database it was made in the dashboard. This is the same rule.
drop policy if exists log_entries_select_own on public.log_entries;
create policy log_entries_select_own
  on public.log_entries
  for select
  to authenticated
  using (user_id = (select auth.uid()));

-- 5. social_follows -----------------------------------------------------------
-- 20261017140000 creates it too (and is a no-op where it exists), but
-- 20261017120000 already puts policies on it, so a new database needs it first.
create table if not exists public.social_follows (
  follower_id uuid not null references auth.users (id) on delete cascade,
  followee_id uuid not null references auth.users (id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (follower_id, followee_id)
);

-- 6. Realtime -----------------------------------------------------------------
-- The app follows changes to these tables (CheckpointRepository.watch*).
do $$
declare
  tbl text;
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    return;
  end if;
  foreach tbl in array array['profiles', 'user_games', 'log_entries', 'social_follows'] loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = tbl
    ) then
      execute format('alter publication supabase_realtime add table public.%I', tbl);
    end if;
  end loop;
end;
$$;

-- 7. The avatars bucket --------------------------------------------------------
-- Public, so photos load from their URL without a policy. Uploads are limited to
-- the member's own folder by 20261014130000; size and type are limited here.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'avatars',
  'avatars',
  true,
  2097152,
  array['image/jpeg', 'image/png', 'image/webp', 'image/gif']
)
on conflict (id) do nothing;
