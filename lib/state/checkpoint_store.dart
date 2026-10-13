import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide SortField;

import 'package:checkpoint/app/nav_tab.dart';
import 'package:checkpoint/services/game_api_service.dart';
import 'package:checkpoint/models/achievement.dart';
import 'package:checkpoint/models/connected_service.dart';
import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/log_entry.dart';
import 'package:checkpoint/models/social_user.dart';
import 'package:checkpoint/models/user_profile.dart';
import 'package:checkpoint/services/auth_service.dart';
import 'package:checkpoint/services/checkpoint_repository.dart';
import 'package:checkpoint/state/library_state.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  // Bumped by every search and by [clearSearch], so a response that arrives
  // after the box was emptied (or after a newer search started) is dropped
  // instead of bringing stale results back.
  int _searchSeq = 0;

  List<String> _recentSearches = [];
  List<String> get recentSearches => List.unmodifiable(_recentSearches);

  static const _maxRecentSearches = 10;

  /// Puts [query] at the top of the recent searches (dropping any earlier copy,
  /// ignoring case) and keeps only the newest [_maxRecentSearches].
  void addRecentSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    _recentSearches
      ..removeWhere((e) => e.toLowerCase() == q.toLowerCase())
      ..insert(0, q);
    if (_recentSearches.length > _maxRecentSearches) {
      _recentSearches.removeRange(_maxRecentSearches, _recentSearches.length);
    }
    notifyListeners();

    // Save recent searches to device
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('recent_searches', _recentSearches);
  }

  Future<void> searchExternalGames(String query) async {
    addRecentSearch(query);
    final seq = ++_searchSeq;
    final results = await _apiService.searchGames(query);
    if (seq != _searchSeq) return;
    _searchResults = results;
    notifyListeners();
  }

  /// Drops the current search results (search box emptied, or the user left
  /// the Search tab) and discards any search still in flight.
  void clearSearch() {
    _searchSeq++;
    if (_searchResults.isEmpty) return;
    _searchResults = [];
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
    followers: 0,
    following: 0,
  );

  Future<void> initialize() async {
    await _loadLocalData();
    _authSubscription = _authService.changes.listen((state) {
      unawaited(_handleAuthUser(state.session?.user));
    });
    await _handleAuthUser(_authService.currentUser);
  }

  Future<void> _loadLocalData() async {
    final prefs = await SharedPreferences.getInstance();
    _steamId = prefs.getString('steam_id');
    _psnId = prefs.getString('psn_id');
    _xboxId = prefs.getString('xbox_id');
    _discordId = prefs.getString('discord_id');
    _recentSearches = List<String>.of(prefs.getStringList('recent_searches') ?? const []);
    
    final savedServices = prefs.getStringList('connected_services') ?? [];
    for (final sName in savedServices) {
      try {
        final service = ConnectedService.values.firstWhere((e) => e.name == sName);
        _connected.add(service);
      } catch (_) {} // Ignore if an enum name changed
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    unawaited(_cancelDataSubscriptions());
    super.dispose();
  }

  Future<void> _handleAuthUser(User? user) async {
    // Token refreshes and pull-to-retry re-enter here for the same user; their
    // already-loaded achievements stay valid, a different user's do not.
    final sameUser = user != null && user.id == _user?.id;
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
        await _refreshSignedInData(user, keepLoadedAchievements: sameUser);
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

  Future<void> _refreshSignedInData(
    User user, {
    bool keepLoadedAchievements = false,
  }) async {
    final fetched = await _repository.fetchUserGames(user.id);
    final userGames = keepLoadedAchievements
        ? _withLoadedAchievements(fetched)
        : fetched;
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

  /// [CheckpointRepository.fetchUserGames] doesn't return achievements, so a
  /// freshly fetched library has `achievements == null` everywhere. Copy over
  /// whatever is already loaded in memory, otherwise every realtime refresh
  /// (a favourite toggled, a rating changed...) would wipe them. Read from
  /// [_libraryGames] at call time so achievements that arrive while a fetch is
  /// in flight are kept too.
  List<Game> _withLoadedAchievements(List<Game> fetched) {
    final loaded = <String, List<Achievement>>{
      for (final g in _libraryGames)
        if (g.achievements != null) g.id: g.achievements!,
    };
    if (loaded.isEmpty) return fetched;
    return [
      for (final g in fetched)
        loaded.containsKey(g.id)
            ? g.copyWith(achievements: loaded[g.id])
            : g,
    ];
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
  Timer? _refreshDebounce;

  Future<void> _refreshCatalogAndLibrary(User user) async {
    if (_pendingSaves > 0) {
      _refreshQueued = true; // Pause refresh until local writes finish
      return;
    }

    // Cancel any waiting refresh, and start a new 300ms countdown.
    // This absorbs "refresh storms" from bulk server inserts into a single UI update.
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        _catalogGames = await _repository.fetchCatalogGames();
        final userGames = _withLoadedAchievements(
          await _repository.fetchUserGames(user.id),
        );
        _libraryGames = List.unmodifiable(userGames);
        _games = List.unmodifiable(
          _mergeCatalogAndUserGames(_catalogGames, userGames),
        );
        notifyListeners();
      } catch (e, st) {
        debugPrint('Library refresh failed: $e\n$st');
      }
    });
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

  /// Selected Library status filter. `null` means "All" (the default).
  GameStatus? _selectedLibraryStatus;

  int get currentBottomNavIndex => _currentBottomNavIndex;

  /// Library tab index: 0 is the "All" tab, then one tab per [GameStatus].
  int get currentLibraryTabIndex => _selectedLibraryStatus == null
      ? 0
      : GameStatus.values.indexOf(_selectedLibraryStatus!) + 1;

  /// Selected Library status, or `null` when "All" is selected.
  GameStatus? get selectedLibraryStatus => _selectedLibraryStatus;

  void setBottomNavIndex(int i) {
    if (i == _currentBottomNavIndex) return;
    _currentBottomNavIndex = i;
    clearSearch();
    notifyListeners();
  }

  void setLibraryTabIndex(int i) {
    final next = i <= 0 ? null : GameStatus.values[i - 1];
    if (next == _selectedLibraryStatus) return;
    _selectedLibraryStatus = next;
    notifyListeners();
  }

  void openLibraryTab(GameStatus status, {SortField? sortBy}) {
    _currentBottomNavIndex = NavTab.library;
    _selectedLibraryStatus = status;
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
  Set<ConnectedService> get connectedServices => Set.unmodifiable(_connected);
  bool isConnected(ConnectedService s) => _connected.contains(s);

  void toggleService(ConnectedService s) async {
    if (!_connected.remove(s)) _connected.add(s);
    notifyListeners();

    // Save connected state to device
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('connected_services', _connected.map((e) => e.name).toList());
  }

  String? _steamId;
  String? get steamId => _steamId;

  void setSteamId(String id) async {
    _steamId = id;
    notifyListeners();
    
    // Save Steam ID to device
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('steam_id', id);
  }

  String? _psnId;
  String? _xboxId;
  String? _discordId;
  String? get psnId => _psnId;
  String? get xboxId => _xboxId;
  String? get discordId => _discordId;

  /// Saves the username for PSN, Xbox or Discord, marks that service as
  /// connected, and persists both the ID and the connected-services list.
  /// Steam keeps using [setSteamId]; Nintendo has no stored ID.
  void setServiceId(ConnectedService service, String id) async {
    final String prefKey;
    switch (service) {
      case ConnectedService.psn:
        _psnId = id;
        prefKey = 'psn_id';
      case ConnectedService.xbox:
        _xboxId = id;
        prefKey = 'xbox_id';
      case ConnectedService.discord:
        _discordId = id;
        prefKey = 'discord_id';
      case ConnectedService.steam || ConnectedService.nintendo:
        debugPrint('setServiceId: ${service.name} has no stored ID.');
        return;
    }
    _connected.add(service);
    notifyListeners();

    // Save the ID and the updated connected list to device
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefKey, id);
    await prefs.setStringList('connected_services', _connected.map((e) => e.name).toList());
  }

  Future<void> syncLibrary() async {
    if (_isSyncing || !isConnected(ConnectedService.steam) || _steamId == null) {
      return;
    }

    _isSyncing = true;
    notifyListeners();

    try {
      final current = _user;
      if (current == null) return;

      final response = await Supabase.instance.client.functions.invoke(
        'sync-steam',
        body: {'steam_id': _steamId},
      );
      
      debugPrint('Steam Sync Complete: ${response.data}');

      // Give the database a brief moment to settle broadcasts
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await _refreshCatalogAndLibrary(current);

    } catch (e) {
      debugPrint('Error syncing Steam library: $e');
      _lastError = 'Could not sync Steam library.';
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  final Set<String> _achievementsLoading = {};

  /// Called when a game's detail page opens. Achievements aren't part of the
  /// library fetch, so if they aren't in memory yet this reads the stored copy
  /// of just that game's `achievements` column and puts it on the local [Game].
  ///
  /// Does nothing when they are already in memory, the game isn't in the
  /// library, or a lookup for it is already running. When the database has
  /// nothing stored (NULL) the game is left with `achievements == null`, which
  /// is the UI's cue to offer "Load Steam Achievements" ([syncGameAchievements]).
  /// Never throws; a failed lookup is logged and treated like "nothing stored".
  ///
  /// Does no notifying before its first `await`, so it is safe to call from
  /// `initState` or right after a frame.
  Future<void> ensureAchievementsLoaded(String gameId) async {
    final current = _user;
    if (current == null) return;
    final game = maybeGame(gameId);
    if (game == null || !game.inLibrary || game.achievements != null) return;
    if (!_achievementsLoading.add(gameId)) return;

    try {
      final stored = await _repository.fetchGameAchievements(current.id, gameId);
      if (stored == null || _user?.id != current.id) return;

      // Re-read the game: a Steam sync may have filled it in while we waited.
      final latest = maybeGame(gameId);
      if (latest == null || latest.achievements != null) return;
      _replaceGame(latest.copyWith(achievements: stored));
    } catch (e, st) {
      debugPrint('Achievements lookup failed for $gameId: $e\n$st');
    } finally {
      _achievementsLoading.remove(gameId);
    }
  }

  /// Loads Steam achievements for a single game on demand (via the
  /// `sync-achievements` Edge Function) and caches them on the local [Game].
  ///
  /// Achievements cost one Steam round trip per game, so they are deliberately
  /// not part of [syncLibrary]. Returns `null` on success, or a message that is
  /// safe to show to the user.
  Future<String?> syncGameAchievements(String gameId) async {
    final steamId = _steamId;
    if (_user == null ||
        steamId == null ||
        !isConnected(ConnectedService.steam)) {
      return 'Connect your Steam account to load achievements.';
    }
    final game = maybeGame(gameId);
    if (game == null) return 'Game not found.';

    try {
      final response = await Supabase.instance.client.functions.invoke(
        'sync-achievements',
        body: {'steam_id': steamId, 'game_id': gameId},
      );
      final data = response.data;
      final achievements =
          data is Map ? Achievement.listFromJson(data['achievements']) : null;
      if (achievements == null) return 'Steam returned an unexpected response.';

      // Re-read the game: it may have changed while the request was in flight.
      _replaceGame((maybeGame(gameId) ?? game).copyWith(achievements: achievements));
      return null;
    } on FunctionException catch (e) {
      debugPrint('Achievements sync failed (${e.status}): ${e.details}');
      // The Edge Function sends actionable messages (e.g. private profile).
      final details = e.details;
      final message = details is Map ? details['error'] : null;
      return message is String && message.isNotEmpty
          ? message
          : 'Could not load Steam achievements.';
    } catch (e) {
      debugPrint('Achievements sync failed: $e');
      return 'Could not load Steam achievements.';
    }
  }

  // ---- Steam title cleanup so IGDB can match the base game ----------------
  static final RegExp _trademarkRe = RegExp(r'[™®©]');
  static final RegExp _colonNoSpaceRe = RegExp(r':(?=\p{L})', unicode: true);
  static final RegExp _separatorsRe = RegExp(r'[:\-–—]');
  static final RegExp _apostropheRe = RegExp(r"['’]");

  // "Title (Deluxe Edition)" / "Title [Director's Cut]"
  static final RegExp _bracketedEditionRe = RegExp(
    r"\s*[\(\[][^\)\]]*\b(?:edition|director['’]?s\s+cut)\b[^\)\]]*[\)\]]",
    caseSensitive: false,
  );

  // "Title - Complete Edition"
  static final RegExp _dashedEditionRe = RegExp(
    r"\s+[-–—]\s+[^-–—]*\b(?:edition|director['’]?s\s+cut)\b.*$",
    caseSensitive: false,
  );

  // "Title Special Edition", "Title: Game of the Year Edition"
  static final RegExp _trailingEditionRe = RegExp(
    r"\s*:?\s*(?:(?:game\s+of\s+the\s+year|goty|definitive|complete|enhanced|deluxe|ultimate|gold|special|anniversary|collector['’]?s|legendary|standard|premium|extended|digital)\s+)*(?:edition|director['’]?s\s+cut)\b.*$",
    caseSensitive: false,
  );

  static final RegExp _spacesRe = RegExp(r'\s+');
  static final RegExp _danglingRe = RegExp(r'[\s\-–—:]+$');

  static String _cleanSteamTitle(String raw) {
    final stripped = raw
        .replaceAll(_trademarkRe, '')
        .replaceAllMapped(_colonNoSpaceRe, (_) => ': ')
        .replaceAll(_spacesRe, ' ')
        .trim();
    final cleaned = stripped
        .replaceAll(_bracketedEditionRe, '')
        .replaceAll(_dashedEditionRe, '')
        .replaceAll(_trailingEditionRe, '')
        .replaceAll(_danglingRe, '')
        .trim();
    // Never search for an empty string (e.g. a game literally named "Edition").
    return cleaned.isEmpty ? stripped : cleaned;
  }

  /// Colons and hyphens -> spaces, apostrophes removed, whitespace collapsed.
  static String _stripPunctuation(String s) => s
      .replaceAll(_apostropheRe, '')
      .replaceAll(_separatorsRe, ' ')
      .replaceAll(_spacesRe, ' ')
      .trim();

  /// Returns `null` when IGDB has no match or the lookup fails, so callers can
  /// skip the title instead of saving placeholder data.
  Future<Game?> _enrichGame(String gameId, String title, double hoursPlayed) async {
    final cleanTitle = _cleanSteamTitle(title);
    try {
      var igdbResults = await _apiService.searchGames(cleanTitle);
      
      // Second chance: retry with punctuation stripped if initial search fails
      if (igdbResults.isEmpty) {
        final looseTitle = _stripPunctuation(cleanTitle);
        if (looseTitle.isNotEmpty && looseTitle != cleanTitle) {
          debugPrint('No IGDB match for "$cleanTitle", retrying as "$looseTitle"');
          await Future<void>.delayed(const Duration(milliseconds: 300));
          igdbResults = await _apiService.searchGames(looseTitle);
        }
      }

      if (igdbResults.isEmpty) {
        debugPrint('No IGDB match for "$cleanTitle" (Steam title: "$title")');
        return null;
      }

      // Prioritize exact name matches to stop sequels (PoE 2) from overriding the original
      final targetTitle = cleanTitle.toLowerCase();
      final igdbGame = igdbResults.firstWhere(
        (g) => g.title.toLowerCase() == targetTitle,
        orElse: () => igdbResults.first,
      );
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
    } catch (e) {
      debugPrint('IGDB lookup failed for "$cleanTitle" (Steam title: "$title"): $e');
      return null;
    }
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

  /// Library games for [s]; pass `null` for every status ("All").
  /// The platform filter applies either way.
  List<Game> libraryFor(GameStatus? s) =>
      _libraryGames
          .where((g) => (s == null || g.status == s) && _matchesPlatform(g))
          .toList()
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

  /// Total hours per platform, based on each game's total playtime (so hours
  /// imported via Steam sync count too, not just manually logged sessions).
  Map<GamePlatform, double> get hoursByPlatform {
    final m = <GamePlatform, double>{};
    for (final g in _libraryGames) {
      if (g.hoursPlayed <= 0) continue;
      final platform =
          g.playedOn ??
          (g.platforms.isNotEmpty ? g.platforms.first : GamePlatform.pc);
      m[platform] = (m[platform] ?? 0) + g.hoursPlayed;
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

  static String _normalizeHandle(String handle) =>
      handle.trim().replaceFirst(RegExp(r'^@+'), '').toLowerCase();

  /// Whether [handle] (with or without the leading "@") is free for the
  /// signed-in user. Case-insensitive; the user's own current handle counts as
  /// available. Throws if signed out or if the lookup fails, so callers can
  /// decide how to degrade (the unique constraint still guards the save).
  Future<bool> isHandleAvailable(String handle) {
    final current = _user;
    if (current == null) {
      throw StateError('Sign in to check username availability.');
    }
    return _repository.isHandleAvailable(_normalizeHandle(handle), current.id);
  }

  /// Uploads [image] to the avatars bucket and returns its public URL. This
  /// doesn't touch the profile; pass the URL to [updateProfile] to save it.
  Future<String> uploadAvatar(XFile image) => _repository.uploadAvatar(image);

  /// Updates the signed-in user's display name, handle (without the leading
  /// "@"), bio and avatar. A null [bio] or [avatarUrl] leaves that field as is.
  /// Returns null on success, or a user-facing error message.
  Future<String?> updateProfile({
    required String name,
    required String handle,
    String? bio,
    String? avatarUrl,
  }) async {
    final current = _user;
    if (current == null) return 'Sign in to edit your profile.';

    final nextName = name.trim();
    final nextHandle = _normalizeHandle(handle);
    final nextBio = bio?.trim();
    if (nextName.isEmpty || nextHandle.isEmpty) {
      return 'Display name and username can\'t be empty.';
    }

    final currentHandle = _profile.handle.replaceFirst(RegExp(r'^@+'), '');
    final unchanged =
        nextName == _profile.name &&
        nextHandle == currentHandle &&
        (nextBio == null || nextBio == _profile.bio) &&
        (avatarUrl == null || avatarUrl == _profile.avatarUrl);
    if (unchanged) return null;

    try {
      await _repository.updateProfile(
        name: nextName,
        handle: nextHandle,
        bio: nextBio,
        avatarUrl: avatarUrl,
      );

      // Optimistically update local profile state and trigger instant UI re-render
      _profile = _profile.copyWith(
        name: nextName,
        handle: '@$nextHandle',
        bio: nextBio,
        avatarUrl: avatarUrl ?? _profile.avatarUrl,
      );
      notifyListeners();

      await _refreshProfile(current);
      return null;
    } on PostgrestException catch (e, st) {
      debugPrint('Profile update failed: $e\n$st');
      if (e.code == '23505') return 'That username is already taken.';
      return 'Could not save your profile. Please try again.';
    } catch (e, st) {
      debugPrint('Profile update failed: $e\n$st');
      return 'Could not save your profile. Please try again.';
    }
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
    final p = platform ?? g.playedOn ?? (g.platforms.isNotEmpty ? g.platforms.first : GamePlatform.pc);
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
    GamePlatform? platform,
    String note = '',
  }) async {
    final current = _user;
    if (current == null) return;
    final g = gameById(gameId);
    final delta = totalHours - g.hoursPlayed;
    final p = platform ?? g.playedOn ?? (g.platforms.isNotEmpty ? g.platforms.first : GamePlatform.pc);
    final next = g.copyWith(
      hoursPlayed: totalHours,
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