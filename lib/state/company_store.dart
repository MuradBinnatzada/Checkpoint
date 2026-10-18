import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:checkpoint/models/company.dart';
import 'package:checkpoint/models/filter_options.dart';
import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/services/game_api_service.dart';
import 'package:checkpoint/state/load_status.dart';
import 'package:checkpoint/utils/lru_cache.dart';

/// One company's [Company], with where the request stands.
@immutable
class CompanyView {
  const CompanyView({this.status = LoadStatus.idle, this.company});

  final LoadStatus status;

  /// Set once [status] is [LoadStatus.ready].
  final Company? company;
}

/// One list of a company's games: the company, which of its games, in what order.
typedef CompanyGamesKey = (int companyId, CompanyRole role, DiscoverSort sort);

/// The company pages (a publisher or developer, see [Company]): what IGDB says
/// about each company, and its games, one list per role and order, paged as the
/// grid is scrolled.
///
/// Kept in memory only, the companies and lists opened last, like
/// [GameDetailsStore]. A list is fetched again when it is older than
/// [staleAfter] or pulled to refresh, like a [BrowseStore] list. Not tied to an
/// account: none of it is personal.
class CompanyStore extends ChangeNotifier {
  CompanyStore({
    GameApiService? apiService,
    int capacity = 20,
    this.staleAfter = const Duration(minutes: 30),
    DateTime Function()? now,
  }) : _apiService = apiService ?? GameApiService(),
       _views = LruCache(capacity),
       _feeds = LruCache(capacity * 2),
       _now = now ?? DateTime.now;

  final GameApiService _apiService;

  /// How long a loaded list of games counts as fresh.
  final Duration staleAfter;

  final DateTime Function() _now;
  final LruCache<int, CompanyView> _views;
  final Map<int, Future<void>> _loading = {};
  final LruCache<CompanyGamesKey, _Feed> _feeds;
  bool _disposed = false;

  // ---- The company ----

  CompanyView viewOf(int companyId) =>
      _views.peek(companyId) ?? const CompanyView();

  /// Makes sure [companyId]'s page is loaded: does nothing while a request is
  /// running or when it is already here; [force] asks again (pull to refresh).
  /// A company already held stays on screen if asking again fails.
  Future<void> load(int companyId, {bool force = false}) {
    final running = _loading[companyId];
    if (running != null) return running;
    final cached = _views[companyId];
    if (!force && cached?.status == LoadStatus.ready) return Future.value();

    late final Future<void> request;
    request = _fetch(companyId, cached).whenComplete(() {
      if (identical(_loading[companyId], request)) _loading.remove(companyId);
    });
    return _loading[companyId] = request;
  }

  Future<void> _fetch(int companyId, CompanyView? cached) async {
    final hasContent = cached?.status == LoadStatus.ready;
    if (!hasContent) {
      _views[companyId] = const CompanyView(status: LoadStatus.loading);
      _notify();
    }
    final company = await _apiService.fetchCompany(companyId);
    if (company != null) {
      _views[companyId] = CompanyView(
        status: LoadStatus.ready,
        company: company,
      );
    } else if (!hasContent) {
      _views[companyId] = const CompanyView(status: LoadStatus.failed);
    }
    _notify();
  }

  // ---- Its games ----

  static final _none = _Feed();

  _Feed _feedOf(CompanyGamesKey key) => _feeds.peek(key) ?? _none;

  /// The games loaded so far for [key], in its order.
  List<CompanyGame> games(CompanyGamesKey key) => _feedOf(key).entries;

  /// The first page of [key] is being fetched (or the list is being refreshed).
  bool isLoadingGames(CompanyGamesKey key) => _feedOf(key).loading;

  /// [key] has been fetched at least once, so an empty [games] means IGDB had
  /// nothing rather than "not asked yet".
  bool isGamesLoaded(CompanyGamesKey key) => _feedOf(key).loadedAt != null;

  /// The first page could not be fetched and there is nothing to show instead.
  bool gamesFailed(CompanyGamesKey key) => _feedOf(key).failed;

  /// IGDB may have more games for [key] than [games] holds.
  bool hasMoreGames(CompanyGamesKey key) => _feedOf(key).hasMore;

  /// The next page of [key] is being fetched.
  bool isLoadingMoreGames(CompanyGamesKey key) => _feedOf(key).loadingMore;

  /// The last attempt to fetch the next page of [key] failed; [loadMoreGames]
  /// retries it.
  bool loadMoreGamesFailed(CompanyGamesKey key) => _feedOf(key).loadMoreFailed;

  /// A game from any loaded list, by id: how a poster tapped on a company's page
  /// is found by the game screen.
  Game? gameById(String id) {
    for (final feed in _feeds.values) {
      for (final entry in feed.entries) {
        if (entry.game.id == id) return entry.game;
      }
    }
    return null;
  }

  /// Makes sure [key] has games: does nothing while the list is loading or still
  /// fresh, otherwise fetches its first page.
  Future<void> loadGames(CompanyGamesKey key) async {
    final feed = _feeds[key];
    if (feed != null) {
      if (feed.loading) return;
      final loadedAt = feed.loadedAt;
      final fresh =
          loadedAt != null && _now().difference(loadedAt) < staleAfter;
      if (fresh && !feed.failed) return;
    }
    await _fetchFirstPage(key);
  }

  /// Fetches the first page of [key] again, whatever its age. Completes when the
  /// request has: it is what pull-to-refresh waits for.
  Future<void> refreshGames(CompanyGamesKey key) async {
    if (_feeds[key]?.loading ?? false) return;
    await _fetchFirstPage(key);
  }

  Future<void> _fetchFirstPage(CompanyGamesKey key) async {
    final feed = _feeds[key] ??= _Feed();
    // A next page that is still on its way must not land on the list this replaces.
    final seq = ++feed.seq;
    feed.loading = true;
    feed.failed = false;
    feed.loadingMore = false;
    feed.loadMoreFailed = false;
    _notify();

    final (companyId, role, sort) = key;
    final page = await _apiService.companyGames(
      companyId,
      role: role,
      sort: sort,
    );
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
    _notify();
  }

  /// Fetches the next page of [key] and appends it. Safe to call whenever: the
  /// grid calls it each time its end scrolls into view, and it does nothing
  /// unless there is a next page and no request is running for the list.
  Future<void> loadMoreGames(CompanyGamesKey key) async {
    final feed = _feeds[key];
    if (feed == null || !feed.hasMore || feed.loading || feed.loadingMore) {
      return;
    }
    final seq = feed.seq;
    feed.loadingMore = true;
    feed.loadMoreFailed = false;
    _notify();

    final (companyId, role, sort) = key;
    final page = await _apiService.companyGames(
      companyId,
      role: role,
      sort: sort,
      offset: feed.nextOffset,
    );
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
      // A page that only repeats listed games means the list is not advancing.
      // Stop there instead of asking for the same page forever. A page whose
      // games were all left out for their role still advances: it fetched hits.
      feed.hasMore = page.hasMore && !(page.items.isNotEmpty && fresh.isEmpty);
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

/// What the store knows about one list of a company's games.
class _Feed {
  List<CompanyGame> entries = const [];

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
