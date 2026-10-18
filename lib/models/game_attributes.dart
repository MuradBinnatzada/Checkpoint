import 'package:flutter/material.dart';

import 'package:checkpoint/models/game_details.dart';

/// A thing about a game the Library can be narrowed by, besides its platform. A
/// game can have several values of each (two genres, three themes...); picking
/// values of one attribute shows the games that have any of them.
///
/// [genre] is read from `Game.genres`, which the library always holds. The others
/// come from IGDB through [GameAttributes], which the server only has for a game
/// once it was filled in from IGDB (see `igdb_synced_at` on `games`).
enum GameAttribute {
  genre('Genre', 'Genres', Icons.category_rounded),
  theme('Theme', 'Themes', Icons.palette_rounded),
  gameMode('Game mode', 'Game modes', Icons.groups_rounded),
  perspective('Perspective', 'Perspectives', Icons.visibility_rounded),
  engine('Engine', 'Engines', Icons.memory_rounded),
  developer('Developer', 'Developers', Icons.code_rounded),
  publisher('Publisher', 'Publishers', Icons.storefront_rounded);

  const GameAttribute(this.label, this.pluralLabel, this.icon);

  /// "Theme": names one value ("Theme: Horror").
  final String label;

  /// "Themes": names the list of values.
  final String pluralLabel;
  final IconData icon;

  /// Whether [GameAttributes] holds it. Only [genre] is on the [Game] itself.
  bool get isFromIgdb => this != genre;

  /// How many values the filter sheet lists before it folds the rest away: the
  /// company lists run to hundreds in a big library.
  int get collapsedCount => switch (this) {
    developer || publisher => 8,
    _ => 12,
  };
}

/// What IGDB says about a game that the Library can be filtered by, as the shared
/// catalog row keeps it: the lists the details screen shows under "Game info".
/// Each is empty when IGDB has no value for it.
@immutable
class GameAttributes {
  const GameAttributes({
    this.themes = const [],
    this.gameModes = const [],
    this.perspectives = const [],
    this.engines = const [],
    this.developers = const [],
    this.publishers = const [],
  });

  final List<String> themes;
  final List<String> gameModes;
  final List<String> perspectives;
  final List<String> engines;
  final List<String> developers;
  final List<String> publishers;

  factory GameAttributes.fromDetails(GameDetails details) => GameAttributes(
    themes: details.themes,
    gameModes: details.gameModes,
    perspectives: details.perspectives,
    engines: details.engines,
    developers: details.developers,
    publishers: details.publishers,
  );

  /// The values of [attribute]; none for [GameAttribute.genre], which is not
  /// kept here.
  List<String> valuesOf(GameAttribute attribute) => switch (attribute) {
    GameAttribute.genre => const [],
    GameAttribute.theme => themes,
    GameAttribute.gameMode => gameModes,
    GameAttribute.perspective => perspectives,
    GameAttribute.engine => engines,
    GameAttribute.developer => developers,
    GameAttribute.publisher => publishers,
  };
}

/// One value a filter can pick, and how many games of the library have it.
@immutable
class FilterOption {
  const FilterOption(this.value, this.count);

  final String value;
  final int count;
}
