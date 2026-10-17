import 'package:flutter/foundation.dart';

import 'package:checkpoint/models/achievement.dart';
import 'package:checkpoint/models/achievement_summary.dart';
import 'package:checkpoint/services/checkpoint_repository.dart';
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
  });

  final LoadStatus status;
  final List<Achievement>? achievements;
}

/// Another member's achievements, in three steps of growing size.
///
/// The achievements themselves are large and personal, so the database hands them
/// out through functions and a screen asks for the big ones from a button, never
/// on open. [loadTotals] gets one small row, the count over all their games, and
/// is fine to call when a profile opens. [loadSummary] gets the progress per game
/// (counts only); [loadGame] gets the full list for one game when it is expanded.
/// All are cached in memory until the account changes. Works for the signed-in
/// member's own id too.
class PublicAchievementsStore extends AccountScopedStore {
  PublicAchievementsStore({
    required this._repository,
    required AuthStore auth,
    int summaryCapacity = 10,
    int gameCapacity = 60,
  }) : _totals = LruCache(summaryCapacity),
       _summaries = LruCache(summaryCapacity),
       _games = LruCache(gameCapacity),
       super(auth);

  final CheckpointRepository _repository;

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

  /// Fetches [userId]'s achievements for [gameId]. Same rules as [loadSummary].
  Future<void> loadGame(String userId, String gameId, {bool force = false}) {
    final key = (userId, gameId);
    final running = _loading[key];
    if (running != null) return running;
    final cached = _games[key];
    if (!force && cached != null && cached.status == LoadStatus.ready) {
      return Future.value();
    }

    late final Future<void> request;
    request = _fetchGame(userId, gameId, cached).whenComplete(() {
      if (identical(_loading[key], request)) _loading.remove(key);
    });
    return _loading[key] = request;
  }

  Future<void> _fetchGame(
    String userId,
    String gameId,
    GameAchievementsView? cached,
  ) async {
    final key = (userId, gameId);
    final epoch = this.epoch;
    final hasContent = cached != null && cached.status == LoadStatus.ready;
    if (!hasContent) {
      _games[key] = const GameAchievementsView(status: LoadStatus.loading);
      notifyIfAlive();
    }
    try {
      final achievements = await _repository.fetchPublicGameAchievements(
        userId,
        gameId,
      );
      if (isStale(epoch)) return;
      _games[key] = GameAchievementsView(
        status: LoadStatus.ready,
        // Nothing stored for the game reads the same as a game without any.
        achievements: achievements ?? const [],
      );
    } catch (e, st) {
      debugPrint('Loading achievements of $userId for $gameId failed: $e\n$st');
      if (isStale(epoch)) return;
      if (!hasContent) {
        _games[key] = const GameAchievementsView(status: LoadStatus.failed);
      }
    }
    notifyIfAlive();
  }
}
