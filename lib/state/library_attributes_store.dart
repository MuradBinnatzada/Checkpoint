import 'package:flutter/foundation.dart';

import 'package:checkpoint/models/game_attributes.dart';
import 'package:checkpoint/services/checkpoint_repository.dart';
import 'package:checkpoint/state/account_scoped_store.dart';
import 'package:checkpoint/state/auth_store.dart';
import 'package:checkpoint/state/load_status.dart';

/// What IGDB says about each game of the signed-in member's library that the
/// Library can be filtered by: themes, game modes, perspectives, engines,
/// developers and publishers (see [GameAttributes]).
///
/// Not part of the library the app loads and saves on the device: the lists would
/// make every library load and every saved copy bigger for a feature most visits
/// to the Library never touch. Instead [ensureLoaded] reads them in one separate
/// request the first time the filter sheet opens, and keeps them in memory until
/// the account changes. The server only has them for games whose catalog row was
/// filled in from IGDB (by opening the game's screen, or by the background
/// backfill), so [knows] is false for the others until then.
///
/// Rows get filled in while the app runs, which this store cannot see:
/// [markStale] says some were, and the next [ensureLoaded] reads again, showing
/// what it holds meanwhile.
class LibraryAttributesStore extends AccountScopedStore {
  LibraryAttributesStore({required this._repository, required AuthStore auth})
    : super(auth);

  final CheckpointRepository _repository;

  Map<String, GameAttributes> _byGame = const {};
  LoadStatus _status = LoadStatus.idle;

  /// Rows were filled in after the last read started, so it may lack them.
  bool _stale = false;
  Future<void>? _loading;

  /// Where the first read stands. Stays [LoadStatus.ready] while a later one
  /// refreshes the data.
  LoadStatus get status => _status;

  /// Whether the server has details for [gameId] (a game with none of them from
  /// IGDB counts: it was looked up).
  bool knows(String gameId) => _byGame.containsKey(gameId);

  /// What the server holds for [gameId]; null until it was filled in.
  GameAttributes? of(String gameId) => _byGame[gameId];

  @override
  void resetForAccount() {
    _byGame = const {};
    _status = LoadStatus.idle;
    _stale = false;
    _loading = null;
  }

  /// Rows of `games` were filled in from IGDB (a game's screen was opened, the
  /// background backfill made progress), so a read that started before may be
  /// missing them. Costs nothing until the data is next asked for.
  void markStale() {
    if (_status != LoadStatus.idle) _stale = true;
  }

  /// Reads the details unless they are already here and still current. Does
  /// nothing while a read is running or without a signed-in member. A failed read
  /// is made again by the next call; details already held stay if [force] or a
  /// stale read fails.
  Future<void> ensureLoaded({bool force = false}) {
    final running = _loading;
    if (running != null) return running;
    if (!force && _status == LoadStatus.ready && !_stale) return Future.value();

    late final Future<void> request;
    request = _fetch().whenComplete(() {
      if (identical(_loading, request)) _loading = null;
    });
    return _loading = request;
  }

  Future<void> _fetch() async {
    final userId = accountId;
    if (userId == null) return;
    final epoch = this.epoch;
    final hasContent = _status == LoadStatus.ready;
    // Anything marked after this point may be missing from the answer.
    _stale = false;
    if (!hasContent) {
      _status = LoadStatus.loading;
      notifyIfAlive();
    }
    try {
      final byGame = await _repository.fetchLibraryAttributes(userId);
      if (isStale(epoch)) return;
      _byGame = byGame;
      _status = LoadStatus.ready;
    } catch (e, st) {
      debugPrint('Loading the library filter details failed: $e\n$st');
      if (isStale(epoch)) return;
      _stale = true; // ask again next time
      if (!hasContent) _status = LoadStatus.failed;
    }
    notifyIfAlive();
  }
}
