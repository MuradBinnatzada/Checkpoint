import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:checkpoint/models/achievement.dart';
import 'package:checkpoint/models/achievement_summary.dart';
import 'package:checkpoint/models/activity_entry.dart';
import 'package:checkpoint/models/browse.dart';
import 'package:checkpoint/models/company.dart';
import 'package:checkpoint/models/connected_service.dart';
import 'package:checkpoint/models/filter_options.dart';
import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/game_attributes.dart';
import 'package:checkpoint/models/game_details.dart';
import 'package:checkpoint/models/game_friends.dart';
import 'package:checkpoint/models/game_cover.dart';
import 'package:checkpoint/models/library_stats.dart';
import 'package:checkpoint/models/log_entry.dart';
import 'package:checkpoint/models/public_profile.dart';
import 'package:checkpoint/models/results_page.dart';
import 'package:checkpoint/models/social_user.dart';
import 'package:checkpoint/models/user_profile.dart';
import 'package:checkpoint/services/auth_service.dart';
import 'package:checkpoint/services/checkpoint_repository.dart';
import 'package:checkpoint/services/connectivity_service.dart';
import 'package:checkpoint/services/game_api_service.dart';
import 'package:checkpoint/state/company_store.dart';

User testUser(String id) => User(
  id: id,
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: '2026-01-01T00:00:00Z',
);

Game testGame(
  String id, {
  String? title,
  GameStatus? status = GameStatus.playing,
  double hours = 12.5,
  bool favorite = false,
  bool cover = true,
  int year = 2020,
  List<GamePlatform> platforms = const [GamePlatform.pc, GamePlatform.ps5],
  GamePlatform? playedOn,
  int? steamAppId = 440,
  int? igdbId = 7,
  List<String> genres = const ['RPG'],
}) {
  final name = title ?? 'Game $id';
  return Game(
    id: id,
    title: name,
    publisher: 'Publisher',
    developer: 'Developer',
    releaseYear: year,
    platforms: platforms,
    genres: genres,
    synopsis: 'A game.',
    coverColors: coverColorsFor(id, name),
    coverIcon: coverIconFor(genres, platforms),
    coverUrl: cover ? 'https://example.com/$id.jpg' : null,
    igdbId: igdbId,
    steamAppId: steamAppId,
    status: status,
    rating: 4.5,
    hoursPlayed: hours,
    playedOn: playedOn ?? (status == null ? null : GamePlatform.pc),
    purchasePrice: 19.99,
    dateAdded: status == null ? null : DateTime.utc(2026, 1, 2, 3, 4, 5),
    isFavorite: favorite,
  );
}

/// A game in a browse list. [score] and [released] are what the list captions
/// show. Like a game from IGDB it has no rating: that is the user's own.
BrowseEntry testEntry(
  String id, {
  String? title,
  double? score = 92.4,
  DateTime? released,
}) => BrowseEntry(
  testGame(id, title: title, status: null, cover: false).copyWith(rating: 0),
  score: score,
  releaseDate: released,
);

LogEntry testLog(String id, String gameId) => LogEntry(
  id: id,
  gameId: gameId,
  timestamp: DateTime.utc(2026, 2, 3, 4, 5, 6),
  hours: 1.5,
  platform: GamePlatform.pc,
  note: 'a note',
);

/// A member as the lists and the search show them.
SocialUser testMember(String id, {String? name, String? avatarUrl}) => SocialUser(
  id: id,
  name: name ?? 'Member $id',
  handle: '@member_$id',
  gamesLogged: 0,
  followers: 0,
  avatarUrl: avatarUrl,
);

/// A member the signed-in user follows who has a game with [status].
FriendWithGame testFriend(
  String id,
  GameStatus status, {
  double rating = 0,
  DateTime? added,
  String? name,
}) => FriendWithGame(
  member: testMember(id, name: name),
  status: status,
  rating: rating,
  dateAdded: added,
);

/// [friends] as `following_game_activity` sends them: [totals] defaults to
/// counting [friends], as when every one of them was sent.
GameFriends testGameFriends(
  List<FriendWithGame> friends, {
  Map<GameStatus, int>? totals,
}) => GameFriends(
  friends: friends,
  totals:
      totals ??
      {
        for (final status in GameStatus.values)
          if (friends.any((f) => f.status == status))
            status: friends.where((f) => f.status == status).length,
      },
);

