import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:checkpoint/models/achievement.dart';
import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/log_entry.dart';
import 'package:checkpoint/services/checkpoint_repository.dart';
import 'package:checkpoint/services/local_cache.dart';
import 'package:checkpoint/state/auth_store.dart';
import 'package:checkpoint/state/profile_store.dart';

/// The signed-in user's games and play sessions, plus the catalog slice behind
/// the Home carousels. Reloads when the account changes.
///
/// Opening the app paints the copy saved on the device first ([LocalCache]), then
/// refreshes from the server. When the server can't be reached the saved copy
/// stays on screen and [isOffline] turns on; only an account with nothing saved
/// gets [loadError]. Edits are not queued offline: they apply locally, fail to
/// save, and the next successful refresh brings back what the server has.
class LibraryStore extends ChangeNotifier {
  LibraryStore({
    required this._repository,
    required this._auth,
    required this._profile,
    LocalCache? cache,
    this._externalGame,
  }) : _cache = cache ?? LocalCache();

  final CheckpointRepository _repository;
  final AuthStore _auth;
  final ProfileStore _profile;
  final LocalCache _cache;

  /// Finds a game that isn't in the library or the catalog slice, e.g. a search
  /// result being opened or added.
  final Game? Function(String id)? _externalGame;

  User? _user;
  StreamSubscription<User?>? _authSubscription;
  final List<StreamSubscription<dynamic>> _dataSubscriptions = [];

  /// Bumped by every account event, so a load that was overtaken (another
  /// account signed in, or a retry started) can tell and stop.
  int _loadSeq = 0;

  /// A small, fixed-size slice of the catalog for the Home carousels. This is
  /// not the whole `games` table: that is no longer downloaded (see
  /// [CheckpointRepository.fetchPopularGames]).
  List<Game> _popularGames = const [];

  /// Ids the server is known to have in `games`: everything it returned for the
  /// library or the popular list (the saved copy included: it only ever holds
  /// what the server returned), plus rows this session inserted. Deliberately
  /// not fed from local edits ([_replaceGame] puts a game in the library before
  /// it is saved), so it only ever holds confirmed rows.
  final Set<String> _gamesInDb = {};

  /// Library + popular games, for [maybeGame] and the Quick Log picker.
  List<Game> _games = const [];
  List<Game> _libraryGames = const [];
  List<LogEntry> _logs = const [];

  /// A load is running.
  bool _loading = true;

  /// There is a library on screen: fetched, or restored from the saved copy.
  bool _loaded = false;
  bool _offline = false;
  DateTime? _syncedAt;
  String? _loadError;
  String? _notice;

  /// Counts local edits (anything that goes through [_saveUserGame], and
  /// deletes). A fetch that was started before an edit can come back without it.
  int _editSeq = 0;

  /// No library on screen yet and one is being loaded: show a spinner. With a
  /// saved copy on screen the refresh happens quietly behind it.
  bool get isLoading => _loading && !_loaded;

  /// A refresh is running behind a library that is already on screen.
  bool get isRefreshing => _loading && _loaded;

  /// The last attempt to reach the server failed, so the library on screen is the
  /// copy saved on this device (or the last one fetched). Clears on the next
  /// successful fetch.
  bool get isOffline => _offline;

  /// When the library on screen was last fetched from (or saved by) the server.
  DateTime? get lastSyncedAt => _syncedAt;

  /// Why nothing could be loaded; set only when there is no library to show.
  String? get loadError => _loadError;

  /// A message about something that just went wrong with an edit (it could not be
  /// saved). The app shell shows it once and calls [clearNotice].
  String? get notice => _notice;

  void clearNotice() => _notice = null;

  void _setNotice(String message) {
    _notice = message;
    notifyListeners();
  }

  Future<void> initialize() async {
    _authSubscription = _auth.userChanges.listen((user) {
      unawaited(_onUser(user));
    });
    await _onUser(_auth.user);
  }

  @override
  void dispose() {
    unawaited(_authSubscription?.cancel());
    unawaited(_cancelDataSubscriptions());
    _refreshDebounce?.cancel();
    super.dispose();
  }

