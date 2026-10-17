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

### Background Steam sync

pg_cron calls `sync-steam` every 15 minutes (`20261017130000_background_steam_sync.sql`). It refreshes the libraries of members who have synced by hand before, were active in the last 30 days and are due (12 hours after their last sync; failures back off), ten per run. The job does nothing until you run the one-time setup at the top of that migration: three Vault secrets (`project_url`, `anon_key`, `cron_secret`) and the function secret `CRON_SECRET` with the same value as `cron_secret`. Pause it with `select cron.unschedule('sync-steam-background');`.

### Account deletion

**Edit Profile > Delete account** (required by the App Store and Google Play) asks for confirmation, then calls the `delete-account` Edge Function. It identifies the caller from their JWT and, using the service role, removes their avatar files, log entries, library, follows (both directions) and profile, clears `created_by` on catalog games they added (the games stay for other members), and finally deletes the Supabase auth user. The identity goes last, so a failure part way leaves an account that can still sign in and retry. The app then signs out and erases everything it held on the device for that account (saved copy, queued offline edits, service names). It needs no extra secrets.

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
