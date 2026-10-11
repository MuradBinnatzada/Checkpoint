import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:checkpoint/data/db_schema.dart';
import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/log_entry.dart';
import 'package:checkpoint/models/social_user.dart';
import 'package:checkpoint/models/user_profile.dart';

class CheckpointRepository {
  CheckpointRepository(this._client);

  final SupabaseClient _client;

  Future<UserProfile> ensureProfile(User user) async {
    final existing = await _client
        .from(Db.profiles)
        .select()
        .eq(Db.id, user.id)
        .maybeSingle();
    if (existing != null) return _profileFromRow(existing, fallbackUser: user);

    final metadata = user.userMetadata ?? const <String, dynamic>{};
    final emailName = _emailLocalPart(user.email);
    final displayName =
        _firstText([
          metadata['full_name'],
          metadata['name'],
          metadata['display_name'],
          emailName,
        ]) ??
        'Player';

    await _client.from(Db.profiles).upsert({
      Db.id: user.id,
      Db.email: user.email,
      Db.displayName: displayName,
      Db.handle: _handleFrom(displayName, user.id),
      Db.bio: '',
      Db.avatarUrl: _firstText([metadata['avatar_url'], metadata['picture']]),
      Db.weeklyGoalHours: 20,
    });

    final inserted = await _client
        .from(Db.profiles)
        .select()
        .eq(Db.id, user.id)
        .single();
    return _profileFromRow(inserted, fallbackUser: user);
  }

  Future<UserProfile> fetchProfile(User user) async {
    final row = await _client
        .from(Db.profiles)
        .select()
        .eq(Db.id, user.id)
        .single();
    return _profileFromRow(row, fallbackUser: user);
  }

  Future<void> updateWeeklyGoal(String userId, double hours) async {
    await _client
        .from(Db.profiles)
        .update({Db.weeklyGoalHours: hours})
        .eq(Db.id, userId);
  }

  Future<List<Game>> fetchCatalogGames() async {
    final rows = await _client.from(Db.games).select().order(Db.title);
    return rows.map<Game>(_gameFromCatalogRow).toList(growable: false);
  }

  Future<List<Game>> fetchUserGames(String userId) async {
    final rows = await _client
        .from(Db.userGames)
        .select('''
          ${Db.id},
          ${Db.userId},
          ${Db.gameId},
          ${Db.status},
          ${Db.rating},
          ${Db.hoursPlayed},
          ${Db.targetHours},
          ${Db.playedOn},
          ${Db.purchasePrice},
          ${Db.dateAdded},
          ${Db.isFavorite},
          ${Db.games}!inner (
            ${Db.id},
            ${Db.igdbId},
            ${Db.slug},
            ${Db.title},
            ${Db.publisher},
            ${Db.developer},
            ${Db.releaseYear},
            ${Db.platforms},
            ${Db.genres},
            ${Db.summary},
            ${Db.coverUrl},
            ${Db.createdAt}
          )
        ''')
        .eq(Db.userId, userId)
        .order(Db.dateAdded, ascending: false);

    return rows.map<Game>(_gameFromUserGameRow).toList(growable: false);
  }

  Future<List<LogEntry>> fetchLogEntries(String userId) async {
    final rows = await _client
        .from(Db.logEntries)
        .select()
        .eq(Db.userId, userId)
        .order(Db.loggedAt, ascending: false);
    return rows.map<LogEntry>(_logFromRow).toList(growable: false);
  }

  Future<List<SocialUser>> fetchSocialUsers(String currentUserId) async {
    final rows = await _client
        .from(Db.profiles)
        .select()
        .neq(Db.id, currentUserId)
        .order(Db.displayName);
    return rows
        .map<SocialUser>((row) => _socialUserFromProfile(row))
        .toList(growable: false);
  }

  Future<Set<String>> fetchFollowingIds(String userId) async {
    final rows = await _client
        .from(Db.socialFollows)
        .select(Db.followeeId)
        .eq(Db.followerId, userId);
    return rows.map<String>((row) => '${row[Db.followeeId]}').toSet();
  }

  Future<int> fetchFollowersCount(String userId) async {
    final rows = await _client
        .from(Db.socialFollows)
        .select(Db.followerId)
        .eq(Db.followeeId, userId);
    return rows.length;
  }