/// A [CheckpointRepository] that answers from memory. [offline] makes every read
/// throw, like a dead connection; [gate] holds the library read until completed.
class FakeRepository implements CheckpointRepository {
  List<Game> library = [];
  List<LogEntry> logs = [];
  List<Game> popular = [];
  bool offline = false;

  /// Writes are refused (as by a constraint or policy) while reads still work.
  bool rejectWrites = false;

  /// Writes can't reach the server while reads still work, like a connection
  /// that dropped between the two.
  bool writesDown = false;

  /// Who the signed-in user follows on the server.
  Set<String> following = {'friend-1'};

  /// The bio saved on the signed-in user's profile.
  String profileBio = '';

  /// The Steam ID saved on the profile; null means no Steam account is connected.
  String? steamId;

  /// `profiles.show_steam_achievements`: whether other members see them.
  bool showSteamAchievements = true;

  /// Holds [setShowSteamAchievements] until completed.
  Completer<void>? privacyGate;

  /// `profiles.connected_services`: the services saved for the signed-in user, as
  /// other members see them (Steam is never in it), and the account names saved
  /// with them (`psn_id`, `xbox_id`, `discord_id`, `instagram_id`, `twitch_id`).
  Set<ConnectedService> connectedServices = {};
  String? savedPsnId;
  String? savedXboxId;
  String? savedDiscordId;
  String? savedInstagramId;
  String? savedTwitchId;

  /// What `sync-steam` answers, or the error it throws when [syncError] is set.
  Object? syncData = {'success': true, 'delayed': null};
  Object? syncError;
  int syncCalls = 0;

  /// Holds [follow] until completed, to have a request in flight.
  Completer<void>? followGate;

  /// Holds [setConnectedAccounts] until completed.
  Completer<void>? servicesGate;

  /// Holds the signed-in user's own profile read ([ensureProfile]) until completed.
  Completer<void>? profileLoadGate;
  Completer<void>? gate;
  int libraryFetches = 0;

  /// The IGDB ids of the library's games whose catalog row IGDB never filled in
  /// ([fetchUnsyncedIgdbIds]). Empty by default, so no catalog backfill runs.
  List<int> unsyncedIgdbIds = [];
  int unsyncedReads = 0;

  /// What the server holds of the library games' IGDB details, by game id
  /// ([fetchLibraryAttributes]): the games filled in from IGDB. Holds [gate]-like
  /// [attributesGate] until completed.
  Map<String, GameAttributes> libraryAttributes = {};
  int attributeReads = 0;
  Completer<void>? attributesGate;

  /// Only the attribute read fails, while the rest of the library still loads.
  bool attributesDown = false;

  /// What reached the server, in order.
  final List<String> writes = [];

  void _checkOnline() {
    if (offline) throw Exception('network down');
  }

  void _checkWrite() {
    _checkOnline();
    if (writesDown) throw Exception('network down');
    if (rejectWrites) throw const PostgrestException(message: 'refused', code: '23514');
  }

  @override
  Future<List<Game>> fetchUserGames(String userId) async {
    libraryFetches++;
    await gate?.future;
    _checkOnline();
    return library;
  }

  @override
  Future<Map<String, GameAttributes>> fetchLibraryAttributes(
    String userId,
  ) async {
    attributeReads++;
    await attributesGate?.future;
    _checkOnline();
    if (attributesDown) throw Exception('details unavailable');
    return Map.of(libraryAttributes);
  }

  @override
  Future<List<int>> fetchUnsyncedIgdbIds(String userId) async {
    unsyncedReads++;
    _checkOnline();
    return List.of(unsyncedIgdbIds);
  }

  @override
  Future<List<LogEntry>> fetchLogEntries(String userId) async {
    _checkOnline();
    return logs;
  }

  @override
  Future<List<Game>> fetchPopularGames({int limit = 20}) async {
    _checkOnline();
    return popular;
  }

