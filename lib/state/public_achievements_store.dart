import 'package:flutter/foundation.dart';

import 'package:checkpoint/models/achievement.dart';
import 'package:checkpoint/models/achievement_summary.dart';
import 'package:checkpoint/services/checkpoint_repository.dart';
import 'package:checkpoint/services/sync_failure.dart';
import 'package:checkpoint/state/account_scoped_store.dart';
import 'package:checkpoint/state/auth_store.dart';
import 'package:checkpoint/state/load_status.dart';
import 'package:checkpoint/utils/lru_cache.dart';

/// A member's achievements added up, with where the request stands.
@immutable
class AchievementTotalsView {
  const AchievementTotalsView({
    this.status = LoadStatus.idle,
    this.totals = const AchievementTotals(),
  });

  final LoadStatus status;
  final AchievementTotals totals;
}

/// Which of a member's games have achievements, and how far they got in each.
@immutable
class AchievementSummaryView {
  const AchievementSummaryView({
    this.status = LoadStatus.idle,
    this.games = const [],
  });

  final LoadStatus status;
  final List<GameAchievementSummary> games;
}

/// One game's achievements for one member. [achievements] is null until loaded.
@immutable
class GameAchievementsView {
  const GameAchievementsView({
    this.status = LoadStatus.idle,
    this.achievements,
    this.error,
  });

  final LoadStatus status;
  final List<Achievement>? achievements;

  /// Why Steam could not be asked, safe to show: with [LoadStatus.failed], or
  /// beside an older list that is shown instead.
  final String? error;
}

/// A member's achievements (another member's, or the signed-in member's own), in
/// three steps of growing size.
///
/// [loadTotals] gets one small row, the count over all their games. [loadSummary]
/// gets the progress per game, counts only: every Steam game they unlocked
/// anything in, counted by their Steam syncs. Both are fine to load with a
/// profile. [loadGame] gets the full list of one game when it is opened: from the
/// database when the list stored there matches the game's counts, otherwise from
/// Steam (through the `sync-achievements` Edge Function, which also stores it).
/// All are cached in memory until the account changes.
class PublicAchievementsStore extends AccountScopedStore {
  PublicAchievementsStore({
    required this._repository,
    required AuthStore auth,
    this._onGameFetched,
    int summaryCapacity = 10,
    int gameCapacity = 60,
  }) : _totals = LruCache(summaryCapacity),
       _summaries = LruCache(summaryCapacity),
       _games = LruCache(gameCapacity),
       super(auth);

  final CheckpointRepository _repository;

  /// Called with each list fetched from Steam, so that the signed-in member's own
  /// library can show it too.
  final void Function(String userId, String gameId, List<Achievement> list)?
  _onGameFetched;

  final LruCache<String, AchievementTotalsView> _totals;
  final LruCache<String, AchievementSummaryView> _summaries;
  final LruCache<(String, String), GameAchievementsView> _games;
  final Map<Object, Future<void>> _loading = {};

  @override
  void resetForAccount() {
    _totals.clear();
    _summaries.clear();
    _games.clear();
    _loading.clear();
  }

  AchievementTotalsView totalsOf(String userId) =>
      _totals.peek(userId) ?? const AchievementTotalsView();

  AchievementSummaryView summaryOf(String userId) =>
      _summaries.peek(userId) ?? const AchievementSummaryView();

  GameAchievementsView gameOf(String userId, String gameId) =>
      _games.peek((userId, gameId)) ?? const GameAchievementsView();

  /// [userId] has just cleared their library, so they have no achievements left
  /// (they are stored with the games). Shows that now instead of the counts and
  /// games held from before, without asking the server again.
  void markCleared(String userId) {
    _totals[userId] = const AchievementTotalsView(status: LoadStatus.ready);
    _summaries.remove(userId);
    _games.removeWhere((key) => key.$1 == userId);
    notifyIfAlive();
  }

  /// [userId] just synced their Steam library, which counted their achievements
  /// again: reads again what is held of theirs (keeping it on screen meanwhile)
  /// and forgets their games' lists, which are fetched again when opened.
  void refreshAfterSync(String userId) {
    _games.removeWhere((key) => key.$1 == userId);
    if (_totals[userId] != null) loadTotals(userId, force: true);
    if (_summaries[userId] != null) loadSummary(userId, force: true);
    notifyIfAlive();
  }

