import 'package:flutter/foundation.dart';

/// One Steam achievement for a game, merged with the player's unlock state.
///
/// Stored as a JSON object inside `user_games.achievements`:
/// `{name, description, icon_url, unlocked, unlocked_at, global_percent}`.
/// Lists fetched before `global_percent` existed don't have it.
@immutable
class Achievement {
  const Achievement({
    required this.name,
    required this.description,
    required this.iconUrl,
    required this.unlocked,
    this.unlockedAt,
    this.globalPercent,
  });

  final String name;
  final String description;
  final String iconUrl;
  final bool unlocked;
  final DateTime? unlockedAt;

  /// The share of all Steam players who have it, 0 to 100; null when unknown.
  final double? globalPercent;

  factory Achievement.fromJson(Map<String, dynamic> json) {
    final unlockedAtRaw = json['unlocked_at'];
    final percent = json['global_percent'];
    return Achievement(
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      iconUrl: json['icon_url']?.toString() ?? '',
      unlocked: json['unlocked'] == true,
      unlockedAt: unlockedAtRaw == null
          ? null
          : DateTime.tryParse('$unlockedAtRaw')?.toLocal(),
      globalPercent: percent is num && percent.isFinite && percent >= 0
          ? percent.toDouble().clamp(0, 100).toDouble()
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'icon_url': iconUrl,
        'unlocked': unlocked,
        'unlocked_at': unlockedAt?.toUtc().toIso8601String(),
        'global_percent': globalPercent,
      };

  /// Parses the raw JSONB value of `user_games.achievements`.
  ///
  /// Returns `null` when the value is null or not a list, which means
  /// "never loaded". An empty list means "loaded, no achievements".
  static List<Achievement>? listFromJson(Object? value) {
    if (value is! List) return null;
    return List<Achievement>.unmodifiable([
      for (final item in value)
        if (item is Map) Achievement.fromJson(Map<String, dynamic>.from(item)),
    ]);
  }
}

/// Unlocked first (most recently unlocked on top), then locked in Steam's own
/// order. `List.sort` isn't stable, so the original index is the tie-break.
List<Achievement> sortAchievements(List<Achievement> source) {
  final indexed = [for (var i = 0; i < source.length; i++) (index: i, item: source[i])];
  indexed.sort((a, b) {
    final x = a.item, y = b.item;
    if (x.unlocked != y.unlocked) return x.unlocked ? -1 : 1;
    if (x.unlocked) {
      final xt = x.unlockedAt, yt = y.unlockedAt;
      if (xt != null && yt != null) {
        final byTime = yt.compareTo(xt);
        if (byTime != 0) return byTime;
      } else if (xt != null) {
        return -1;
      } else if (yt != null) {
        return 1;
      }
    }
    return a.index.compareTo(b.index);
  });
  return [for (final e in indexed) e.item];
}
