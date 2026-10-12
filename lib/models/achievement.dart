import 'package:flutter/foundation.dart';

/// One Steam achievement for a game, merged with the player's unlock state.
///
/// Stored as a JSON object inside `user_games.achievements`:
/// `{name, description, icon_url, unlocked, unlocked_at}`.
@immutable
class Achievement {
  const Achievement({
    required this.name,
    required this.description,
    required this.iconUrl,
    required this.unlocked,
    this.unlockedAt,
  });

  final String name;
  final String description;
  final String iconUrl;
  final bool unlocked;
  final DateTime? unlockedAt;

  factory Achievement.fromJson(Map<String, dynamic> json) {
    final unlockedAtRaw = json['unlocked_at'];
    return Achievement(
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      iconUrl: json['icon_url']?.toString() ?? '',
      unlocked: json['unlocked'] == true,
      unlockedAt: unlockedAtRaw == null
          ? null
          : DateTime.tryParse('$unlockedAtRaw')?.toLocal(),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'icon_url': iconUrl,
        'unlocked': unlocked,
        'unlocked_at': unlockedAt?.toUtc().toIso8601String(),
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