  /// Fetches [userId]'s achievement count. Same rules as [loadSummary]. In
  /// [_loading] the summary is keyed by the bare user id and a game by
  /// `(userId, gameId)`, so the totals get `(userId, null)`.
  Future<void> loadTotals(String userId, {bool force = false}) {
    final key = (userId, null);
    final running = _loading[key];
    if (running != null) return running;
    final cached = _totals[userId];
    if (!force && cached != null && cached.status == LoadStatus.ready) {
      return Future.value();
    }

    late final Future<void> request;
    request = _fetchTotals(userId, cached).whenComplete(() {
      if (identical(_loading[key], request)) _loading.remove(key);
    });
    return _loading[key] = request;
  }

  Future<void> _fetchTotals(String userId, AchievementTotalsView? cached) async {
    final epoch = this.epoch;
    final hasContent = cached != null && cached.status == LoadStatus.ready;
    if (!hasContent) {
      _totals[userId] = const AchievementTotalsView(status: LoadStatus.loading);
      notifyIfAlive();
    }
    try {
      final totals = await _repository.fetchAchievementTotals(userId);
      if (isStale(epoch)) return;
      _totals[userId] = AchievementTotalsView(
        status: LoadStatus.ready,
        totals: totals,
      );
    } catch (e, st) {
      debugPrint('Loading achievement totals of $userId failed: $e\n$st');
      if (isStale(epoch)) return;
      if (!hasContent) {
        _totals[userId] = const AchievementTotalsView(status: LoadStatus.failed);
      }
    }
    notifyIfAlive();
  }

  /// Fetches [userId]'s achievement progress per game. Does nothing while it is
  /// loading or already loaded, unless [force] (a retry or refresh); a copy
  /// already held stays on screen while a forced one is on its way.
  Future<void> loadSummary(String userId, {bool force = false}) {
    final running = _loading[userId];
    if (running != null) return running;
    final cached = _summaries[userId];
    if (!force && cached != null && cached.status == LoadStatus.ready) {
      return Future.value();
    }

    late final Future<void> request;
    request = _fetchSummary(userId, cached).whenComplete(() {
      if (identical(_loading[userId], request)) _loading.remove(userId);
    });
    return _loading[userId] = request;
  }

  Future<void> _fetchSummary(
    String userId,
    AchievementSummaryView? cached,
  ) async {
    final epoch = this.epoch;
    final hasContent = cached != null && cached.status == LoadStatus.ready;
    if (!hasContent) {
      _summaries[userId] = const AchievementSummaryView(
        status: LoadStatus.loading,
      );
      notifyIfAlive();
    }
    try {
      final games = await _repository.fetchAchievementSummary(userId);
      if (isStale(epoch)) return;
      _summaries[userId] = AchievementSummaryView(
        status: LoadStatus.ready,
        games: List.unmodifiable(games),
      );
    } catch (e, st) {
      debugPrint('Loading achievements of $userId failed: $e\n$st');
      if (isStale(epoch)) return;
      if (!hasContent) {
        _summaries[userId] = const AchievementSummaryView(
          status: LoadStatus.failed,
        );
      }
    }
    notifyIfAlive();
  }

  /// Fetches [userId]'s achievements for [gameId]. Same rules as [loadSummary];
  /// [force] (the refresh button) asks Steam even when the stored list is up to
  /// date.
  ///
  /// The list stored in the database is used when it matches [expected], the
  /// game's counts from the summary (which Steam syncs keep current). One that
  /// doesn't, or none at all (a game never opened), is fetched from Steam; when
  /// that fails, a stored list is still shown, with the reason beside it.
  Future<void> loadGame(
    String userId,
    String gameId, {
    GameAchievementSummary? expected,
    bool force = false,
  }) {
    final key = (userId, gameId);
    final running = _loading[key];
    if (running != null) return running;
    final cached = _games[key];
    if (!force && cached != null && cached.status == LoadStatus.ready) {
      return Future.value();
    }

    late final Future<void> request;
    request = _fetchGame(userId, gameId, cached, expected, force).whenComplete(
      () {
        if (identical(_loading[key], request)) _loading.remove(key);
      },
    );
    return _loading[key] = request;
  }