  Future<void> follow({
    required String followerId,
    required String followeeId,
  }) async {
    await _client.from(Db.socialFollows).insert({
      Db.followerId: followerId,
      Db.followeeId: followeeId,
    });
  }

  Future<void> unfollow({
    required String followerId,
    required String followeeId,
  }) async {
    await _client
        .from(Db.socialFollows)
        .delete()
        .eq(Db.followerId, followerId)
        .eq(Db.followeeId, followeeId);
  }

  Future<void> upsertUserGame({
    required String userId,
    required String gameId,
    required GameStatus status,
    required double rating,
    required double hoursPlayed,
    required double targetHours,
    required GamePlatform? playedOn,
    required double purchasePrice,
    required bool isFavorite,
    DateTime? dateAdded,
  }) async {
    await _client.from(Db.userGames).upsert({
      Db.userId: userId,
      Db.gameId: gameId,
      Db.status: gameStatusToDb(status),
      Db.rating: rating,
      Db.hoursPlayed: hoursPlayed,
      Db.targetHours: targetHours,
      Db.playedOn: playedOn == null ? null : gamePlatformToDb(playedOn),
      Db.purchasePrice: purchasePrice,
      Db.dateAdded: (dateAdded ?? DateTime.now()).toUtc().toIso8601String(),
      Db.isFavorite: isFavorite,
    }, onConflict: '${Db.userId},${Db.gameId}');
  }

  Future<void> insertLogEntry({
    required String userId,
    required String gameId,
    required double hours,
    required GamePlatform platform,
    required String note,
  }) async {
    await _client.from(Db.logEntries).insert({
      Db.userId: userId,
      Db.gameId: gameId,
      Db.hours: hours,
      Db.platform: gamePlatformToDb(platform),
      Db.note: note.trim(),
    });
  }

  Future<void> upsertBaseGame(Game game) async {
    await _client.from(Db.games).upsert({
      Db.id: game.id,
      Db.title: game.title,
      Db.developer: game.developer,
      Db.publisher: game.publisher,
      Db.releaseYear: game.releaseYear,
      Db.genres: game.genres,
      Db.summary: game.synopsis,
      Db.coverUrl: game.coverUrl,
    });
  }

  Future<void> deleteUserGame(String userId, String gameId) async {
    // Delete logs first to satisfy foreign key constraints (if cascade isn't on)
    await _client.from(Db.logEntries).delete().eq(Db.userId, userId).eq(Db.gameId, gameId);
    // Delete the game from the user's library
    await _client.from(Db.userGames).delete().eq(Db.userId, userId).eq(Db.gameId, gameId);
  }

  Stream<List<Map<String, dynamic>>> watchCatalogGames() =>
      _client.from(Db.games).stream(primaryKey: [Db.id]).order(Db.title);

  Stream<List<Map<String, dynamic>>> watchUserGames(String userId) => _client
      .from(Db.userGames)
      .stream(primaryKey: [Db.id])
      .eq(Db.userId, userId);

  Stream<List<Map<String, dynamic>>> watchLogEntries(String userId) => _client
      .from(Db.logEntries)
      .stream(primaryKey: [Db.id])
      .eq(Db.userId, userId);

  Stream<List<Map<String, dynamic>>> watchProfile(String userId) =>
      _client.from(Db.profiles).stream(primaryKey: [Db.id]).eq(Db.id, userId);

  Stream<List<Map<String, dynamic>>> watchFollows(String userId) => _client
      .from(Db.socialFollows)
      .stream(primaryKey: [Db.followerId, Db.followeeId])
      .eq(Db.followerId, userId);
}

UserProfile _profileFromRow(Map<String, dynamic> row, {User? fallbackUser}) {
  final metadata = fallbackUser?.userMetadata ?? const <String, dynamic>{};
  final emailName = _emailLocalPart(fallbackUser?.email);
  final name =
      _firstText([
        row[Db.displayName],
        metadata['full_name'],
        metadata['name'],
        emailName,
      ]) ??
      'Player';

  return UserProfile(
    name: name,
    handle: _withAt(
      _firstText([row[Db.handle]]) ??
          _handleFrom(name, fallbackUser?.id ?? 'guest'),
    ),
    bio: _firstText([row[Db.bio]]) ?? '',
    joined: _date(row[Db.createdAt]) ?? DateTime.now(),
    weeklyGoalHours: _double(row[Db.weeklyGoalHours], fallback: 20),
    followers: 0,
    following: 0,
  );
}

