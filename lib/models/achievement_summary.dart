import 'package:flutter/foundation.dart';

/// One game's achievement progress for a member: what
/// `public_achievement_summary` returns. The achievements themselves are fetched
/// per game, on request (see `fetchPublicGameAchievements`).
@immutable
class GameAchievementSummary {
  const GameAchievementSummary({
    required this.gameId,
    required this.title,
    required this.unlocked,
    required this.total,
    this.coverUrl,
  });

  final String gameId;
  final String title;
  final String? coverUrl;
  final int unlocked;
  final int total;

  /// 0 to 1.
  double get progress => total == 0 ? 0 : unlocked / total;
}