  @override
  Future<UserProfile> ensureProfile(User user) async {
    // The row as it is when the request is made, like a read that is under way.
    final services = {...connectedServices};
    await profileLoadGate?.future;
    _checkOnline();
    return UserProfile(
      name: 'Ada',
      handle: '@ada',
      bio: profileBio,
      steamId: steamId,
      connectedServices: services,
      psnId: savedPsnId,
      xboxId: savedXboxId,
      discordId: savedDiscordId,
      instagramId: savedInstagramId,
      twitchId: savedTwitchId,
      showSteamAchievements: showSteamAchievements,
      joined: DateTime.utc(2026, 1, 1),
      followers: 0,
      following: 0,
    );
  }

  @override
  Future<UserProfile> fetchProfile(User user) => ensureProfile(user);

  @override
  Future<void> setConnectedAccounts(ConnectedAccounts accounts) async {
    await servicesGate?.future;
    _checkWrite();
    connectedServices = {...accounts.services};
    savedPsnId = accounts.psnId;
    savedXboxId = accounts.xboxId;
    savedDiscordId = accounts.discordId;
    savedInstagramId = accounts.instagramId;
    savedTwitchId = accounts.twitchId;
    writes.add('services:${connectedServicesToDb(accounts.services).join(',')}');
  }

  @override
  Future<void> setSteamId(String id) async {
    _checkWrite();
    steamId = id.trim();
    writes.add('steam:$steamId');
  }

  @override
  Future<void> setShowSteamAchievements(bool show) async {
    await privacyGate?.future;
    _checkWrite();
    showSteamAchievements = show;
    writes.add('show-achievements:$show');
  }

  @override
  Future<void> clearSteamId() async {
    _checkWrite();
    steamId = null;
    writes.add('steam:');
  }

  @override
  Future<Object?> syncSteamLibrary() async {
    syncCalls++;
    final error = syncError;
    if (error != null) throw error;
    return syncData;
  }

  @override
  Future<Set<String>> fetchFollowingIds(String userId) async {
    _checkOnline();
    return {...following};
  }

  @override
  Future<int> fetchFollowersCount(String userId) async {
    _checkOnline();
    return 3;
  }

  @override
  Future<void> follow({required String followerId, required String followeeId}) async {
    await followGate?.future;
    _checkWrite();
    // The table's key is (follower, followee): following twice is an error.
    if (!following.add(followeeId)) {
      throw const PostgrestException(message: 'duplicate key', code: '23505');
    }
    writes.add('follow:$followeeId');
  }

  @override
  Future<void> unfollow({required String followerId, required String followeeId}) async {
    _checkWrite();
    following.remove(followeeId);
    writes.add('unfollow:$followeeId');
  }

  @override
  Future<void> deleteUserGame(String userId, String gameId) async {
    _checkWrite();
    writes.add('delete:$gameId');
  }

  @override
  Future<void> clearLibrary(String userId) async {
    _checkWrite();
    writes.add('clear-library');
    library = [];
    logs = [];
    // Achievements are stored with the games.
    achievementSummaries.remove(userId);
    memberAchievements.removeWhere((key, _) => key.$1 == userId);
  }

  @override
  Future<void> upsertBaseGame(Game game) async {
    _checkWrite();
    writes.add('base:${game.id}');
  }

  @override
  Future<void> insertLogEntry({
    required String userId,
    required String gameId,
    required double hours,
    required GamePlatform platform,
    required String note,
    DateTime? loggedAt,
  }) async {
    _checkWrite();
    writes.add('log:$gameId:$hours');
    logTimes.add(loggedAt);
  }

  /// The `logged_at` each inserted session was sent with, in order (null: the
  /// server's own time).
  final List<DateTime?> logTimes = [];