  Future<void> _fetchGame(
    String userId,
    String gameId,
    GameAchievementsView? cached,
    GameAchievementSummary? expected,
    bool force,
  ) async {
    final key = (userId, gameId);
    final epoch = this.epoch;
    final hasContent = cached != null && cached.status == LoadStatus.ready;
    if (!hasContent) {
      _games[key] = const GameAchievementsView(status: LoadStatus.loading);
      notifyIfAlive();
    }

    var stored = hasContent ? cached.achievements : null;
    if (!force) {
      try {
        stored = await _repository.fetchPublicGameAchievements(userId, gameId);
      } catch (e, st) {
        // Steam is asked below; if that fails too, this is the error shown.
        debugPrint('Reading achievements of $userId for $gameId failed: $e\n$st');
      }
      if (isStale(epoch)) return;
      if (stored != null && _matches(stored, expected)) {
        _games[key] = GameAchievementsView(
          status: LoadStatus.ready,
          achievements: stored,
        );
        notifyIfAlive();
        return;
      }
    }

    try {
      final fresh = await _repository.fetchSteamGameAchievements(
        userId,
        gameId,
      );
      if (isStale(epoch)) return;
      final list = fresh ?? stored ?? const <Achievement>[];
      _games[key] = GameAchievementsView(
        status: LoadStatus.ready,
        achievements: list,
      );
      _updateSummary(userId, gameId, list);
      if (fresh != null) _onGameFetched?.call(userId, gameId, fresh);
    } catch (e, st) {
      debugPrint('Fetching achievements of $userId for $gameId from Steam failed: $e\n$st');
      if (isStale(epoch)) return;
      final error = _steamFailureMessage(e, own: userId == accountId);
      _games[key] = stored != null
          ? GameAchievementsView(
              status: LoadStatus.ready,
              achievements: stored,
              error: error,
            )
          : GameAchievementsView(status: LoadStatus.failed, error: error);
    }
    notifyIfAlive();
  }

  /// Whether [list] is the one the summary counted: same unlocked and total.
  static bool _matches(List<Achievement> list, GameAchievementSummary? expected) {
    if (expected == null) return true;
    return list.length == expected.total &&
        list.where((a) => a.unlocked).length == expected.unlocked;
  }

  /// Puts the counts of a list just fetched on the game's summary row, so the
  /// profile agrees with what the game shows.
  void _updateSummary(String userId, String gameId, List<Achievement> list) {
    final summary = _summaries.peek(userId);
    if (summary == null || summary.status != LoadStatus.ready) return;
    final index = summary.games.indexWhere((g) => g.gameId == gameId);
    if (index < 0) return;
    final old = summary.games[index];
    final unlocked = list.where((a) => a.unlocked).length;
    if (old.unlocked == unlocked && old.total == list.length) return;
    final games = [...summary.games];
    games[index] = GameAchievementSummary(
      gameId: old.gameId,
      title: old.title,
      coverUrl: old.coverUrl,
      unlocked: unlocked,
      total: list.length,
    );
    _summaries[userId] = AchievementSummaryView(
      status: LoadStatus.ready,
      games: List.unmodifiable(games),
    );
  }
}

/// What to say when Steam could not be asked for a member's achievements.
String _steamFailureMessage(Object error, {required bool own}) {
  final failure = SyncFailure.from(error);
  return switch (failure.code) {
    SyncFailureCode.steamProfilePrivate =>
      own
          ? failure.message
          : 'Their Steam game details are private, so Steam does not share these achievements.',
    SyncFailureCode.noSteamId =>
      own
          ? 'Connect your Steam account to load achievements.'
          : 'They have not connected a Steam account.',
    SyncFailureCode.gameNotLinked =>
      'This game is not linked to a Steam game yet.',
    SyncFailureCode.achievementsHidden =>
      'They keep their Steam achievements private.',
    SyncFailureCode.notInLibrary =>
      own
          ? 'That game is not in your library.'
          : 'This game is not in their library anymore.',
    _ when failure.isDelayed => failure.message,
    _ => 'Could not load the achievements from Steam.',
  };
}
