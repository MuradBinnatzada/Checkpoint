import 'package:flutter_test/flutter_test.dart';

import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/log_entry.dart';
import 'package:checkpoint/models/year_review.dart';

import 'support/fakes.dart';

void main() {
  var n = 0;
  LogEntry session(String gameId, DateTime at, double hours, {GamePlatform platform = GamePlatform.pc}) =>
      LogEntry(id: 's${n++}', gameId: gameId, timestamp: at, hours: hours, platform: platform);

  final hades = testGame('hades', title: 'Hades', genres: const ['Roguelike', 'Action']);
  final celeste = testGame('celeste', title: 'Celeste', genres: const ['Platformer', 'Action'])
      .copyWith(status: GameStatus.completed, dateAdded: DateTime(2025, 12, 30))
      .withCompletedAt(DateTime(2026, 3, 2));
  final outer = testGame('outer', title: 'Outer Wilds', genres: const ['Adventure'])
      .copyWith(status: GameStatus.completed, dateAdded: DateTime(2026, 1, 5));
  final library = [hades, celeste, outer];

  final sessions = [
    session('hades', DateTime(2026, 1, 1, 21), 2),
    session('hades', DateTime(2026, 1, 2, 21), 1.5, platform: GamePlatform.steamDeck),
    session('hades', DateTime(2026, 1, 3, 9), 3),
    session('celeste', DateTime(2026, 1, 3, 20), 1),
    session('outer', DateTime(2026, 2, 10, 20), 4),
    session('gone', DateTime(2026, 2, 11, 20), 0.5), // a game removed since
    session('hades', DateTime(2025, 12, 31, 23), 10), // last year
  ];

  final review = YearReview.of(year: 2026, sessions: sessions, games: library);

  test('adds up the sessions of the year only', () {
    expect(review.hours, 12);
    expect(review.sessionCount, 6);
    expect(review.gamesPlayed, 4);
    expect(review.daysPlayed, 5);
    expect(review.hoursByMonth.take(3), [7.5, 4.5, 0]);
    expect(review.hoursByMonth, hasLength(12));
  });

  test('a streak is days in a row, across the turn of a month too', () {
    expect(review.longestStreak, 3);
    final turn = YearReview.of(
      year: 2026,
      sessions: [
        session('hades', DateTime(2026, 3, 30), 1),
        session('hades', DateTime(2026, 3, 31), 1),
        session('hades', DateTime(2026, 4, 1), 1),
        session('hades', DateTime(2026, 4, 2), 1),
      ],
      games: library,
    );
    expect(turn.longestStreak, 4);
  });

  test('lists the most played games and genres, a removed game only in the totals', () {
    expect([for (final g in review.topGames) (g.game.title, g.hours)], [
      ('Hades', 6.5),
      ('Outer Wilds', 4.0),
      ('Celeste', 1.0),
    ]);
    expect([for (final g in review.topGenres) (g.genre, g.hours)], [
      ('Action', 7.5),
      ('Roguelike', 6.5),
      ('Adventure', 4.0),
      ('Platformer', 1.0),
    ]);
    expect(review.hoursByPlatform.keys, [GamePlatform.pc, GamePlatform.steamDeck]);
    expect(review.hoursByPlatform[GamePlatform.steamDeck], 1.5);
  });

  test('a completion counts in the year it was marked, or without a date the year it was last played', () {
    expect(review.completed.map((g) => g.id), ['celeste', 'outer']);
    final lastYear = YearReview.of(year: 2025, sessions: sessions, games: library);
    expect(lastYear.completed, isEmpty);
    expect(lastYear.hours, 10);
  });

  test('the busiest day is the one with the most hours, the first of a tie', () {
    // Jan 3 (3 h of Hades, 1 of Celeste) and Feb 10 (4 h) tie.
    expect(review.busiestDay, DateTime.utc(2026, 1, 3));
    expect(review.busiestDayHours, 4);
    final tie = YearReview.of(
      year: 2026,
      sessions: [session('hades', DateTime(2026, 5, 2), 2), session('hades', DateTime(2026, 5, 1), 2)],
      games: library,
    );
    expect(tie.busiestDay, DateTime.utc(2026, 5, 1));
  });

  test('counts the games added to the library in the year', () {
    // Outer Wilds, and Hades (testGame adds it on 2026-01-02); Celeste came in 2025.
    expect(review.addedCount, 2);
  });

  test('a year with nothing in it is empty', () {
    final empty = YearReview.of(year: 2019, sessions: sessions, games: library);
    expect(empty.isEmpty, isTrue);
    expect(empty.busiestDay, isNull);
    expect(empty.longestStreak, 0);
  });

  test('the years to pick from are the ones with something in them, newest first', () {
    expect(
      YearReview.yearsOf(sessions: sessions, games: library, currentYear: 2026),
      [2026, 2025],
    );
    expect(YearReview.yearsOf(sessions: const [], games: const [], currentYear: 2027), [2027]);
  });
}