  @override
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
  }) async {
    _checkWrite();
    writes.add('game:$gameId:$status:$rating');
    backdrops[gameId] = customBackdropUrl;
  }

  /// The backdrop each game's last save sent.
  final Map<String, String?> backdrops = {};

  @override
  Future<ResultsPage<SocialUser>> searchSocialUsers(
    String currentUserId, {
    String query = '',
    int offset = 0,
    int limit = 30,
  }) async {
    _checkOnline();
    return ResultsPage<SocialUser>(const [
      SocialUser(id: 'm1', name: 'Member', handle: '@member', gamesLogged: 0, followers: 0),
    ], hasMore: false);
  }

  // ---- Other members ----

  /// Members the server knows, by id. A missing id is a deleted account.
  final Map<String, PublicProfile> members = {
    'm1': const PublicProfile(
      id: 'm1',
      name: 'Member One',
      handle: '@member_one',
      steamConnected: true,
    ),
  };

  /// What `public_profile_stats` answers, per member (default: 5 / 2 / not
  /// following / 2 games).
  final Map<String, PublicProfileStats> stats = {};

  /// A member's games. The profile's favorites, rated list and library pages are
  /// cut from these the way the database does it.
  final Map<String, List<Game>> memberGames = {};

  /// Followers and following lists, per member id.
  final Map<String, List<SocialUser>> followersOf = {};
  final Map<String, List<SocialUser>> followingOf = {};

  /// Per member: the progress per game, and the achievements of each game.
  final Map<String, List<GameAchievementSummary>> achievementSummaries = {};
  final Map<(String, String), List<Achievement>?> memberAchievements = {};

  /// What Steam has for a member's game, handed out by the `sync-achievements`
  /// fake. A game missing here fails, as one Steam can't answer for does.
  final Map<(String, String), List<Achievement>> steamAchievements = {};

  /// Thrown by the Steam fetch instead of answering (a FunctionException with a
  /// code, say). Null: answer from [steamAchievements].
  Object? steamAchievementsError;

  /// Holds profile reads / follower and following lists until completed, to
  /// have a request in flight.
  Completer<void>? profileGate;
  Completer<void>? followListGate;

  /// Fails these reads, as a dropped connection does.
  bool failProfileReads = false;
  bool failFollowLists = false;
  bool failAchievementReads = false;

  /// Fails only the count, as a database without `public_achievement_totals` does.
  bool failAchievementTotals = false;

  /// What was asked of the server about other members, in order.
  final List<String> memberReads = [];

  List<Game> _gamesOf(String userId) => memberGames[userId] ?? const [];

  @override
  Future<PublicProfile?> fetchPublicProfile(String userId) async {
    memberReads.add('profile:$userId');
    await profileGate?.future;
    _checkOnline();
    if (failProfileReads) throw Exception('profile read failed');
    return members[userId];
  }

  @override
  Future<PublicProfileStats> fetchPublicProfileStats(String userId) async {
    memberReads.add('stats:$userId');
    _checkOnline();
    if (failProfileReads) throw Exception('profile read failed');
    return stats[userId] ??
        PublicProfileStats(
          followers: 5,
          following: 2,
          viewerFollows: false,
          games: _gamesOf(userId).length,
        );
  }

  @override
  Future<List<Game>> fetchPublicFavorites(String userId) async {
    _checkOnline();
    return [
      for (final g in _gamesOf(userId))
        if (g.isFavorite) g,
    ].take(CheckpointRepository.publicFavoritesLimit).toList();
  }

  /// A member's latest sessions, newest first.
  final Map<String, List<ActivityEntry>> memberActivity = {};

  /// Holds the whole-library read of another member until completed.
  Completer<void>? memberLibraryGate;
  bool failMemberLibrary = false;

  @override
  Future<LibraryStats> fetchPublicLibraryStats(String userId) async {
    memberReads.add('stats-rows:$userId');
    _checkOnline();
    if (failProfileReads) throw Exception('profile read failed');
    return LibraryStats.of(_gamesOf(userId));
  }

  @override
  Future<List<Game>> fetchPublicLibrary(String userId) async {
    memberReads.add('library:$userId');
    await memberLibraryGate?.future;
    _checkOnline();
    if (failMemberLibrary) throw Exception('library read failed');
    return _gamesOf(userId);
  }

  @override
  Future<List<ActivityEntry>> fetchPublicActivity(
    String userId, {
    int limit = CheckpointRepository.publicActivityLimit,
  }) async {
    _checkOnline();
    return (memberActivity[userId] ?? const <ActivityEntry>[])
        .take(limit)
        .toList();
  }

  ResultsPage<SocialUser> _page(List<SocialUser> all, int offset, int limit) {
    final items = all.skip(offset).take(limit).toList();
    return ResultsPage<SocialUser>(items, hasMore: items.length >= limit);
  }

  @override
  Future<ResultsPage<SocialUser>> fetchFollowers(
    String userId, {
    int offset = 0,
    int limit = CheckpointRepository.followListPageSize,
  }) async {
    memberReads.add('followers:$userId:$offset');
    await followListGate?.future;
    _checkOnline();
    if (failFollowLists) throw Exception('list failed');
    return _page(followersOf[userId] ?? const [], offset, limit);
  }

  @override
  Future<ResultsPage<SocialUser>> fetchFollowing(
    String userId, {
    int offset = 0,
    int limit = CheckpointRepository.followListPageSize,
  }) async {
    memberReads.add('following:$userId:$offset');
    await followListGate?.future;
    _checkOnline();
    if (failFollowLists) throw Exception('list failed');
    return _page(followingOf[userId] ?? const [], offset, limit);
  }

  /// The members the signed-in user follows who have each game, by game id, as
  /// `following_game_activity` answers. [friendsGate] holds the read until
  /// completed; [failFriendsReads] fails it.
  final Map<String, GameFriends> friendsWithGame = {};
  Completer<void>? friendsGate;
  bool failFriendsReads = false;

  /// The games [fetchFriendsWithGame] was asked about, in order.
  final List<String> friendReads = [];

  @override
  Future<GameFriends> fetchFriendsWithGame(String gameId) async {
    friendReads.add(gameId);
    await friendsGate?.future;
    _checkOnline();
    if (failFriendsReads) throw Exception('friends read failed');
    return friendsWithGame[gameId] ?? const GameFriends();
  }

  /// Added up from [achievementSummaries], as the database does.
  @override
  Future<AchievementTotals> fetchAchievementTotals(String userId) async {
    memberReads.add('achievement-totals:$userId');
    _checkOnline();
    if (failAchievementTotals) throw Exception('achievement totals failed');
    final games = achievementSummaries[userId] ?? const <GameAchievementSummary>[];
    return AchievementTotals(
      unlocked: games.fold(0, (sum, g) => sum + g.unlocked),
      total: games.fold(0, (sum, g) => sum + g.total),
      games: games.length,
      completedGames: games.where((g) => g.unlocked == g.total).length,
    );
  }

  @override
  Future<List<GameAchievementSummary>> fetchAchievementSummary(String userId) async {
    memberReads.add('achievements:$userId');
    _checkOnline();
    if (failAchievementReads) throw Exception('achievements failed');
    return achievementSummaries[userId] ?? const [];
  }

  @override
  Future<List<Achievement>?> fetchPublicGameAchievements(
    String userId,
    String gameId,
  ) async {
    memberReads.add('achievements:$userId:$gameId');
    _checkOnline();
    if (failAchievementReads) throw Exception('achievements failed');
    return memberAchievements[(userId, gameId)];
  }

  /// The signed-in user's stored list for one of their games (null: never
  /// loaded). It sits with every member's in [memberAchievements], as in the
  /// database, where both are the `achievements` column of a library row.
  @override
  Future<List<Achievement>?> fetchGameAchievements(
    String userId,
    String gameId,
  ) async {
    _checkOnline();
    return memberAchievements[(userId, gameId)];
  }

  /// Like the function, stores what Steam answered where the database keeps it.
  @override
  Future<List<Achievement>?> fetchSteamGameAchievements(
    String userId,
    String gameId,
  ) async {
    memberReads.add('steam:$userId:$gameId');
    _checkOnline();
    final error = steamAchievementsError;
    if (error != null) throw error;
    final list = steamAchievements[(userId, gameId)];
    if (list == null) throw Exception('steam failed');
    memberAchievements[(userId, gameId)] = list;
    return list;
  }

  @override
  Stream<void> watchUserGames(String userId) => const Stream.empty();

  @override
  Stream<List<Map<String, dynamic>>> watchLogEntries(String userId) =>
      const Stream.empty();

  @override
  Stream<List<Map<String, dynamic>>> watchProfile(String userId) =>
      const Stream.empty();

  @override
  Stream<List<Map<String, dynamic>>> watchFollows(String userId) =>
      const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// An [AuthService] whose session the test controls.
