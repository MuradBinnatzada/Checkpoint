import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:checkpoint/models/browse.dart';
import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/services/game_api_service.dart';

/// The "Browse by" lists of the Discover tab: most popular, highest rated and new
/// releases. Each list is paged, one request at a time, as its grid is scrolled.
///
/// A list is kept in memory once loaded, so reopening it (or coming back to the
/// Discover tab) shows it at once instead of asking IGDB again; it is fetched
/// again only when it is older than [staleAfter], or when the user pulls to
/// refresh. These lists are the same for everyone, so unlike [SearchStore] this
/// store does not follow the signed-in account or the selected tab. Nothing is
/// saved for offline use.
class BrowseStore extends ChangeNotifier {
  BrowseStore({
    GameApiService? apiService,
    this.staleAfter = const Duration(minutes: 30),
    DateTime Function()? now,
  }) : _apiService = apiService ?? GameApiService(),
       _now = now ?? DateTime.now;

  final GameApiService _apiService;

  /// How long a loaded list counts as fresh. "New releases" moves daily and the
  /// others slowly, and every page costs a request against the IGDB quota.
  final Duration staleAfter;

  final DateTime Function() _now;

  final Map<BrowseMode, _Feed> _feeds = {
    for (final mode in BrowseMode.values) mode: _Feed(),
  };

  // ---- Reading a list ----

  /// The games loaded so far for [mode], best first.
  List<BrowseEntry> entries(BrowseMode mode) => _feeds[mode]!.entries;

  /// The first page of [mode] is being fetched (or the list is being refreshed).
  bool isLoading(BrowseMode mode) => _feeds[mode]!.loading;

  /// [mode] has been fetched at least once, so an empty [entries] means IGDB had
  /// nothing rather than "not asked yet".
  bool isLoaded(BrowseMode mode) => _feeds[mode]!.loadedAt != null;

  /// The first page could not be fetched and there is nothing to show instead.
  /// [load] or [refresh] tries again.
  bool hasFailed(BrowseMode mode) => _feeds[mode]!.failed;

  /// IGDB may have more games for [mode] than [entries] holds.
  bool hasMore(BrowseMode mode) => _feeds[mode]!.hasMore;

  /// The next page of [mode] is being fetched.
  bool isLoadingMore(BrowseMode mode) => _feeds[mode]!.loadingMore;

  /// The last attempt to fetch the next page of [mode] failed; [loadMore]
  /// retries it.
  bool loadMoreFailed(BrowseMode mode) => _feeds[mode]!.loadMoreFailed;

  /// A game from any loaded list, by id. This is how a poster that was tapped in
  /// a list is found by the game screen: it is not in the library.
  Game? gameById(String id) {
    for (final feed in _feeds.values) {
      for (final entry in feed.entries) {
        if (entry.game.id == id) return entry.game;
      }
    }
    return null;
  }

  // ---- Loading ----

  /// Makes sure [mode] has games: does nothing while the list is loading or still
  /// fresh, otherwise fetches its first page. A list that is stale stays on
  /// screen while the new page is on its way (and if that fails).
  Future<void> load(BrowseMode mode) async {
    final feed = _feeds[mode]!;
    if (feed.loading) return;
    if (feed.entries.isNotEmpty && !_isStale(feed)) return;
    await _fetchFirstPage(mode);
  }

  /// Fetches the first page of [mode] again, whatever its age. Completes when
  /// the request has: it is what pull-to-refresh waits for.
  Future<void> refresh(BrowseMode mode) async {
    if (_feeds[mode]!.loading) return;
    await _fetchFirstPage(mode);
  }

  bool _isStale(_Feed feed) {
    final loadedAt = feed.loadedAt;
    return loadedAt == null || _now().difference(loadedAt) >= staleAfter;
  }

  Future<void> _fetchFirstPage(BrowseMode mode) async {
    final feed = _feeds[mode]!;
    // A next page that is still on its way (see [loadMore]) must not land on the
    // list this replaces.
    final seq = ++feed.seq;
    feed.loading = true;
    feed.failed = false;
    feed.loadingMore = false;
    feed.loadMoreFailed = false;
    notifyListeners();

    final page = await _apiService.browseGames(mode);
    if (seq != feed.seq) return;
    feed.loading = false;
    if (page == null) {
      // With games on screen, keep them: a stale list beats an error.
      feed.failed = feed.entries.isEmpty;
    } else {
      feed.entries = List.unmodifiable(page.items);
      feed.nextOffset = page.fetched;
      feed.hasMore = page.hasMore;
      feed.loadedAt = _now();
    }
    notifyListeners();
  }

  /// Fetches the next page of [mode] and appends it. Safe to call whenever: the
  /// grid calls it each time its end scrolls into view, and it does nothing
  /// unless there is a next page and no request is running for the list.
  Future<void> loadMore(BrowseMode mode) async {
    final feed = _feeds[mode]!;
    if (!feed.hasMore || feed.loading || feed.loadingMore) return;
    final seq = feed.seq;
    feed.loadingMore = true;
    feed.loadMoreFailed = false;
    notifyListeners();

    final page = await _apiService.browseGames(mode, offset: feed.nextOffset);
    // A refresh took over and already reset the flags.
    if (seq != feed.seq) return;
    feed.loadingMore = false;
    if (page == null) {
      feed.loadMoreFailed = true;
    } else {
      final seen = {for (final e in feed.entries) e.game.id};
      final fresh = [
        for (final e in page.items)
          if (seen.add(e.game.id)) e,
      ];
      feed.entries = List.unmodifiable([...feed.entries, ...fresh]);
      feed.nextOffset += page.fetched;
      // A page of nothing but games already listed means the list is not
      // advancing. Stop there instead of asking for the same page forever.
      feed.hasMore = page.hasMore && !(page.items.isNotEmpty && fresh.isEmpty);
    }
    notifyListeners();
  }
}

/// What the store knows about one list.
class _Feed {
  List<BrowseEntry> entries = const [];

  /// IGDB hits consumed so far: where the next page starts.
  int nextOffset = 0;
  bool hasMore = false;
  bool loading = false;
  bool loadingMore = false;
  bool loadMoreFailed = false;
  bool failed = false;

  /// When the first page last arrived; null until it has.
  DateTime? loadedAt;

  /// Bumped by every first-page fetch, so a response that was overtaken by a
  /// refresh is dropped instead of replacing newer games.
  int seq = 0;
}
