import 'package:flutter/foundation.dart';

import 'package:checkpoint/models/game.dart';

/// One play session on someone's profile: which game, for how long, on what and
/// when. The note the player wrote is not part of it.
@immutable
class ActivityEntry {
  const ActivityEntry({
    required this.game,
    required this.hours,
    required this.platform,
    required this.at,
  });

  /// The game as the catalog knows it, with no tracking state of the player's.
  final Game game;
  final double hours;
  final GamePlatform platform;
  final DateTime at;
}
