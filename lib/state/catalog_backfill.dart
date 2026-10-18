import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:checkpoint/models/game_details.dart';
import 'package:checkpoint/services/checkpoint_repository.dart';
import 'package:checkpoint/services/game_api_service.dart';

/// Fills in, from IGDB, the catalog rows of the signed-in user's library games
/// that never were (`games.igdb_synced_at` is NULL: games imported from Steam or
/// added before the details screen saved what IGDB says), so every game shows its
/// exact platforms without its screen being opened first.
///
/// Runs in the background once the library has loaded ([start]): asks the server
/// which games are still to do ([CheckpointRepository.fetchUnsyncedIgdbIds]),
/// sends them to `igdb-handler` [batchSize] at a time, [pause] apart, and hands
/// what each batch answers to [onUpdates], so the library shows it right away.
/// When IGDB is limiting requests (or down) it waits the `retry_after` the server
/// gives and goes on with the same batch, up to [maxWaits] times a run; any other
/// failure (no connection, a function deployed before the mode existed) ends the
/// run, and the next library load picks up what is still to do. Nothing awaits
/// it, so it never holds up the screen.
class CatalogBackfill {
  CatalogBackfill({
    required this._repository,
    required this._apiService,
    required this._onUpdates,
    this.batchSize = 25,
    this.pause = const Duration(seconds: 2),
    this.maxWaits = 5,
    Future<void> Function(Duration delay)? wait,
  }) : assert(batchSize > 0 && batchSize <= GameApiService.maxBackfillIds),
       _wait = wait ?? _delay;

  final CheckpointRepository _repository;
  final GameApiService _apiService;

  /// Called with each batch's games: what their catalog rows hold now.
  final void Function(List<GameDetails> updates) _onUpdates;

  /// How the run waits (between batches, and for a rate limit to pass).
  final Future<void> Function(Duration delay) _wait;

  /// Games per request; at most [GameApiService.maxBackfillIds].
  final int batchSize;

  /// Between two requests: IGDB's quota is shared by every member, so a long
  /// library is sent a little at a time, never in a burst.
  final Duration pause;

  /// Rate-limit waits one run accepts before it gives up until the next load.
  final int maxWaits;

  /// The longest a `retry_after` is waited for in one go.
  static const maxRetryAfter = Duration(minutes: 15);

  static Future<void> _delay(Duration delay) => Future<void>.delayed(delay);

  /// Bumped by every new run and by [stop], so a run that was overtaken stops.
  int _run = 0;
  String? _userId;
  bool _running = false;

  /// [start] was called again for the same user while a run was going.
  bool _again = false;

  bool get isRunning => _running;

  /// Starts filling in [userId]'s library in the background. While a run for
  /// them is going it makes one more pass when done instead (the library may
  /// have changed: a Steam sync imported games); a run for anyone else stops.
  void start(String userId) {
    if (_running && _userId == userId) {
      _again = true;
      return;
    }
    final run = ++_run;
    _userId = userId;
    _running = true;
    _again = false;
    unawaited(_loop(run, userId));
  }

  /// Stops the run that is going, if any (a sign-out, another account, a
  /// cleared library).
  void stop() {
    _run++;
    _userId = null;
    _running = false;
    _again = false;
  }

  Future<void> _loop(int run, String userId) async {
    try {
      do {
        _again = false;
        if (!await _pass(run, userId)) return;
      } while (_again && run == _run);
    } finally {
      if (run == _run) _running = false;
    }
  }

  /// One pass over what the server lists as still to do; false when it stopped
  /// before the end.
  Future<bool> _pass(int run, String userId) async {
    final List<int> ids;
    try {
      ids = await _repository.fetchUnsyncedIgdbIds(userId);
    } catch (e) {
      debugPrint('Catalog backfill: could not list the games to fill in: $e');
      return false;
    }
    var waits = 0;
    var next = 0;
    while (next < ids.length) {
      if (run != _run) return false;
      final batch = ids.sublist(next, math.min(next + batchSize, ids.length));
      final result = await _apiService.backfillCatalog(batch);
      if (run != _run) return false;
      if (result.failed) {
        final retryAfter = result.retryAfter;
        if (retryAfter == null || ++waits > maxWaits) return false;
        await _wait(retryAfter > maxRetryAfter ? maxRetryAfter : retryAfter);
        continue; // the same batch again
      }
      if (result.games.isNotEmpty) _onUpdates(result.games);
      next += batch.length;
      if (next < ids.length) await _wait(pause);
    }
    return true;
  }
}
