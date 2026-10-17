# Checkpoint

Your game library and playtime tracker. Build a library, log your hours, rate games, import your Steam library, and follow other players.

## Features

- Search games (powered by IGDB) and add them to your library, or browse the most popular, highest rated and newest releases
- Track status, playtime, and ratings per game
- Import your Steam library and sync achievements
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

### Edge Function errors

The functions answer a failure with `{ "error": "...", "code": "...", "retry_after": 60 }` and a `Retry-After` header when waiting helps. The app turns the `code` into a message (`lib/services/sync_failure.dart`): rate limiting or downtime at Steam or IGDB shows **Sync Delayed** on the Profile tab, and a sync that IGDB only got part of the way through reports the games left for the next one in `delayed`.

### Rate limits

Steam, IGDB and Twitch answer HTTP 429 when they are over their limits. The functions retry a 429 with exponential backoff and jitter (`supabase/functions/_shared/backoff.ts`), waiting for the `Retry-After` the API sent when it is short. The waits are capped so a request never hangs: a search retries for about 3.5 s, an achievements load for 6 s. A limit that outlasts the retries is reported as `*_RATE_LIMITED` with `retry_after`, and `igdb-handler` then answers further searches from the same instance with that error for up to a minute without calling IGDB.

### Row ownership

`profiles`, `user_games`, `log_entries` and `social_follows` carry restrictive RLS policies for INSERT, UPDATE and DELETE (`20261017120000_enforce_row_ownership.sql`): a signed-in member can only write rows whose owner column is their own `auth.uid()`, whatever other policies exist on the table. The migration fails if a table ends up without them.

### Public profiles and followers

Tapping a member in **Search > Users** (or in a follower list) opens their profile, laid out like your own: photo, name, bio, followers and following (one screen with a tab for each), their favorites, latest play sessions, playtime, the four status boxes (each opens their library), hours per platform, a ratings chart and a short menu into their library, wishlist and follow lists. The accounts they connected are small icons above the bio, game profiles (Steam, PSN, Xbox, Nintendo) first, then social media (Discord, Instagram, Twitch); Steam, Xbox, PSN, Instagram and Twitch open the account, Discord copies the username. Your own Profile tab is the same page built from your live library, with **Edit Profile** and **Settings** under the counts and **Sign out** at the top right beside your name. You connect, rename and disconnect services (and sync your Steam library) under **Settings > Account > Connect accounts**. Their **Library** screen is the same screen as yours (tabs per status with counts, search, platform filter, sorting, grid or list). The Followers and Following counts on your own Profile tab open the same two-tab screen.

All of it is read through views and functions that name their columns, never from the `profiles`, `user_games` or `log_entries` tables, which stay own-row only: `public_profiles`, `public_user_games`, `public_followers`, `public_following`, `public_recent_activity` and `public_profile_stats` (`20261017140000_public_profiles_and_social_graph.sql`, `20261017150000_public_connected_services.sql`, `20261018120000_public_profile_details.sql`, `20261019120000_instagram_twitch_accounts.sql`). What other signed-in members can see is listed in the migration headers and in `docs/privacy.html`: the profile header including bio, Steam ID, PSN id, Xbox gamertag and Discord, Instagram and Twitch usernames (the links need them), the library without purchase prices, and the latest sessions without their notes. Never exposed: email, purchase price, session notes. Achievements are the exception that is only fetched on request: a profile loads without them, and **View Achievements** calls `public_achievement_summary` (progress per game, counted in the database) and, when a game is opened, `public_game_achievements` (that game's list). Both are `SECURITY DEFINER` functions that need a signed-in caller, because RLS works on rows and letting members read each other's `user_games` rows would hand over the `achievements` column too.

The numbers on a profile (games per status, hours, hours per platform, the ratings chart) are worked out in the app by `LibraryStats` from a few columns of the member's library (a page of 500 at a time), the same code that serves your own profile. The member's whole library, with covers, is read only when their Library screen opens. The state lives in `PublicProfileStore`, `PublicLibraryStore`, `SocialGraphStore` and `PublicAchievementsStore` (`lib/state/`), which keep their data in memory only and drop it on sign-out; none of them touches `ProfileStore`.

Your own connected services are mirrored from the device to your `profiles` row (`connected_services`, `psn_id`, `xbox_id`, `discord_id`, `instagram_id`, `twitch_id`) by `ProfileStore`: the device list is saved first, and a change that can't be sent while offline is remembered (`accounts_pending.<user id>`) and sent when the connection is back. Otherwise the server's list is adopted on load, so a second device shows the same services. Apply the migrations before shipping a build that reads them.

### Background Steam sync

pg_cron calls `sync-steam` every 15 minutes (`20261017130000_background_steam_sync.sql`). It refreshes the libraries of members who have synced by hand before, were active in the last 30 days and are due (12 hours after their last sync; failures back off), ten per run. The job does nothing until you run the one-time setup at the top of that migration: three Vault secrets (`project_url`, `anon_key`, `cron_secret`) and the function secret `CRON_SECRET` with the same value as `cron_secret`. Pause it with `select cron.unschedule('sync-steam-background');`.

### Account deletion

**Settings > Account > Delete account** (required by the App Store and Google Play) asks for confirmation, then calls the `delete-account` Edge Function. It identifies the caller from their JWT and, using the service role, removes their avatar files, log entries, library, follows (both directions) and profile, clears `created_by` on catalog games they added (the games stay for other members), and finally deletes the Supabase auth user. The identity goes last, so a failure part way leaves an account that can still sign in and retry. The app then signs out and erases everything it held on the device for that account (saved copy, queued offline edits, service names). It needs no extra secrets.

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
