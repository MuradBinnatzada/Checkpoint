import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide SortField;

import 'package:checkpoint/app/nav_tab.dart';
import 'package:checkpoint/services/game_api_service.dart';
import 'package:checkpoint/models/connected_service.dart';
import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/log_entry.dart';
import 'package:checkpoint/models/social_user.dart';
import 'package:checkpoint/models/user_profile.dart';
import 'package:checkpoint/services/auth_service.dart';
import 'package:checkpoint/services/checkpoint_repository.dart';
import 'package:checkpoint/state/library_state.dart';
import 'package:flutter/material.dart';

class CheckpointStore extends ChangeNotifier {
  CheckpointStore({
    required CheckpointRepository repository,
    required AuthService authService,
  }) : this._(repository, authService);

  CheckpointStore._(this._repository, this._authService)
    : _profile = _guestProfile();

  factory CheckpointStore.supabase(SupabaseClient client) {
    return CheckpointStore(
      repository: CheckpointRepository(client),
      authService: AuthService(client),
    );
  }

  final CheckpointRepository _repository;
  final AuthService _authService;

  final GameApiService _apiService = GameApiService();
  List<Game> _searchResults = [];
  List<Game> get searchResults => _searchResults;

  Future<void> searchExternalGames(String query) async {
    _searchResults = await _apiService.searchGames(query);
    notifyListeners();
  }

  User? _user;
  UserProfile _profile;
  List<Game> _catalogGames = const [];
  List<Game> _games = const [];
  List<Game> _libraryGames = const [];
  List<LogEntry> _logs = const [];
  List<SocialUser> _socialUsers = const [];
  Set<String> _followingIds = {};
  int _followersCount = 0;
  bool _isLoading = true;
  String? _lastError;
  StreamSubscription<AuthState>? _authSubscription;
  final List<StreamSubscription<dynamic>> _dataSubscriptions = [];

  static final _epoch = DateTime.fromMillisecondsSinceEpoch(0);

  static UserProfile _guestProfile() => UserProfile(
    name: 'Player',
    handle: '@guest',
    bio: '',
    joined: DateTime.now(),
    weeklyGoalHours: 20,
    followers: 0,
    following: 0,
  );

  Future<void> initialize() async {
    _authSubscription = _authService.changes.listen((state) {
      unawaited(_handleAuthUser(state.session?.user));
    });
    await _handleAuthUser(_authService.currentUser);
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    unawaited(_cancelDataSubscriptions());
    super.dispose();
  }