class FakeAuthService implements AuthService {
  FakeAuthService([this.user]);

  User? user;

  /// What the device has saved while [user] is null (see persistedUserId).
  String? persistedId;
  bool restoreWorks = false;
  int restoreCalls = 0;
  final _changes = StreamController<AuthState>.broadcast();

  @override
  User? get currentUser => user;

  @override
  Future<String?> persistedUserId() async => persistedId;

  @override
  Future<bool> restoreSession() async {
    restoreCalls++;
    if (restoreWorks && persistedId != null) {
      emit(testUser(persistedId!));
      return true;
    }
    return false;
  }

  @override
  Future<void> discardPersistedSession() async => persistedId = null;

  /// What [deleteAccount] throws, when set; the account is untouched then.
  Object? deleteError;
  int deleteCalls = 0;

  /// Like the real one: the server removes the account, then the session ends.
  @override
  Future<void> deleteAccount() async {
    deleteCalls++;
    final error = deleteError;
    if (error != null) throw error;
    emit(null);
  }

  @override
  Future<void> signOut() async => emit(null);

  /// What [signInWithGoogle] throws, when set; otherwise it signs `u1` in.
  Object? signInError;

  @override
  Future<void> signInWithGoogle() async {
    final error = signInError;
    if (error != null) throw error;
    emit(testUser('u1'));
  }

