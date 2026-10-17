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

/// A member's achievements added up over every game that has any stored: what
/// `public_achievement_totals` returns. Small enough to load with a profile, so
/// the count shows without a tap; the games behind it are fetched on request.
@immutable
class AchievementTotals {
  const AchievementTotals({
    this.unlocked = 0,
    this.total = 0,
    this.games = 0,
    this.completedGames = 0,
  });

  final int unlocked;
  final int total;

  /// Games with achievements stored.
  final int games;

  /// Of those, the ones with every achievement unlocked.
  final int completedGames;

  bool get isEmpty => total == 0;

  /// Every achievement of every game is unlocked.
  bool get allUnlocked => total > 0 && unlocked == total;

  /// 0 to 1.
  double get progress => total == 0 ? 0 : unlocked / total;
}
