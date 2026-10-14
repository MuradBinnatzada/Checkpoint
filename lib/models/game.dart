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
  playstation('PlayStation', Icons.sports_esports_rounded, Color(0xFF6E96FF)),
  xbox('Xbox', Icons.videogame_asset_rounded, Color(0xFF6CC24A)),
  nswitch('Switch', Icons.videogame_asset_outlined, Color(0xFFFF6B6B)),
  nintendo('Nintendo', Icons.videogame_asset_rounded, Color(0xFFE60012)),
  mobile('Mobile', Icons.smartphone_rounded, Color(0xFFFFB74D)),
  vr('VR', Icons.headset_rounded, Color(0xFFB388FF)),
  emulator('Emulator', Icons.memory_rounded, Color(0xFF4DB6AC));

  const GamePlatform(this.label, this.icon, this.color);
  final String label;
  final IconData icon;
  final Color color;

  /// Platforms offered in the "Played on" pickers. The generic Nintendo entry
  /// is left out because Switch covers it; it stays in the enum so existing
  /// data and the game's own platform badges still work.
  static final List<GamePlatform> selectable = [
    for (final p in values)
      if (p != GamePlatform.nintendo) p,
  ];
}

// Emulator is stored under its original name, 'retro', so saved rows keep
// satisfying any database constraint that predates the rename.
String gamePlatformToDb(GamePlatform platform) =>
    platform == GamePlatform.emulator ? 'retro' : platform.name;

GamePlatform? gamePlatformFromDb(Object? value) {
  final raw = value?.toString().trim();
  if (raw == null || raw.isEmpty) return null;
  final normalized = raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
  return switch (normalized) {
    'pc' => GamePlatform.pc,
    'steamdeck' => GamePlatform.steamDeck,
    'ps5' || 'playstation5' => GamePlatform.ps5,
    'ps4' || 'playstation4' => GamePlatform.ps4,
    // Generic PlayStation: legacy consoles (PS1/PS2/PS3/PSP/Vita) roll up here.
    'playstation' ||
    'ps1' ||
    'ps2' ||
    'ps3' ||
    'psp' ||
    'vita' ||
    'psvita' ||
    'playstation1' ||
    'playstation2' ||
    'playstation3' ||
    'playstationportable' ||
    'playstationvita' => GamePlatform.playstation,
    'xbox' || 'xboxseries' || 'xboxone' => GamePlatform.xbox,
    'switch' || 'nswitch' || 'nintendoswitch' => GamePlatform.nswitch,
    'nintendo' => GamePlatform.nintendo,
    'mobile' || 'ios' || 'android' => GamePlatform.mobile,
    'vr' => GamePlatform.vr,
    // 'retro' is how Emulator is stored (see gamePlatformToDb); accept both.
    'emulator' || 'retro' => GamePlatform.emulator,
    _ => null,
  };
}

/// `games.release_year` only accepts 1950-2100 or NULL (`games_release_year_check`).
/// Returns [year] when it fits, otherwise null. This covers the model's
/// `0 = unknown` placeholder as well as any out-of-range value.
int? sanitizeReleaseYear(int? year) =>
    (year == null || year < 1950 || year > 2100) ? null : year;

/// IGDB `first_release_date` (UNIX seconds, UTC) -> 4-digit year, or null when
/// the value is missing, malformed, or outside 1950-2100.
int? releaseYearFromUnixSeconds(Object? seconds) {
  if (seconds is! num || !seconds.isFinite) return null;
  final s = seconds.toInt();
  if (s.abs() > 8640000000000) return null; // beyond what DateTime can represent
  final year = DateTime.fromMillisecondsSinceEpoch(s * 1000, isUtc: true).year;
  return sanitizeReleaseYear(year);
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
  final GamePlatform? playedOn;
  final double purchasePrice; // 0 = unknown
  final DateTime? dateAdded;

  /// Steam achievements merged with the user's unlocks. `null` = never loaded;
  /// an empty list = loaded, but the game has none.
  final List<Achievement>? achievements;

  bool get inLibrary => status != null;
  double? get costPerHour =>
      (purchasePrice <= 0 || hoursPlayed <= 0) ? null : purchasePrice / hoursPlayed;

  Game copyWith({
    GameStatus? status,
    double? rating,
    double? hoursPlayed,
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
        playedOn: playedOn ?? this.playedOn,
        purchasePrice: purchasePrice ?? this.purchasePrice,
        dateAdded: dateAdded ?? this.dateAdded,
        isFavorite: isFavorite ?? this.isFavorite,
        achievements: achievements ?? this.achievements,
      );
}