import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/game_details.dart';
import 'package:checkpoint/services/game_api_service.dart';

/// An IGDB hit with every field the app reads, with [overrides] on top.
Map<String, dynamic> hit([Map<String, dynamic> overrides = const {}]) => {
  'id': 113112,
  'name': 'Hades',
  'summary': 'Escape the underworld.',
  'first_release_date': 1600000000, // 2020
  'cover': {'url': '//images.igdb.com/igdb/image/upload/t_thumb/hades.jpg'},
  'genres': [
    {'name': 'Roguelike'},
    {'name': 'Action'},
  ],
  'platforms': [
    {'id': 6},
    {'id': 130},
  ],
  'involved_companies': [
    {
      'company': {'name': 'Supergiant Games'},
    },
  ],
  ...overrides,
};

void main() {
  group('GameApiService.gameFromHit', () {
    test('reads a complete hit', () {
      final game = GameApiService.gameFromHit(hit())!;

      expect(game.id, gameIdForIgdb(113112));
      expect(game.igdbId, 113112);
      expect(game.title, 'Hades');
      expect(game.synopsis, 'Escape the underworld.');
      expect(game.releaseYear, 2020);
      expect(game.platforms, [GamePlatform.pc, GamePlatform.nswitch]);
      expect(game.genres, ['Roguelike', 'Action']);
      expect(game.publisher, 'Supergiant Games');
      expect(game.developer, 'Supergiant Games');
      expect(
        game.coverUrl,
        'https://images.igdb.com/igdb/image/upload/t_cover_big/hades.jpg',
      );
    });

    test('a hit with nothing but an id still makes a game', () {
      final game = GameApiService.gameFromHit({'id': 7})!;

      expect(game.title, 'Unknown');
      expect(game.publisher, 'Unknown Publisher');
      expect(game.developer, 'Unknown Publisher');
      expect(game.releaseYear, 0);
      expect(game.hasReleaseYear, isFalse);
      expect(game.platforms, isEmpty);
      expect(game.genres, isEmpty);
      expect(game.synopsis, '');
      expect(game.coverUrl, isNull);
    });

    test('explicit nulls are the same as missing fields', () {
      final game = GameApiService.gameFromHit({
        'id': 7,
        'name': null,
        'summary': null,
        'first_release_date': null,
        'cover': null,
        'genres': null,
        'platforms': null,
        'involved_companies': null,
      })!;

      expect(game.title, 'Unknown');
      expect(game.releaseYear, 0);
      expect(game.coverUrl, isNull);
      expect(game.genres, isEmpty);
    });

    test('a hit without a usable IGDB id is left out', () {
      expect(GameApiService.gameFromHit(hit({'id': null})), isNull);
      expect(GameApiService.gameFromHit(hit({'id': 0})), isNull);
      expect(GameApiService.gameFromHit(hit({'id': -3})), isNull);
      expect(GameApiService.gameFromHit(hit({'id': '113112'})), isNull);
      expect(GameApiService.gameFromHit(hit()..remove('id')), isNull);
      expect(GameApiService.gameFromHit(null), isNull);
      expect(GameApiService.gameFromHit('Hades'), isNull);
      expect(GameApiService.gameFromHit(const [1, 2]), isNull);
    });

    test('a blank or non-text title and summary fall back', () {
      final blank = GameApiService.gameFromHit(
        hit({'name': '   ', 'summary': ''}),
      )!;
      expect(blank.title, 'Unknown');
      expect(blank.synopsis, '');

      final wrongType = GameApiService.gameFromHit(
        hit({
          'name': 42,
          'summary': ['x'],
        }),
      )!;
      expect(wrongType.title, 'Unknown');
      expect(wrongType.synopsis, '');
    });

    group('cover', () {
      test('is missing when IGDB sends none, or something else', () {
        for (final cover in [
          null,
          5,
          'url',
          <String, dynamic>{},
          {'url': null},
          {'url': ''},
          {'url': 12},
        ]) {
          expect(
            GameApiService.gameFromHit(hit({'cover': cover}))!.coverUrl,
            isNull,
            reason: '$cover',
          );
        }
      });
    });

    group('company', () {
      test('is the first one that has a name', () {
        final game = GameApiService.gameFromHit(
          hit({
            'involved_companies': [
              null,
              <String, dynamic>{},
              {'company': null},
              {'company': <String, dynamic>{}},
              {
                'company': {'name': '  '},
              },
              {
                'company': {'name': ' Real Studio '},
              },
              {
                'company': {'name': 'Second Studio'},
              },
            ],
          }),
        )!;

        expect(game.publisher, 'Real Studio');
        expect(game.developer, 'Real Studio');
      });

      test('falls back when none has a name, or the field is not a list', () {
        for (final involved in [
          <Object?>[],
          [null],
          'Supergiant',
          3,
          <String, dynamic>{},
        ]) {
          final game = GameApiService.gameFromHit(
            hit({'involved_companies': involved}),
          )!;
          expect(game.publisher, 'Unknown Publisher', reason: '$involved');
        }
      });
    });

    group('genres', () {
      test('skips entries without a name', () {
        final game = GameApiService.gameFromHit(
          hit({
            'genres': [
              null,
              5,
              <String, dynamic>{},
              {'name': null},
              {'name': ' '},
              {'name': ' RPG '},
            ],
          }),
        )!;

        expect(game.genres, ['RPG']);
      });

      test('are empty when the field is not a list', () {
        expect(
          GameApiService.gameFromHit(hit({'genres': 'RPG'}))!.genres,
          isEmpty,
        );
      });
    });

    group('platforms', () {
      test('are listed once each, console by console, in the order IGDB gave them', () {
        final game = GameApiService.gameFromHit(
          hit({
            'platforms': [
              {'id': 7}, // PS1
              {'id': 167}, // PS5
              {'id': 8}, // PS2: its own platform
              {'id': 6},
              {'id': 14}, // Mac: another PC
              {'id': 7}, // PS1 again
            ],
          }),
        )!;

        expect(game.platforms, [
          GamePlatform.ps1,
          GamePlatform.ps5,
          GamePlatform.ps2,
          GamePlatform.pc,
        ]);
      });

      test('of Skyrim are PC, PS3 and Xbox 360, exactly', () {
        final game = GameApiService.gameFromHit(
          hit({
            'platforms': [
              {'id': 6, 'name': 'PC (Microsoft Windows)'},
              {'id': 9, 'name': 'PlayStation 3'},
              {'id': 12, 'name': 'Xbox 360'},
            ],
          }),
        )!;

        expect(game.platforms, [
          GamePlatform.pc,
          GamePlatform.ps3,
          GamePlatform.xbox360,
        ]);
        expect(game.playedOnOptions, [
          GamePlatform.pc,
          GamePlatform.steamDeck,
          GamePlatform.ps3,
          GamePlatform.xbox360,
          GamePlatform.emulator,
        ]);
      });

      test('near-identical IGDB entries share one platform', () {
        final game = GameApiService.gameFromHit(
          hit({
            'platforms': [
              {'id': 18}, // NES
              {'id': 99}, // Famicom
              {'id': 12}, // Xbox 360
              {'id': 36}, // Xbox Live Arcade
              {'id': 20}, // DS
              {'id': 159}, // DSi
            ],
          }),
        )!;

        expect(game.platforms, [
          GamePlatform.nes,
          GamePlatform.xbox360,
          GamePlatform.nds,
        ]);
      });

      test('of a mobile-only game are Android and iOS, nothing else', () {
        final game = GameApiService.gameFromHit(
          hit({
            'name': 'Dream League Soccer',
            'platforms': [
              {'id': 34, 'name': 'Android'},
              {'id': 39, 'name': 'iOS'},
            ],
          }),
        )!;

        expect(game.platforms, [GamePlatform.android, GamePlatform.ios]);
        expect(game.playedOnOptions, [GamePlatform.ios, GamePlatform.android]);
      });

      test('never include Steam Deck or Emulator, whatever IGDB lists', () {
        final everything = [
          for (var id = 0; id < 600; id++) {'id': id},
        ];
        final game = GameApiService.gameFromHit(
          hit({'platforms': everything}),
        )!;

        expect(game.platforms, isNotEmpty);
        expect(game.platforms.where((p) => p.isManualOnly), isEmpty);
      });

      test('skip platforms the app does not track, and entries that are not platforms', () {
        final game = GameApiService.gameFromHit(
          hit({
            'platforms': [
              null,
              6,
              'PC',
              <String, dynamic>{},
              {'id': null},
              {'id': 82}, // Web browser
              {'id': 6},
            ],
          }),
        )!;

        expect(game.platforms, [GamePlatform.pc]);
      });
    });

    group('release date', () {
      test('is unknown when missing, malformed or out of range', () {
        for (final date in [null, 'soon', double.nan, 1e20, -2000000000]) {
          final game = GameApiService.gameFromHit(
            hit({'first_release_date': date}),
          )!;
          expect(game.releaseYear, 0, reason: '$date');
        }
      });
    });
  });

  group('GameApiService.entryFromHit', () {
    test('carries the game, its score and the exact release date', () {
      final entry = GameApiService.entryFromHit(
        hit({
          'total_rating': 91.37,
          'total_rating_count': 812,
          'first_release_date': 1760400000, // 2025-10-14 00:00 UTC
        }),
      )!;

      expect(entry.game.id, gameIdForIgdb(113112));
      expect(entry.game.title, 'Hades');
      expect(entry.score, 91.37);
      expect(entry.releaseDate, DateTime.utc(2025, 10, 14));
    });

    test('a whole-number score is still a double', () {
      expect(
        GameApiService.entryFromHit(hit({'total_rating': 90}))!.score,
        90.0,
      );
    });

    test('a hit without the figures still makes an entry', () {
      final entry = GameApiService.entryFromHit({'id': 7})!;

      expect(entry.game.igdbId, 7);
      expect(entry.score, isNull);
      expect(entry.releaseDate, isNull);
    });

    test('malformed figures are left out, not thrown on', () {
      for (final bad in [
        null,
        'high',
        double.nan,
        double.infinity,
        <String, dynamic>{},
      ]) {
        expect(
          GameApiService.entryFromHit(hit({'total_rating': bad}))!.score,
          isNull,
          reason: '$bad',
        );
      }
      for (final bad in [null, 'soon', double.nan, 1e20, -2000000000]) {
        expect(
          GameApiService.entryFromHit(hit({'first_release_date': bad}))!
              .releaseDate,
          isNull,
          reason: '$bad',
        );
      }
    });

    test('a hit that is not a game is left out', () {
      expect(GameApiService.entryFromHit(hit({'id': null})), isNull);
      expect(GameApiService.entryFromHit(null), isNull);
      expect(GameApiService.entryFromHit('Hades'), isNull);
    });
  });

  group('GameApiService.detailsFromResponse', () {
    // What igdb-handler answers for Skyrim (trimmed).
    Map<String, dynamic> skyrim([Map<String, dynamic> overrides = const {}]) => {
      'game': {
        'id': 472,
        'name': 'The Elder Scrolls V: Skyrim',
        'storyline': 'The Empire of Tamriel is on the edge.',
        'platforms': [
          {'id': 6, 'name': 'PC (Microsoft Windows)'},
          {'id': 9, 'name': 'PlayStation 3'},
          {'id': 12, 'name': 'Xbox 360'},
        ],
        'genres': [
          {'name': 'Role-playing (RPG)'},
          {'name': 'Adventure'},
        ],
        'themes': [
          {'name': 'Action'},
          {'name': 'Fantasy'},
        ],
        'game_modes': [
          {'name': 'Single player'},
        ],
        'player_perspectives': [
          {'name': 'First person'},
          {'name': 'Third person'},
        ],
        'game_engines': [
          {'name': 'Creation Engine'},
        ],
        'involved_companies': [
          {'developer': true, 'publisher': false, 'company': {'name': 'Bethesda Game Studios'}},
          {'developer': false, 'publisher': true, 'company': {'name': 'Bethesda Softworks'}},
          {'developer': true, 'supporting': true, 'company': {'name': 'Helper Studio'}},
        ],
        'similar_games': [
          {
            'id': 306,
            'name': 'The Elder Scrolls IV: Oblivion',
            'cover': {'url': '//images.igdb.com/igdb/image/upload/t_thumb/oblivion.jpg'},
            'platforms': [
              {'id': 6},
            ],
          },
          {'id': 999}, // not expanded: no name to show
        ],
      },
      'time_to_beat': {'hastily': 90000, 'normally': 180000, 'completely': 540000, 'count': 12},
      ...overrides,
    };

    test('reads the exact platforms and every attribute', () {
      final details = GameApiService.detailsFromResponse(skyrim())!;

      expect(details.igdbId, 472);
      expect(details.platforms, [GamePlatform.pc, GamePlatform.ps3, GamePlatform.xbox360]);
      expect(details.genres, ['Role-playing (RPG)', 'Adventure']);
      expect(details.themes, ['Action', 'Fantasy']);
      expect(details.gameModes, ['Single player']);
      expect(details.perspectives, ['First person', 'Third person']);
      expect(details.engines, ['Creation Engine']);
      expect(details.storyline, 'The Empire of Tamriel is on the edge.');
      expect(details.hasInfo, isTrue);
    });

    test('lists the main developers and the publishers, not the supporting studios', () {
      final details = GameApiService.detailsFromResponse(skyrim())!;

      expect(details.developers, ['Bethesda Game Studios']);
      expect(details.publishers, ['Bethesda Softworks']);
    });

    test('with no company flagged, the first stands in for both', () {
      final game = (skyrim()['game'] as Map<String, dynamic>)
        ..['involved_companies'] = [
          {'company': {'name': 'Solo Dev'}},
          {'company': {'name': 'Other'}},
        ];

      final details = GameApiService.detailsFromResponse({'game': game})!;

      expect(details.developers, ['Solo Dev']);
      expect(details.publishers, ['Solo Dev']);
    });

    test('similar games are catalog games, and one without a name is left out', () {
      final details = GameApiService.detailsFromResponse(skyrim())!;

      expect(details.similarGames, hasLength(1));
      final oblivion = details.similarGames.single;
      expect(oblivion.title, 'The Elder Scrolls IV: Oblivion');
      expect(oblivion.id, gameIdForIgdb(306));
      expect(oblivion.coverUrl, 'https://images.igdb.com/igdb/image/upload/t_cover_big/oblivion.jpg');
      expect(oblivion.inLibrary, isFalse);
    });

    test('the time to beat comes in seconds', () {
      final ttb = GameApiService.detailsFromResponse(skyrim())!.timeToBeat!;

      expect(ttb.hastily, const Duration(hours: 25));
      expect(ttb.normally, const Duration(hours: 50));
      expect(ttb.completely, const Duration(hours: 150));
      expect(ttb.count, 12);
    });

    test('a sparse game gives a sparse result, not a failure', () {
      final details = GameApiService.detailsFromResponse({
        'game': {'id': 5},
        'time_to_beat': null,
      })!;

      expect(details.platforms, isEmpty);
      expect(details.hasInfo, isFalse);
      expect(details.storyline, isNull);
      expect(details.similarGames, isEmpty);
      expect(details.timeToBeat, isNull);
    });

    test('an answer without a game is no details', () {
      for (final bad in [
        null,
        'x',
        <String, dynamic>{},
        {'error': 'IGDB is unavailable right now', 'code': 'IGDB_UNAVAILABLE'},
        {'game': null},
        {'game': {'name': 'No id'}},
        {'game': {'id': 0}},
      ]) {
        expect(GameApiService.detailsFromResponse(bad), isNull, reason: '$bad');
      }
    });
  });

  group('TimeToBeat.fromJson', () {
    test('keeps the figures it has', () {
      final ttb = TimeToBeat.fromJson({'normally': 3600, 'count': 2})!;

      expect(ttb.hastily, isNull);
      expect(ttb.normally, const Duration(hours: 1));
      expect(ttb.completely, isNull);
      expect(ttb.count, 2);
    });

    test('is null when there is no usable figure', () {
      expect(TimeToBeat.fromJson({'hastily': 0, 'normally': -3, 'completely': 'x'}), isNull);
      expect(TimeToBeat.fromJson(null), isNull);
      expect(TimeToBeat.fromJson([1, 2]), isNull);
    });
  });

  group('GameApiService.backfillFromResponse', () {
    test('reads each game with its exact platforms and genres', () {
      final games = GameApiService.backfillFromResponse({
        'games': [
          {
            'igdb_id': 472,
            'platforms': ['pc', 'ps3', 'xbox360'],
            'genres': ['Role-playing (RPG)', ' Adventure ', ''],
          },
          {'igdb_id': 1942, 'platforms': [], 'genres': []},
        ],
        'unknown': [99],
      })!;

      expect([for (final g in games) g.igdbId], [472, 1942]);
      expect(games.first.platforms, [GamePlatform.pc, GamePlatform.ps3, GamePlatform.xbox360]);
      expect(games.first.genres, ['Role-playing (RPG)', 'Adventure']);
      expect(games.last.platforms, isEmpty);
    });

    test('reads the old platform families as a library row does, and skips what it does not know', () {
      final games = GameApiService.backfillFromResponse({
        'games': [
          {
            'igdb_id': 7,
            'platforms': ['playstation', 'steamDeck', 'web', 3],
          },
        ],
      })!;

      expect(games.single.platforms, releasePlatformsFromDb(['playstation']));
      expect(games.single.genres, isEmpty);
    });

    test('skips a game without a usable IGDB id', () {
      final games = GameApiService.backfillFromResponse({
        'games': [
          {'igdb_id': 0},
          {'igdb_id': '472'},
          {'platforms': ['pc']},
          'x',
          null,
          {'igdb_id': 5.0},
        ],
      })!;

      expect([for (final g in games) g.igdbId], [5]);
    });

    test('is null for anything but a games list', () {
      for (final other in [null, 'x', [], {}, {'games': 'x'}, {'error': 'nope', 'code': 'BAD_REQUEST'}]) {
        expect(GameApiService.backfillFromResponse(other), isNull, reason: '$other');
      }
    });
  });

  group('GameApiService.backfillFailure', () {
    test('a rate limit waits as long as the server says', () {
      final result = GameApiService.backfillFailure(
        const FunctionException(status: 429, details: {'code': 'IGDB_RATE_LIMITED', 'retry_after': 42}),
      );
      expect(result.failed, isTrue);
      expect(result.games, isEmpty);
      expect(result.retryAfter, const Duration(seconds: 42));
    });

    test('IGDB being down, or a busy server that says nothing, waits a minute', () {
      for (final error in [
        const FunctionException(status: 503, details: {'code': 'IGDB_UNAVAILABLE'}),
        const FunctionException(status: 502),
      ]) {
        expect(GameApiService.backfillFailure(error).retryAfter, const Duration(minutes: 1), reason: '$error');
      }
    });

    test('no connection, a refused request or an old deploy stop the backfill instead', () {
      for (final error in [
        const FunctionException(status: 0),
        const FunctionException(status: 400, details: {'code': 'BAD_REQUEST'}),
        const FunctionException(status: 401, details: {'code': 'UNAUTHENTICATED'}),
        Exception('boom'),
      ]) {
        final result = GameApiService.backfillFailure(error);
        expect(result.failed, isTrue, reason: '$error');
        expect(result.retryAfter, isNull, reason: '$error');
      }
    });
  });
}
