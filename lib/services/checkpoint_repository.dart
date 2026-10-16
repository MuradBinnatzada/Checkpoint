import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:checkpoint/data/db_schema.dart';
import 'package:checkpoint/models/achievement.dart';
import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/log_entry.dart';
import 'package:checkpoint/models/social_user.dart';
import 'package:checkpoint/models/user_profile.dart';

/// `user_games.achievements` (added by 20261012120000_add_achievements_to_user_games.sql).
/// Only read through [CheckpointRepository.fetchGameAchievements]; the library
/// queries leave it out on purpose.
/// Move into `Db` in data/db_schema.dart if you'd rather keep column names there.
const _achievementsColumn = 'achievements';

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

  static const _avatarBucket = 'avatars';

  static const _avatarMimeTypes = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'gif': 'image/gif',
  };

  String _requireUserId() {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw StateError('Not signed in.');
    return id;
  }

  /// Whether [handle] is free to use. The `handle` column is citext, so the
  /// match is case-insensitive; the lookup also lowercases for clarity.
  /// [currentUserId]'s own row is excluded, so keeping your current handle
  /// counts as available.
  ///
  /// Reads `public_profiles`, not `profiles`: the table only exposes the
  /// caller's own row, so it can't see whether someone else holds a handle.
  Future<bool> isHandleAvailable(String handle, String currentUserId) async {
    final normalized = handle
        .trim()
        .replaceFirst(RegExp(r'^@+'), '')
        .toLowerCase();
    if (normalized.isEmpty) return false;

    final rows = await _client
        .from(Db.publicProfiles)
        .select(Db.id)
        .eq(Db.handle, normalized)
        .neq(Db.id, currentUserId)
        .limit(1);
    return rows.isEmpty;
  }

  /// Saves the signed-in user's display name, handle, bio and avatar.
  ///
  /// [handle] is stored lowercase and without the leading "@" (the app adds
  /// it back when reading the profile). [bio] and [avatarUrl] are only written
  /// when non-null, so passing null leaves the stored value untouched; pass an
  /// empty [bio] to clear it.
  Future<void> updateProfile({
    required String name,
    required String handle,
    String? bio,
    String? avatarUrl,
  }) async {
    final userId = _requireUserId();
    await _client
        .from(Db.profiles)
        .update({
          Db.displayName: name.trim(),
          Db.handle: handle.trim().replaceFirst(RegExp(r'^@+'), '').toLowerCase(),
          if (bio != null) Db.bio: bio.trim(),
          Db.avatarUrl: ?avatarUrl,
        })
        .eq(Db.id, userId);
  }

  /// Saves the signed-in user's Steam ID64 on their own `profiles` row.
  /// The `sync-steam` Edge Function reads it back from there, keyed by the
  /// caller's verified user ID. Read it with [fetchProfile] / [ensureProfile]
  /// (it comes back as [UserProfile.steamId]).
  Future<void> setSteamId(String steamId) async {
    final userId = _requireUserId();
    await _client
        .from(Db.profiles)
        .update({Db.steamId: steamId.trim()})
        .eq(Db.id, userId);
  }

  /// Removes the signed-in user's Steam ID from their own `profiles` row.
  Future<void> clearSteamId() async {
    final userId = _requireUserId();
    await _client
        .from(Db.profiles)
        .update({Db.steamId: null})
        .eq(Db.id, userId);
  }

  /// Uploads [image] to the public `avatars` bucket and returns its public
  /// URL. Files go under `<userId>/` with a unique name per upload, so a new
  /// photo never collides with a cached copy of the old one.
  Future<String> uploadAvatar(XFile image) async {
    final userId = _requireUserId();
    final bytes = await image.readAsBytes();

    final name = image.name.isNotEmpty ? image.name : image.path;
    final dot = name.lastIndexOf('.');
    var ext = dot == -1 ? '' : name.substring(dot + 1).toLowerCase();
    if (!_avatarMimeTypes.containsKey(ext)) ext = 'jpg';

    final path = '$userId/${DateTime.now().millisecondsSinceEpoch}.$ext';
    final storage = _client.storage.from(_avatarBucket);
    await storage.uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(
        contentType: _avatarMimeTypes[ext],
        cacheControl: '3600',
        upsert: false,
      ),
    );
    return storage.getPublicUrl(path);
  }

  /// A small slice of the global catalog for the Home carousels: the newest
  /// [limit] rows of `games`. This replaces the old "download every game"
  /// fetch, so the payload stays the same size however big the catalog grows.
  /// Anything else (library games, search results) is loaded on demand.
  Future<List<Game>> fetchPopularGames({int limit = 20}) async {
    final rows = await _client
        .from(Db.games)
        .select()
        .order(Db.createdAt, ascending: false)
        .limit(limit);
    return rows.map<Game>(_gameFromCatalogRow).toList(growable: false);
  }

  /// The user's whole library. Columns are listed explicitly (rather than
  /// `select()`) so the heavy `achievements` JSONB column is never part of this
  /// payload; load it per game with [fetchGameAchievements] instead.
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

  /// Reads only the `achievements` column of one `user_games` row.
  ///
  /// Returns `null` when achievements were never loaded (the column is NULL, or
  /// the game isn't in the user's library), and an empty list when they were
  /// loaded but the game has none. See [Achievement.listFromJson].
  Future<List<Achievement>?> fetchGameAchievements(
    String userId,
    String gameId,
  ) async {
    final row = await _client
        .from(Db.userGames)
        .select(_achievementsColumn)
        .eq(Db.userId, userId)
        .eq(Db.gameId, gameId)
        .maybeSingle();
    return Achievement.listFromJson(row?[_achievementsColumn]);
  }

  Future<List<LogEntry>> fetchLogEntries(String userId) async {
    final rows = await _client
        .from(Db.logEntries)
        .select()
        .eq(Db.userId, userId)
        .order(Db.loggedAt, ascending: false);
    return rows.map<LogEntry>(_logFromRow).toList(growable: false);
  }

  /// Other members, for the Search tab. Reads the `public_profiles` view, which
  /// only has the public fields; `profiles` itself holds `email` / `steam_id`
  /// and is readable only for your own row. Keep the column list in sync with
  /// what [_socialUserFromProfile] reads and with the view.
  Future<List<SocialUser>> fetchSocialUsers(String currentUserId) async {
    final rows = await _client
        .from(Db.publicProfiles)
        .select('id, handle, display_name, avatar_url')
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

  /// Adds [game] to the global catalog if it isn't there yet.
  ///
  /// `ignoreDuplicates` makes this INSERT ... ON CONFLICT DO NOTHING, so a game
  /// that already exists (added earlier by another user, or by sync-steam) is
  /// left exactly as it is. That matters because the app no longer holds the
  /// whole catalog in memory to check first, and RLS only lets a user edit the
  /// catalog rows they created; a plain upsert on someone else's row would fail.
  Future<void> upsertBaseGame(Game game) async {
    await _client.from(Db.games).upsert({
      Db.id: game.id,
      Db.title: game.title,
      Db.developer: game.developer,
      Db.publisher: game.publisher,
      // games_release_year_check allows 1950-2100 or NULL; 0 ("unknown") becomes NULL.
      Db.releaseYear: sanitizeReleaseYear(game.releaseYear),
      Db.platforms: game.platforms.map(gamePlatformToDb).toList(),
      Db.genres: game.genres,
      Db.summary: game.synopsis,
      Db.coverUrl: game.coverUrl,
    }, onConflict: Db.id, ignoreDuplicates: true);
  }

  Future<void> deleteUserGame(String userId, String gameId) async {
    // Delete logs first to satisfy foreign key constraints (if cascade isn't on)
    await _client.from(Db.logEntries).delete().eq(Db.userId, userId).eq(Db.gameId, gameId);
    // Delete the game from the user's library
    await _client.from(Db.userGames).delete().eq(Db.userId, userId).eq(Db.gameId, gameId);
  }

  /// Emits an event whenever one of [userId]'s `user_games` rows changes.
  ///
  /// This deliberately isn't `.stream()`: that API has no column selection, so
  /// it would start with a `select *` of the whole library (achievements JSONB
  /// included). The store only uses this as a "refetch the library" trigger,
  /// so a plain change subscription with no initial snapshot is enough. Callers
  /// get the data from [fetchUserGames], which leaves `achievements` out.
  ///
  /// Like the stream it replaces, the user_id filter means DELETE events are
  /// not delivered (Realtime can't filter them); local deletes are applied
  /// optimistically by the store.
  Stream<void> watchUserGames(String userId) {
    late final StreamController<void> controller;
    RealtimeChannel? channel;
    controller = StreamController<void>(
      onListen: () {
        channel = _client
            .channel('user_games:$userId')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: Db.userGames,
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: Db.userId,
                value: userId,
              ),
              callback: (_) => controller.add(null),
            )
            .subscribe();
      },
      onCancel: () async {
        final c = channel;
        channel = null;
        if (c != null) await _client.removeChannel(c);
      },
    );
    return controller.stream;
  }

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
    avatarUrl: _firstText([row[Db.avatarUrl]]),
    steamId: _firstText([row[Db.steamId]]),
    joined: _date(row[Db.createdAt]) ?? DateTime.now(),
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
    playedOn: gamePlatformFromDb(row[Db.playedOn]),
    purchasePrice: _double(row[Db.purchasePrice]),
    dateAdded: _date(row[Db.dateAdded]),
    isFavorite: row[Db.isFavorite] == true,
    // `achievements` is intentionally not read here: fetchUserGames doesn't
    // select it. See fetchGameAchievements.
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