  /// What [signOutOtherDevices] throws, when set.
  Object? signOutOthersError;
  int signOutOthersCalls = 0;

  @override
  Future<void> signOutOtherDevices() async {
    signOutOthersCalls++;
    final error = signOutOthersError;
    if (error != null) throw error;
  }

  @override
  Stream<AuthState> get changes => _changes.stream;

  /// Signs [next] in (or out, when null) and announces it, as Supabase does.
  void emit(User? next) {
    user = next;
    _changes.add(
      AuthState(
        next == null ? AuthChangeEvent.signedOut : AuthChangeEvent.signedIn,
        next == null
            ? null
            : Session(accessToken: 't', tokenType: 'bearer', user: next),
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A [ConnectivityService] the test drives.
class FakeConnectivity implements ConnectivityService {
  final controller = StreamController<bool>.broadcast();

  @override
  Stream<bool> get onlineChanges => controller.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A [GameApiService] whose browse lists the test controls. [answer] gives the
/// page for a mode and offset (null = the request failed); by default every mode
/// has one page of two games named after it. [gate] holds every answer until
/// completed, to have a request in flight.
class FakeBrowseApi extends GameApiService {
  ResultsPage<BrowseEntry>? Function(BrowseMode mode, int offset) answer =
      (mode, offset) => ResultsPage([
        testEntry('${mode.name}-1'),
        testEntry('${mode.name}-2'),
      ], hasMore: false);
  Completer<void>? gate;

  /// What was asked, in order.
  final List<(BrowseMode, int)> calls = [];

  int callsFor(BrowseMode mode) => calls.where((c) => c.$1 == mode).length;

  @override
  Future<ResultsPage<BrowseEntry>?> browseGames(
    BrowseMode mode, {
    int offset = 0,
    int limit = GameApiService.browsePageSize,
  }) async {
    calls.add((mode, offset));
    await gate?.future;
    return answer(mode, offset);
  }
}

/// A [GameApiService] whose game details the test controls. [answer] gives the
/// details for an IGDB id (null = the request failed). [gate] holds every answer
/// until completed, to have a request in flight.
class FakeDetailsApi extends GameApiService {
  GameDetails? Function(int igdbId) answer = (id) => null;
  Completer<void>? gate;

  /// The IGDB ids asked for, in order.
  final List<int> calls = [];

  @override
  Future<GameDetails?> fetchDetails(int igdbId) async {
    calls.add(igdbId);
    await gate?.future;
    return answer(igdbId);
  }
}

/// A [GameApiService] whose companies and their games (and, as a
/// [FakeDetailsApi], game details) the test controls. [company] gives a
/// company's page (null = the request failed); [games] gives a page of a list
/// for an offset (null = failed), by default one page of two games named after
/// the list; [companies] what the studio search finds. [gate] holds every
/// answer until completed.
class FakeCompanyApi extends FakeDetailsApi {
  Company? Function(int id) company = (id) => Company(id: id, name: 'Company $id', publishedCount: 3, developedCount: 2);
  ResultsPage<CompanyGame>? Function(CompanyGamesKey key, int offset) games = (key, offset) => ResultsPage([
    companyGame('${key.$1}-${key.$2.name}-1'),
    companyGame('${key.$1}-${key.$2.name}-2'),
  ], hasMore: false);

  /// What the studio search finds for a query (null = the request failed).
  List<CompanySummary>? Function(String query) companies = (query) => [
    CompanySummary(id: 56, name: 'Studio $query'),
  ];

  final List<int> companyCalls = [];
  final List<(CompanyGamesKey, int)> gameCalls = [];

  @override
  Future<List<CompanySummary>?> searchCompanies(
    String query, {
    int limit = GameApiService.searchPageSize,
  }) async {
    await gate?.future;
    return companies(query);
  }

  @override
  Future<Company?> fetchCompany(int companyId) async {
    companyCalls.add(companyId);
    await gate?.future;
    return company(companyId);
  }

  @override
  Future<ResultsPage<CompanyGame>?> companyGames(
    int companyId, {
    CompanyRole role = CompanyRole.any,
    DiscoverSort sort = DiscoverSort.popular,
    int offset = 0,
    int limit = GameApiService.browsePageSize,
  }) async {
    final key = (companyId, role, sort);
    gameCalls.add((key, offset));
    await gate?.future;
    return games(key, offset);
  }
}

/// A game on a company's page, developed by it.
CompanyGame companyGame(String id) => CompanyGame(testEntry(id), developed: true, published: false);

/// A [GameApiService] whose catalog backfill the test controls. [answer] gives
/// what a batch of IGDB ids comes back with; by default every game is filled in
/// with [backfilledPlatforms] and [backfilledGenres]. [gate] holds every answer
/// until completed, to have a request in flight.
class FakeBackfillApi extends GameApiService {
  static const backfilledPlatforms = [GamePlatform.pc, GamePlatform.ps3, GamePlatform.xbox360];
  static const backfilledGenres = ['Role-playing (RPG)', 'Adventure'];

  CatalogBackfillResult Function(List<int> igdbIds) answer = (ids) => CatalogBackfillResult([
    for (final id in ids)
      GameDetails(igdbId: id, platforms: backfilledPlatforms, genres: backfilledGenres),
  ]);
  Completer<void>? gate;

  /// Each batch of IGDB ids asked for, in order.
  final List<List<int>> calls = [];

  @override
  Future<CatalogBackfillResult> backfillCatalog(List<int> igdbIds) async {
    calls.add(List.of(igdbIds));
    await gate?.future;
    return answer(igdbIds);
  }
}

/// IGDB's details for a game, as [FakeDetailsApi] answers by default: Skyrim's
/// exact platforms, some attributes, a storyline, one similar game and a time to
/// beat.
GameDetails testDetails({
  int igdbId = 7,
  List<GamePlatform> platforms = const [GamePlatform.pc, GamePlatform.ps3, GamePlatform.xbox360],
  List<Game>? similarGames,
  Map<String, int> companyIds = const {},
  TimeToBeat? timeToBeat = const TimeToBeat(
    hastily: Duration(hours: 25),
    normally: Duration(hours: 50),
    completely: Duration(hours: 150),
    count: 4358,
  ),
}) => GameDetails(
  igdbId: igdbId,
  platforms: platforms,
  genres: const ['Role-playing (RPG)', 'Adventure'],
  themes: const ['Fantasy', 'Open world'],
  gameModes: const ['Single player'],
  perspectives: const ['First person'],
  engines: const ['Creation Engine'],
  developers: const ['Bethesda Game Studios'],
  publishers: const ['Bethesda Softworks'],
  companyIds: companyIds,
  storyline: 'The Empire of Tamriel is on the edge.',
  similarGames: similarGames ?? [testGame('similar-1', title: 'Oblivion', status: null, cover: false, igdbId: 306)],
  timeToBeat: timeToBeat,
);
