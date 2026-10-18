import 'package:flutter/foundation.dart';

import 'package:checkpoint/models/game.dart';

/// How long IGDB's players take to finish a game: a rushed run ([hastily]), a
/// normal one ([normally]) and a complete one ([completely]). Any can be missing.
@immutable
class TimeToBeat {
  const TimeToBeat({
    this.hastily,
    this.normally,
    this.completely,
    this.count = 0,
  });

  final Duration? hastily;
  final Duration? normally;
  final Duration? completely;

  /// How many players submitted a time; 0 when IGDB does not say.
  final int count;

  bool get isEmpty => hastily == null && normally == null && completely == null;

  /// From the `time_to_beat` the `igdb-handler` function sends (figures in
  /// seconds), or null when there is none.
  static TimeToBeat? fromJson(Object? json) {
    if (json is! Map) return null;
    Duration? seconds(Object? v) =>
        v is num && v.isFinite && v > 0 ? Duration(seconds: v.round()) : null;
    final count = json['count'];
    final result = TimeToBeat(
      hastily: seconds(json['hastily']),
      normally: seconds(json['normally']),
      completely: seconds(json['completely']),
      count: count is num && count.isFinite && count > 0 ? count.toInt() : 0,
    );
    return result.isEmpty ? null : result;
  }
}

/// What IGDB says about a game beyond what the library holds: the exact
/// platforms, the attributes the details screen lists, the storyline, similar
/// games and the time to beat. Loaded when a game's screen opens and kept in
/// memory (see `GameDetailsStore`); the stable part is also saved on the shared
/// catalog row by the server.
@immutable
class GameDetails {
  const GameDetails({
    required this.igdbId,
    this.platforms = const [],
    this.genres = const [],
    this.themes = const [],
    this.gameModes = const [],
    this.perspectives = const [],
    this.engines = const [],
    this.developers = const [],
    this.publishers = const [],
    this.companyIds = const {},
    this.storyline,
    this.similarGames = const [],
    this.timeToBeat,
  });

  final int igdbId;

  /// Exact release platforms (PS3 and Xbox 360, not "PlayStation" and "Xbox").
  final List<GamePlatform> platforms;
  final List<String> genres;
  final List<String> themes;
  final List<String> gameModes;
  final List<String> perspectives;
  final List<String> engines;

  /// The main developers and the publishers, not the supporting studios.
  final List<String> developers;
  final List<String> publishers;

  /// IGDB's company id of each of [developers] and [publishers] it gave one
  /// for, by name: what opens the company's page.
  final Map<String, int> companyIds;
  final String? storyline;

  /// Games IGDB considers alike, as catalog games (none of the user's state).
  final List<Game> similarGames;
  final TimeToBeat? timeToBeat;

  /// Whether there is any attribute to list in the game info panel.
  bool get hasInfo =>
      developers.isNotEmpty ||
      publishers.isNotEmpty ||
      themes.isNotEmpty ||
      gameModes.isNotEmpty ||
      perspectives.isNotEmpty ||
      engines.isNotEmpty;
}

/// What one `backfill` request of `igdb-handler` came back with: the games whose
/// catalog rows the server filled in (or found filled in), or why there are none.
@immutable
class CatalogBackfillResult {
  const CatalogBackfillResult(this.games) : failed = false, retryAfter = null;

  /// The request failed. [retryAfter] is set when waiting fixes it (IGDB is
  /// limiting requests or down): how long to wait before the next request.
  const CatalogBackfillResult.failed({this.retryAfter})
    : games = const [],
      failed = true;

  /// Each game with what its catalog row holds now: exact platforms and genres
  /// (the rest of [GameDetails] is left empty). A game the server could not fill
  /// in this time is not here, and is asked about again later.
  final List<GameDetails> games;
  final bool failed;
  final Duration? retryAfter;
}
