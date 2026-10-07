import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:checkpoint/app/nav_tab.dart';
import 'package:checkpoint/data/mock_data.dart';
import 'package:checkpoint/data/mock_social.dart';
import 'package:checkpoint/models/connected_service.dart';
import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/log_entry.dart';
import 'package:checkpoint/models/social_user.dart';
import 'package:checkpoint/models/user_profile.dart';
import 'package:checkpoint/state/library_state.dart';

class CheckpointStore extends ChangeNotifier {
  CheckpointStore({
    required List<Game> games,
    required List<LogEntry> logs,
    required UserProfile profile,
  })  : _games = List.of(games),
        _logs = List.of(logs)..sort((a, b) => b.timestamp.compareTo(a.timestamp)),
        _profile = profile;

  factory CheckpointStore.seeded() {
    final now = DateTime.now();
    final games = MockData.games(now);
    return CheckpointStore(
      games: games,
      logs: MockData.logs(games, now),
      profile: MockData.profile(),
    );
  }

  final List<Game> _games;
  final List<LogEntry> _logs; // always newest-first
  UserProfile _profile;
  int _logSeq = 1000;
  static final _epoch = DateTime.fromMillisecondsSinceEpoch(0);

  // ── navigation ─────────────────────────────────────────────────────────────
  // The store owns both levels of navigation so any widget can drive them:
  //   • currentBottomNavIndex  → which bottom-bar destination is visible (NavTab.*)
  //   • currentLibraryTabIndex → which status tab is open inside My Library
  //                              (index into GameStatus.values, same order as the TabBar)
  int _currentBottomNavIndex = NavTab.home;
  int _currentLibraryTabIndex = 0;

  int get currentBottomNavIndex => _currentBottomNavIndex;
  int get currentLibraryTabIndex => _currentLibraryTabIndex;
  GameStatus get currentLibraryStatus => GameStatus.values[_currentLibraryTabIndex];

  void setBottomNavIndex(int i) {
    if (i == _currentBottomNavIndex) return;
    _currentBottomNavIndex = i;
    notifyListeners();
  }

  /// Called by the Library's TabController when the user taps or swipes a tab,
  /// so the store never goes stale.
  void setLibraryTabIndex(int i) {
    if (i == _currentLibraryTabIndex) return;
    _currentLibraryTabIndex = i;
    notifyListeners();
  }

  /// THE navigation helper for stat cards: switches the bottom bar to My Library
  /// AND selects [status]'s tab, with a single `notifyListeners()`.
  ///
  /// • The platform filter is cleared, because stat-card counts are unfiltered —
  ///   otherwise "To Play 4" could land on a tab showing 1 game.
  /// • [sortBy] (optional) re-sorts high→low, for cards that aren't tied to one
  ///   status (e.g. hours → most-played first). Omit it to keep the current sort.
  void openLibraryTab(GameStatus status, {SortField? sortBy}) {
    _currentBottomNavIndex = NavTab.library;
    _currentLibraryTabIndex = GameStatus.values.indexOf(status);
    _platformFilter = null;
    if (sortBy != null) {
      _sortField = sortBy;
      _sortDescending = true;
    }
    notifyListeners();
  }

  // ── library view preferences ───────────────────────────────────────────────
  LibraryView _libraryView = LibraryView.grid;
  SortField _sortField = SortField.dateAdded;
  bool _sortDescending = true;
  GamePlatform? _platformFilter;

  LibraryView get libraryView => _libraryView;
  SortField get sortField => _sortField;
  bool get sortDescending => _sortDescending;
  GamePlatform? get platformFilter => _platformFilter;

  void setLibraryView(LibraryView v) {
    _libraryView = v;
    notifyListeners();
  }

  /// Picking the active field again flips the direction.
  void setSort(SortField f) {
    if (f == _sortField) {
      _sortDescending = !_sortDescending;
    } else {
      _sortField = f;
      _sortDescending = true;
    }
    notifyListeners();
  }

  void setPlatformFilter(GamePlatform? p) {
    _platformFilter = p;
    notifyListeners();
  }

    // ── auth (mock) ────────────────────────────────────────────────────────────
  bool _isLoggedIn = true; // set false to preview read-only mode
  bool get isLoggedIn => _isLoggedIn;

  void logIn() => _setLoggedIn(true);
  void logOut() => _setLoggedIn(false);

  void _setLoggedIn(bool v) {
    if (v == _isLoggedIn) return;
    _isLoggedIn = v;
    notifyListeners();
  }

