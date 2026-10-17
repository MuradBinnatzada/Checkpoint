import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:checkpoint/models/achievement.dart';
import 'package:checkpoint/models/achievement_summary.dart';
import 'package:checkpoint/models/activity_entry.dart';
import 'package:checkpoint/models/browse.dart';
import 'package:checkpoint/models/connected_service.dart';
import 'package:checkpoint/models/game.dart';
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
}) {
  final name = title ?? 'Game $id';
  const genres = ['RPG'];
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
    igdbId: 7,
    steamAppId: 440,
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

  /// The Steam ID saved on the profile; null means no Steam account is connected.
  String? steamId;

  /// `profiles.connected_services`: the services saved for the signed-in user, as
  /// other members see them (Steam is never in it), and the account names saved
  /// with them (`psn_id`, `xbox_id`, `discord_id`).
  Set<ConnectedService> connectedServices = {};
  String? savedPsnId;
  String? savedXboxId;
  String? savedDiscordId;

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
      bio: '',
      steamId: steamId,
      connectedServices: services,
      psnId: savedPsnId,
      xboxId: savedXboxId,
      discordId: savedDiscordId,
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
    writes.add('services:${connectedServicesToDb(accounts.services).join(',')}');
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
  }) async {
    _checkWrite();
    writes.add('log:$gameId:$hours');
  }

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
    DateTime? dateAdded,
  }) async {
    _checkWrite();
    writes.add('game:$gameId:$status:$rating');
  }

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

  /// Holds profile reads / follower and following lists until completed, to
  /// have a request in flight.
  Completer<void>? profileGate;
  Completer<void>? followListGate;

  /// Fails these reads, as a dropped connection does.
  bool failProfileReads = false;
  bool failFollowLists = false;
  bool failAchievementReads = false;

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