SocialUser _socialUserFromProfile(Map<String, dynamic> row) {
  final name = _firstText([row[Db.displayName], row[Db.handle]]) ?? 'Player';
  return SocialUser(
    id: '${row[Db.id]}',
    name: name,
    handle: _withAt(
      _firstText([row[Db.handle]]) ?? _handleFrom(name, '${row[Db.id]}'),
    ),
    gamesLogged: 0,
    followers: 0,
  );
}

Game _gameFromCatalogRow(Map<String, dynamic> row) {
  final id = '${row[Db.id]}';
  final title = _firstText([row[Db.title]]) ?? 'Untitled Game';
  final platforms = _platforms(row[Db.platforms]);
  final genres = _strings(row[Db.genres]);
  return Game(
    id: id,
    title: title,
    publisher: _firstText([row[Db.publisher]]) ?? 'Unknown publisher',
    developer: _firstText([row[Db.developer]]) ?? 'Unknown developer',
    releaseYear: _int(row[Db.releaseYear]),
    platforms: platforms.isEmpty ? const [GamePlatform.pc] : platforms,
    genres: genres,
    synopsis: _firstText([row[Db.summary]]) ?? '',
    coverColors: _coverColors(id, title),
    coverIcon: _coverIcon(genres, platforms),
    coverUrl: _firstText([row[Db.coverUrl]]),
  );
}

  Game _gameFromUserGameRow(Map<String, dynamic> row) {
  final nested = row[Db.games];
  final gameRow = nested is Map<String, dynamic>
      ? nested
      : Map<String, dynamic>.from(nested as Map);
  final catalogGame = _gameFromCatalogRow(gameRow);
  assert(row.containsKey(Db.isFavorite));
  return catalogGame.copyWith(
    status: gameStatusFromDb(row[Db.status]),
    rating: _double(row[Db.rating]),
    hoursPlayed: _double(row[Db.hoursPlayed]),
    targetHours: _double(row[Db.targetHours]),
    playedOn: gamePlatformFromDb(row[Db.playedOn]),
    purchasePrice: _double(row[Db.purchasePrice]),
    dateAdded: _date(row[Db.dateAdded]),
    isFavorite: row[Db.isFavorite] == true,
  );
}

LogEntry _logFromRow(Map<String, dynamic> row) => LogEntry(
  id: '${row[Db.id]}',
  gameId: '${row[Db.gameId]}',
  timestamp: _date(row[Db.loggedAt]) ?? DateTime.now(),
  hours: _double(row[Db.hours]),
  platform: gamePlatformFromDb(row[Db.platform]) ?? GamePlatform.pc,
  note: _firstText([row[Db.note]]) ?? '',
);

List<String> _strings(Object? value) {
  if (value is List) {
    return value.map((v) => '$v').where((v) => v.trim().isNotEmpty).toList();
  }
  if (value is String && value.trim().isNotEmpty) return [value.trim()];
  return const [];
}

List<GamePlatform> _platforms(Object? value) =>
    _strings(value).map(gamePlatformFromDb).whereType<GamePlatform>().toList();

String? _firstText(List<Object?> values) {
  for (final value in values) {
    final text = value?.toString().trim();
    if (text != null && text.isNotEmpty) return text;
  }
  return null;
}

String? _emailLocalPart(String? email) {
  final text = email?.trim();
  if (text == null || text.isEmpty) return null;
  return text.split('@').first;
}

String _withAt(String handle) => handle.startsWith('@') ? handle : '@$handle';

String _handleFrom(String seed, String suffix) {
  final base = seed
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9_]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  final safeBase = base.length < 3 ? 'player' : base;
  final safeSuffix = suffix.replaceAll('-', '');
  return '${safeBase}_${safeSuffix.substring(0, math.min(6, safeSuffix.length))}'
      .substring(0, math.min(24, safeBase.length + 7));
}

DateTime? _date(Object? value) {
  if (value == null) return null;
  return DateTime.tryParse('$value')?.toLocal();
}

double _double(Object? value, {double fallback = 0}) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? fallback;
}

int _int(Object? value, {int fallback = 0}) {
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? fallback;
}

List<Color> _coverColors(String id, String title) {
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

IconData _coverIcon(List<String> genres, List<GamePlatform> platforms) {
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
