import 'package:flutter_test/flutter_test.dart';

import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/library_stats.dart';

import 'support/fakes.dart';

void main() {
  Game g(
    String id, {
    GameStatus? status = GameStatus.playing,
    double rating = 0,
    double hours = 0,
    GamePlatform? playedOn,
    List<GamePlatform> platforms = const [GamePlatform.pc],
  }) => testGame(
    id,
    status: status,
    hours: hours,
    platforms: platforms,
    playedOn: playedOn,
    cover: false,
  ).copyWith(rating: rating);

  test('an empty library has nothing in it', () {
    final stats = LibraryStats.of(const []);

    expect(stats.games, 0);
    expect(stats.totalHours, 0);
    expect(stats.ratedCount, 0);
    expect(stats.averageRating, 0);
    expect(stats.hoursByPlatform, isEmpty);
    expect(stats.count(GameStatus.completed), 0);
  });

  test('counts the games in each status and adds up the hours', () {
    final stats = LibraryStats.of([
      g('a', status: GameStatus.playing, hours: 4),
      g('b', status: GameStatus.playing, hours: 1.5),
      g('c', status: GameStatus.completed, hours: 20),
      g('d', status: GameStatus.wishlist, hours: 0),
    ]);

    expect(stats.games, 4);
    expect(stats.count(GameStatus.playing), 2);
    expect(stats.count(GameStatus.completed), 1);
    expect(stats.count(GameStatus.wishlist), 1);
    expect(stats.count(GameStatus.dropped), 0);
    expect(stats.totalHours, 25.5);
  });

  group('hours by platform', () {
    test('goes to the platform played on, else the first released on, else PC; most played first', () {
      final stats = LibraryStats.of([
        g('a', hours: 5, playedOn: GamePlatform.ps5),
        // No "played on" yet (testGame picks PC for a game that has a status).
        g(
          'b',
          status: null,
          hours: 2,
          platforms: const [GamePlatform.xbox, GamePlatform.pc],
        ),
        g('c', status: null, hours: 9, platforms: const []),
        g(
          'd',
          hours: 0,
          playedOn: GamePlatform.nswitch,
        ), // no hours: not listed
      ]);

      expect(stats.hoursByPlatform, {
        GamePlatform.pc: 9,
        GamePlatform.ps5: 5,
        GamePlatform.xbox: 2,
      });
      expect(stats.hoursByPlatform.keys.first, GamePlatform.pc);
    });

    test(
      'is what LibraryStore reports for the same games (one implementation)',
      () {
        final games = [
          g('a', hours: 3, playedOn: GamePlatform.ps5),
          g('b', hours: 7),
        ];

        expect(
          LibraryStats.hoursByPlatformOf(games),
          LibraryStats.of(games).hoursByPlatform,
        );
      },
    );
  });

  group('ratings', () {
    test('are counted per half-star step; unrated games are left out', () {
      final stats = LibraryStats.of([
        g('a', rating: 4.5),
        g('b', rating: 4.5),
        g('c', rating: 0.5),
        g('d', rating: 5),
        g('e', rating: 0), // unrated
      ]);

      expect(stats.ratedCount, 4);
      expect(stats.ratingCounts, {4.5: 2, 0.5: 1, 5.0: 1});
      expect(stats.averageRating, closeTo((4.5 + 4.5 + 0.5 + 5) / 4, 1e-9));
    });

    test('a stray in-between value lands in the nearest bar', () {
      final stats = LibraryStats.of([g('a', rating: 3.7), g('b', rating: 12)]);

      expect(stats.ratingCounts, {3.5: 1, 5.0: 1});
    });

    test('every step from half a star to five has a place', () {
      expect(LibraryStats.ratingSteps, hasLength(10));
      expect(LibraryStats.ratingSteps.first, 0.5);
      expect(LibraryStats.ratingSteps.last, 5);
    });
  });
}
