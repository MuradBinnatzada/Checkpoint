import 'package:flutter_test/flutter_test.dart';

import 'package:checkpoint/models/game.dart';
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
      test('are listed once per brand, in the order IGDB gave them', () {
        final game = GameApiService.gameFromHit(
          hit({
            'platforms': [
              {'id': 7}, // PS1
              {'id': 167}, // PS5
              {'id': 8}, // PS2: another PlayStation
              {'id': 6},
              {'id': 14}, // Mac: another PC
            ],
          }),
        )!;

        expect(game.platforms, [
          GamePlatform.playstation,
          GamePlatform.ps5,
          GamePlatform.pc,
        ]);
      });

      test('of a mobile-only game are just Mobile', () {
        final game = GameApiService.gameFromHit(
          hit({
            'name': 'Dream League Soccer',
            'platforms': [
              {'id': 34, 'name': 'Android'},
              {'id': 39, 'name': 'iOS'},
            ],
          }),
        )!;

        expect(game.platforms, [GamePlatform.mobile]);
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
              {'id': 82},
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
}
