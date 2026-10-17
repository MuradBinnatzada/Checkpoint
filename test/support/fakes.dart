import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/game_cover.dart';
import 'package:checkpoint/models/log_entry.dart';
import 'package:checkpoint/models/results_page.dart';
import 'package:checkpoint/models/social_user.dart';
import 'package:checkpoint/models/user_profile.dart';
import 'package:checkpoint/services/auth_service.dart';
import 'package:checkpoint/services/checkpoint_repository.dart';
import 'package:checkpoint/services/connectivity_service.dart';

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
}) {
  final name = title ?? 'Game $id';
  const genres = ['RPG'];
  const platforms = [GamePlatform.pc, GamePlatform.ps5];
  return Game(
    id: id,
    title: name,
    publisher: 'Publisher',
    developer: 'Developer',
    releaseYear: 2020,
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
    playedOn: status == null ? null : GamePlatform.pc,
    purchasePrice: 19.99,
    dateAdded: status == null ? null : DateTime.utc(2026, 1, 2, 3, 4, 5),
    isFavorite: favorite,
  );
}

LogEntry testLog(String id, String gameId) => LogEntry(
  id: id,
  gameId: gameId,
  timestamp: DateTime.utc(2026, 2, 3, 4, 5, 6),
  hours: 1.5,
  platform: GamePlatform.pc,
  note: 'a note',
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

  /// What `sync-steam` answers, or the error it throws when [syncError] is set.
  Object? syncData = {'success': true, 'delayed': null};
  Object? syncError;
  int syncCalls = 0;

  /// Holds [follow] until completed, to have a request in flight.
  Completer<void>? followGate;
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
    _checkOnline();
    return UserProfile(
      name: 'Ada',
      handle: '@ada',
      bio: '',
      steamId: steamId,
      joined: DateTime.utc(2026, 1, 1),
      followers: 0,
      following: 0,
    );
  }

  @override
  Future<UserProfile> fetchProfile(User user) => ensureProfile(user);

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
