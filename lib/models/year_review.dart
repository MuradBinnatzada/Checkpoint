import 'package:flutter/foundation.dart';

import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/log_entry.dart';

/// A game and the hours logged on it in a year.
typedef GameHours = ({Game game, double hours});

/// A genre and the hours logged on its games in a year.
typedef GenreHours = ({String genre, double hours});

/// One year of play, worked out from the sessions the member logged and their
/// library: how much, when, what and where. Hours a Steam import added without
/// a session are in no year, as nothing says when they were played.
@immutable
class YearReview {
  const YearReview._({
    required this.year,
    required this.hours,
    required this.sessionCount,
    required this.gamesPlayed,
    required this.daysPlayed,
    required this.longestStreak,
    required this.hoursByMonth,
    required this.topGames,
    required this.hoursByPlatform,
    required this.topGenres,
    required this.completed,
    required this.addedCount,
    required this.busiestDay,
    required this.busiestDayHours,
  });

  /// How many games and genres the review lists at most.
  static const topCount = 5;

  final int year;

  /// Hours of every session played in [year].
  final double hours;
  final int sessionCount;

  /// Different games with a session in [year].
  final int gamesPlayed;

  /// Different days with a session.
  final int daysPlayed;

  /// The most days in a row with a session.
  final int longestStreak;

  /// Twelve values, January first.
  final List<double> hoursByMonth;

  /// The most played games, most hours first, at most [topCount].
  final List<GameHours> topGames;

  /// Hours per platform the sessions were played on, most first.
  final Map<GamePlatform, double> hoursByPlatform;

  /// The genres played the most (a game's hours count for each of its genres),
  /// at most [topCount].
  final List<GenreHours> topGenres;

  /// The games completed in [year], the latest first: marked completed then, or
  /// (completed before the date was recorded) last played then.
  final List<Game> completed;

  /// Games that came into the library in [year].
  final int addedCount;

  /// The day with the most hours, and how many; null without sessions.
  final DateTime? busiestDay;
  final double busiestDayHours;

  bool get isEmpty => sessionCount == 0 && completed.isEmpty && addedCount == 0;

  /// The review of [year]. [games] is the library: a session of a game no longer
  /// in it still counts in the totals, but not in the lists of games.
  factory YearReview.of({
    required int year,
    required List<LogEntry> sessions,
    required List<Game> games,
  }) {
    final byId = {for (final g in games) g.id: g};
    final inYear = [for (final s in sessions) if (s.timestamp.year == year) s];

    var hours = 0.0;
    final byMonth = List<double>.filled(12, 0);
    final byGame = <String, double>{};
    final byPlatform = <GamePlatform, double>{};
    final byDay = <DateTime, double>{};
    for (final s in inYear) {
      hours += s.hours;
      byMonth[s.timestamp.month - 1] += s.hours;
      byGame.update(s.gameId, (h) => h + s.hours, ifAbsent: () => s.hours);
      byPlatform.update(s.platform, (h) => h + s.hours, ifAbsent: () => s.hours);
      final day = _day(s.timestamp);
      byDay.update(day, (h) => h + s.hours, ifAbsent: () => s.hours);
    }

    final topGames = <GameHours>[
      for (final e in byGame.entries)
        if (byId[e.key] case final game?) (game: game, hours: e.value),
    ]..sort((a, b) {
        final c = b.hours.compareTo(a.hours);
        return c != 0 ? c : a.game.title.compareTo(b.game.title);
      });

    final byGenre = <String, double>{};
    for (final e in byGame.entries) {
      for (final genre in {...?byId[e.key]?.genres}) {
        byGenre.update(genre, (h) => h + e.value, ifAbsent: () => e.value);
      }
    }
    final topGenres = <GenreHours>[
      for (final e in byGenre.entries) (genre: e.key, hours: e.value),
    ]..sort((a, b) {
        final c = b.hours.compareTo(a.hours);
        return c != 0 ? c : a.genre.compareTo(b.genre);
      });

    // The day each game was last played, for completions without a date.
    final lastPlayed = <String, DateTime>{};
    for (final s in sessions) {
      final seen = lastPlayed[s.gameId];
      if (seen == null || s.timestamp.isAfter(seen)) lastPlayed[s.gameId] = s.timestamp;
    }
    DateTime? completedOn(Game g) {
      if (g.status != GameStatus.completed) return null;
      return g.completedAt ?? lastPlayed[g.id];
    }

    final completed = [
      for (final g in games)
        if (completedOn(g)?.year == year) g,
    ]..sort((a, b) => completedOn(b)!.compareTo(completedOn(a)!));

    DateTime? busiest;
    var busiestHours = 0.0;
    for (final e in byDay.entries) {
      if (e.value > busiestHours || (e.value == busiestHours && busiest != null && e.key.isBefore(busiest))) {
        busiest = e.key;
        busiestHours = e.value;
      }
    }

    final platforms = byPlatform.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return YearReview._(
      year: year,
      hours: hours,
      sessionCount: inYear.length,
      gamesPlayed: byGame.length,
      daysPlayed: byDay.length,
      longestStreak: _longestStreak(byDay.keys),
      hoursByMonth: List.unmodifiable(byMonth),
      topGames: List.unmodifiable(topGames.take(topCount)),
      hoursByPlatform: Map.unmodifiable({for (final e in platforms) e.key: e.value}),
      topGenres: List.unmodifiable(topGenres.take(topCount)),
      completed: List.unmodifiable(completed),
      addedCount: games.where((g) => g.inLibrary && g.dateAdded?.year == year).length,
      busiestDay: busiest,
      busiestDayHours: busiestHours,
    );
  }

  /// The years there is something to review, newest first: every year with a
  /// session, a completion or a game added, and always [currentYear].
  static List<int> yearsOf({
    required List<LogEntry> sessions,
    required List<Game> games,
    required int currentYear,
  }) {
    final years = <int>{
      currentYear,
      for (final s in sessions) s.timestamp.year,
      for (final g in games)
        if (g.inLibrary) ...[?g.dateAdded?.year, ?g.completedAt?.year],
    };
    return years.where((y) => y <= currentYear).toList()..sort((a, b) => b.compareTo(a));
  }

  /// The calendar day of [t], as a UTC date so a daylight saving change can't
  /// make two days 23 hours apart.
  static DateTime _day(DateTime t) => DateTime.utc(t.year, t.month, t.day);

  static int _longestStreak(Iterable<DateTime> days) {
    final sorted = days.toList()..sort();
    var best = 0;
    var run = 0;
    DateTime? previous;
    for (final day in sorted) {
      run = previous != null && day.difference(previous).inDays == 1 ? run + 1 : 1;
      if (run > best) best = run;
      previous = day;
    }
    return best;
  }
}
