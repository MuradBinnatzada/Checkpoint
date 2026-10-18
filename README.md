# Checkpoint

Your game library and playtime tracker. Build a library, log your hours, rate games, import your Steam library, and follow other players.

## Features

- Search games (powered by IGDB) and add them to your library, or browse the most popular, highest rated and newest releases
- Track status, playtime, and ratings per game
- Import your Steam library; achievement progress for every Steam game, on your profile and other members'
- Follow other players and browse their libraries
- Offline support: the library is cached locally and edits made offline sync when you reconnect
- Google sign-in

## Tech stack

- **App:** Flutter / Dart (Android, iOS, web, desktop targets)
- **Backend:** [Supabase](https://supabase.com) (auth, Postgres, Edge Functions)
- **Edge Functions** (`supabase/functions`): `igdb-handler`, `sync-steam`, `sync-achievements`, `delete-account`. Third-party API credentials (Twitch/IGDB, Steam) live server-side only.

## Project layout

```
lib/
  app/        app shell and root widget
  models/     data models
  screens/    home, search, library, game detail, profile
  services/   Supabase repository, auth, IGDB, connectivity, local cache, offline edits
  state/      domain stores (auth, library, profile, ...)
  widgets/    shared UI
supabase/     config, migrations, edge functions
test/         unit and widget tests
docs/         landing page and privacy policy
```

## Getting started

Prerequisites: the [Flutter SDK](https://docs.flutter.dev/get-started/install) (see `pubspec.yaml` for the required SDK version).

```bash
flutter pub get
flutter run
```

Run the tests:

```bash
flutter test
```

### CI/CD

GitHub Actions (`.github/workflows`):

- **CI** (`ci.yml`) runs `flutter analyze` and `flutter test` on every pull request and push to `main`, type-checks the Edge Functions with `deno check`, and runs the shared helpers' tests (`deno test supabase/functions/_shared/`).
- **Deploy Supabase** (`deploy-supabase.yml`) applies new migrations (`supabase db push`) and deploys the Edge Functions when `supabase/` changes on `main`, or when started by hand. It needs the repository secrets `SUPABASE_ACCESS_TOKEN` and `SUPABASE_DB_PASSWORD` and the variable `SUPABASE_PROJECT_ID`. It runs in the `production` environment, where you can require a reviewer before migrations touch the live database.

### Naming migrations

A migration's file name starts with its timestamp, and `supabase db push` applies them in that order. It refuses a new file that sorts before one the database already has. The files here run up to `20261025120000`, ahead of the dates they were written. Until that date has passed, don't take the name `supabase migration new` gives (today's date): name a new migration after the newest file in `supabase/migrations`, e.g. `20261026120000_<what_it_does>.sql`.

### Edge Function errors

The functions answer a failure with `{ "error": "...", "code": "...", "retry_after": 60 }` and a `Retry-After` header when waiting helps. The app turns the `code` into a message (`lib/services/sync_failure.dart`): rate limiting or downtime at Steam or IGDB shows **Sync Delayed** on the Profile tab, and a sync that IGDB only got part of the way through reports the games left for the next one in `delayed`.

### Rate limits

Steam, IGDB and Twitch answer HTTP 429 when they are over their limits. The functions retry a 429 with exponential backoff and jitter (`supabase/functions/_shared/backoff.ts`), waiting for the `Retry-After` the API sent when it is short. The waits are capped so a request never hangs: a search retries for about 3.5 s, an achievements load for 6 s. A limit that outlasts the retries is reported as `*_RATE_LIMITED` with `retry_after`, and `igdb-handler` then answers further searches from the same instance with that error for up to a minute without calling IGDB.

### Row ownership

`profiles`, `user_games`, `log_entries` and `social_follows` carry restrictive RLS policies for INSERT, UPDATE and DELETE (`20261017120000_enforce_row_ownership.sql`): a signed-in member can only write rows whose owner column is their own `auth.uid()`, whatever other policies exist on the table. The migration fails if a table ends up without them.

### Public profiles and followers

Tapping a member in **Search > Users** (or in a follower list) opens their profile, laid out like your own: photo, name, bio, followers and following (one screen with a tab for each), their favorites, latest play sessions, playtime, the four status boxes (each opens their library), hours per platform, a ratings chart and a short menu into their library, wishlist and follow lists. The accounts they connected are small icons above the bio, game profiles (Steam, PSN, Xbox, Nintendo) first, then social media (Discord, Instagram, Twitch); Steam, Xbox, PSN, Instagram and Twitch open the account, Discord copies the username. Your own Profile tab is the same page built from your live library, with **Edit Profile** and **Settings** under the counts and **Sign out** at the top right beside your name. You connect, rename and disconnect services (and sync your Steam library) under **Settings > Account > Connect accounts**. Their **Library** screen is the same screen as yours (tabs per status with counts, search, platform filter, sorting, grid or list). The Followers and Following counts on your own Profile tab open the same two-tab screen.

All of it is read through views and functions that name their columns, never from the `profiles`, `user_games` or `log_entries` tables, which stay own-row only: `public_profiles`, `public_user_games`, `public_followers`, `public_following`, `public_recent_activity` and `public_profile_stats` (`20261017140000_public_profiles_and_social_graph.sql`, `20261017150000_public_connected_services.sql`, `20261018120000_public_profile_details.sql`, `20261019120000_instagram_twitch_accounts.sql`). What other signed-in members can see is listed in the migration headers and in `docs/privacy.html`: the profile header including bio, Steam ID, PSN id, Xbox gamertag and Discord, Instagram and Twitch usernames (the links need them), the library without purchase prices, and the latest sessions without their notes. Never exposed: email, purchase price, session notes. Achievements show as counts: the profile loads `public_achievement_totals` (unlocked out of all, over every game) and `public_achievement_summary` (every game with at least one achievement unlocked and how far they got, most complete first, up to 500), both read from count columns, never from the lists. Tapping a game opens its achievements in a dialog (search, all / unlocked / locked, Steam's share of players who have each one). The list comes from `public_game_achievements` when the one stored matches the game's counts, otherwise from Steam through `sync-achievements`, which may load another member's game too (see below). These are `SECURITY DEFINER` functions that need a signed-in caller, because RLS works on rows and letting members read each other's `user_games` rows would hand over the `achievements` column too.

A game's screen has a **Friends** panel: which of the members you follow completed the game, are playing it or want to play it (To Play and Wishlist together), each as their photo (tap to open their profile) with the stars they gave, if any. It is one call to `following_game_activity` (`20261022120000_friends_on_game_screen.sql`), which returns up to 20 members per status, rated first, and the full count of each; it exposes nothing `public_user_games` doesn't already. Dropped is left out, and the panel is hidden when signed out or when none of them has the game.

### Achievement counts

`user_games` keeps each Steam game's `achievements_unlocked` and `achievements_total` (`20261021120000_steam_achievement_counts.sql`). Every Steam sync (by hand or in the background) counts the games played since they were last counted, one `GetPlayerAchievements` request per game (Steam has no call that answers for many games with a Web API key), six at a time, most recently played first. `achievements_playtime` remembers the playtime at the count, so a game not played since is not asked about again. A sync counts at most 400 games (60 in the background) and stops starting new requests 125 s in (40 s in the background), on a Steam 429 or on a private profile; the rest is counted on the next sync, and counting never fails a sync. A trigger keeps the counts in step whenever a full list is written to `achievements`, and sets `achievements_synced_at`.

`sync-achievements` takes an optional `user_id`. With another member's id it loads that member's list for the game from the Steam ID on *their* profile (the request can't name a Steam ID), saves it on their row and answers it; a list fetched in the last 10 minutes is answered from the row without asking Steam, so viewers can't make it hammer Steam. That is what Steam shows anyone on their public Steam profile, and what `public_game_achievements` already hands out once stored. Apply the migration, then deploy `sync-steam` and `sync-achievements`, then ship the app. Existing members see every game after their next Steam sync.

The numbers on a profile (games per status, hours, hours per platform, the ratings chart) are worked out in the app by `LibraryStats` from a few columns of the member's library (a page of 500 at a time), the same code that serves your own profile. The member's whole library, with covers, is read only when their Library screen opens. The state lives in `PublicProfileStore`, `PublicLibraryStore`, `SocialGraphStore` and `PublicAchievementsStore` (`lib/state/`), which keep their data in memory only and drop it on sign-out; none of them touches `ProfileStore`.

Your own connected services are mirrored from the device to your `profiles` row (`connected_services`, `psn_id`, `xbox_id`, `discord_id`, `instagram_id`, `twitch_id`) by `ProfileStore`: the device list is saved first, and a change that can't be sent while offline is remembered (`accounts_pending.<user id>`) and sent when the connection is back. Otherwise the server's list is adopted on load, so a second device shows the same services. Apply the migrations before shipping a build that reads them.

### Background Steam sync

pg_cron calls `sync-steam` every 15 minutes (`20261017130000_background_steam_sync.sql`). It refreshes the libraries of members who have synced by hand before, were active in the last 30 days and are due (12 hours after their last sync; failures back off), ten per run. The job does nothing until you run the one-time setup at the top of that migration: three Vault secrets (`project_url`, `anon_key`, `cron_secret`) and the function secret `CRON_SECRET` with the same value as `cron_secret`. Pause it with `select cron.unschedule('sync-steam-background');`.

### Account deletion

**Settings > Account > Delete account** (required by the App Store and Google Play) asks for confirmation, then calls the `delete-account` Edge Function. It identifies the caller from their JWT and, using the service role, removes their avatar files, log entries, library, follows (both directions) and profile, clears `created_by` on catalog games they added (the games stay for other members), and finally deletes the Supabase auth user. The identity goes last, so a failure part way leaves an account that can still sign in and retry. The app then signs out and erases everything it held on the device for that account (saved copy, queued offline edits, service names). It needs no extra secrets.

**Game details.** Opening a game asks `igdb-handler` (`mode: "details"`, by IGDB id) for its whole page: the exact release platforms (PS3 and Xbox 360 are two platforms, as on IGDB), genres, themes, game modes, player perspectives, game engine, main developers, publishers, storyline, similar games and time to beat. The details screen shows them, and the exact platforms and genres also replace what the library held, so "Played on" offers exactly the platforms the game is on. The stable part (platforms, genres, themes, modes, perspectives, engines, developers, publishers) is saved on the game's shared `games` row by the function, at most once a week, and the Library filters read it (next paragraph); storyline, similar games and time to beat change over time and are only kept in memory. The time to beat panel says when IGDB's figure comes from fewer than 10 players, and links to the game on HowLongToBeat. It is a link only: HowLongToBeat (Ziff Davis) forbids automated access to its data (`robots.txt` disallows `/api` and says scraping needs written permission), so the app never fetches from it. Games nobody has opened yet (a library imported from Steam before this, say) are filled in the same way in the background: after the library loads, and after a Steam sync, the app lists the library games whose `games` row was never filled in (`igdb_synced_at` is NULL, a separate query that returns only those ids, so the library payload does not grow) and sends them to `igdb-handler` (`mode: "backfill"`, up to 50 IGDB ids, one IGDB request) 25 at a time, two seconds apart. The function writes each due row as `details` does and answers each game's exact platforms and genres, which the library shows right away. On `IGDB_RATE_LIMITED` / `IGDB_UNAVAILABLE` the app waits the `retry_after` it is given and carries on; any other failure ends the run until the next load (`lib/state/catalog_backfill.dart`). Apply `20261020120000_igdb_game_details.sql` and redeploy `igdb-handler` before shipping the app build; platform names live in `GamePlatform` (`lib/models/game.dart`) and must stay in step with `lib/services/game_api_service.dart` and `supabase/functions/_shared/platforms.ts`.

**Library filters.** The filter icon in the Library header (badged with how many things are picked) opens a sheet to narrow the library by platform (one), and by genre, theme, game mode, player perspective, engine, developer and publisher (any number of values of each: a game needs any one of an attribute's picked values and a match in every attribute picked). Each list holds only the values at least one of your games has, most common first with a count, and a long one (developers, publishers) shows its first values with "Show all" and a search box. What is picked shows as removable chips under the title, and the sheet and the empty state say so when picks leave games out. Genres and platforms are on the games the library already loads. Themes, modes, perspectives, engines, developers and publishers are not: adding six lists to every game would grow the library payload and the copy saved on the device (the part that is already slow to read) for something most visits never use. `LibraryAttributesStore` (`lib/state/library_attributes_store.dart`) reads them in one separate paged query (`CheckpointRepository.fetchLibraryAttributes`: `user_games` joined to `games` for the rows with `igdb_synced_at` set, those six columns only) the first time the sheet opens, keeps them in memory until the account changes, and reads again on the next open after `LibraryStore` reports that the server filled in rows (a game's screen opened, a backfill batch). A game whose row was never filled in has no values yet, so those filters leave it out; the sheet, the chip row and the empty state say how many games that is, and it shrinks as the background backfill and the game screens fill rows in. Another member's Library screen keeps its platform menu only.

### Using your own backend

The app ships pointing at the project's Supabase instance with a public anon key, which is safe to expose when Row Level Security is enabled. To run against your own backend:

1. Create a Supabase project and apply the SQL in `supabase/migrations`.
2. Deploy the functions in `supabase/functions` and set their secrets (Twitch client ID/secret for IGDB, Steam API key, and `CRON_SECRET` if you want the background sync).
3. Update the Supabase URL and key in `lib/main.dart`.
4. Create Google OAuth client IDs and update `lib/services/auth_service.dart`. For iOS, pass `--dart-define=GOOGLE_IOS_CLIENT_ID=...`.

## Privacy

See [docs/privacy.html](docs/privacy.html).

## License

Copyright (c) 2026 Murad Binnatzada. All rights reserved. This is proprietary software, and the source is visible for reference only. See [LICENSE](LICENSE).