  Future<void> _handleAuthUser(User? user) async {
    _user = user;
    _isLoading = true;
    _lastError = null;
    notifyListeners();

    await _cancelDataSubscriptions();

    try {
      _catalogGames = await _repository.fetchCatalogGames();
      if (user == null) {
        _profile = _guestProfile();
        _games = List.unmodifiable(_catalogGames);
        _libraryGames = const [];
        _logs = const [];
        _socialUsers = const [];
        _followingIds = {};
        _followersCount = 0;
        _startPublicSubscriptions();
      } else {
        await _authService.ensureProfile(user);
        _profile = await _repository.ensureProfile(user);
        await _refreshSignedInData(user);
        _startSignedInSubscriptions(user);
      }
    } catch (e, st) {
      debugPrint('Supabase load failed: $e\n$st');
      _lastError =
          'Could not load Checkpoint data. Pull to retry or sign in again.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _refreshSignedInData(User user) async {
    final userGames = await _repository.fetchUserGames(user.id);
    _libraryGames = List.unmodifiable(userGames);
    _games = List.unmodifiable(
      _mergeCatalogAndUserGames(_catalogGames, userGames),
    );
    _logs = List.unmodifiable(await _repository.fetchLogEntries(user.id));
    _socialUsers = List.unmodifiable(
      await _repository.fetchSocialUsers(user.id),
    );
    _followingIds = await _repository.fetchFollowingIds(user.id);
    _followersCount = await _repository.fetchFollowersCount(user.id);
  }

  Future<void> removeFromLibrary(String id) async {
    final current = _user;
    if (current == null) return;

    // Remove from local library list
    _libraryGames = List.unmodifiable(_libraryGames.where((g) => g.id != id));
    
    // Find the catalog version of the game and reset its status
    final game = gameById(id);
    final catalogById = <String, Game>{for (final g in _games) g.id: g};
    // Revert to a clean catalog state (stripping status, rating, hours)
    catalogById[id] = game.copyWith(
      hoursPlayed: 0,
      targetHours: 0,
      rating: 0,
    ); // Note: You may need to manually set status to null if your copyWith ignores nulls

    _games = List.unmodifiable(catalogById.values.toList()..sort((a, b) => a.title.compareTo(b.title)));
    notifyListeners();

    try {
      await _repository.deleteUserGame(current.id, id);
    } catch (e) {
      debugPrint('Delete failed: $e');
    }
  }

  Future<void> toggleFavorite(String id) async {
    final game = gameById(id);
    final isCurrentlyFavorite = game.isFavorite;

    // Enforce Top 4 Limit
    final currentFavorites = _libraryGames.where((g) => g.isFavorite).length;
    if (!isCurrentlyFavorite && currentFavorites >= 4) {
      _lastError = 'You can only have 4 favorite games.';
      notifyListeners();
      return;
    }

    final next = game.copyWith(isFavorite: !isCurrentlyFavorite);
    _replaceGame(next);
    await _saveUserGame(next);
  }

  List<Game> _mergeCatalogAndUserGames(
    List<Game> catalog,
    List<Game> userGames,
  ) {
    final byId = <String, Game>{for (final game in catalog) game.id: game};
    for (final game in userGames) {
      byId[game.id] = game;
    }
    final merged = byId.values.toList()
      ..sort((a, b) => a.title.compareTo(b.title));
    return merged;
  }

  void _startPublicSubscriptions() {
    _dataSubscriptions.add(
      _repository.watchCatalogGames().listen((_) async {
        await _refreshCatalogOnly();
      }),
    );
  }

  void _startSignedInSubscriptions(User user) {
    _dataSubscriptions
      ..add(
        _repository.watchCatalogGames().listen(
          (_) async => _refreshCatalogAndLibrary(user),
        ),
      )
      ..add(
        _repository
            .watchUserGames(user.id)
            .listen((_) async => _refreshCatalogAndLibrary(user)),
      )
      ..add(
        _repository
            .watchLogEntries(user.id)
            .listen((_) async => _refreshLogs(user.id)),
      )
      ..add(
        _repository
            .watchProfile(user.id)
            .listen((_) async => _refreshProfile(user)),
      )
      ..add(
        _repository
            .watchFollows(user.id)
            .listen((_) async => _refreshSocial(user.id)),
      );
  }

  Future<void> _cancelDataSubscriptions() async {
    for (final subscription in _dataSubscriptions) {
      await subscription.cancel();
    }
    _dataSubscriptions.clear();
  }

  Future<void> _refreshCatalogOnly() async {
    try {
      _catalogGames = await _repository.fetchCatalogGames();
      if (_user == null) _games = List.unmodifiable(_catalogGames);
      notifyListeners();
    } catch (e, st) {
      debugPrint('Catalog refresh failed: $e\n$st');
    }
  }

  int _pendingSaves = 0;
  bool _refreshQueued = false;

  Future<void> _refreshCatalogAndLibrary(User user) async {
    if (_pendingSaves > 0) {
      _refreshQueued = true; // Pause refresh until local writes finish
      return;
    }
    try {
      _catalogGames = await _repository.fetchCatalogGames();
      final userGames = await _repository.fetchUserGames(user.id);
      _libraryGames = List.unmodifiable(userGames);
      _games = List.unmodifiable(
        _mergeCatalogAndUserGames(_catalogGames, userGames),
      );
      notifyListeners();
    } catch (e, st) {
      debugPrint('Library refresh failed: $e\n$st');
    }
  }

  Future<void> _refreshLogs(String userId) async {
    try {
      _logs = List.unmodifiable(await _repository.fetchLogEntries(userId));
      notifyListeners();
    } catch (e, st) {
      debugPrint('Log refresh failed: $e\n$st');
    }
  }

  Future<void> _refreshProfile(User user) async {
    try {
      _profile = await _repository.fetchProfile(user);
      notifyListeners();
    } catch (e, st) {
      debugPrint('Profile refresh failed: $e\n$st');
    }
  }

  Future<void> _refreshSocial(String userId) async {
    try {
      _socialUsers = List.unmodifiable(
        await _repository.fetchSocialUsers(userId),
      );
      _followingIds = await _repository.fetchFollowingIds(userId);
      _followersCount = await _repository.fetchFollowersCount(userId);
      notifyListeners();
    } catch (e, st) {
      debugPrint('Social refresh failed: $e\n$st');
    }
  }

  int _currentBottomNavIndex = NavTab.home;
  int _currentLibraryTabIndex = 0;

  int get currentBottomNavIndex => _currentBottomNavIndex;
  int get currentLibraryTabIndex => _currentLibraryTabIndex;
  GameStatus get currentLibraryStatus =>
      GameStatus.values[_currentLibraryTabIndex];

  void setBottomNavIndex(int i) {
    if (i == _currentBottomNavIndex) return;
    _currentBottomNavIndex = i;
    notifyListeners();
  }

  void setLibraryTabIndex(int i) {
    if (i == _currentLibraryTabIndex) return;
    _currentLibraryTabIndex = i;
    notifyListeners();
  }

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

  bool get isLoggedIn => _user != null;
  bool get isLoading => _isLoading;
  String? get lastError => _lastError;

  Future<void> refresh() => _handleAuthUser(_user);

  Future<void> signInWithEmail(String email, String password) =>
      _authService.signInWithEmail(email, password);

  Future<bool> signUpWithEmail(
    String email,
    String password, {
    String? displayName,
  }) => _authService.signUpWithEmail(email, password, displayName: displayName);

  Future<void> signInWithGoogle() => _authService.signInWithGoogle();

  Future<void> logIn() => signInWithGoogle();

  Future<void> logOut() => _authService.signOut();

  String authMessageFor(Object e) => AuthService.messageFor(e);

  bool isFollowing(String userId) => _followingIds.contains(userId);
  int get followersCount => _followersCount;
  int get followingCount => _followingIds.length;

  Future<void> toggleFollow(String userId) async {
    final current = _user;
    if (current == null) return;
    final wasFollowing = _followingIds.contains(userId);
    if (wasFollowing) {
      _followingIds = {..._followingIds}..remove(userId);
    } else {
      _followingIds = {..._followingIds, userId};
    }
    notifyListeners();

    try {
      if (wasFollowing) {
        await _repository.unfollow(followerId: current.id, followeeId: userId);
      } else {
        await _repository.follow(followerId: current.id, followeeId: userId);
      }
      await _refreshSocial(current.id);
    } catch (e, st) {
      debugPrint('Follow update failed: $e\n$st');
      await _refreshSocial(current.id);
    }
  }

  List<SocialUser> searchUsers(String query) {
    final q = query.trim().toLowerCase();
    return _socialUsers
        .where(
          (u) => q.isEmpty || '${u.name} ${u.handle}'.toLowerCase().contains(q),
        )
        .toList()
      ..sort((a, b) => b.followers.compareTo(a.followers));
  }

  int _seed(Game g) =>
      g.id.codeUnits.fold<int>(7, (s, c) => (s * 31 + c) & 0x7fffffff);

  List<Game> get popularThisMonth {
    final list = List.of(
      _catalogGames,
    )..sort((a, b) => ((_seed(b) * 37) % 101).compareTo((_seed(a) * 37) % 101));
    return list.take(10).toList();
  }

  List<Game> get trendingAmongFriends {
    final list = List.of(_libraryGames)
      ..sort((a, b) => ((_seed(b) * 53) % 97).compareTo((_seed(a) * 53) % 97));
    if (list.isEmpty) return popularThisMonth;
    return list.take(10).toList();
  }

  String playersLabel(Game g) => '${12 + _seed(g) % 88}k players';
  int friendsPlaying(Game g) => 1 + _seed(g) % 5;

  final Set<ConnectedService> _connected = {};
  bool _isSyncing = false;

  bool get isSyncing => _isSyncing;
  int get connectedCount => _connected.length;
  bool isConnected(ConnectedService s) => _connected.contains(s);

  void toggleService(ConnectedService s) {
    if (!_connected.remove(s)) _connected.add(s);
    notifyListeners();
  }

  String? _steamId;

  void setSteamId(String id) {
    _steamId = id;
    notifyListeners();
  }

  Future<void> syncLibrary() async {
    if (_isSyncing || !isConnected(ConnectedService.steam) || _steamId == null) {
      return;
    }

    _isSyncing = true;
    notifyListeners();

    try {
      final response = await Supabase.instance.client.functions.invoke(
        'sync-steam',
        body: {'steam_id': _steamId},
      );

      final data = response.data as Map<String, dynamic>;
      final List<dynamic> rawGames = data['games'] ?? [];
      final current = _user;

      // Non-game software that Steam lists alongside games. Word boundaries
      // keep short terms like "obs" from matching titles such as "Observer".
      final junkFilter = RegExp(
        r'\b(?:blender|wallpaper engine|soundpad|aseprite|obs|3dmark)\b',
        caseSensitive: false,
      );

      if (current != null) {
        for (final raw in rawGames) {
          final String title = raw['name'] ?? '';
          final int playtimeMinutes = raw['playtime_forever'] ?? 0;
          final double hoursPlayed = (playtimeMinutes / 60.0);

          if (title.isEmpty) continue;
          if (junkFilter.hasMatch(title)) continue;

          final appId = raw['appid'].toString();
          // Keep the deterministic UUID so Postgres is happy and we avoid duplicates
          final gameId = '57e40000-0000-0000-0000-${appId.padLeft(12, '0')}';

          final game = await _enrichGame(gameId, title, hoursPlayed);

          // Throttle the bulk sync so IGDB doesn't rate-limit the lookups.
          // Runs before the null check so unmatched titles are throttled too.
          await Future<void>.delayed(const Duration(milliseconds: 300));

          // No IGDB match (or lookup failed): skip rather than save a stub.
          if (game == null) continue;

          await _saveUserGame(game);
        }
        await _refreshCatalogAndLibrary(current);
      }
    } catch (e) {
      debugPrint('Error syncing Steam library: $e');
      _lastError = 'Could not sync Steam library.';
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  // ---- Steam title cleanup so IGDB can match the base game ----------------
  static final RegExp _trademarkRe = RegExp(r'[™®©]');

  // "Title (Deluxe Edition)" / "Title [Director's Cut]"
  static final RegExp _bracketedEditionRe = RegExp(
    r"\s*[\(\[][^\)\]]*\b(?:edition|director['’]?s\s+cut)\b[^\)\]]*[\)\]]",
    caseSensitive: false,
  );

  // "Title - Complete Edition". Dash-separated only, so real subtitles after
  // a colon ("The Witcher 3: Wild Hunt") are left alone.
  static final RegExp _dashedEditionRe = RegExp(
    r"\s+[-–—]\s+[^-–—]*\b(?:edition|director['’]?s\s+cut)\b.*$",
    caseSensitive: false,
  );

  // "Title Special Edition", "Title: Game of the Year Edition", "Title Director's Cut"
  static final RegExp _trailingEditionRe = RegExp(
    r"\s*:?\s*(?:(?:game\s+of\s+the\s+year|goty|definitive|complete|enhanced|deluxe|ultimate|gold|special|anniversary|collector['’]?s|legendary|standard|premium|extended|digital)\s+)*(?:edition|director['’]?s\s+cut)\b.*$",
    caseSensitive: false,
  );

  static final RegExp _spacesRe = RegExp(r'\s+');
  static final RegExp _danglingRe = RegExp(r'[\s\-–—:]+$');

  static String _cleanSteamTitle(String raw) {
    final stripped =
        raw.replaceAll(_trademarkRe, '').replaceAll(_spacesRe, ' ').trim();
    final cleaned = stripped
        .replaceAll(_bracketedEditionRe, '')
        .replaceAll(_dashedEditionRe, '')
        .replaceAll(_trailingEditionRe, '')
        .replaceAll(_danglingRe, '')
        .trim();
    // Never search for an empty string (e.g. a game literally named "Edition").
    return cleaned.isEmpty ? stripped : cleaned;
  }

  /// Returns `null` when IGDB has no match or the lookup fails, so callers can
  /// skip the title instead of saving placeholder data.
  Future<Game?> _enrichGame(String gameId, String title, double hoursPlayed) async {
    final cleanTitle = _cleanSteamTitle(title);
    try {
      final igdbResults = await _apiService.searchGames(cleanTitle);
      if (igdbResults.isEmpty) {
        debugPrint('No IGDB match for "$cleanTitle" (Steam title: "$title")');
      } else {
        final igdbGame = igdbResults.first;
        // Map IGDB data to a new Game object while injecting our Steam ID and hours
        return Game(
          id: gameId,
          title: igdbGame.title,
          publisher: igdbGame.publisher,
          developer: igdbGame.developer,
          releaseYear: igdbGame.releaseYear,
          platforms: igdbGame.platforms,
          genres: igdbGame.genres,
          synopsis: igdbGame.synopsis,
          coverColors: igdbGame.coverColors,
          coverIcon: igdbGame.coverIcon,
          coverUrl: igdbGame.coverUrl,
          hoursPlayed: hoursPlayed,
          status: GameStatus.playing,
          playedOn: GamePlatform.pc,
          dateAdded: DateTime.now(),
        );
      }
    } catch (e) {
      debugPrint('IGDB lookup failed for "$cleanTitle" (Steam title: "$title"): $e');
    }

    // IGDB found nothing or the lookup failed: no fallback game.
    return null;
  }

  List<Game> get games => List.unmodifiable(_games);
  List<Game> get libraryGames => List.unmodifiable(_libraryGames);
  UserProfile get profile => _profile;

  Game? maybeGame(String id) {
    for (final g in _libraryGames) {
      if (g.id == id) return g;
    }
    for (final g in _games) {
      if (g.id == id) return g;
    }
    for (final g in _searchResults) {
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
      SortField.dateAdded => (a.dateAdded ?? _epoch).compareTo(
        b.dateAdded ?? _epoch,
      ),
      SortField.rating => a.rating.compareTo(b.rating),
      SortField.hoursPlayed => a.hoursPlayed.compareTo(b.hoursPlayed),
      SortField.releaseYear => a.releaseYear.compareTo(b.releaseYear),
    };
    if (c != 0) return _sortDescending ? -c : c;
    return a.title.compareTo(b.title);
  }

  List<Game> libraryFor(GameStatus s) =>
      _libraryGames.where((g) => g.status == s && _matchesPlatform(g)).toList()
        ..sort(_compare);

  List<Game> playingNow() {
    final list = _libraryGames
        .where((g) => g.status == GameStatus.playing)
        .toList();
    list.sort(
      (a, b) =>
          (lastPlayed(b.id) ?? _epoch).compareTo(lastPlayed(a.id) ?? _epoch),
    );
    return list;
  }

  DateTime? lastPlayed(String gameId) {
    for (final l in _logs) {
      if (l.gameId == gameId) return l.timestamp;
    }
    return null;
  }

  List<LogEntry> logsFor(String gameId) =>
      _logs.where((l) => l.gameId == gameId).toList();

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

  int count(GameStatus s) => _libraryGames.where((g) => g.status == s).length;
  double get totalHours =>
      _libraryGames.fold<double>(0, (sum, g) => sum + g.hoursPlayed);

  double get hoursThisWeek {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    return _logs
        .where((l) => l.timestamp.isAfter(cutoff))
        .fold<double>(0, (s, l) => s + l.hours);
  }

  double get averageRating {
    final rated = _libraryGames.where((g) => g.rating > 0).toList();
    if (rated.isEmpty) return 0;
    return rated.fold<double>(0, (s, g) => s + g.rating) / rated.length;
  }

  Map<GamePlatform, double> get hoursByPlatform {
    final m = <GamePlatform, double>{};
    for (final l in _logs) {
      m[l.platform] = (m[l.platform] ?? 0) + l.hours;
    }
    final entries = m.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(entries);
  }

  List<Game> get topRated {
    final rated = _libraryGames.where((g) => g.rating > 0).toList()
      ..sort((a, b) {
        final c = b.rating.compareTo(a.rating);
        return c != 0 ? c : b.hoursPlayed.compareTo(a.hoursPlayed);
      });
    return rated.take(8).toList();
  }

  Future<void> addToLibrary(String id, GameStatus status) =>
      setStatus(id, status);

  Future<void> setStatus(String id, GameStatus status) async {
    final game = gameById(id);
    final next = game.copyWith(
      status: status,
      dateAdded: game.dateAdded ?? DateTime.now(),
    );
    _replaceGame(next);
    await _saveUserGame(next);
  }

  Future<void> setRating(String id, double rating) async {
    final game = gameById(id);
    final next = game.copyWith(
      status: game.status ?? GameStatus.playing,
      rating: rating,
      dateAdded: game.dateAdded ?? DateTime.now(),
    );
    _replaceGame(next);
    await _saveUserGame(next);
  }

  Future<void> setPlayedOn(String id, GamePlatform platform) async {
    final game = gameById(id);
    final next = game.copyWith(
      status: game.status ?? GameStatus.playing,
      playedOn: platform,
      dateAdded: game.dateAdded ?? DateTime.now(),
    );
    _replaceGame(next);
    await _saveUserGame(next);
  }

  Future<void> setPurchasePrice(String id, double price) async {
    final game = gameById(id);
    final next = game.copyWith(
      status: game.status ?? GameStatus.playing,
      purchasePrice: math.max(0, price),
      dateAdded: game.dateAdded ?? DateTime.now(),
    );
    _replaceGame(next);
    await _saveUserGame(next);
  }

  Future<void> setWeeklyGoal(double hours) async {
    final current = _user;
    if (current == null) return;
    final clamped = hours.clamp(1.0, 120.0).toDouble();
    _profile = _profile.copyWith(weeklyGoalHours: clamped);
    notifyListeners();
    await _repository.updateWeeklyGoal(current.id, clamped);
  }

  GameStatus _statusAfterLogging(GameStatus? s) =>
      s == GameStatus.completed ? GameStatus.completed : GameStatus.playing;

  Future<void> logSession({
    required String gameId,
    required double hours,
    GamePlatform? platform,
    String note = '',
  }) async {
    if (hours <= 0) return;
    final current = _user;
    if (current == null) return;
    final g = gameById(gameId);
    final p = platform ?? g.playedOn ?? g.platforms.first;
    final next = g.copyWith(
      hoursPlayed: g.hoursPlayed + hours,
      playedOn: p,
      status: _statusAfterLogging(g.status),
      dateAdded: g.dateAdded ?? DateTime.now(),
    );
    _replaceGame(next);
    _logs = [
      LogEntry(
        id: 'local-${DateTime.now().microsecondsSinceEpoch}',
        gameId: gameId,
        timestamp: DateTime.now(),
        hours: hours,
        platform: p,
        note: note.trim(),
      ),
      ..._logs,
    ];
    notifyListeners();

    await _saveUserGame(next);
    await _repository.insertLogEntry(
      userId: current.id,
      gameId: gameId,
      hours: hours,
      platform: p,
      note: note,
    );
    await _refreshLogs(current.id);
  }

  Future<void> updateTime({
    required String gameId,
    required double totalHours,
    required double targetHours,
    GamePlatform? platform,
    String note = '',
  }) async {
    final current = _user;
    if (current == null) return;
    final g = gameById(gameId);
    final delta = totalHours - g.hoursPlayed;
    final p = platform ?? g.playedOn ?? g.platforms.first;
    final next = g.copyWith(
      hoursPlayed: totalHours,
      targetHours: targetHours,
      playedOn: platform ?? g.playedOn,
      status: delta > 0.01
          ? _statusAfterLogging(g.status)
          : (g.status ?? GameStatus.playing),
      dateAdded: g.dateAdded ?? DateTime.now(),
    );
    _replaceGame(next);
    await _saveUserGame(next);

    if (delta > 0.01) {
      await _repository.insertLogEntry(
        userId: current.id,
        gameId: gameId,
        hours: delta,
        platform: p,
        note: note,
      );
      await _refreshLogs(current.id);
    }
  }

  void _replaceGame(Game next) {
    // Unconditionally update or add to the library list
    final libraryById = <String, Game>{
      for (final game in _libraryGames) game.id: game,
    };
    libraryById[next.id] = next;
    _libraryGames = List.unmodifiable(
      libraryById.values.toList()..sort((a, b) => a.title.compareTo(b.title)),
    );

    // Unconditionally update the main catalog list
    final catalogById = <String, Game>{
      for (final game in _games) game.id: game,
    };
    catalogById[next.id] = next;
    _games = List.unmodifiable(
      catalogById.values.toList()..sort((a, b) => a.title.compareTo(b.title)),
    );
    
    notifyListeners();
  }

  Future<void> _saveUserGame(Game game) async {
    final current = _user;
    if (current == null || game.status == null) return;
    
    _pendingSaves++;
    
    try {
      // Optimization: Only upsert to the global catalog if it's a brand new game
      if (!_catalogGames.any((g) => g.id == game.id)) {
        await _repository.upsertBaseGame(game);
      }

      await _repository.upsertUserGame(
        userId: current.id,
        gameId: game.id,
        status: game.status!,
        rating: game.rating,
        hoursPlayed: game.hoursPlayed,
        targetHours: game.targetHours,
        playedOn: game.playedOn,
        purchasePrice: game.purchasePrice,
        dateAdded: game.dateAdded,
        isFavorite: game.isFavorite,
      );
    } catch (e, st) {
      debugPrint('User game save failed: $e\n$st');
      _lastError = 'Could not save that game update.';
      _refreshQueued = true; // Revert to server truth once writes settle
    } finally {
      _pendingSaves--;
      if (_pendingSaves == 0 && _refreshQueued) {
        _refreshQueued = false;
        await _refreshCatalogAndLibrary(current);
      }
    }
  }
}