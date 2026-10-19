import 'dart:math' as math;

import 'package:checkpoint/models/game.dart';

/// "What should I play next?": picks one game at random from the member's
/// library, out of the statuses and the platform asked for. [next] goes through
/// every candidate once, in a shuffled order, before any comes up again, so
/// "pick another" never lands on the same game twice in a row.
class NextGamePicker {
  NextGamePicker({
    required List<Game> library,
    this.statuses = defaultStatuses,
    this.platform,
    math.Random? random,
  }) : _random = random ?? math.Random(),
       candidates = List.unmodifiable([
         for (final g in library)
           if (statuses.contains(g.status) && _playableOn(g, platform)) g,
       ]);

  /// The backlog: games owned and not started, and the ones under way.
  static const defaultStatuses = {GameStatus.toPlay, GameStatus.playing};

  /// The statuses the member can pick from.
  static const choosable = [GameStatus.toPlay, GameStatus.playing, GameStatus.wishlist, GameStatus.dropped];

  final Set<GameStatus> statuses;

  /// Only games played on, or released for, this platform; null: any.
  final GamePlatform? platform;

  final math.Random _random;

  /// The games a pick comes from, in library order.
  final List<Game> candidates;

  final List<Game> _bag = [];
  Game? _last;

  /// The next pick, or null when there is nothing to pick from.
  Game? next() {
    if (candidates.isEmpty) return null;
    if (_bag.isEmpty) {
      _bag.addAll(candidates);
      _bag.shuffle(_random);
      // A new round never starts with the game the last one ended on.
      if (_bag.length > 1 && identical(_bag.last, _last)) {
        _bag.insert(0, _bag.removeLast());
      }
    }
    return _last = _bag.removeLast();
  }

  /// The platforms the library's games of [statuses] are played on or released
  /// for, in [GamePlatform] order: what the platform filter offers.
  static List<GamePlatform> platformsOf(List<Game> library, Set<GameStatus> statuses) {
    final found = <GamePlatform>{
      for (final g in library)
        if (statuses.contains(g.status)) ...[?g.playedOn, ...g.platforms],
    };
    return found.toList()..sort((a, b) => a.index.compareTo(b.index));
  }

  static bool _playableOn(Game g, GamePlatform? platform) =>
      platform == null || g.playedOn == platform || g.platforms.contains(platform);
}