  // ── social (mock) ──────────────────────────────────────────────────────────
  final Set<String> _followingIds = {
    for (final u in MockSocial.users)
      if (u.startsFollowed) u.id,
  };

  bool isFollowing(String userId) => _followingIds.contains(userId);
  int get followersCount => _profile.followers;
  int get followingCount => _profile.following + _followingIds.length;

  void toggleFollow(String userId) {
    if (!_isLoggedIn) return;
    if (!_followingIds.remove(userId)) _followingIds.add(userId);
    notifyListeners();
  }

  List<SocialUser> searchUsers(String query) {
    final q = query.trim().toLowerCase();
    return MockSocial.users
        .where((u) => q.isEmpty || '${u.name} ${u.handle}'.toLowerCase().contains(q))
        .toList()
      ..sort((a, b) => b.followers.compareTo(a.followers));
  }

  // Deterministic fake popularity so the Home lists look stable between runs.
  int _seed(Game g) => g.id.codeUnits.fold<int>(7, (s, c) => (s * 31 + c) & 0x7fffffff);

  List<Game> get popularThisMonth {
    final list = List.of(_games)
      ..sort((a, b) => ((_seed(b) * 37) % 101).compareTo((_seed(a) * 37) % 101));
    return list.take(10).toList();
  }

  List<Game> get trendingAmongFriends {
    final list = List.of(_games)
      ..sort((a, b) => ((_seed(b) * 53) % 97).compareTo((_seed(a) * 53) % 97));
    return list.take(10).toList();
  }

  String mockPlayersLabel(Game g) => '${12 + _seed(g) % 88}k playing';
  int mockFriendsPlaying(Game g) => 1 + _seed(g) % 5;

  // ── connected accounts (mock) ──────────────────────────────────────────────
  final Set<ConnectedService> _connected = {ConnectedService.steam};
  bool _isSyncing = false;

  bool get isSyncing => _isSyncing;
  int get connectedCount => _connected.length;
  bool isConnected(ConnectedService s) => _connected.contains(s);

  void toggleService(ConnectedService s) {
    if (!_connected.remove(s)) _connected.add(s);
    notifyListeners();
  }

  /// Mock sync: a 2 s spinner, no real import.
  Future<void> syncLibrary() async {
    if (_isSyncing || _connected.isEmpty) return;
    _isSyncing = true;
    notifyListeners();
    await Future<void>.delayed(const Duration(seconds: 2));
    _isSyncing = false;
    notifyListeners();
  }

  // ── reads ──────────────────────────────────────────────────────────────────
  List<Game> get games => List.unmodifiable(_games);
  UserProfile get profile => _profile;

  Game? maybeGame(String id) {
    for (final g in _games) {
      if (g.id == id) return g;
    }
    return null;
  }

  Game gameById(String id) => maybeGame(id)!;

  bool _matchesPlatform(Game g) {
    final p = _platformFilter;
    if (p == null) return true;
    return g.playedOn == p || (g.playedOn == null && g.platforms.contains(p));
  }

  int _compare(Game a, Game b) {
    final c = switch (_sortField) {
      SortField.dateAdded => (a.dateAdded ?? _epoch).compareTo(b.dateAdded ?? _epoch),
      SortField.rating => a.rating.compareTo(b.rating),
      SortField.hoursPlayed => a.hoursPlayed.compareTo(b.hoursPlayed),
      SortField.releaseYear => a.releaseYear.compareTo(b.releaseYear),
    };
    if (c != 0) return _sortDescending ? -c : c;
    return a.title.compareTo(b.title);
  }

  /// Library list for a tab — respects the active platform filter and sort.
  List<Game> libraryFor(GameStatus s) =>
      _games.where((g) => g.status == s && _matchesPlatform(g)).toList()..sort(_compare);

  /// Unfiltered, most-recently-played first (used by the Home hero).
  List<Game> playingNow() {
    final list = _games.where((g) => g.status == GameStatus.playing).toList();
    list.sort((a, b) => (lastPlayed(b.id) ?? _epoch).compareTo(lastPlayed(a.id) ?? _epoch));
    return list;
  }

  DateTime? lastPlayed(String gameId) {
    for (final l in _logs) {
      if (l.gameId == gameId) return l.timestamp;
    }
    return null;
  }

  List<LogEntry> logsFor(String gameId) => _logs.where((l) => l.gameId == gameId).toList();

  /// Newest session per distinct game.
  List<LogEntry> recentActivity({int limit = 10}) {
    final seen = <String>{};
    final out = <LogEntry>[];
    for (final l in _logs) {
      if (seen.add(l.gameId)) {
        out.add(l);
        if (out.length >= limit) break;
      }
    }
    return out;
  }

