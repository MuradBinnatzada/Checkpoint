import 'package:flutter/material.dart';

import 'package:checkpoint/models/achievement.dart';

enum GameStatus {
  playing('Playing', Icons.play_circle_rounded, Color(0xFFBB86FC)),
  toPlay('To Play', Icons.inventory_2_rounded, Color(0xFF4FC3F7)),
  completed('Completed', Icons.verified_rounded, Color(0xFF7DDC9C)),
  dropped('Dropped', Icons.block_rounded, Color(0xFFCF6679)),
  wishlist('Wishlist', Icons.bookmark_rounded, Color(0xFFFFC857));

  const GameStatus(this.label, this.icon, this.color);
  final String label;
  final IconData icon;
  final Color color;
}

String gameStatusToDb(GameStatus status) => switch (status) {
      GameStatus.playing => 'playing',
      GameStatus.toPlay => 'to_play',
      GameStatus.completed => 'completed',
      GameStatus.dropped => 'dropped',
      GameStatus.wishlist => 'wishlist',
    };

GameStatus? gameStatusFromDb(Object? value) {
  final raw = value?.toString().trim();
  return switch (raw) {
    'playing' => GameStatus.playing,
    'to_play' || 'toPlay' || 'To Play' => GameStatus.toPlay,
    'completed' => GameStatus.completed,
    'dropped' => GameStatus.dropped,
    'wishlist' => GameStatus.wishlist,
    _ => null,
  };
}

enum GamePlatform {
  pc('PC', Icons.desktop_windows_rounded, Color(0xFF8AB4F8)),
  steamDeck('Steam Deck', Icons.videogame_asset_rounded, Color(0xFF66C0F4)),
  ps5('PS5', Icons.sports_esports_rounded, Color(0xFF5B8CFF)),
  ps4('PS4', Icons.sports_esports_outlined, Color(0xFF7BA4FF)),
  xbox('Xbox', Icons.videogame_asset_rounded, Color(0xFF6CC24A)),
  nswitch('Switch', Icons.videogame_asset_outlined, Color(0xFFFF6B6B)),
  nintendo('Nintendo', Icons.videogame_asset_rounded, Color(0xFFE60012)),
  mobile('Mobile', Icons.smartphone_rounded, Color(0xFFFFB74D)),
  vr('VR', Icons.headset_rounded, Color(0xFFB388FF)),
  retro('Retro', Icons.save_rounded, Color(0xFF4DB6AC));

  const GamePlatform(this.label, this.icon, this.color);
  final String label;
  final IconData icon;
  final Color color;
}

String gamePlatformToDb(GamePlatform platform) => platform.name;

GamePlatform? gamePlatformFromDb(Object? value) {
  final raw = value?.toString().trim();
  if (raw == null || raw.isEmpty) return null;
  final normalized = raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
  return switch (normalized) {
    'pc' => GamePlatform.pc,
    'steamdeck' => GamePlatform.steamDeck,
    'ps5' || 'playstation5' => GamePlatform.ps5,
    'ps4' || 'playstation4' => GamePlatform.ps4,
    'xbox' || 'xboxseries' || 'xboxone' => GamePlatform.xbox,
    'switch' || 'nswitch' || 'nintendoswitch' => GamePlatform.nswitch,
    'nintendo' => GamePlatform.nintendo,
    'mobile' || 'ios' || 'android' => GamePlatform.mobile,
    'vr' => GamePlatform.vr,
    'retro' => GamePlatform.retro,
    _ => null,
  };
}

/// Catalog metadata + the user's tracking state for that game.
/// `status == null` means "in the catalog, not in my library".
@immutable
class Game {
  const Game({
    required this.id,
    required this.title,
    required this.publisher,
    required this.developer,
    required this.releaseYear,
    required this.platforms,
    required this.genres,
    required this.synopsis,
    required this.coverColors,
    required this.coverIcon,
    this.coverUrl,
    this.status,
    this.rating = 0,
    this.hoursPlayed = 0,
    this.targetHours = 0,
    this.playedOn,
    this.purchasePrice = 0,
    this.dateAdded,
    this.isFavorite = false,
    this.achievements,
  });

  final String id;
  final String title;
  final String publisher;
  final String developer;
  final int releaseYear;
  final List<GamePlatform> platforms;
  final List<String> genres;
  final String synopsis;
  final List<Color> coverColors;
  final IconData coverIcon;
  final String? coverUrl;
  final bool isFavorite;

  // user state
  final GameStatus? status;
  final double rating; // 0 = unrated, 0.5 steps up to 5
  final double hoursPlayed;
  final double targetHours; // 0 = no target
  final GamePlatform? playedOn;
  final double purchasePrice; // 0 = unknown
  final DateTime? dateAdded;

  /// Steam achievements merged with the user's unlocks. `null` = never loaded;
  /// an empty list = loaded, but the game has none.
  final List<Achievement>? achievements;

  bool get inLibrary => status != null;
  double get progress =>
      targetHours <= 0 ? 0 : (hoursPlayed / targetHours).clamp(0.0, 1.0).toDouble();
  double? get costPerHour =>
      (purchasePrice <= 0 || hoursPlayed <= 0) ? null : purchasePrice / hoursPlayed;

  Game copyWith({
    GameStatus? status,
    double? rating,
    double? hoursPlayed,
    double? targetHours,
    GamePlatform? playedOn,
    double? purchasePrice,
    DateTime? dateAdded,
    String? coverUrl,
    bool? isFavorite,
    List<Achievement>? achievements,
  }) =>
      Game(
        id: id,
        title: title,
        publisher: publisher,
        developer: developer,
        releaseYear: releaseYear,
        platforms: platforms,
        genres: genres,
        synopsis: synopsis,
        coverColors: coverColors,
        coverIcon: coverIcon,
        coverUrl: coverUrl ?? this.coverUrl,
        status: status ?? this.status,
        rating: rating ?? this.rating,
        hoursPlayed: hoursPlayed ?? this.hoursPlayed,
        targetHours: targetHours ?? this.targetHours,
        playedOn: playedOn ?? this.playedOn,
        purchasePrice: purchasePrice ?? this.purchasePrice,
        dateAdded: dateAdded ?? this.dateAdded,
        isFavorite: isFavorite ?? this.isFavorite,
        achievements: achievements ?? this.achievements,
      );
}