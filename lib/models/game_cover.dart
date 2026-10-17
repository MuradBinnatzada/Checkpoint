import 'package:flutter/material.dart';

import 'package:checkpoint/models/game.dart';

/// Placeholder cover gradient for a game without artwork, derived from its id and
/// title so the same game always gets the same colours.
List<Color> coverColorsFor(String id, String title) {
  final hash = '$id$title'.codeUnits.fold<int>(
    17,
    (value, code) => (value * 31 + code) & 0x7fffffff,
  );
  final hue = (hash % 360).toDouble();
  return [
    HSLColor.fromAHSL(1, hue, 0.62, 0.46).toColor(),
    HSLColor.fromAHSL(1, (hue + 42) % 360, 0.52, 0.16).toColor(),
  ];
}

/// Placeholder cover icon for a game without artwork, picked from its genres and
/// platforms.
IconData coverIconFor(List<String> genres, List<GamePlatform> platforms) {
  final hay = genres.join(' ').toLowerCase();
  if (hay.contains('rpg')) return Icons.auto_awesome_rounded;
  if (hay.contains('strategy') || hay.contains('tactic')) {
    return Icons.extension_rounded;
  }
  if (hay.contains('platform')) return Icons.bolt_rounded;
  if (hay.contains('racing')) return Icons.sports_motorsports_rounded;
  if (hay.contains('horror')) return Icons.nights_stay_rounded;
  if (platforms.contains(GamePlatform.mobile)) return Icons.smartphone_rounded;
  return Icons.sports_esports_rounded;
}