  // ── derived stats ──────────────────────────────────────────────────────────
  int count(GameStatus s) => _games.where((g) => g.status == s).length;
  double get totalHours => _games.fold<double>(0, (sum, g) => sum + g.hoursPlayed);

  double get hoursThisWeek {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    return _logs.where((l) => l.timestamp.isAfter(cutoff)).fold<double>(0, (s, l) => s + l.hours);
  }

  double get averageRating {
    final rated = _games.where((g) => g.rating > 0).toList();
    if (rated.isEmpty) return 0;
    return rated.fold<double>(0, (s, g) => s + g.rating) / rated.length;
  }

  Map<GamePlatform, double> get hoursByPlatform {
    final m = <GamePlatform, double>{};
    for (final l in _logs) {
      m[l.platform] = (m[l.platform] ?? 0) + l.hours;
    }
    final entries = m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(entries);
  }

  List<Game> get topRated {
    final rated = _games.where((g) => g.rating > 0).toList()
      ..sort((a, b) {
        final c = b.rating.compareTo(a.rating);
        return c != 0 ? c : b.hoursPlayed.compareTo(a.hoursPlayed);
      });
    return rated.take(8).toList();
  }

  // ── mutations ──────────────────────────────────────────────────────────────
  void _update(String id, Game Function(Game g) change) {
    final i = _games.indexWhere((g) => g.id == id);
    if (i < 0) return;
    _games[i] = change(_games[i]);
    notifyListeners();
  }

  void addToLibrary(String id, GameStatus status) => setStatus(id, status);

  void setStatus(String id, GameStatus status) => _update(
      id, (g) => g.copyWith(status: status, dateAdded: g.dateAdded ?? DateTime.now()));

  void setRating(String id, double rating) => _update(id, (g) => g.copyWith(rating: rating));

  void setPlayedOn(String id, GamePlatform platform) =>
      _update(id, (g) => g.copyWith(playedOn: platform));

  /// 0 (or empty field) clears the price.
  void setPurchasePrice(String id, double price) =>
      _update(id, (g) => g.copyWith(purchasePrice: math.max(0, price)));

  void setWeeklyGoal(double hours) {
    _profile = _profile.copyWith(weeklyGoalHours: hours.clamp(1.0, 120.0).toDouble());
    notifyListeners();
  }

  GameStatus _statusAfterLogging(GameStatus? s) =>
      s == GameStatus.completed ? GameStatus.completed : GameStatus.playing;

  /// Adds a session of [hours] on [platform] (defaults to last/first platform).
  void logSession({
    required String gameId,
    required double hours,
    GamePlatform? platform,
    String note = '',
  }) {
    if (hours <= 0) return;
    final g = gameById(gameId);
    final p = platform ?? g.playedOn ?? g.platforms.first;
    _logs.insert(
      0,
      LogEntry(
        id: 'log-${_logSeq++}',
        gameId: gameId,
        timestamp: DateTime.now(),
        hours: hours,
        platform: p,
        note: note.trim(),
      ),
    );
    _update(
      gameId,
      (cur) => cur.copyWith(
        hoursPlayed: cur.hoursPlayed + hours,
        playedOn: p,
        status: _statusAfterLogging(cur.status),
        dateAdded: cur.dateAdded ?? DateTime.now(),
      ),
    );
  }

  /// "Log Hours" modal: set the new total + target. A positive change is
  /// recorded as a session so activity and platform stats stay consistent.
  void updateTime({
    required String gameId,
    required double totalHours,
    required double targetHours,
    GamePlatform? platform,
    String note = '',
  }) {
    final g = gameById(gameId);
    final delta = totalHours - g.hoursPlayed;
    final p = platform ?? g.playedOn ?? g.platforms.first;
    if (delta > 0.01) {
      _logs.insert(
        0,
        LogEntry(
          id: 'log-${_logSeq++}',
          gameId: gameId,
          timestamp: DateTime.now(),
          hours: delta,
          platform: p,
          note: note.trim(),
        ),
      );
    }
    _update(
      gameId,
      (cur) => cur.copyWith(
        hoursPlayed: totalHours,
        targetHours: targetHours,
        playedOn: platform ?? cur.playedOn,
        status: delta > 0.01 ? _statusAfterLogging(cur.status) : cur.status,
        dateAdded: cur.dateAdded ?? DateTime.now(),
      ),
    );
  }
}
