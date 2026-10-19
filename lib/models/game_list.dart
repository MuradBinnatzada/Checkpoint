import 'package:flutter/foundation.dart';

import 'package:checkpoint/models/game.dart';

/// A member's named list of games, in the order they put them in
/// (`game_lists` and `game_list_items`). The games are as the catalog knows
/// them: none of the owner's library state is on them.
@immutable
class GameList {
  const GameList({
    required this.id,
    required this.ownerId,
    required this.title,
    this.description = '',
    this.isPublic = false,
    this.games = const [],
    this.updatedAt,
  });

  /// What the database accepts (20261019115300_game_lists.sql).
  static const titleMax = 80;
  static const descriptionMax = 500;
  static const maxLists = 100;
  static const maxGames = 500;

  final String id;
  final String ownerId;
  final String title;
  final String description;

  /// Whether every signed-in member can open it (from the owner's profile or a
  /// link); a private list is the owner's only.
  final bool isPublic;

  /// In the list's order.
  final List<Game> games;
  final DateTime? updatedAt;

  bool contains(String gameId) => games.any((g) => g.id == gameId);

  GameList copyWith({
    String? title,
    String? description,
    bool? isPublic,
    List<Game>? games,
    DateTime? updatedAt,
  }) => GameList(
    id: id,
    ownerId: ownerId,
    title: title ?? this.title,
    description: description ?? this.description,
    isPublic: isPublic ?? this.isPublic,
    games: games ?? this.games,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
