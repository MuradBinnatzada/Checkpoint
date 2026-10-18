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

    test('keeps the chosen backdrop, and withoutUserState drops it', () {
      const art = 'https://images.igdb.com/igdb/image/upload/t_1080p/ar5l8.jpg';
      final game = testGame('g1').withBackdrop(art);

      expect(Game.fromJson(game.toJson()).customBackdropUrl, art);
      expect(game.copyWith(rating: 2).customBackdropUrl, art);
      expect(game.withBackdrop(null).customBackdropUrl, isNull);
      expect(game.withBackdrop(null).coverUrl, game.coverUrl);
      expect(game.withoutUserState().customBackdropUrl, isNull);
      expect(Game.fromJson(gameJson()).customBackdropUrl, isNull); // saved before backdrops
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
          'playedOn': 'atari2600',
          'dateAdded': 'last tuesday',
          'platforms': ['pc', 'atari2600', null, 7],
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

    test('platform names are matched loosely, and each console is its own platform', () {
      expect(gamePlatformFromDb('PS5'), GamePlatform.ps5);
      expect(gamePlatformFromDb('Steam Deck'), GamePlatform.steamDeck);
      expect(gamePlatformFromDb('PlayStation 2'), GamePlatform.ps2);
      expect(gamePlatformFromDb('PlayStation 3'), GamePlatform.ps3);
      expect(gamePlatformFromDb('Xbox 360'), GamePlatform.xbox360);
      expect(gamePlatformFromDb('Xbox Series X|S'), GamePlatform.xboxSeries);
      expect(gamePlatformFromDb('Nintendo Switch'), GamePlatform.nswitch);
      expect(gamePlatformFromDb('Wii U'), GamePlatform.wiiU);
      expect(gamePlatformFromDb('Dreamcast'), GamePlatform.dreamcast);
      expect(gamePlatformFromDb('iOS'), GamePlatform.ios);
    });

    test('what older versions stored still reads as the whole family', () {
      expect(gamePlatformFromDb('playstation'), GamePlatform.playstation);
      expect(gamePlatformFromDb('xbox'), GamePlatform.xbox);
      expect(gamePlatformFromDb('nintendo'), GamePlatform.nintendo);
      expect(gamePlatformFromDb('mobile'), GamePlatform.mobile);
    });

    test('every platform survives being stored and read back', () {
      for (final p in GamePlatform.values) {
        expect(gamePlatformFromDb(gamePlatformToDb(p)), p, reason: p.name);
      }
    });

    test('nothing, blanks and strangers are no platform', () {
      expect(gamePlatformFromDb(null), isNull);
      expect(gamePlatformFromDb('  '), isNull);
      expect(gamePlatformFromDb('atari2600'), isNull);
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
          'atari2600',
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

  group('GamePlatform', () {
    test('every platform has a family, and so an icon and a colour', () {
      for (final p in GamePlatform.values) {
        expect(p.icon, isNotNull, reason: p.name);
        expect(p.color, isNotNull, reason: p.name);
      }
      expect(GamePlatform.ps3.family, PlatformFamily.playstation);
      expect(GamePlatform.xbox360.family, PlatformFamily.xbox);
      expect(GamePlatform.wiiU.family, PlatformFamily.nintendo);
      expect(GamePlatform.dreamcast.family, PlatformFamily.sega);
    });

    test('only consoles and handhelds can be emulated', () {
      expect(GamePlatform.ps3.isConsole, isTrue);
      expect(GamePlatform.gba.isConsole, isTrue);
      expect(GamePlatform.dreamcast.isConsole, isTrue);
      for (final p in [GamePlatform.pc, GamePlatform.steamDeck, GamePlatform.ios, GamePlatform.android, GamePlatform.vr, GamePlatform.emulator]) {
        expect(p.isConsole, isFalse, reason: p.name);
      }
    });

    test('Emulator and Steam Deck are never a stored release platform name', () {
      expect(gamePlatformToDb(GamePlatform.emulator), 'retro');
      expect(gamePlatformToDb(GamePlatform.xbox360), 'xbox360');
      expect(gamePlatformToDb(GamePlatform.wiiU), 'wiiU');
    });

    test('the pickers list the platforms of each family newest first', () {
      final order = GamePlatform.values;
      expect(order.indexOf(GamePlatform.ps5), lessThan(order.indexOf(GamePlatform.ps4)));
      expect(order.indexOf(GamePlatform.ps4), lessThan(order.indexOf(GamePlatform.ps3)));
      expect(order.indexOf(GamePlatform.xboxSeries), lessThan(order.indexOf(GamePlatform.xbox360)));
      expect(order.indexOf(GamePlatform.nswitch), lessThan(order.indexOf(GamePlatform.wii)));
    });
  });

  group('Game.playedOnOptions', () {
    // In the library only when it was played somewhere. Not a Steam game, unless
    // [steamAppId] says so.
    Game released(
      List<GamePlatform> platforms, {
      GamePlatform? playedOn,
      int? steamAppId,
    }) => testGame(
      'g',
      title: 'Dream League Soccer',
      status: playedOn == null ? null : GameStatus.playing,
      platforms: platforms,
      playedOn: playedOn,
      steamAppId: steamAppId,
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

    test('Skyrim offers PC, PS3 and Xbox 360 and what derives from them, nothing else', () {
      expect(
        released([GamePlatform.pc, GamePlatform.ps3, GamePlatform.xbox360], steamAppId: 489830, playedOn: GamePlatform.pc).playedOnOptions,
        [GamePlatform.pc, GamePlatform.steamDeck, GamePlatform.ps3, GamePlatform.xbox360, GamePlatform.emulator],
      );
    });

    test('a Steam game known only as PC offers just PC and Steam Deck, not every platform', () {
      final options = released([GamePlatform.pc], steamAppId: 292030, playedOn: GamePlatform.pc).playedOnOptions;

      expect(options, [GamePlatform.pc, GamePlatform.steamDeck]);
      expect(options, isNot(contains(GamePlatform.mobile)));
      expect(options, isNot(contains(GamePlatform.ios)));
    });

    test('a mobile-only game offers its own platforms and no PC', () {
      expect(released([GamePlatform.ios, GamePlatform.android]).playedOnOptions, [GamePlatform.ios, GamePlatform.android]);
    });

    test('a game on retro consoles offers those consoles and Emulator', () {
      expect(
        released([GamePlatform.snes, GamePlatform.gba]).playedOnOptions,
        [GamePlatform.snes, GamePlatform.gba, GamePlatform.emulator],
      );
    });

    test('the older whole-family values still offer an emulator', () {
      expect(released([GamePlatform.playstation]).playedOnOptions, [GamePlatform.playstation, GamePlatform.emulator]);
    });

    test('keeps a saved Nintendo choice, which is not on the list of unknown-game choices', () {
      final options = released([GamePlatform.pc], playedOn: GamePlatform.nintendo).playedOnOptions;

      expect(options, contains(GamePlatform.nintendo));
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
