import 'package:flutter/foundation.dart';

import 'package:checkpoint/l10n/l10n.dart';

/// Steam's text of an achievement in one language.
typedef AchievementText = ({String name, String description});

/// One Steam achievement for a game, merged with the player's unlock state.
///
/// Stored as a JSON object inside `user_games.achievements`:
/// `{api_name, name, description, icon_url, unlocked, unlocked_at,
/// global_percent, translations}`, the name and description in English and
/// Steam's own translations by language (`sync-achievements` adds the app's
/// language). Lists fetched before `global_percent`, `api_name` or
/// `translations` existed don't have them.
@immutable
class Achievement {
  const Achievement({
    required this._name,
    required this._description,
    required this.iconUrl,
    required this.unlocked,
    this.unlockedAt,
    this.globalPercent,
    this.apiName,
    this.translations = const {},
  });

  final String _name;
  final String _description;

  /// Steam's name, in English, as every member's list stores it.
  String get englishName => _name;
  String get englishDescription => _description;

  /// Steam's API name: what its translations are joined on.
  final String? apiName;

  /// Steam's name and description by language code ("ru").
  final Map<String, AchievementText> translations;

  AchievementText? get _translation => translations[L10n.languageCode];

  /// The name in the app's language when Steam has it, else in English.
  String get name => _translation?.name ?? englishName;

  /// The description in the app's language when Steam has it, else in English.
  /// A hidden achievement Steam gives no text for is said to be hidden.
  String get description {
    final translated = _translation?.description ?? '';
    if (translated.isNotEmpty) return translated;
    return englishDescription == _hiddenEnglish ? L10n.current.hiddenAchievement : englishDescription;
  }

  /// What `sync-achievements` says for a hidden achievement with no description.
  static const _hiddenEnglish = 'Hidden achievement';

  final String iconUrl;
  final bool unlocked;
  final DateTime? unlockedAt;

  /// The share of all Steam players who have it, 0 to 100; null when unknown.
  final double? globalPercent;

  factory Achievement.fromJson(Map<String, dynamic> json) {
    final unlockedAtRaw = json['unlocked_at'];
    final percent = json['global_percent'];
    final apiName = json['api_name'];
    final rawTranslations = json['translations'];
    return Achievement(
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      apiName: apiName is String && apiName.isNotEmpty ? apiName : null,
      translations: {
        if (rawTranslations is Map)
          for (final MapEntry(:key, :value) in rawTranslations.entries)
            if (value is Map && value['name'] is String && (value['name'] as String).isNotEmpty)
              '$key': (name: value['name'] as String, description: value['description']?.toString() ?? ''),
      },
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
        'api_name': ?apiName,
        'name': englishName,
        'description': englishDescription,
        if (translations.isNotEmpty)
          'translations': {
            for (final MapEntry(:key, :value) in translations.entries)
              key: {'name': value.name, 'description': value.description},
          },
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
