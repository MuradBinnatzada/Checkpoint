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
  Completer<void>? gate;
  int libraryFetches = 0;

  void _checkOnline() {
    if (offline) throw Exception('network down');
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
      joined: DateTime.utc(2026, 1, 1),
      followers: 0,
      following: 0,
    );
  }

  @override
  Future<UserProfile> fetchProfile(User user) => ensureProfile(user);

  @override
  Future<Set<String>> fetchFollowingIds(String userId) async {
    _checkOnline();
    return {'friend-1'};
  }

  @override
  Future<int> fetchFollowersCount(String userId) async {
    _checkOnline();
    return 3;
  }

  @override
  Future<void> deleteUserGame(String userId, String gameId) async {
    _checkOnline();
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
    _checkOnline();
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
  final _changes = StreamController<AuthState>.broadcast();

  @override
  User? get currentUser => user;

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
