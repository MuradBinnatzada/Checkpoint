import 'dart:convert';

import 'package:flutter/material.dart' show Color, Icons;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/services/checkpoint_repository.dart';
import 'package:checkpoint/services/sync_failure.dart';

import 'support/fakes.dart';

/// The Supabase REST API, answered from memory. Each request is recorded in
/// [requests]; [reply] queues what the next ones get (an empty queue answers
/// `[]`), so a test reads like "the server says X, the repository returns Y".
class _FakeApi {
  final requests = <http.Request>[];
  final _replies = <(int, Object?)>[];
  Object? Function(http.Request)? _table;

  /// From now on, answer every request from [rows] the way PostgREST answers a
  /// keyset-paged read: it honours `<column>=gt.<cursor>`, `order=<column>.asc|desc`
  /// and `limit`. Lets a test check that paging really reaches every row.
  void serveTable(List<Map<String, dynamic>> rows, String column) {
    _table = (request) {
      final query = request.url.queryParameters;
      var matching = [...rows];
      final after = query[column];
      if (after != null && after.startsWith('gt.')) {
        final cursor = after.substring(3);
        matching = [
          for (final r in matching)
            if ((r[column] as String).compareTo(cursor) > 0) r,
        ];
      }
      matching.sort((a, b) => (a[column] as String).compareTo(b[column] as String));
      if ((query['order'] ?? '').split('.').skip(1).firstOrNull == 'desc') {
        matching = matching.reversed.toList();
      }
      return matching.take(int.parse(query['limit'] ?? '1000')).toList();
    };
  }

  void reply(Object? body, {int status = 200}) => _replies.add((status, body));

  http.Request get last => requests.last;

  /// The request body as JSON.
  Object? bodyOf(http.Request request) => jsonDecode(request.body);

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    final table = _table;
    if (table != null) {
      return http.Response(
        jsonEncode(table(request)),
        200,
        request: request,
        headers: {'content-type': 'application/json'},
      );
    }
    final (status, body) = _replies.isEmpty ? (200, const <Object?>[]) : _replies.removeAt(0);
    return http.Response(
      jsonEncode(body),
      status,
      request: request, // the client library reads the request back off the response
      headers: {'content-type': 'application/json'},
    );
  }
}

Map<String, dynamic> userGameRow(
  String gameId, {
  String title = 'Hades',
  Object? hours = 12.5,
  String? addedAt = '2026-03-01T10:00:00+00:00',
  Map<String, dynamic>? gameOverrides,
}) => {
  'id': 'ug-$gameId',
  'user_id': 'u1',
  'game_id': gameId,
  'status': 'playing',
  'rating': 4.5,
  'hours_played': hours,
  'played_on': 'ps5',
  'purchase_price': 24.99,
  'date_added': addedAt,
  'is_favorite': true,
  'games': {
    'id': gameId,
    'igdb_id': 113112,
    'steam_app_id': 1145360,
    'slug': 'hades',
    'title': title,
    'publisher': 'Supergiant Games',
    'developer': 'Supergiant Games',
    'release_year': 2020,
    'platforms': ['pc', 'switch'],
    'genres': ['Roguelike', 'Action'],
    'summary': 'Escape the underworld.',
    'cover_url': 'https://images.igdb.com/hades.jpg',
    'created_at': '2026-01-01T00:00:00+00:00',
    ...?gameOverrides,
  },
};

/// A catalog game as search returns it: its id is derived from [igdbId], or it
/// is a legacy Steam-keyed row when [igdbId] is null.
Game catalogGame({int? igdbId = 7, int releaseYear = 2020}) => Game(
  id: igdbId == null ? '57e40000-0000-0000-0000-000000000440' : gameIdForIgdb(igdbId),
  title: 'Seven',
  publisher: 'Publisher',
  developer: 'Developer',
  releaseYear: releaseYear,
  platforms: const [GamePlatform.pc, GamePlatform.ps5],
  genres: const ['RPG'],
  synopsis: 'A game.',
  coverColors: const [Color(0xFF000000), Color(0xFF111111)],
  coverIcon: Icons.sports_esports_rounded,
  igdbId: igdbId,
);

