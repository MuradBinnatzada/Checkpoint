# Checkpoint

Your game library and playtime tracker. Build a library, log your hours, rate games, import your Steam library, and follow other players.

## Features

- Search games (powered by IGDB) and add them to your library
- Track status, playtime, and ratings per game
- Import your Steam library and sync achievements
- Follow other players and browse their libraries
- Offline support: the library is cached locally and edits made offline sync when you reconnect
- Google sign-in

## Tech stack

- **App:** Flutter / Dart (Android, iOS, web, desktop targets)
- **Backend:** [Supabase](https://supabase.com) (auth, Postgres, Edge Functions)
- **Edge Functions** (`supabase/functions`): `igdb-handler`, `sync-steam`, `sync-achievements`. Third-party API credentials (Twitch/IGDB, Steam) live server-side only.

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

### Using your own backend

The app ships pointing at the project's Supabase instance with a public anon key, which is safe to expose when Row Level Security is enabled. To run against your own backend:

1. Create a Supabase project and apply the SQL in `supabase/migrations`.
2. Deploy the functions in `supabase/functions` and set their secrets (Twitch client ID/secret for IGDB, Steam API key).
3. Update the Supabase URL and key in `lib/main.dart`.
4. Create Google OAuth client IDs and update `lib/services/auth_service.dart`. For iOS, pass `--dart-define=GOOGLE_IOS_CLIENT_ID=...`.

## Privacy

See [docs/privacy.html](docs/privacy.html).

## License

Copyright (c) 2026 Murad Binnatzada. All rights reserved. This is proprietary software, and the source is visible for reference only. See [LICENSE](LICENSE).
