import 'package:flutter/foundation.dart';

import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/game_details.dart';
import 'package:checkpoint/services/game_api_service.dart';
import 'package:checkpoint/state/load_status.dart';
import 'package:checkpoint/utils/lru_cache.dart';

/// One game's [GameDetails], with where the request stands.
@immutable
class GameDetailsView {
  const GameDetailsView({this.status = LoadStatus.idle, this.details});

  final LoadStatus status;

  /// Set once [status] is [LoadStatus.ready].
  final GameDetails? details;
}

/// What IGDB says about a game beyond what the library holds (see [GameDetails]),
/// asked for when the game's screen opens. The exact platforms and genres also go
/// to [onLoaded], so the library shows them everywhere, not only on that screen.
///
/// Kept in memory only (the 30 games opened last), not on the device: storyline,
/// similar games and time to beat are large, change over time and are only read
/// on one screen, while the stable part is saved on the game's catalog row by the
/// server and comes back with the library. Not tied to an account: none of it is
/// personal.
class GameDetailsStore extends ChangeNotifier {
  GameDetailsStore({
    GameApiService? apiService,
    this._onLoaded,
    int capacity = 30,
  }) : _apiService = apiService ?? GameApiService(),
       _views = LruCache(capacity);

  final GameApiService _apiService;

  /// Called with a game's id and its details each time they arrive.
  final void Function(String gameId, GameDetails details)? _onLoaded;

  final LruCache<String, GameDetailsView> _views;
  final Map<String, Future<void>> _loading = {};
  bool _disposed = false;

  GameDetailsView viewOf(String gameId) =>
      _views.peek(gameId) ?? const GameDetailsView();

  /// A game that turned up as a similar game of one whose details are loaded, as
  /// the catalog knows it, so that tapping it can open its screen.
  Game? similarGameById(String id) {
    for (final view in _views.values) {
      for (final game in view.details?.similarGames ?? const <Game>[]) {
        if (game.id == id) return game;
      }
    }
    return null;
  }

  /// Makes sure [game]'s details are loaded: does nothing for a game without an
  /// IGDB id, while a request is running, or when they are already here; [force]
  /// asks again (a retry). Details already held stay on screen if asking again
  /// fails.
  Future<void> load(Game game, {bool force = false}) {
    final igdbId = game.igdbId;
    if (igdbId == null) return Future.value();
    final running = _loading[game.id];
    if (running != null) return running;
    final cached = _views[game.id];
    if (!force && cached != null && cached.status == LoadStatus.ready) {
      return Future.value();
    }

    late final Future<void> request;
    request = _fetch(game.id, igdbId, cached).whenComplete(() {
      if (identical(_loading[game.id], request)) _loading.remove(game.id);
    });
    return _loading[game.id] = request;
  }

  Future<void> _fetch(
    String gameId,
    int igdbId,
    GameDetailsView? cached,
  ) async {
    final hasContent = cached != null && cached.status == LoadStatus.ready;
    if (!hasContent) {
      _views[gameId] = const GameDetailsView(status: LoadStatus.loading);
      _notify();
    }
    final details = await _apiService.fetchDetails(igdbId);
    if (details != null) {
      _views[gameId] = GameDetailsView(
        status: LoadStatus.ready,
        details: details,
      );
      _onLoaded?.call(gameId, details);
    } else if (!hasContent) {
      _views[gameId] = const GameDetailsView(status: LoadStatus.failed);
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