  /// Loads everything again for the signed-in user (the Retry buttons).
  Future<void> refresh() => _onUser(_user);

  Future<void> _onUser(User? user) async {
    final seq = ++_loadSeq;
    // Token refreshes and pull-to-retry re-enter here for the same user; their
    // already-loaded achievements stay valid, a different user's do not.
    final previous = _user;
    final sameUser = user != null && user.id == previous?.id;
    _user = user;
    if (!sameUser) {
      _refreshDebounce?.cancel();
      _libraryGames = const [];
      _logs = const [];
      _games = List.unmodifiable(_mergeGames(_popularGames, const []));
      _loaded = false;
      _offline = false;
      _syncedAt = null;
      // The previous account's saved copy goes too (it stays valid only while
      // that account stays signed in).
      if (previous != null) unawaited(_cache.clearAccount(previous.id));
    }
    _loading = true;
    _loadError = null;
    notifyListeners();

    await _cancelDataSubscriptions();
    if (seq != _loadSeq) return;

    try {
      await _hydratePopular(seq);
      if (user == null) {
        // Signed out: only the Home carousels to load, and nothing to subscribe to.
        final popular = await _fetchPopularGamesSafe();
        if (seq != _loadSeq) return;
        _popularGames = popular;
        _games = List.unmodifiable(popular);
      } else {
        // Keyed on what is on screen, not on "a different user": a load that was
        // overtaken by a second auth event never got to read the saved copy, and
        // the load that overtook it sees the same user.
        if (!_loaded) await _hydrateFromCache(user.id, seq);
        if (seq != _loadSeq) return;
        await _refreshSignedInData(user, seq, keepLoadedAchievements: sameUser);
        if (seq != _loadSeq) return;
        _startSubscriptions(user);
      }
      _offline = false;
    } catch (e, st) {
      if (seq != _loadSeq) return;
      debugPrint('Supabase load failed: $e\n$st');
      if (_loaded) {
        // The saved copy (or the last fetch) is still on screen: say so, don't
        // replace it with an error.
        _offline = true;
      } else {
        _loadError =
            'Could not load Checkpoint data. Pull to retry or sign in again.';
      }
    } finally {
      if (seq == _loadSeq) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  /// Puts the saved Home carousel games on screen while the network answers.
  Future<void> _hydratePopular(int seq) async {
    if (_popularGames.isNotEmpty) return;
    final saved = await _cache.readPopular();
    if (saved == null || seq != _loadSeq || _popularGames.isNotEmpty) return;
    _popularGames = saved.value;
    _gamesInDb.addAll(saved.value.map((g) => g.id));
    _games = List.unmodifiable(_mergeGames(_popularGames, _libraryGames));
    notifyListeners();
  }

  /// Puts the library saved on this device on screen while the network answers.
  Future<void> _hydrateFromCache(String userId, int seq) async {
    final library = await _cache.readLibrary(userId);
    final logs = await _cache.readLogs(userId);
    if (seq != _loadSeq) return;
    if (library == null && logs == null) return;
    if (library != null) {
      _applyUserGames(library.value);
      _syncedAt = library.savedAt;
      _loaded = true;
    }
    if (logs != null) _logs = List.unmodifiable(logs.value);
    notifyListeners();
  }

  Future<void> _refreshSignedInData(
    User user,
    int seq, {
    bool keepLoadedAchievements = false,
  }) async {
    final editsAtStart = _editSeq;
    // Three independent reads, started together, so launch waits for the slowest
    // one instead of the sum of all of them. Nothing is assigned until every
    // read has finished, so a failure leaves the previous state untouched. (If
    // any read fails, the record `.wait` throws a ParallelWaitError once all of
    // them are done; the caller already treats any error as "load failed".)
    final (fetched, logs, popular) = await (
      _repository.fetchUserGames(user.id),
      _repository.fetchLogEntries(user.id),
      _fetchPopularGamesSafe(),
    ).wait;
    if (seq != _loadSeq) return;

    _popularGames = popular;
    _applyUserGames(
      keepLoadedAchievements ? _withLoadedAchievements(fetched) : fetched,
    );
    _logs = List.unmodifiable(logs);
    _loaded = true;
    _offline = false;
    _syncedAt = DateTime.now();
    unawaited(_cache.writeLibrary(user.id, fetched));
    unawaited(_cache.writeLogs(user.id, logs));

    // The saved copy let the user edit games while this was still loading. If one
    // of those edits landed after the server was read, the data above predates
    // it: fetch again once the writes have settled.
    if (_editSeq != editsAtStart || _pendingSaves > 0) {
      unawaited(_refreshLibrary(user));
    }
  }

  /// Makes [userGames] the library, records their ids as known to exist in
  /// `games`, and rebuilds the combined [_games] list.
  void _applyUserGames(List<Game> userGames) {
    _libraryGames = List.unmodifiable(userGames);
    _gamesInDb.addAll(userGames.map((g) => g.id));
    _games = List.unmodifiable(_mergeGames(_popularGames, userGames));
  }

  /// The Home carousels are a nicety, so a failure here must not fail the whole
  /// load. Keeps whatever was loaded before and logs the error.
  Future<List<Game>> _fetchPopularGamesSafe() async {
    try {
      final games = await _repository.fetchPopularGames();
      _gamesInDb.addAll(games.map((g) => g.id));
      unawaited(_cache.writePopular(games));
      return games;
    } catch (e, st) {
      debugPrint('Popular games load failed: $e\n$st');
      return _popularGames;
    }
  }

  Future<void> removeFromLibrary(String id) async {
    final current = _user;
    if (current == null) return;
    _editSeq++;

    // Remove from local library list
    _libraryGames = List.unmodifiable(_libraryGames.where((g) => g.id != id));

    // Rebuild the combined list from its sources (popular + library) so the
    // removed game's library state can't linger in it. The game stays in the
    // list as a plain catalog entry, so an open detail page doesn't flash
    // "Game not found" while it closes, and a later search shows it as not in
    // the library. (Game.copyWith can't clear a status, hence withoutUserState.)
    final removed = maybeGame(id);
    final catalogById = <String, Game>{
      for (final g in _mergeGames(_popularGames, _libraryGames)) g.id: g,
    };
    if (removed != null) catalogById.putIfAbsent(id, removed.withoutUserState);

    _games = List.unmodifiable(catalogById.values.toList()..sort((a, b) => a.title.compareTo(b.title)));
    notifyListeners();

    try {
      await _repository.deleteUserGame(current.id, id);
      // Realtime doesn't announce deletes, so the saved copy is told directly.
      unawaited(_cache.removeGame(current.id, id));
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
      _setNotice('You can only have 4 favorite games.');
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

  List<Game> _mergeGames(List<Game> popular, List<Game> userGames) {
    final byId = <String, Game>{for (final game in popular) game.id: game};
    for (final game in userGames) {
      byId[game.id] = game;
    }
    final merged = byId.values.toList()
      ..sort((a, b) => a.title.compareTo(b.title));
    return merged;
  }

  void _startSubscriptions(User user) {
    void onError(Object e, StackTrace st) =>
        debugPrint('Library realtime stream failed: $e\n$st');
    _dataSubscriptions
      ..add(
        _repository
            .watchUserGames(user.id)
            .listen((_) => unawaited(_refreshLibrary(user)), onError: onError),
      )
      ..add(
        _repository
            .watchLogEntries(user.id)
            .listen((_) => unawaited(_refreshLogs(user.id)), onError: onError),
      );
  }

  Future<void> _cancelDataSubscriptions() async {
    for (final subscription in _dataSubscriptions) {
      await subscription.cancel();
    }
    _dataSubscriptions.clear();
  }

  int _pendingSaves = 0;
  bool _refreshQueued = false;
  Timer? _refreshDebounce;

  Future<void> _refreshLibrary(User user) async {
    if (_pendingSaves > 0) {
      _refreshQueued = true; // Pause refresh until local writes finish
      return;
    }

    // Cancel any waiting refresh, and start a new 300ms countdown.
    // This absorbs "refresh storms" from bulk server inserts into a single UI update.
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final fetched = await _repository.fetchUserGames(user.id);
        if (_user?.id != user.id) return; // signed out or switched while we waited
        _applyUserGames(_withLoadedAchievements(fetched));
        _loaded = true;
        _offline = false;
        _syncedAt = DateTime.now();
        notifyListeners();
        unawaited(_cache.writeLibrary(user.id, fetched));
      } catch (e, st) {
        debugPrint('Library refresh failed: $e\n$st');
        if (_user?.id == user.id && _loaded && !_offline) {
          _offline = true;
          notifyListeners();
        }
      }
    });
  }

  Future<void> _refreshLogs(String userId) async {
    try {
      final logs = await _repository.fetchLogEntries(userId);
      if (_user?.id != userId) return;
      _logs = List.unmodifiable(logs);
      notifyListeners();
      unawaited(_cache.writeLogs(userId, logs));
    } catch (e, st) {
      debugPrint('Log refresh failed: $e\n$st');
    }
  }

  // ---- Home carousels (the "players" and "friends" figures are placeholders) ----

  int _seed(Game g) =>
      g.id.codeUnits.fold<int>(7, (s, c) => (s * 31 + c) & 0x7fffffff);

  List<Game> get popularThisMonth {
    final list = List.of(_popularGames)
      ..sort((a, b) => ((_seed(b) * 37) % 101).compareTo((_seed(a) * 37) % 101));
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

  // ---- Steam ----

  bool _isSyncing = false;

  bool get isSyncing => _isSyncing;

  /// Syncs the signed-in user's Steam library. Returns null when a sync ran and
  /// succeeded, otherwise a message that is safe to show (nothing was synced).
  Future<String?> syncLibrary() async {
    final current = _user;
    if (current == null) return 'Sign in to sync your library.';
    if (_isSyncing) return 'A sync is already running.';
    if (!_profile.steamConnected || _profile.steamId == null) {
      return 'Connect your Steam account first to sync your library.';
    }

    _isSyncing = true;
    notifyListeners();

    try {
      final data = await _repository.syncSteamLibrary();
      debugPrint('Steam Sync Complete: $data');

      // Give the database a brief moment to settle broadcasts
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await _refreshLibrary(current);
      return null;
    } catch (e) {
      debugPrint('Error syncing Steam library: $e');
      return 'Could not sync Steam library.';
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
    // Local check only, to avoid a pointless request. The Edge Function
    // re-checks against the profile row on the server.
    if (_user == null ||
        _profile.steamId == null ||
        !_profile.steamConnected) {
      return 'Connect your Steam account to load achievements.';
    }
    final game = maybeGame(gameId);
    if (game == null) return 'Game not found.';

    try {
      final data = await _repository.syncGameAchievements(gameId);
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

  // ---- Reading the library ----

  /// The signed-in user's games, in no particular order. Sort and filter them
  /// with [LibraryViewStore.visible].
  List<Game> get libraryGames => _libraryGames;

  /// Library + popular games.
  List<Game> get games => _games;

  Game? maybeGame(String id) {
    for (final g in _libraryGames) {
      if (g.id == id) return g;
    }
    for (final g in _games) {
      if (g.id == id) return g;
    }
    return _externalGame?.call(id);
  }

  Game gameById(String id) => maybeGame(id)!;

  List<Game> playingNow() {
    final list = _libraryGames
        .where((g) => g.status == GameStatus.playing)
        .toList();
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    list.sort(
      (a, b) =>
          (lastPlayed(b.id) ?? epoch).compareTo(lastPlayed(a.id) ?? epoch),
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

  // ---- Editing the library ----

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

    _editSeq++;
    _pendingSaves++;

    try {
      // Only touch the global catalog for a game the server hasn't confirmed yet
      // (typically a fresh search result). The insert is ON CONFLICT DO NOTHING,
      // so if another user added it first this is a harmless no-op.
      if (!_gamesInDb.contains(game.id)) {
        await _repository.upsertBaseGame(game);
        _gamesInDb.add(game.id);
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
      _setNotice('Could not save that game update.');
      _refreshQueued = true; // Revert to server truth once writes settle
    } finally {
      _pendingSaves--;
      if (_pendingSaves == 0 && _refreshQueued) {
        _refreshQueued = false;
        await _refreshLibrary(current);
      }
    }
  }
}
