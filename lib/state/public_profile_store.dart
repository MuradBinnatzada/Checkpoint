import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/public_profile.dart';
import 'package:checkpoint/services/checkpoint_repository.dart';
import 'package:checkpoint/state/account_scoped_store.dart';
import 'package:checkpoint/state/auth_store.dart';
import 'package:checkpoint/utils/lru_cache.dart';

enum PublicProfileStatus {
  /// The first answer is on its way (or nothing was asked for yet).
  loading,
  ready,

  /// No member has this id (the account was deleted, or the id is wrong).
  notFound,

  /// The request failed and there is nothing saved to show.
  failed,
}

/// Everything the Public Profile screen shows about one member, as of [loadedAt].
@immutable
class PublicProfileView {
  const PublicProfileView({
    required this.status,
    this.profile,
    this.stats,
    this.favorites = const [],
    this.rated = const [],
    this.library = const [],
    this.libraryExhausted = false,
    this.loadingMoreLibrary = false,
    this.loadMoreLibraryFailed = false,
    this.refreshFailed = false,
    this.loadedAt,
  });

  const PublicProfileView.loading() : this(status: PublicProfileStatus.loading);

  final PublicProfileStatus status;
  final PublicProfile? profile;
  final PublicProfileStats? stats;

  /// Their (up to four) favorites.
  final List<Game> favorites;

  /// Their best-rated games, best first.
  final List<Game> rated;

  /// The pages of their library loaded so far, newest first.
  final List<Game> library;

  /// A page came back with nothing new, so there is no point asking for more.
  final bool libraryExhausted;
  final bool loadingMoreLibrary;
  final bool loadMoreLibraryFailed;

  /// The last refresh failed, so what is shown may be out of date.
  final bool refreshFailed;
  final DateTime? loadedAt;

  /// How many games they have, whether or not all are loaded.
  int get libraryTotal => math.max(stats?.games ?? 0, library.length);

  bool get libraryHasMore => !libraryExhausted && library.length < libraryTotal;

  /// Their follower count with the signed-in member's own follow or unfollow
  /// since [stats] were read applied, so the count moves as soon as the button
  /// does. [viewerFollows] is the signed-in member's follow state now.
  int followersFor({required bool viewerFollows}) {
    final s = stats;
    if (s == null) return 0;
    final delta = (viewerFollows ? 1 : 0) - (s.viewerFollows ? 1 : 0);
    return math.max(0, s.followers + delta);
  }

  PublicProfileView copyWith({
    List<Game>? library,
    bool? libraryExhausted,
    bool? loadingMoreLibrary,
    bool? loadMoreLibraryFailed,
    bool? refreshFailed,
  }) => PublicProfileView(
    status: status,
    profile: profile,
    stats: stats,
    favorites: favorites,
    rated: rated,
    library: library ?? this.library,
    libraryExhausted: libraryExhausted ?? this.libraryExhausted,
    loadingMoreLibrary: loadingMoreLibrary ?? this.loadingMoreLibrary,
    loadMoreLibraryFailed: loadMoreLibraryFailed ?? this.loadMoreLibraryFailed,
    refreshFailed: refreshFailed ?? this.refreshFailed,
    loadedAt: loadedAt,
  );
}

/// Other members' profiles: header, counts and games. It never touches
/// [ProfileStore], which holds the signed-in member's own profile.
///
/// A profile is fetched when its screen opens and kept in memory (the 20 most
/// recently opened) so that opening it again is instant; one older than
/// [cacheLifetime] is shown while a fresh copy is fetched. Nothing is saved to
/// the device, and everything is dropped when the account changes.
///
/// Achievements are not part of a profile: see [PublicAchievementsStore]. The
/// follower and following lists are in [SocialGraphStore].
class PublicProfileStore extends AccountScopedStore {
  PublicProfileStore({
    required this._repository,
    required AuthStore auth,
    this.cacheLifetime = const Duration(minutes: 5),
    DateTime Function()? now,
    int capacity = 20,
  }) : _now = now ?? DateTime.now,
       _views = LruCache(capacity),
       super(auth);

  final CheckpointRepository _repository;
  final Duration cacheLifetime;
  final DateTime Function() _now;

  final LruCache<String, PublicProfileView> _views;
  final Map<String, Future<void>> _loading = {};

  @override
  void resetForAccount() {
    _views.clear();
    _loading.clear();
  }

  /// What is known about [userId]'s profile; "loading" until [load] has an answer.
  PublicProfileView viewOf(String userId) =>
      _views.peek(userId) ?? const PublicProfileView.loading();