void main() {
  late _FakeApi api;
  late SupabaseClient client;
  late CheckpointRepository repo;

  setUp(() {
    api = _FakeApi();
    client = SupabaseClient(
      'http://localhost:54321',
      'anon-key',
      httpClient: MockClient(api.handle),
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    repo = CheckpointRepository(client);
  });

  tearDown(() async {
    await client.dispose();
  });

  group('fetchUserGames', () {
    test('turns a library row into a Game', () async {
      api.reply([userGameRow('00000000-0000-4000-8000-000000113112')]);

      final games = await repo.fetchUserGames('u1');

      expect(games, hasLength(1));
      final game = games.single;
      expect(game.id, '00000000-0000-4000-8000-000000113112');
      expect(game.title, 'Hades');
      expect(game.igdbId, 113112);
      expect(game.steamAppId, 1145360);
      expect(game.developer, 'Supergiant Games');
      expect(game.releaseYear, 2020);
      expect(game.platforms, [GamePlatform.pc, GamePlatform.nswitch]);
      expect(game.genres, ['Roguelike', 'Action']);
      expect(game.coverUrl, 'https://images.igdb.com/hades.jpg');
      // The user's own fields.
      expect(game.status, GameStatus.playing);
      expect(game.rating, 4.5);
      expect(game.hoursPlayed, 12.5);
      expect(game.playedOn, GamePlatform.ps5);
      expect(game.purchasePrice, 24.99);
      expect(game.isFavorite, isTrue);
      expect(game.dateAdded!.toUtc(), DateTime.utc(2026, 3, 1, 10));
      expect(game.inLibrary, isTrue);
    });

    test('asks for the user\'s rows only, and never for the heavy achievements column', () async {
      await repo.fetchUserGames('u1');

      final query = api.last.url.queryParameters;
      expect(api.last.url.path, '/rest/v1/user_games');
      expect(query['user_id'], 'eq.u1');
      expect(query['select'], isNot(contains('achievements')));
      expect(query['select'], contains('games!inner'));
      // The read continues with `game_id > cursor`, so it has to run oldest id first.
      expect(query['order'], startsWith('game_id.asc'));
      expect(query['limit'], '500');
    });

    test('copes with numbers sent as text and with missing catalog fields', () async {
      api.reply([
        userGameRow(
          'g1',
          hours: '7.25', // numeric columns can arrive as strings
          gameOverrides: {
            'title': '   ',
            'publisher': null,
            'developer': '',
            'release_year': null,
            'platforms': null,
            'genres': 'Strategy', // a bare string instead of a list
            'summary': null,
            'cover_url': '',
            'igdb_id': '42',
            'steam_app_id': null,
          },
        ),
      ]);

      final game = (await repo.fetchUserGames('u1')).single;

      expect(game.hoursPlayed, 7.25);
      expect(game.title, 'Untitled Game');
      expect(game.publisher, 'Unknown publisher');
      expect(game.developer, 'Unknown developer');
      expect(game.releaseYear, 0);
      expect(game.platforms, [GamePlatform.pc]); // no platform data falls back to PC
      expect(game.genres, ['Strategy']);
      expect(game.synopsis, '');
      expect(game.coverUrl, isNull);
      expect(game.igdbId, 42);
      expect(game.steamAppId, isNull);
    });

    test('returns the newest additions first, undated rows last', () async {
      api.reply([
        userGameRow('a', addedAt: '2026-01-01T00:00:00+00:00'),
        userGameRow('b', addedAt: null),
        userGameRow('c', addedAt: '2026-06-01T00:00:00+00:00'),
      ]);

      final games = await repo.fetchUserGames('u1');

      expect([for (final g in games) g.id], ['c', 'a', 'b']);
    });

    test('reads a library bigger than one page, every game exactly once', () async {
      api.serveTable([
        for (var i = 0; i < 1200; i++) userGameRow('g${i.toString().padLeft(4, '0')}'),
      ], 'game_id');

      final games = await repo.fetchUserGames('u1');

      expect(games.map((g) => g.id).toSet(), hasLength(1200));
      expect(games, hasLength(1200)); // no game read twice
      expect(api.requests, hasLength(3)); // 500 + 500 + 200
      expect(api.requests[0].url.queryParameters.containsKey('game_id'), isFalse);
      expect(api.requests[1].url.queryParameters['game_id'], 'gt.g0499');
    });

    test('a library of exactly one page needs one more request to know it is done', () async {
      api.serveTable([
        for (var i = 0; i < 500; i++) userGameRow('g${i.toString().padLeft(4, '0')}'),
      ], 'game_id');

      final games = await repo.fetchUserGames('u1');

      expect(games, hasLength(500));
      expect(api.requests, hasLength(2));
    });
  });

  group('fetchLogEntries', () {
    test('reads more sessions than one page holds, every one exactly once', () async {
      api.serveTable([
        for (var i = 0; i < 1100; i++)
          {
            'id': 'l${i.toString().padLeft(4, '0')}',
            'game_id': 'g1',
            'logged_at': '2026-02-01T08:00:00+00:00',
            'hours': 1,
            'platform': 'pc',
            'note': '',
          },
      ], 'id');

      final logs = await repo.fetchLogEntries('u1');

      expect(logs.map((l) => l.id).toSet(), hasLength(1100));
      expect(logs, hasLength(1100));
    });

    test('parses sessions and returns the newest first', () async {
      api.reply([
        {
          'id': 'l1',
          'game_id': 'g1',
          'logged_at': '2026-02-01T08:00:00+00:00',
          'hours': 1.5,
          'platform': 'pc',
          'note': '  first run  ',
        },
        {
          'id': 'l2',
          'game_id': 'g2',
          'logged_at': '2026-04-01T08:00:00+00:00',
          'hours': '2', // numeric as text
          'platform': 'nonsense', // unknown platform falls back to PC
          'note': null,
        },
      ]);

      final logs = await repo.fetchLogEntries('u1');

      expect([for (final l in logs) l.id], ['l2', 'l1']);
      expect(logs[0].hours, 2);
      expect(logs[0].platform, GamePlatform.pc);
      expect(logs[0].note, '');
      expect(logs[1].hours, 1.5);
      expect(logs[1].note, 'first run');
      expect(logs[1].timestamp.toUtc(), DateTime.utc(2026, 2, 1, 8));
    });
  });

  group('profiles', () {
    test('ensureProfile reads an existing row and prefixes the handle with @', () async {
      api.reply({
        'id': 'u1',
        'display_name': 'Ada',
        'handle': 'ada',
        'bio': ' Speedrunner ',
        'avatar_url': ' ',
        'steam_id': '76561198000000000',
        'created_at': '2026-01-05T00:00:00+00:00',
      });

      final profile = await repo.ensureProfile(testUser('u1'));

      expect(profile.name, 'Ada');
      expect(profile.handle, '@ada');
      expect(profile.bio, 'Speedrunner');
      expect(profile.avatarUrl, isNull); // blank text is no avatar
      expect(profile.steamId, '76561198000000000');
      expect(profile.joined.toUtc(), DateTime.utc(2026, 1, 5));
      expect(api.requests, hasLength(1)); // nothing was written
    });

    test('a blank steam_id means no Steam account is connected', () async {
      api.reply({'id': 'u1', 'display_name': 'Ada', 'handle': 'ada', 'steam_id': '  '});

      final profile = await repo.ensureProfile(testUser('u1'));

      expect(profile.steamId, isNull);
    });

    test('ensureProfile creates the row for a new user from their sign-in details', () async {
      api.reply(null); // maybeSingle: no row yet
      api.reply(null); // the upsert
      api.reply({
        'id': 'u9',
        'display_name': 'Grace Hopper',
        'handle': 'grace_hopper_u9abc',
        'created_at': '2026-02-02T00:00:00+00:00',
      });
      final user = User(
        id: 'u9abcdef-0000',
        appMetadata: const {},
        userMetadata: const {'full_name': 'Grace Hopper', 'picture': 'https://example.com/g.png'},
        aud: 'authenticated',
        createdAt: '2026-01-01T00:00:00Z',
        email: 'grace@example.com',
      );

      final profile = await repo.ensureProfile(user);

      final upsert = api.requests[1];
      expect(upsert.method, 'POST');
      expect(upsert.url.path, '/rest/v1/profiles');
      final row = api.bodyOf(upsert) as Map<String, dynamic>;
      expect(row['id'], 'u9abcdef-0000');
      expect(row['email'], 'grace@example.com');
      expect(row['display_name'], 'Grace Hopper');
      expect(row['avatar_url'], 'https://example.com/g.png');
      expect(row['bio'], '');
      // lowercase, only [a-z0-9_], unique per user, and within the 24 character limit
      expect(row['handle'], matches(RegExp(r'^grace_hopper_u9abcd$')));
      expect((row['handle'] as String).length, lessThanOrEqualTo(24));
      expect(profile.name, 'Grace Hopper');
    });

    test('the display name falls back to the email name, then to "Player"', () async {
      api.reply({'id': 'u1', 'display_name': null, 'handle': null});

      final fromEmail = await repo.ensureProfile(
        User(
          id: 'abcdef12',
          appMetadata: const {},
          userMetadata: const {},
          aud: 'authenticated',
          createdAt: '2026-01-01T00:00:00Z',
          email: 'ada.l@example.com',
        ),
      );
      expect(fromEmail.name, 'ada.l');
      expect(fromEmail.handle, '@ada_l_abcdef');

      api.reply({'id': 'u2'});
      final anonymous = await repo.ensureProfile(testUser('u2'));
      expect(anonymous.name, 'Player');
    });

    test('isHandleAvailable ignores the @ and the case, and excludes the caller', () async {
      api.reply(<Object?>[]);

      expect(await repo.isHandleAvailable('  @@Ada ', 'u1'), isTrue);

      expect(api.last.url.path, '/rest/v1/public_profiles'); // never the private table
      expect(api.last.url.queryParameters['handle'], 'eq.ada');
      expect(api.last.url.queryParameters['id'], 'neq.u1');
    });

    test('isHandleAvailable is false when someone else has it, and for an empty handle', () async {
      api.reply([
        {'id': 'u2'},
      ]);
      expect(await repo.isHandleAvailable('taken', 'u1'), isFalse);

      final before = api.requests.length;
      expect(await repo.isHandleAvailable(' @ ', 'u1'), isFalse);
      expect(api.requests, hasLength(before)); // answered without asking the server
    });
  });

  group('social', () {
    test('searchSocialUsers reads only public columns and flags a full page', () async {
      api.reply([
        {'id': 'm1', 'handle': 'zed', 'display_name': 'Zed', 'avatar_url': null},
        {'id': 'm2', 'handle': null, 'display_name': null, 'avatar_url': null},
      ]);

      final page = await repo.searchSocialUsers('u1', limit: 2);

      expect(api.last.url.path, '/rest/v1/public_profiles');
      expect(api.last.url.queryParameters['select'], isNot(contains('email')));
      expect(api.last.url.queryParameters['id'], 'neq.u1');
      expect(page.hasMore, isTrue); // a full page: there may be another
      expect(page.items[0].name, 'Zed');
      expect(page.items[0].handle, '@zed');
      expect(page.items[1].name, 'Player');
      expect(page.items[1].handle, startsWith('@player_'));
    });

    test('searchSocialUsers makes the typed text safe for the or() filter', () async {
      await repo.searchSocialUsers('u1', query: ' @Ada,(x)"%*\\ ');

      final filter = api.last.url.queryParameters['or']!;
      expect(filter, startsWith('(display_name.ilike.%'));
      // none of the characters that would end the value or act as wildcards survive
      final term = RegExp(r'display_name\.ilike\.%(.*?)%,').firstMatch(filter)!.group(1)!;
      expect(term, isNot(matches(RegExp(r'[,()"\\%*]'))));
      expect(term.trim(), startsWith('Ada'));
    });

    test('searchSocialUsers asks for the right slice', () async {
      await repo.searchSocialUsers('u1', offset: 30, limit: 30);

      expect(api.last.url.queryParameters['offset'], '30');
      expect(api.last.url.queryParameters['limit'], '30');
    });

    test('a short page ends the member list', () async {
      api.reply([
        {'id': 'm1', 'handle': 'zed', 'display_name': 'Zed'},
      ]);

      final page = await repo.searchSocialUsers('u1', limit: 30);

      expect(page.hasMore, isFalse);
    });

    test('fetchFollowingIds and fetchFollowersCount count what the server lists', () async {
      api.reply([
        {'followee_id': 'a'},
        {'followee_id': 'b'},
        {'followee_id': 'a'},
      ]);
      expect(await repo.fetchFollowingIds('u1'), {'a', 'b'});

      api.reply([
        {'follower_id': 'x'},
        {'follower_id': 'y'},
      ]);
      expect(await repo.fetchFollowersCount('u1'), 2);
    });
  });

  group('achievements', () {
    test('null means never loaded; an empty list means the game has none', () async {
      api.reply({'achievements': null});
      expect(await repo.fetchGameAchievements('u1', 'g1'), isNull);

      api.reply(null); // the game is not in the library
      expect(await repo.fetchGameAchievements('u1', 'g1'), isNull);

      api.reply({'achievements': <Object?>[]});
      expect(await repo.fetchGameAchievements('u1', 'g1'), isEmpty);
    });

    test('parses stored achievements', () async {
      api.reply({
        'achievements': [
          {
            'name': 'First Blood',
            'description': 'Win a fight',
            'icon_url': 'https://example.com/a.jpg',
            'unlocked': true,
            'unlocked_at': '2026-05-05T12:00:00.000Z',
          },
          {'name': 'Hidden', 'unlocked': false, 'unlocked_at': null},
        ],
      });

      final list = (await repo.fetchGameAchievements('u1', 'g1'))!;

      expect(list, hasLength(2));
      expect(list[0].unlocked, isTrue);
      expect(list[0].unlockedAt!.toUtc(), DateTime.utc(2026, 5, 5, 12));
      expect(list[1].description, '');
      expect(list[1].unlockedAt, isNull);
    });
  });

  group('writes', () {
    test('upsertBaseGame stores a missing release year as NULL and never overwrites a row', () async {
      await repo.upsertBaseGame(catalogGame(releaseYear: 0));

      expect(api.last.method, 'POST');
      expect(api.last.url.queryParameters['on_conflict'], 'igdb_id');
      expect(api.last.headers['Prefer'], contains('resolution=ignore-duplicates'));
      final row = api.bodyOf(api.last) as Map<String, dynamic>;
      expect(row['igdb_id'], 7);
      expect(row['release_year'], isNull);
      expect(row['platforms'], ['pc', 'ps5']);
    });

    test('upsertBaseGame refuses a game without an IGDB id', () async {
      await expectLater(repo.upsertBaseGame(catalogGame(igdbId: null)), throwsStateError);
      expect(api.requests, isEmpty);
    });

    test('upsertUserGame writes the status in its database spelling, keyed on user and game', () async {
      await repo.upsertUserGame(
        userId: 'u1',
        gameId: 'g1',
        status: GameStatus.toPlay,
        rating: 3,
        hoursPlayed: 4.5,
        playedOn: GamePlatform.emulator,
        purchasePrice: 0,
        isFavorite: false,
        dateAdded: DateTime.utc(2026, 7, 1, 9),
      );

      expect(api.last.url.queryParameters['on_conflict'], 'user_id,game_id');
      final row = api.bodyOf(api.last) as Map<String, dynamic>;
      expect(row['status'], 'to_play');
      expect(row['played_on'], 'retro'); // how Emulator is stored
      expect(row['date_added'], '2026-07-01T09:00:00.000Z');
      expect(row['is_favorite'], isFalse);
    });

    test('insertLogEntry trims the note', () async {
      await repo.insertLogEntry(
        userId: 'u1',
        gameId: 'g1',
        hours: 2,
        platform: GamePlatform.ps5,
        note: '  boss down  ',
      );

      final row = api.bodyOf(api.last) as Map<String, dynamic>;
      expect(row['note'], 'boss down');
      expect(row['platform'], 'ps5');
    });
  });

  group('Edge Functions', () {
    test('syncSteamLibrary posts to sync-steam and returns the reply', () async {
      api.reply({
        'success': true,
        'delayed': null,
        'summary': {'added': 3},
      });

      final data = await repo.syncSteamLibrary();

      expect(api.last.method, 'POST');
      expect(api.last.url.path, '/functions/v1/sync-steam');
      expect((data as Map)['summary'], {'added': 3});
      expect(SyncFailure.fromDelayed(data), isNull);
    });

    test('a coded error from the function reaches the app as a SyncFailure', () async {
      api.reply(
        {'error': 'Steam is limiting requests right now', 'code': 'STEAM_RATE_LIMITED', 'retry_after': 300},
        status: 429,
      );

      final error = await repo.syncSteamLibrary().then<Object?>((_) => null, onError: (Object e) => e);

      expect(error, isA<FunctionException>());
      final failure = SyncFailure.from(error!);
      expect(failure.code, SyncFailureCode.steamRateLimited);
      expect(failure.isDelayed, isTrue);
      expect(failure.retryAfter, const Duration(minutes: 5));
    });

    test('syncGameAchievements sends only the game id', () async {
      api.reply({'success': true, 'achievements': <Object?>[]});

      await repo.syncGameAchievements('g1');

      expect(api.last.url.path, '/functions/v1/sync-achievements');
      expect(api.bodyOf(api.last), {'game_id': 'g1'});
    });
  });
}
