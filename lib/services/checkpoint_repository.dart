import 'dart:async';
import 'dart:math' as math;

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:checkpoint/data/db_schema.dart';
import 'package:checkpoint/models/achievement.dart';
import 'package:checkpoint/models/achievement_summary.dart';
import 'package:checkpoint/models/activity_entry.dart';
import 'package:checkpoint/models/connected_service.dart';
import 'package:checkpoint/models/friend_activity.dart';
import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/game_attributes.dart';
import 'package:checkpoint/models/game_cover.dart';
import 'package:checkpoint/models/game_friends.dart';
import 'package:checkpoint/models/game_list.dart';
import 'package:checkpoint/models/library_stats.dart';
import 'package:checkpoint/models/log_entry.dart';
import 'package:checkpoint/models/public_profile.dart';
import 'package:checkpoint/models/results_page.dart';
import 'package:checkpoint/models/social_user.dart';
import 'package:checkpoint/models/user_profile.dart';

/// `user_games.achievements`, added by 20261016120000_unify_game_ids_on_igdb_id.sql.
/// (20261012120000_add_achievements_to_user_games.sql holds the steam_id migration
/// by mistake, so it never created this column.)
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
    final metadata = user.userMetadata ?? const <String, dynamic>{};
    // Google sends a name; an email sign-up sends the one typed in
    // (AuthService.signUpWithEmail), and Apple's is saved just after sign-in
    // (AuthService.signInWithApple). The name and handle are public, so they
    // are never made from the email address.
    final accountName = _firstText([
      metadata['full_name'],
      metadata['name'],
      metadata['display_name'],
    ]);
    if (existing != null) {
      // Apple's name can arrive after the row was made with the stand-in: a
      // row that still has it, untouched, takes the name.
      if (accountName != null &&
          existing[Db.displayName] == _defaultName &&
          existing[Db.handle] == _handleFrom(_defaultName, user.id)) {
        final renamed = await _client
            .from(Db.profiles)
            .update({
              Db.displayName: accountName,
              Db.handle: _handleFrom(accountName, user.id),
            })
            .eq(Db.id, user.id)
            .select()
            .single();
        return _profileFromRow(renamed, fallbackUser: user);
      }
      return _profileFromRow(existing, fallbackUser: user);
    }

    final displayName = accountName ?? _defaultName;

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

  /// The name of a profile whose account came without one.
  static const _defaultName = 'Player';

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

  /// Starts connecting the signed-in user's Steam account through the
  /// `steam-link` Edge Function, which answers the Steam sign-in page to open.
  /// When the user signs in there, the function saves the Steam ID Steam
  /// confirms on their `profiles` row (members can't write it themselves); read
  /// it back with [fetchProfile] as [UserProfile.steamId]. [returnTo] is where
  /// the browser goes when it is done, with `steam_link=ok` or an error code;
  /// null for nowhere. Throws [FunctionException] when the function answers with
  /// an error.
  Future<Uri> startSteamLink({Uri? returnTo}) async {
    final response = await _client.functions.invoke(
      'steam-link',
      body: {if (returnTo != null) 'return_to': returnTo.toString()},
    );
    final data = response.data;
    final url = data is Map ? data['url'] : null;
    final page = url is String ? Uri.tryParse(url) : null;
    // Nothing but Steam's own page is ever opened as "Sign in through Steam".
    if (page == null || page.scheme != 'https' || page.host != 'steamcommunity.com') {
      throw const FormatException('steam-link did not answer a Steam sign-in page');
    }
    return page;
  }

  /// Removes the signed-in user's Steam ID from their own `profiles` row.
  Future<void> clearSteamId() async {
    final userId = _requireUserId();
    await _client
        .from(Db.profiles)
        .update({Db.steamId: null})
        .eq(Db.id, userId);
  }

  /// Saves whether other members may see the signed-in user's Steam achievements
  /// (`profiles.show_steam_achievements`). The achievement functions and
  /// `sync-achievements` read it on every request, so it holds from the next one.
  Future<void> setShowSteamAchievements(bool show) async {
    final userId = _requireUserId();
    await _client
        .from(Db.profiles)
        .update({Db.showSteamAchievements: show})
        .eq(Db.id, userId);
  }

  /// Saves which services the signed-in user has connected, and the account
  /// names behind PSN, Xbox, Discord, Instagram and Twitch, on their own
  /// `profiles` row. This is what
  /// other members see on the profile: the icons, and what tapping one opens.
  /// Replaces everything, so sending the same accounts twice is harmless, and a
  /// service that is not connected has its name cleared. Never Steam: it follows
  /// from the Steam ID. Read back with [fetchProfile] (as
  /// [UserProfile.connectedServices] and its account names).
  Future<void> setConnectedAccounts(ConnectedAccounts accounts) async {
    final userId = _requireUserId();
    String? name(ConnectedService s) {
      if (!accounts.services.contains(s)) return null;
      final text = accounts.nameOf(s)?.trim();
      if (text == null || text.isEmpty) return null;
      return text.length <= accountNameMaxLength
          ? text
          : text.substring(0, accountNameMaxLength);
    }

    await _client
        .from(Db.profiles)
        .update({
          Db.connectedServices: connectedServicesToDb(accounts.services),
          Db.psnId: name(ConnectedService.psn),
          Db.xboxId: name(ConnectedService.xbox),
          Db.discordId: name(ConnectedService.discord),
          Db.instagramId: name(ConnectedService.instagram),
          Db.twitchId: name(ConnectedService.twitch),
        })
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

  /// The catalog's game with [igdbId], or null when it has none: a game opened
  /// from a shared link. Anyone may read the catalog, signed in or not.
  Future<Game?> fetchCatalogGame(int igdbId) async {
    final row = await _client
        .from(Db.games)
        .select()
        .eq(Db.igdbId, igdbId)
        .maybeSingle();
    return row == null ? null : _gameFromCatalogRow(row);
  }

  /// Rows per request for the paged reads below ([_readAllPages]). It has to stay
  /// under the API's row cap (`max_rows` in supabase/config.toml and in the
  /// project's API settings, 1000 by default): a request for more is silently cut
  /// to the cap, and a library past it would load incomplete.
  static const int _pageSize = 500;

  /// Members per page of the Users tab.
  static const int _socialUsersPageSize = 30;

  /// Columns of a library row: its own fields and the catalog game it points at.
  /// Listed explicitly (rather than `select()`) so the heavy `achievements` JSONB
  /// column is never part of this payload; load it per game with
  /// [fetchGameAchievements] instead.
  static final String _userGameColumns = '''
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
          ${Db.customBackdropUrl},
          ${Db.completedAt},
          ${Db.review},
          ${Db.games}!inner (
            ${Db.id},
            ${Db.igdbId},
            ${Db.steamAppId},
            ${Db.slug},
            ${Db.title},
            ${Db.publisher},
            ${Db.developer},
            ${Db.releaseYear},
            ${Db.platforms},
            ${Db.genres},
            ${Db.summary},
            ${Db.coverUrl},
            ${Db.releaseDate},
            ${Db.createdAt}
          )
        ''';

  /// The user's whole library, read [_pageSize] rows at a time so that no single
  /// request is large or runs into the API's row cap. Pages are keyed on
  /// `game_id` (unique per user, and the lead of an existing index), not on an
  /// offset, so rows added or removed while it runs can't shift later pages and
  /// skip or repeat a game. The pages are joined and returned together: the
  /// library the store shows is never a partial one.
  Future<List<Game>> fetchUserGames(String userId) async {
    final rows = await _readAllPages(Db.gameId, (after) {
      final query = _client
          .from(Db.userGames)
          .select(_userGameColumns)
          .eq(Db.userId, userId);
      return (after == null ? query : query.gt(Db.gameId, after))
          // Ascending, because the next page asks for `game_id > cursor`.
          .order(Db.gameId, ascending: true)
          .limit(_pageSize);
    });
    // Newest first, the order the old single ordered query returned.
    return rows.map<Game>(_gameFromUserGameRow).toList()..sort(_newestFirst);
  }

  /// The IGDB ids of the games in [userId]'s library whose catalog row was never
  /// filled in from IGDB (`games.igdb_synced_at` is NULL), for the background
  /// backfill (`CatalogBackfill`). A separate read rather than a column of
  /// [fetchUserGames], so the library payload and the copy saved on the device
  /// don't grow by a timestamp per game: this one answers only the games still
  /// to do, which is nothing once a library is filled in. It also reads the
  /// server's state as it is now, so rows filled in meanwhile (by another member,
  /// or by opening a game's screen) drop out without the library being read again.
  /// Paged like [fetchUserGames]: a library just imported from Steam can be long.
  /// Also the wishlist and To Play games not out yet whose row is due again (see
  /// [_fetchDueUpcoming]), each id once.
  Future<List<int>> fetchUnsyncedIgdbIds(String userId) async {
    final (never, upcoming) = await (
      _readAllPages(Db.gameId, (after) {
        final query = _client
            .from(Db.userGames)
            .select('${Db.gameId}, ${Db.games}!inner(${Db.igdbId})')
            .eq(Db.userId, userId)
            .isFilter('${Db.games}.${Db.igdbSyncedAt}', null)
            .not('${Db.games}.${Db.igdbId}', 'is', null);
        return (after == null ? query : query.gt(Db.gameId, after))
            .order(Db.gameId, ascending: true)
            .limit(_pageSize);
      }),
      _fetchDueUpcoming(userId),
    ).wait;
    return {
      for (final row in [...never, ...upcoming])
        if (row[Db.games] case final Map<dynamic, dynamic> game)
          if (_intOrNull(game[Db.igdbId]) case final int igdbId
              when igdbId > 0)
            igdbId,
    }.toList();
  }

  /// Wishlist and To Play games that aren't out yet (or have no date), whose
  /// catalog row was filled in a week ago or more: IGDB moves release dates, and
  /// the wishlist release alerts read them. `igdb-handler` answers a row filled
  /// in less than a week ago as it is, so asking for these costs nothing until
  /// they are due.
  Future<List<Map<String, dynamic>>> _fetchDueUpcoming(String userId) {
    final weekAgo = DateTime.now().toUtc().subtract(const Duration(days: 7)).toIso8601String();
    final today = _day(DateTime.now());
    return _readAllPages(Db.gameId, (after) {
      final query = _client
          .from(Db.userGames)
          .select('${Db.gameId}, ${Db.games}!inner(${Db.igdbId})')
          .eq(Db.userId, userId)
          .inFilter(Db.status, [
            gameStatusToDb(GameStatus.wishlist),
            gameStatusToDb(GameStatus.toPlay),
          ])
          .lt('${Db.games}.${Db.igdbSyncedAt}', weekAgo)
          .not('${Db.games}.${Db.igdbId}', 'is', null)
          .or('${Db.releaseDate}.is.null,${Db.releaseDate}.gte.$today', referencedTable: Db.games);
      return (after == null ? query : query.gt(Db.gameId, after))
          .order(Db.gameId, ascending: true)
          .limit(_pageSize);
    });
  }

  /// What IGDB says about the user's library games that the library filters work
  /// on (themes, game modes, perspectives, engines, developers, publishers), by
  /// game id. Only the games whose catalog row was filled in from IGDB are here
  /// (`games.igdb_synced_at` is set); a game missing from the answer has no
  /// details yet, which is not the same as a game IGDB has no values for (that one
  /// is here, with empty lists).
  ///
  /// A read of its own, made when the filter sheet opens, and not part of
  /// [fetchUserGames]: the lists would add a few hundred bytes to every game of
  /// every library load and of the copy saved on the device, for something most
  /// visits to the Library never use. Paged like [fetchUserGames].
  Future<Map<String, GameAttributes>> fetchLibraryAttributes(
    String userId,
  ) async {
    final rows = await _readAllPages(Db.gameId, (after) {
      final query = _client
          .from(Db.userGames)
          .select('''
            ${Db.gameId},
            ${Db.games}!inner (
              ${Db.themes},
              ${Db.gameModes},
              ${Db.playerPerspectives},
              ${Db.gameEngines},
              ${Db.developers},
              ${Db.publishers}
            )
          ''')
          .eq(Db.userId, userId)
          .not('${Db.games}.${Db.igdbSyncedAt}', 'is', null);
      return (after == null ? query : query.gt(Db.gameId, after))
          .order(Db.gameId, ascending: true)
          .limit(_pageSize);
    });
    return {
      for (final row in rows)
        if (row[Db.games] case final Map<dynamic, dynamic> game)
          '${row[Db.gameId]}': _attributesFromRow(
            Map<String, dynamic>.from(game),
          ),
    };
  }

  static int _newestFirst(Game a, Game b) {
    final x = a.dateAdded;
    final y = b.dateAdded;
    if (x == null || y == null) {
      return x == null ? (y == null ? 0 : 1) : -1;
    }
    return y.compareTo(x);
  }

  /// Reads every row a query matches. [readPage] must return the page of up to
  /// [_pageSize] rows that follows the cursor `after` (null for the first page),
  /// ordered by [cursorColumn], a column whose values are unique within the query.
  /// Stops at the first page that comes back short.
  Future<List<Map<String, dynamic>>> _readAllPages(
    String cursorColumn,
    Future<List<Map<String, dynamic>>> Function(Object? after) readPage,
  ) async {
    final all = <Map<String, dynamic>>[];
    Object? after;
    while (true) {
      final rows = await readPage(after);
      all.addAll(rows);
      if (rows.length < _pageSize) return all;
      after = rows.last[cursorColumn];
      if (after == null) return all; // can't continue without a cursor
    }
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

  /// Imports the signed-in user's Steam library through the `sync-steam` Edge
  /// Function. There is no body: the function looks up this user's Steam ID on
  /// `profiles` using the authenticated session, and never trusts one sent by
  /// the client. Returns the function's response data.
  Future<Object?> syncSteamLibrary() async {
    final response = await _client.functions.invoke('sync-steam');
    return response.data;
  }

  /// Loads one game's Steam achievements through the `sync-achievements` Edge
  /// Function. Only the game goes in the body; the function reads the Steam ID
  /// from `profiles` and ignores any `steam_id` sent by the client. Throws
  /// [FunctionException] when the function answers with an error. Returns the
  /// function's response data.
  Future<Object?> syncGameAchievements(String gameId) async {
    final response = await _client.functions.invoke(
      'sync-achievements',
      body: {'game_id': gameId},
    );
    return response.data;
  }

  /// Every play session of the user, newest first. Read in pages like
  /// [fetchUserGames]: a long-time player passes the API's row cap.
  Future<List<LogEntry>> fetchLogEntries(String userId) async {
    final rows = await _readAllPages(Db.id, (after) {
      final query = _client
          .from(Db.logEntries)
          .select()
          .eq(Db.userId, userId);
      return (after == null ? query : query.gt(Db.id, after))
          .order(Db.id, ascending: true) // see fetchUserGames
          .limit(_pageSize);
    });
    return rows.map<LogEntry>(_logFromRow).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  /// One page of other members, for the Users tab: [limit] members starting at
  /// [offset], by display name. A non-empty [query] keeps those whose name or
  /// @handle contains it (case-insensitive). The search runs in the database, so
  /// the app never holds the whole member list.
  ///
  /// Reads the `public_profiles` view, which only has the public fields;
  /// `profiles` itself holds `email` / `steam_id` and is readable only for your
  /// own row. Keep the column list in sync with what [_socialUserFromProfile]
  /// reads and with the view.
  Future<ResultsPage<SocialUser>> searchSocialUsers(
    String currentUserId, {
    String query = '',
    int offset = 0,
    int limit = _socialUsersPageSize,
  }) async {
    var request = _client
        .from(Db.publicProfiles)
        .select(_memberWithCountsColumns)
        .neq(Db.id, currentUserId);
    final term = _likeTerm(query);
    if (term.isNotEmpty) {
      request = request.or(
        '${Db.displayName}.ilike.%$term%,${Db.handle}.ilike.%$term%',
      );
    }
    // `id` breaks ties between equal names, so a page boundary is stable.
    final rows = await request
        .order(Db.displayName, ascending: true)
        .order(Db.id, ascending: true)
        .range(offset, offset + limit - 1);
    final users = rows
        .map<SocialUser>((row) => _socialUserFromProfile(row))
        .toList(growable: false);
    // A full page means there may be another.
    return ResultsPage<SocialUser>(users, hasMore: users.length >= limit);
  }

  /// Makes [query] safe to put inside a PostgREST `or(...)` filter and an
  /// `ilike` pattern: a leading "@" is dropped, and the characters that would end
  /// the value or act as wildcards become spaces.
  static String _likeTerm(String query) => query
      .trim()
      .replaceFirst(RegExp(r'^@+'), '')
      .replaceAll(RegExp(r'[,()"\\%*]'), ' ')
      .trim();

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

  // ---- Other members: profile, games, follow lists, achievements ----
  //
  // Everything below reads views and functions made for the purpose, never the
  // `profiles` / `user_games` tables (own rows only). See
  // 20261017140000_public_profiles_and_social_graph.sql for what each exposes.

  /// Columns of a member row: `public_profiles`, `public_followers` and
  /// `public_following` all have them, under the same names.
  static const String _memberColumns = 'id, handle, display_name, avatar_url';

  /// [_memberColumns] plus the counts under each member in the Users tab; only
  /// `public_profiles` has them (20261018180000_member_list_counts.sql).
  static const String _memberWithCountsColumns =
      '$_memberColumns, ${Db.gamesCount}, ${Db.followersCount}, ${Db.viewerFollows}';

  /// Followers and following per request.
  static const int followListPageSize = 30;

  /// Favorites on a profile: the app lets a member pick four.
  static const int publicFavoritesLimit = 4;

  /// Recent sessions on a profile.
  static const int publicActivityLimit = 4;

  /// Everything `public_profiles` has: see 20261018120000_public_profile_details.sql.
  static final String _publicProfileColumns = [
    _memberColumns,
    Db.steamConnected,
    Db.connectedServices,
    Db.bio,
    Db.steamId,
    Db.psnId,
    Db.xboxId,
    Db.discordId,
    Db.instagramId,
    Db.twitchId,
    Db.joinedAt,
    Db.showSteamAchievements,
  ].join(', ');

  /// The header of [userId]'s profile, or null when no such member exists.
  Future<PublicProfile?> fetchPublicProfile(String userId) async {
    final row = await _client
        .from(Db.publicProfiles)
        .select(_publicProfileColumns)
        .eq(Db.id, userId)
        .maybeSingle();
    return row == null ? null : _publicProfileFromRow(row);
  }

  /// Follower, following and game counts of [userId], and whether the signed-in
  /// member follows them. One request. Throws when the server returns no row,
  /// which it does without a session.
  Future<PublicProfileStats> fetchPublicProfileStats(String userId) async {
    final data = await _client.rpc(
      Db.rpcProfileStats,
      params: {'target_user': userId},
    );
    final row = data is List ? data.firstOrNull : data;
    if (row is! Map) throw StateError('No profile stats for $userId.');
    return PublicProfileStats(
      followers: _int(row['followers']),
      following: _int(row['following']),
      viewerFollows: row['viewer_follows'] == true,
      games: _int(row['games']),
    );
  }

  /// The catalog columns of a game, as `games`, `public_user_games` and
  /// `public_recent_activity` all have them.
  static final List<String> _catalogColumns = [
    Db.igdbId,
    Db.steamAppId,
    Db.title,
    Db.publisher,
    Db.developer,
    Db.releaseYear,
    Db.platforms,
    Db.genres,
    Db.summary,
    Db.coverUrl,
  ];

  /// Columns of `public_user_games`. No purchase price, no achievements.
  static final String _publicGameColumns = [
    Db.gameId,
    Db.status,
    Db.rating,
    Db.hoursPlayed,
    Db.playedOn,
    Db.dateAdded,
    Db.isFavorite,
    Db.customBackdropUrl,
    Db.review,
    Db.completedAt,
    ..._catalogColumns,
  ].join(', ');

  /// What [LibraryStats] needs and nothing more, so a big library is a small read.
  static final String _statsColumns = [
    Db.gameId,
    Db.status,
    Db.rating,
    Db.hoursPlayed,
    Db.playedOn,
    Db.platforms,
  ].join(', ');

  /// Columns of `public_recent_activity`.
  static final String _activityColumns = [
    Db.gameId,
    Db.hours,
    Db.platform,
    Db.loggedAt,
    ..._catalogColumns,
  ].join(', ');

  PostgrestFilterBuilder<List<Map<String, dynamic>>> _publicGames(
    String userId, [
    String? columns,
  ]) => _client
      .from(Db.publicUserGames)
      .select(columns ?? _publicGameColumns)
      .eq(Db.userId, userId);

  /// [userId]'s favorite games, newest first, at most [publicFavoritesLimit].
  Future<List<Game>> fetchPublicFavorites(String userId) async {
    final rows = await _publicGames(userId)
        .eq(Db.isFavorite, true)
        .order(Db.dateAdded, ascending: false, nullsFirst: false)
        .order(Db.gameId, ascending: true)
        .limit(publicFavoritesLimit);
    return rows.map<Game>(_gameFromPublicRow).toList(growable: false);
  }

  /// Counts and sums over [userId]'s whole library (games per status, hours,
  /// ratings). Reads only the few columns they need, a page of 500 at a time, so
  /// even a big library is a small payload.
  Future<LibraryStats> fetchPublicLibraryStats(String userId) async {
    final rows = await _readAllPages(Db.gameId, (after) {
      final query = _publicGames(userId, _statsColumns);
      return (after == null ? query : query.gt(Db.gameId, after))
          .order(Db.gameId, ascending: true)
          .limit(_pageSize);
    });
    return LibraryStats.of(rows.map<Game>(_gameFromPublicRow));
  }

  /// [userId]'s whole library, newest first, for their Library screen. Read like
  /// [fetchUserGames]: a page of 500 at a time, keyed on `game_id`.
  Future<List<Game>> fetchPublicLibrary(String userId) async {
    final rows = await _readAllPages(Db.gameId, (after) {
      final query = _publicGames(userId);
      return (after == null ? query : query.gt(Db.gameId, after))
          .order(Db.gameId, ascending: true)
          .limit(_pageSize);
    });
    return rows.map<Game>(_gameFromPublicRow).toList()..sort(_newestFirst);
  }

  /// [userId]'s latest play sessions, newest first, one per game (the latest of
  /// each), at most [limit]. The notes they wrote are not readable.
  Future<List<ActivityEntry>> fetchPublicActivity(
    String userId, {
    int limit = publicActivityLimit,
  }) async {
    // Several sessions of one game count once, so ask for more rows than [limit].
    final rows = await _client
        .from(Db.publicRecentActivity)
        .select(_activityColumns)
        .eq(Db.userId, userId)
        .order(Db.loggedAt, ascending: false)
        .order(Db.id, ascending: true)
        .limit(limit * 10);
    final seen = <String>{};
    final entries = <ActivityEntry>[];
    for (final row in rows) {
      if (!seen.add('${row[Db.gameId]}')) continue;
      entries.add(_activityFromRow(row));
      if (entries.length >= limit) break;
    }
    return entries;
  }

  /// The members who follow [userId], newest follow first. A full page means
  /// there may be another.
  Future<ResultsPage<SocialUser>> fetchFollowers(
    String userId, {
    int offset = 0,
    int limit = followListPageSize,
  }) => _fetchFollowList(Db.publicFollowers, userId, offset, limit);

  /// The members [userId] follows, newest follow first.
  Future<ResultsPage<SocialUser>> fetchFollowing(
    String userId, {
    int offset = 0,
    int limit = followListPageSize,
  }) => _fetchFollowList(Db.publicFollowing, userId, offset, limit);

  Future<ResultsPage<SocialUser>> _fetchFollowList(
    String view,
    String userId,
    int offset,
    int limit,
  ) async {
    final rows = await _client
        .from(view)
        .select(_memberColumns)
        .eq(Db.userId, userId)
        .order(Db.followedAt, ascending: false)
        // `id` breaks ties between follows made at the same moment.
        .order(Db.id, ascending: true)
        .range(offset, offset + limit - 1);
    final users = rows
        .map<SocialUser>(_socialUserFromProfile)
        .toList(growable: false);
    return ResultsPage<SocialUser>(users, hasMore: users.length >= limit);
  }

  /// Members per status the Friends panel of a game's screen is sent; the
  /// counts cover all of them.
  static const int friendsPerStatus = 20;

  /// The members the signed-in one follows who have [gameId] in their library,
  /// with their status and rating: [friendsPerStatus] at most per status (rated
  /// first, then the most recently added) and how many there are in all. One
  /// request. Empty without a session.
  Future<GameFriends> fetchFriendsWithGame(String gameId) async {
    final data = await _client.rpc(
      Db.rpcFollowingGameActivity,
      params: {'target_game': gameId, 'per_status': friendsPerStatus},
    );
    if (data is! List) return const GameFriends();
    final friends = <FriendWithGame>[];
    final totals = <GameStatus, int>{};
    for (final raw in data) {
      if (raw is! Map) continue;
      final row = Map<String, dynamic>.from(raw);
      final status = gameStatusFromDb(row[Db.status]);
      if (status == null) continue;
      totals[status] = _int(row['status_total']);
      friends.add(
        FriendWithGame(
          member: _socialUserFromProfile(row),
          status: status,
          rating: _double(row[Db.rating]),
          dateAdded: _date(row[Db.dateAdded]),
          review: _firstText([row[Db.review]]) ?? '',
        ),
      );
    }
    return GameFriends(
      friends: List.unmodifiable(friends),
      totals: Map.unmodifiable(totals),
    );
  }

  /// Items of "From people you follow" on Home. The server caps it at 100.
  static const int friendsFeedLimit = 30;

  /// What the members the signed-in one follows did lately, newest first: the
  /// sessions they logged (the latest of each game), the games they completed and
  /// the ratings they gave, at most [limit] in all. One request. Empty without a
  /// session.
  Future<List<FriendActivity>> fetchFollowingActivity({
    int limit = friendsFeedLimit,
  }) async {
    final data = await _client.rpc(
      Db.rpcFollowingRecentActivity,
      params: {'max_rows': limit},
    );
    if (data is! List) return const [];
    final items = <FriendActivity>[];
    for (final raw in data) {
      if (raw is! Map) continue;
      final row = Map<String, dynamic>.from(raw);
      final kind = switch (row['kind']) {
        'session' => FriendActivityKind.session,
        'completed' => FriendActivityKind.completed,
        'rated' => FriendActivityKind.rated,
        _ => null,
      };
      final at = _date(row['occurred_at']);
      if (kind == null || at == null) continue;
      items.add(
        FriendActivity(
          member: _socialUserFromProfile({...row, Db.id: row[Db.userId]}),
          game: _gameFromCatalogRow({...row, Db.id: row[Db.gameId]}),
          kind: kind,
          at: at,
          hours: _double(row[Db.hours]),
          rating: _double(row[Db.rating]),
        ),
      );
    }
    return List.unmodifiable(items);
  }

  /// [userId]'s achievements added up: unlocked, total, games with any and games
  /// finished. Counted in the database and one small row, so it is fine to load
  /// with a profile. Empty (all zeros) when they have none.
  Future<AchievementTotals> fetchAchievementTotals(String userId) async {
    final data = await _client.rpc(
      Db.rpcAchievementTotals,
      params: {'target_user': userId},
    );
    final row = data is List ? (data.isEmpty ? null : data.first) : data;
    if (row is! Map) return const AchievementTotals();
    return AchievementTotals(
      unlocked: _int(row['unlocked']),
      total: _int(row['total']),
      games: _int(row['games']),
      completedGames: _int(row['completed_games']),
    );
  }

  /// Which of [userId]'s games have achievements, and how far they got in each.
  /// Counted in the database: no achievement rows are sent. Empty when they have
  /// none. Call it only when a viewer asks to see them.
  Future<List<GameAchievementSummary>> fetchAchievementSummary(
    String userId,
  ) async {
    final data = await _client.rpc(
      Db.rpcAchievementSummary,
      params: {'target_user': userId},
    );
    if (data is! List) return const [];
    return [
      for (final row in data)
        if (row is Map) _achievementSummaryFromRow(Map<String, dynamic>.from(row)),
    ];
  }

  /// [userId]'s achievements for one game, or null when they have none stored
  /// for it. Same meaning as [fetchGameAchievements], for another member.
  Future<List<Achievement>?> fetchPublicGameAchievements(
    String userId,
    String gameId,
  ) async {
    final data = await _client.rpc(
      Db.rpcGameAchievements,
      params: {'target_user': userId, 'target_game': gameId},
    );
    return Achievement.listFromJson(data);
  }

  /// [userId]'s achievements for [gameId] as Steam has them now, through the
  /// `sync-achievements` Edge Function: another member's (from the Steam account
  /// on their profile) or the signed-in member's. The function saves the list on
  /// their library row, and answers another member's from that row when it was
  /// fetched a few minutes ago. Throws [FunctionException] when it answers with an
  /// error; null when the answer has no list.
  Future<List<Achievement>?> fetchSteamGameAchievements(
    String userId,
    String gameId,
  ) async {
    final response = await _client.functions.invoke(
      'sync-achievements',
      body: {'game_id': gameId, 'user_id': userId},
    );
    final data = response.data;
    return data is Map ? Achievement.listFromJson(data['achievements']) : null;
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
    String? customBackdropUrl,
    DateTime? dateAdded,
    String review = '',
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
      Db.customBackdropUrl: customBackdropUrl,
      Db.review: review.trim(),
    }, onConflict: '${Db.userId},${Db.gameId}');
  }

  /// Inserts a play session. [loggedAt] is when it was logged, for a session
  /// that was kept on the device while the server was out of reach; without it
  /// the server stamps the time it arrives.
  Future<void> insertLogEntry({
    required String userId,
    required String gameId,
    required double hours,
    required GamePlatform platform,
    required String note,
    DateTime? loggedAt,
  }) async {
    await _client.from(Db.logEntries).insert({
      Db.userId: userId,
      Db.gameId: gameId,
      Db.hours: hours,
      Db.platform: gamePlatformToDb(platform),
      Db.note: note.trim(),
      if (loggedAt != null) Db.loggedAt: loggedAt.toUtc().toIso8601String(),
    });
  }

  /// Saves an edited play session: its hours, platform, note and when it was
  /// played (a session logged on the wrong day moves to the right one).
  Future<void> updateLogEntry({
    required String id,
    required double hours,
    required GamePlatform platform,
    required String note,
    required DateTime loggedAt,
  }) async {
    await _client
        .from(Db.logEntries)
        .update({
          Db.hours: hours,
          Db.platform: gamePlatformToDb(platform),
          Db.note: note.trim(),
          Db.loggedAt: loggedAt.toUtc().toIso8601String(),
        })
        .eq(Db.id, id);
  }

  /// Deletes one play session. The game's total is the store's to change.
  Future<void> deleteLogEntry(String id) async {
    await _client.from(Db.logEntries).delete().eq(Db.id, id);
  }

  /// Adds [game] to the global catalog if it isn't there yet, through the
  /// `igdb-handler` Edge Function (mode `add`).
  ///
  /// A game's identity is its IGDB id: `games.igdb_id` is unique and `games.id`
  /// must be [gameIdForIgdb] of it (database constraint), so the game added here
  /// from search and the same game imported by Steam sync are one row.
  ///
  /// Members can't write the catalog (20261019132900_security_hardening.sql), so
  /// only the IGDB id is sent: the function builds a missing row from IGDB's own
  /// answer, and a game that already exists (added earlier by another user, or by
  /// sync-steam) is left exactly as it is. Throws [StateError] when IGDB has no
  /// game by that id, and the [FunctionException] of a failed call.
  Future<void> addToCatalog(Game game) async {
    final igdbId = game.igdbId;
    if (igdbId == null) {
      // Only games read back from the database can lack an IGDB id (legacy
      // Steam-keyed rows), and those already exist, so they never get here.
      throw StateError('Cannot add "${game.title}" to the catalog without an IGDB id.');
    }
    assert(game.id == gameIdForIgdb(igdbId), 'games.id must be derived from igdb_id');
    final response = await _client.functions.invoke(
      'igdb-handler',
      body: {
        'mode': 'add',
        'igdb_ids': [igdbId],
      },
    );
    final data = response.data;
    bool lists(String key) => data is Map && data[key] is List && (data[key] as List).contains(igdbId);
    if (!lists('added') && !lists('existing')) {
      throw StateError('IGDB has no game "${game.title}" ($igdbId) to add to the catalog.');
    }
  }

  /// Takes [gameId] out of the library together with its play sessions, in one
  /// transaction (`remove_library_game`): both go, or neither does. The server
  /// works on the session's own rows, which are [userId]'s.
  Future<void> deleteUserGame(String userId, String gameId) async {
    await _client.rpc(Db.rpcRemoveLibraryGame, params: {'target_game': gameId});
  }

  /// Removes the user's whole library: every play session and every game (with
  /// its stored achievements), in one transaction (`clear_library`). The shared
  /// catalog is untouched.
  Future<void> clearLibrary(String userId) async {
    await _client.rpc(Db.rpcClearLibrary);
  }

  // ---- Lists ----

  /// A list with its games, in their order, each with the catalog columns.
  static final String _listColumns = '''
          ${Db.id},
          ${Db.userId},
          ${Db.title},
          ${Db.description},
          ${Db.isPublic},
          ${Db.updatedAt},
          ${Db.gameListItems} (
            ${Db.position},
            ${Db.games} (
              ${Db.id},
              ${[..._catalogColumns, Db.releaseDate].join(', ')}
            )
          )
        ''';

  /// [userId]'s lists, the last changed first. Another member's private lists
  /// are never returned (RLS), so for them this is their public lists.
  Future<List<GameList>> fetchLists(String userId) async {
    final rows = await _client
        .from(Db.gameLists)
        .select(_listColumns)
        .eq(Db.userId, userId)
        .order(Db.updatedAt, ascending: false)
        .order(Db.position, referencedTable: Db.gameListItems);
    return rows.map<GameList>(_listFromRow).toList(growable: false);
  }

  /// One list, or null when it doesn't exist or isn't the caller's to see (a
  /// private list of someone else): a list opened from a link.
  Future<GameList?> fetchList(String listId) async {
    final row = await _client
        .from(Db.gameLists)
        .select(_listColumns)
        .eq(Db.id, listId)
        .order(Db.position, referencedTable: Db.gameListItems)
        .maybeSingle();
    return row == null ? null : _listFromRow(row);
  }

  /// Makes a list for the signed-in member and returns it (empty).
  Future<GameList> createList({
    required String title,
    String description = '',
    bool isPublic = false,
  }) async {
    final row = await _client
        .from(Db.gameLists)
        .insert({
          Db.title: title.trim(),
          Db.description: description.trim(),
          Db.isPublic: isPublic,
        })
        .select(_listColumns)
        .single();
    return _listFromRow(row);
  }

  Future<void> updateList(
    String listId, {
    required String title,
    required String description,
    required bool isPublic,
  }) async {
    await _client
        .from(Db.gameLists)
        .update({
          Db.title: title.trim(),
          Db.description: description.trim(),
          Db.isPublic: isPublic,
        })
        .eq(Db.id, listId);
  }

  /// Deletes a list and its entries (the games stay in the catalog and library).
  Future<void> deleteList(String listId) async {
    await _client.from(Db.gameLists).delete().eq(Db.id, listId);
  }

  /// Puts [gameId] in the list at [position]. The game must be in the catalog.
  Future<void> addToList(String listId, String gameId, int position) async {
    await _client.from(Db.gameListItems).upsert({
      Db.listId: listId,
      Db.gameId: gameId,
      Db.position: position,
    }, onConflict: '${Db.listId},${Db.gameId}');
  }

  Future<void> removeFromList(String listId, String gameId) async {
    await _client
        .from(Db.gameListItems)
        .delete()
        .eq(Db.listId, listId)
        .eq(Db.gameId, gameId);
  }

  /// Saves the order of the list's games: [gameIds] first to last.
  Future<void> reorderList(String listId, List<String> gameIds) async {
    if (gameIds.isEmpty) return;
    await _client.from(Db.gameListItems).upsert([
      for (var i = 0; i < gameIds.length; i++)
        {Db.listId: listId, Db.gameId: gameIds[i], Db.position: i},
    ], onConflict: '${Db.listId},${Db.gameId}');
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
  final name =
      _firstText([
        row[Db.displayName],
        metadata['full_name'],
        metadata['name'],
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
    connectedServices: connectedServicesFromDb(row[Db.connectedServices]),
    psnId: _firstText([row[Db.psnId]]),
    xboxId: _firstText([row[Db.xboxId]]),
    discordId: _firstText([row[Db.discordId]]),
    instagramId: _firstText([row[Db.instagramId]]),
    twitchId: _firstText([row[Db.twitchId]]),
    showSteamAchievements: row[Db.showSteamAchievements] != false,
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
    // Only the Users tab selects the counts; other lists leave them at 0.
    gamesLogged: _int(row[Db.gamesCount]),
    followers: _int(row[Db.followersCount]),
    startsFollowed: row[Db.viewerFollows] == true,
    avatarUrl: _firstText([row[Db.avatarUrl]]),
  );
}

PublicProfile _publicProfileFromRow(Map<String, dynamic> row) {
  final name = _firstText([row[Db.displayName], row[Db.handle]]) ?? 'Player';
  return PublicProfile(
    id: '${row[Db.id]}',
    name: name,
    handle: _withAt(
      _firstText([row[Db.handle]]) ?? _handleFrom(name, '${row[Db.id]}'),
    ),
    avatarUrl: _firstText([row[Db.avatarUrl]]),
    steamConnected: row[Db.steamConnected] == true,
    // Only an explicit "no" hides them, as the column's default is "yes".
    showSteamAchievements: row[Db.showSteamAchievements] != false,
    services: connectedServicesFromDb(row[Db.connectedServices]),
    bio: _firstText([row[Db.bio]]),
    steamId: _firstText([row[Db.steamId]]),
    psnId: _firstText([row[Db.psnId]]),
    xboxId: _firstText([row[Db.xboxId]]),
    discordId: _firstText([row[Db.discordId]]),
    instagramId: _firstText([row[Db.instagramId]]),
    twitchId: _firstText([row[Db.twitchId]]),
    joined: _date(row[Db.joinedAt]),
  );
}

/// A play session on someone's profile, from a `public_recent_activity` row. The
/// game is the catalog game, with none of the player's own state.
ActivityEntry _activityFromRow(Map<String, dynamic> row) => ActivityEntry(
  game: _gameFromCatalogRow({...row, Db.id: row[Db.gameId]}),
  hours: _double(row[Db.hours]),
  platform: gamePlatformFromDb(row[Db.platform]) ?? GamePlatform.pc,
  at: _date(row[Db.loggedAt]) ?? DateTime.now(),
);

/// A game on another member's profile: the catalog data and the owner's tracking
/// fields, from a `public_user_games` row. The purchase price is never read.
Game _gameFromPublicRow(Map<String, dynamic> row) {
  final catalogGame = _gameFromCatalogRow({...row, Db.id: row[Db.gameId]});
  return catalogGame.copyWith(
    status: gameStatusFromDb(row[Db.status]),
    rating: _double(row[Db.rating]),
    hoursPlayed: _double(row[Db.hoursPlayed]),
    playedOn: gamePlatformFromDb(row[Db.playedOn]),
    dateAdded: _date(row[Db.dateAdded]),
    isFavorite: row[Db.isFavorite] == true,
    review: _firstText([row[Db.review]]) ?? '',
  ).withBackdrop(_firstText([row[Db.customBackdropUrl]])).withCompletedAt(_date(row[Db.completedAt]));
}

GameAttributes _attributesFromRow(Map<String, dynamic> row) => GameAttributes(
  themes: _strings(row[Db.themes]),
  gameModes: _strings(row[Db.gameModes]),
  perspectives: _strings(row[Db.playerPerspectives]),
  engines: _strings(row[Db.gameEngines]),
  developers: _strings(row[Db.developers]),
  publishers: _strings(row[Db.publishers]),
);

GameAchievementSummary _achievementSummaryFromRow(Map<String, dynamic> row) =>
    GameAchievementSummary(
      gameId: '${row[Db.gameId]}',
      title: _firstText([row[Db.title]]) ?? 'Untitled Game',
      coverUrl: _firstText([row[Db.coverUrl]]),
      unlocked: _int(row['unlocked']),
      total: _int(row['total']),
    );

Game _gameFromCatalogRow(Map<String, dynamic> row) {
  final id = '${row[Db.id]}';
  final title = _firstText([row[Db.title]]) ?? 'Untitled Game';
  final steamAppId = _intOrNull(row[Db.steamAppId]);
  // Release platforms only: a stored Steam Deck / Emulator is stray data (see
  // releasePlatformsFromDb). Steam sync used to leave the list empty, and a game
  // owned on Steam is a PC game; any other game with none known keeps none rather
  // than being given a platform it may never have been released on.
  var platforms = releasePlatformsFromDb(_strings(row[Db.platforms]));
  if (platforms.isEmpty &&
      (steamAppId != null || id.startsWith(legacySteamIdPrefix))) {
    platforms = const [GamePlatform.pc];
  }
  final genres = _strings(row[Db.genres]);
  return Game(
    id: id,
    title: title,
    publisher: _firstText([row[Db.publisher]]) ?? 'Unknown publisher',
    developer: _firstText([row[Db.developer]]) ?? 'Unknown developer',
    releaseYear: _int(row[Db.releaseYear]),
    platforms: platforms,
    genres: genres,
    synopsis: _firstText([row[Db.summary]]) ?? '',
    coverColors: coverColorsFor(id, title),
    coverIcon: coverIconFor(genres, platforms),
    coverUrl: _firstText([row[Db.coverUrl]]),
    igdbId: _intOrNull(row[Db.igdbId]),
    steamAppId: steamAppId,
    releaseDate: _releaseDay(row[Db.releaseDate]),
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
    review: _firstText([row[Db.review]]) ?? '',
    // `achievements` is intentionally not read here: fetchUserGames doesn't
    // select it. See fetchGameAchievements.
  ).withBackdrop(_firstText([row[Db.customBackdropUrl]])).withCompletedAt(_date(row[Db.completedAt]));
}

GameList _listFromRow(Map<String, dynamic> row) {
  final items = [
    for (final item in row[Db.gameListItems] as List? ?? const [])
      if (item is Map && item[Db.games] is Map) Map<String, dynamic>.from(item),
  ]..sort((a, b) => _int(a[Db.position]).compareTo(_int(b[Db.position])));
  return GameList(
    id: '${row[Db.id]}',
    ownerId: '${row[Db.userId]}',
    title: _firstText([row[Db.title]]) ?? 'Untitled list',
    description: _firstText([row[Db.description]]) ?? '',
    isPublic: row[Db.isPublic] == true,
    games: [
      for (final item in items)
        _gameFromCatalogRow(Map<String, dynamic>.from(item[Db.games] as Map)),
    ],
    updatedAt: _date(row[Db.updatedAt]),
  );
}

LogEntry _logFromRow(Map<String, dynamic> row) => LogEntry(
  id: '${row[Db.id]}',
  gameId: '${row[Db.gameId]}',
  timestamp: _date(row[Db.loggedAt]) ?? DateTime.now(),
  hours: _double(row[Db.hours]),
  platform: gamePlatformFromDb(row[Db.platform]) ?? GamePlatform.pc,
  note: _firstText([row[Db.note]]) ?? '',
  fromSteam: row[Db.source] == 'steam',
);

List<String> _strings(Object? value) {
  if (value is List) {
    return value.map((v) => '$v').where((v) => v.trim().isNotEmpty).toList();
  }
  if (value is String && value.trim().isNotEmpty) return [value.trim()];
  return const [];
}

String? _firstText(List<Object?> values) {
  for (final value in values) {
    final text = value?.toString().trim();
    if (text != null && text.isNotEmpty) return text;
  }
  return null;
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
  final handle = '${safeBase}_${safeSuffix.substring(0, math.min(6, safeSuffix.length))}';
  return handle.substring(0, math.min(24, handle.length));
}

DateTime? _date(Object? value) {
  if (value == null) return null;
  return DateTime.tryParse('$value')?.toLocal();
}

/// A `date` column ("2026-11-14") as that calendar day, at midnight on the
/// device: a release day is the same day everywhere, not an instant.
DateTime? _releaseDay(Object? value) {
  final parsed = value == null ? null : DateTime.tryParse('$value');
  return parsed == null ? null : DateTime(parsed.year, parsed.month, parsed.day);
}

/// [d]'s calendar day as a `date` column takes it: "2026-11-14".
String _day(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

double _double(Object? value, {double fallback = 0}) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? fallback;
}

int _int(Object? value, {int fallback = 0}) {
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? fallback;
}

int? _intOrNull(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toInt();
  return int.tryParse('$value');
}