  /// A game from any loaded profile, as the catalog knows it: the owner's status,
  /// rating and hours are cleared, so the game screen never shows them as the
  /// signed-in member's own. This is how a poster tapped on someone's profile is
  /// found by the game screen (it is usually not in the member's library).
  Game? gameById(String id) {
    for (final view in _views.values) {
      for (final games in [view.favorites, view.rated, view.library]) {
        for (final game in games) {
          if (game.id == id) return game.withoutUserState();
        }
      }
    }
    return null;
  }

  bool _isFresh(PublicProfileView view) {
    final at = view.loadedAt;
    return (view.status == PublicProfileStatus.ready ||
            view.status == PublicProfileStatus.notFound) &&
        at != null &&
        _now().difference(at) < cacheLifetime;
  }

  /// Makes sure [userId]'s profile is loaded: does nothing while a request for it
  /// is running or the copy held is fresh, otherwise fetches it. A copy that is
  /// stale stays on screen while the new one is on its way (and if that fails).
  /// [force] fetches whatever the age, for pull-to-refresh and retry.
  Future<void> load(String userId, {bool force = false}) {
    final running = _loading[userId];
    if (running != null) return running;
    final cached = _views[userId];
    if (!force && cached != null && _isFresh(cached)) return Future.value();

    late final Future<void> request;
    request = _fetch(userId, cached).whenComplete(() {
      if (identical(_loading[userId], request)) _loading.remove(userId);
    });
    return _loading[userId] = request;
  }

  Future<void> _fetch(String userId, PublicProfileView? cached) async {
    final epoch = this.epoch;
    final hasContent =
        cached != null &&
        (cached.status == PublicProfileStatus.ready ||
            cached.status == PublicProfileStatus.notFound);
    if (!hasContent) {
      _views[userId] = const PublicProfileView.loading();
      notifyIfAlive();
    }

    try {
      final (profile, stats, favorites, rated, library) = await (
        _repository.fetchPublicProfile(userId),
        _repository.fetchPublicProfileStats(userId),
        _repository.fetchPublicFavorites(userId),
        _repository.fetchPublicRatedGames(userId),
        _repository.fetchPublicLibrary(userId),
      ).wait;
      if (isStale(epoch)) return;
      _views[userId] = profile == null
          ? PublicProfileView(
              status: PublicProfileStatus.notFound,
              loadedAt: _now(),
            )
          : PublicProfileView(
              status: PublicProfileStatus.ready,
              profile: profile,
              stats: stats,
              favorites: favorites,
              rated: rated,
              library: library,
              loadedAt: _now(),
            );
    } catch (e, st) {
      debugPrint('Public profile load failed: $e\n$st');
      if (isStale(epoch)) return;
      _views[userId] = hasContent
          ? cached.copyWith(refreshFailed: true)
          : const PublicProfileView(status: PublicProfileStatus.failed);
    }
    notifyIfAlive();
  }

  /// Fetches the next page of [userId]'s library and adds it to the end. Does
  /// nothing unless the profile is loaded, has more games and is not already
  /// loading a page, so the screen can call it whenever the end comes into view.
  Future<void> loadMoreLibrary(String userId) async {
    final view = _views.peek(userId);
    if (view == null ||
        view.status != PublicProfileStatus.ready ||
        !view.libraryHasMore ||
        view.loadingMoreLibrary) {
      return;
    }
    final epoch = this.epoch;
    _views[userId] = view.copyWith(
      loadingMoreLibrary: true,
      loadMoreLibraryFailed: false,
    );
    notifyIfAlive();

    try {
      final page = await _repository.fetchPublicLibrary(
        userId,
        offset: view.library.length,
      );
      if (isStale(epoch)) return;
      final current = _views.peek(userId) ?? view;
      final seen = {for (final g in current.library) g.id};
      final fresh = [
        for (final g in page)
          if (seen.add(g.id)) g,
      ];
      _views[userId] = current.copyWith(
        library: [...current.library, ...fresh],
        // Nothing new means the source stopped advancing (games removed since the
        // count was read): don't ask for the same page forever.
        libraryExhausted: fresh.isEmpty,
        loadingMoreLibrary: false,
      );
    } catch (e, st) {
      debugPrint('Loading more of a public library failed: $e\n$st');
      if (isStale(epoch)) return;
      final current = _views.peek(userId) ?? view;
      _views[userId] = current.copyWith(
        loadingMoreLibrary: false,
        loadMoreLibraryFailed: true,
      );
    }
    notifyIfAlive();
  }
}
