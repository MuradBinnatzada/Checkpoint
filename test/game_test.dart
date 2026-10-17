import 'package:flutter_test/flutter_test.dart';

import 'package:checkpoint/models/game.dart';

import 'support/fakes.dart';

/// What [Game.toJson] writes, with [overrides] applied on top.
Map<String, dynamic> gameJson([Map<String, dynamic> overrides = const {}]) => {
  'id': 'g1',
  'title': 'Hades',
  'publisher': 'Supergiant Games',
  'developer': 'Supergiant Games',
  'releaseYear': 2020,
  'platforms': ['pc', 'ps5'],
  'genres': ['Roguelike'],
  'synopsis': 'Escape the underworld.',
  'coverUrl': null,
  'igdbId': null,
  'steamAppId': null,
  'status': null,
  'rating': 0,
  'hoursPlayed': 0,
  'playedOn': null,
  'purchasePrice': 0,
  'dateAdded': null,
  'isFavorite': false,
  ...overrides,
};

void main() {
  group('Game.fromJson', () {
    test('reads back what toJson wrote', () {
      final game = testGame('g1', favorite: true);
      final read = Game.fromJson(game.toJson());

      expect(read.id, game.id);
      expect(read.platforms, game.platforms);
      expect(read.status, game.status);
      expect(
        read.dateAdded!.toUtc(),
        game.dateAdded!.toUtc(),
      ); // same instant; read back in local time
      expect(read.isFavorite, isTrue);
    });

    test('optional fields may be null', () {
      final game = Game.fromJson(gameJson());

      expect(game.coverUrl, isNull);
      expect(game.igdbId, isNull);
      expect(game.steamAppId, isNull);
      expect(game.status, isNull);
      expect(game.playedOn, isNull);
      expect(game.dateAdded, isNull);
      expect(game.isFavorite, isFalse);
      expect(game.inLibrary, isFalse);
    });

    test('accepts whole numbers where it expects decimals', () {
      final game = Game.fromJson(
        gameJson({'rating': 4, 'hoursPlayed': 10, 'purchasePrice': 60}),
      );

      expect(game.rating, 4.0);
      expect(game.hoursPlayed, 10.0);
      expect(game.purchasePrice, 60.0);
    });

    test('values it does not know become null, not an error', () {
      final game = Game.fromJson(
        gameJson({
          'status': 'archived',
          'playedOn': 'dreamcast',
          'dateAdded': 'last tuesday',
          'platforms': ['pc', 'dreamcast', null, 7],
        }),
      );

      expect(game.status, isNull);
      expect(game.playedOn, isNull);
      expect(game.dateAdded, isNull);
      expect(game.platforms, [GamePlatform.pc]);
    });

    test(
      'a missing required field throws, so the offline cache drops the entry',
      () {
        for (final field in [
          'id',
          'title',
          'publisher',
          'developer',
          'synopsis',
          'releaseYear',
          'rating',
        ]) {
          expect(
            () => Game.fromJson(gameJson({field: null})),
            throwsA(isA<TypeError>()),
            reason: '$field: null',
          );
        }
      },
    );
  });

  group('status and platform names', () {
    test(
      'a status reads back from its database spelling and a few older ones',
      () {
        for (final status in GameStatus.values) {
          expect(gameStatusFromDb(gameStatusToDb(status)), status);
        }
        expect(gameStatusFromDb(' to_play '), GameStatus.toPlay);
        expect(gameStatusFromDb('To Play'), GameStatus.toPlay);
      },
    );

    test('nothing, blanks and strangers are no status', () {
      expect(gameStatusFromDb(null), isNull);
      expect(gameStatusFromDb(''), isNull);
      expect(gameStatusFromDb('archived'), isNull);
      expect(gameStatusFromDb(3), isNull);
    });

    test('a platform reads back from its database spelling', () {
      for (final platform in GamePlatform.values) {
        expect(gamePlatformFromDb(gamePlatformToDb(platform)), platform);
      }
      expect(gamePlatformToDb(GamePlatform.emulator), 'retro');
    });

    test('platform names are matched loosely, and old consoles roll up', () {
      expect(gamePlatformFromDb('PS5'), GamePlatform.ps5);
      expect(gamePlatformFromDb('Steam Deck'), GamePlatform.steamDeck);
      expect(gamePlatformFromDb('PlayStation 2'), GamePlatform.playstation);
      expect(gamePlatformFromDb('Nintendo Switch'), GamePlatform.nswitch);
      expect(gamePlatformFromDb('iOS'), GamePlatform.mobile);
    });

    test('nothing, blanks and strangers are no platform', () {
      expect(gamePlatformFromDb(null), isNull);
      expect(gamePlatformFromDb('  '), isNull);
      expect(gamePlatformFromDb('dreamcast'), isNull);
      expect(gamePlatformFromDb(42), isNull);
    });
  });

  group('release platforms', () {
    test('Steam Deck and Emulator are manual "played on" choices only', () {
      expect(
        [
          for (final p in GamePlatform.values)
            if (p.isManualOnly) p,
        ],
        [GamePlatform.steamDeck, GamePlatform.emulator],
      );
    });

    test('a stored list keeps real platforms once each and drops the manual-only ones', () {
      expect(
        releasePlatformsFromDb([
          'steamdeck',
          'pc',
          'Steam Deck',
          'retro',
          'emulator',
          'PC',
          'dreamcast',
          null,
          3,
        ]),
        [GamePlatform.pc],
      );
      expect(releasePlatformsFromDb(const []), isEmpty);
    });

    test('the offline cache drops a stray Steam Deck or Emulator too', () {
      final game = Game.fromJson(
        gameJson({
          'platforms': ['steamdeck', 'mobile', 'retro'],
        }),
      );

      expect(game.platforms, [GamePlatform.mobile]);
    });
  });

  group('Game.playedOnOptions', () {
    // In the library only when it was played somewhere.
    Game released(List<GamePlatform> platforms, {GamePlatform? playedOn}) =>
        testGame(
          'g',
          title: 'Dream League Soccer',
          status: playedOn == null ? null : GameStatus.playing,
          platforms: platforms,
          playedOn: playedOn,
        );

    test('a mobile-only game offers Mobile and nothing else', () {
      expect(released([GamePlatform.mobile]).playedOnOptions, [
        GamePlatform.mobile,
      ]);
    });

    test('Steam Deck is offered for a PC game only', () {
      expect(released([GamePlatform.pc]).playedOnOptions, [
        GamePlatform.pc,
        GamePlatform.steamDeck,
      ]);
      expect(
        released([GamePlatform.ps5]).playedOnOptions,
        isNot(contains(GamePlatform.steamDeck)),
      );
      expect(
        released([GamePlatform.nswitch]).playedOnOptions,
        isNot(contains(GamePlatform.steamDeck)),
      );
    });

    test('Emulator is offered for a console game only', () {
      expect(released([GamePlatform.nintendo]).playedOnOptions, [
        GamePlatform.nintendo,
        GamePlatform.emulator,
      ]);
      expect(
        released([GamePlatform.pc]).playedOnOptions,
        isNot(contains(GamePlatform.emulator)),
      );
      expect(
        released([GamePlatform.mobile]).playedOnOptions,
        isNot(contains(GamePlatform.emulator)),
      );
    });

    test(
      'a multi-platform game offers each release once, in platform order',
      () {
        expect(
          released([GamePlatform.ps5, GamePlatform.pc, GamePlatform.xbox])
              .playedOnOptions,
          [
            GamePlatform.pc,
            GamePlatform.steamDeck,
            GamePlatform.ps5,
            GamePlatform.xbox,
            GamePlatform.emulator,
          ],
        );
      },
    );

    test('the saved choice stays offered even when the game was not released there', () {
      expect(
        released([
          GamePlatform.mobile,
        ], playedOn: GamePlatform.emulator).playedOnOptions,
        [GamePlatform.mobile, GamePlatform.emulator],
      );
    });

    test('a game with no known release platform offers every choice', () {
      expect(released(const []).playedOnOptions, GamePlatform.selectable);
    });
  });

  group('release year', () {
    test('only 1950-2100 is a valid year', () {
      expect(sanitizeReleaseYear(null), isNull);
      expect(sanitizeReleaseYear(0), isNull);
      expect(sanitizeReleaseYear(1949), isNull);
      expect(sanitizeReleaseYear(1950), 1950);
      expect(sanitizeReleaseYear(2100), 2100);
      expect(sanitizeReleaseYear(2101), isNull);
    });

    test('IGDB timestamps become a year; anything else is unknown', () {
      expect(releaseYearFromUnixSeconds(1600000000), 2020);
      expect(releaseYearFromUnixSeconds(1600000000.0), 2020);
      expect(releaseYearFromUnixSeconds(-631152000), 1950);

      expect(releaseYearFromUnixSeconds(null), isNull);
      expect(releaseYearFromUnixSeconds('1600000000'), isNull);
      expect(releaseYearFromUnixSeconds(double.nan), isNull);
      expect(releaseYearFromUnixSeconds(double.infinity), isNull);
      expect(releaseYearFromUnixSeconds(1e20), isNull);
      expect(releaseYearFromUnixSeconds(-1000000000), isNull); // 1938
    });

    test('hasReleaseYear is false for the 0 placeholder', () {
      expect(testGame('g1', year: 0).hasReleaseYear, isFalse);
      expect(testGame('g1', year: 2020).hasReleaseYear, isTrue);
    });
  });

  test('a game id is its IGDB id, zero-padded', () {
    expect(gameIdForIgdb(7), '00000000-0000-4000-8000-000000000007');
    expect(gameIdForIgdb(113112), '00000000-0000-4000-8000-000000113112');
  });
}
