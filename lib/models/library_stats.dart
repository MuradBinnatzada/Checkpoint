import 'package:flutter/foundation.dart';

import 'package:checkpoint/models/game.dart';

/// Numbers about a library, worked out from its games: how many are in each
/// status, the hours played in total and per platform, and how the ratings are
/// spread. The same code serves the signed-in member's library and another
/// member's, so the two profile pages always add up the same way.
@immutable
class LibraryStats {
  const LibraryStats({
    this.games = 0,
    this.byStatus = const {},
    this.totalHours = 0,
    this.hoursByPlatform = const {},
    this.ratingCounts = const {},
    this.ratedCount = 0,
    this.averageRating = 0,
  });

  /// Every rating a game can have, lowest first (half-star steps).
  static const List<double> ratingSteps = [
    0.5,
    1,
    1.5,
    2,
    2.5,
    3,
    3.5,
    4,
    4.5,
    5,
  ];

  factory LibraryStats.of(Iterable<Game> library) {
    final byStatus = <GameStatus, int>{};
    final ratingCounts = <double, int>{};
    var games = 0;
    var totalHours = 0.0;
    var ratingSum = 0.0;
    var ratedCount = 0;
    for (final g in library) {
      games++;
      final status = g.status;
      if (status != null) byStatus[status] = (byStatus[status] ?? 0) + 1;
      totalHours += g.hoursPlayed;
      if (g.rating > 0) {
        ratedCount++;
        ratingSum += g.rating;
        // Ratings are stored in half-star steps; round so a stray value still
        // lands in a bar.
        final step = ((g.rating * 2).round() / 2).clamp(0.5, 5.0).toDouble();
        ratingCounts[step] = (ratingCounts[step] ?? 0) + 1;
      }
    }
    return LibraryStats(
      games: games,
      byStatus: Map.unmodifiable(byStatus),
      totalHours: totalHours,
      hoursByPlatform: hoursByPlatformOf(library),
      ratingCounts: Map.unmodifiable(ratingCounts),
      ratedCount: ratedCount,
      averageRating: ratedCount == 0 ? 0 : ratingSum / ratedCount,
    );
  }

  /// Total hours per platform, most played first, based on each game's total
  /// playtime (so hours imported by Steam sync count too, not just logged
  /// sessions). A game counts for the platform it was played on, else the first
  /// it was released on, else PC.
  static Map<GamePlatform, double> hoursByPlatformOf(Iterable<Game> library) {
    final m = <GamePlatform, double>{};
    for (final g in library) {
      if (g.hoursPlayed <= 0) continue;
      final platform =
          g.playedOn ??
          (g.platforms.isNotEmpty ? g.platforms.first : GamePlatform.pc);
      m[platform] = (m[platform] ?? 0) + g.hoursPlayed;
    }
    final entries = m.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(entries);
  }

  /// Games in the library, whatever their status.
  final int games;
  final Map<GameStatus, int> byStatus;
  final double totalHours;
  final Map<GamePlatform, double> hoursByPlatform;

  /// Games per rating, keyed by [ratingSteps]. Unrated games are not counted.
  final Map<double, int> ratingCounts;
  final int ratedCount;

  /// 0 when nothing is rated.
  final double averageRating;

  int count(GameStatus status) => byStatus[status] ?? 0;
}
