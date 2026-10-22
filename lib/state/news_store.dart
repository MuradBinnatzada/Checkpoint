import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:checkpoint/models/news.dart';
import 'package:checkpoint/services/news_api_service.dart';
import 'package:checkpoint/state/account_scoped_store.dart';
import 'package:checkpoint/state/auth_store.dart';
import 'package:checkpoint/state/load_status.dart';

/// The News screen's data: the latest articles from the gaming outlets (paged,
/// and narrowed to one outlet if asked) and Steam's news for the member's own
/// games. Both are live questions asked when the screen opens, kept in memory
/// for [freshFor] so opening it again at once shows them without asking, and
/// dropped when the account changes. Signed out, nothing is asked.
class NewsStore extends AccountScopedStore {
  NewsStore({required AuthStore auth, NewsApiService? api})
    : _api = api ?? NewsApiService(),
      super(auth);

  final NewsApiService _api;

  /// How long what was fetched is shown again without asking.
  static const Duration freshFor = Duration(minutes: 5);

  // ---- Latest ----

  LoadStatus _latestStatus = LoadStatus.idle;
  List<NewsArticle> _latest = const [];
  List<NewsSource> _sources = const [];
  String? _sourceId;
  bool _hasMore = false;
  bool _loadingMore = false;
  bool _loadMoreFailed = false;
  DateTime? _latestAt;
  int _latestSeq =
      0; // bumped by every request for page one, so an old answer is dropped

  LoadStatus get latestStatus => _latestStatus;
  List<NewsArticle> get latest => _latest;

  /// The outlets the list can be narrowed to, as the function listed them.
  List<NewsSource> get sources => _sources;

  /// The outlet the list is narrowed to; null for all.
  String? get sourceId => _sourceId;
  bool get hasMore => _hasMore;
  bool get loadingMore => _loadingMore;
  bool get loadMoreFailed => _loadMoreFailed;

  /// Fetches the first page of the latest articles, unless the list is fresh (and
  /// [force] is not set). The list on screen stays until the new one is here; a
  /// failed refresh keeps it.
  Future<void> loadLatest({bool force = false}) async {
    if (accountId == null) return;
    final at = _latestAt;
    final fresh = at != null && DateTime.now().difference(at) < freshFor;
    if (!force && _latestStatus == LoadStatus.ready && fresh) return;
    final epoch = this.epoch;
    final seq = ++_latestSeq;
    final sourceId = _sourceId;
    if (_latestStatus != LoadStatus.ready) {
      _latestStatus = LoadStatus.loading;
      notifyIfAlive();
    }
    final page = await _api.latest(sourceId: sourceId);
    if (isStale(epoch) || seq != _latestSeq) return;
    if (page == null) {
      if (_latestStatus != LoadStatus.ready) _latestStatus = LoadStatus.failed;
    } else {
      _latest = List.unmodifiable(page.articles);
      if (page.sources.isNotEmpty) _sources = List.unmodifiable(page.sources);
      _hasMore = page.hasMore;
      _loadingMore = false;
      _loadMoreFailed = false;
      _latestStatus = LoadStatus.ready;
      _latestAt = DateTime.now();
    }
    notifyIfAlive();
  }

  /// Narrows the list to the outlet [id] (null: all) and fetches it again, the
  /// list on screen emptied meanwhile so it never shows the other outlet's news.
  Future<void> setSource(String? id) async {
    if (id == _sourceId) return;
    _sourceId = id;
    _latest = const [];
    _hasMore = false;
    _loadingMore = false;
    _loadMoreFailed = false;
    _latestStatus = LoadStatus.idle;
    _latestAt = null;
    notifyIfAlive();
    await loadLatest(force: true);
  }

  /// Fetches the next page of the latest articles and appends it. Safe to call
  /// whenever: it does nothing unless there is a next page and none is loading.
  Future<void> loadMoreLatest() async {
    if (accountId == null ||
        !_hasMore ||
        _loadingMore ||
        _latestStatus != LoadStatus.ready) {
      return;
    }
    final epoch = this.epoch;
    final seq = _latestSeq;
    _loadingMore = true;
    _loadMoreFailed = false;
    notifyIfAlive();
    final page = await _api.latest(sourceId: _sourceId, offset: _latest.length);
    if (isStale(epoch) || seq != _latestSeq) return;
    _loadingMore = false;
    if (page == null) {
      _loadMoreFailed = true;
    } else {
      final seen = {for (final a in _latest) a.id};
      final fresh = [
        for (final a in page.articles)
          if (seen.add(a.id)) a,
      ];
      _latest = List.unmodifiable([..._latest, ...fresh]);
      // A page with nothing new means the source is not advancing: stop there.
      _hasMore = page.hasMore && !(page.articles.isNotEmpty && fresh.isEmpty);
    }
    notifyIfAlive();
  }

  // ---- My games ----

  LoadStatus _mineStatus = LoadStatus.idle;
  List<NewsArticle> _mine = const [];
  List<int> _mineIds = const [];
  DateTime? _mineAt;
  int _mineSeq = 0;

  LoadStatus get myGamesStatus => _mineStatus;
  List<NewsArticle> get myGames => _mine;

  /// Fetches Steam's news for [appIds], unless they are the ones fetched for
  /// lately (and [force] is not set). With none there is nothing to ask.
  Future<void> loadMyGames(List<int> appIds, {bool force = false}) async {
    if (accountId == null) return;
    final ids = appIds.take(NewsApiService.maxAppIds).toList();
    if (ids.isEmpty) {
      // Nothing to ask for; what was held is for games the library no longer has.
      if (_mineStatus == LoadStatus.ready && _mine.isEmpty && _mineIds.isEmpty) {
        return;
      }
      _mineSeq++;
      _mine = const [];
      _mineIds = const [];
      _mineStatus = LoadStatus.ready;
      notifyIfAlive();
      return;
    }
    final at = _mineAt;
    final fresh = at != null && DateTime.now().difference(at) < freshFor;
    if (!force &&
        _mineStatus == LoadStatus.ready &&
        fresh &&
        listEquals(ids, _mineIds)) {
      return;
    }
    final epoch = this.epoch;
    final seq = ++_mineSeq;
    if (_mineStatus != LoadStatus.ready || !listEquals(ids, _mineIds)) {
      _mineStatus = LoadStatus.loading;
      notifyIfAlive();
    }
    final articles = await _api.steamNews(ids);
    if (isStale(epoch) || seq != _mineSeq) return;
    if (articles == null) {
      _mineStatus = _mine.isEmpty || !listEquals(ids, _mineIds)
          ? LoadStatus.failed
          : LoadStatus.ready;
    } else {
      _mine = List.unmodifiable(articles);
      _mineIds = ids;
      _mineStatus = LoadStatus.ready;
      _mineAt = DateTime.now();
    }
    notifyIfAlive();
  }

  @override
  void resetForAccount() {
    _latestSeq++;
    _mineSeq++;
    _latestStatus = LoadStatus.idle;
    _latest = const [];
    _sources = const [];
    _sourceId = null;
    _hasMore = false;
    _loadingMore = false;
    _loadMoreFailed = false;
    _latestAt = null;
    _mineStatus = LoadStatus.idle;
    _mine = const [];
    _mineIds = const [];
    _mineAt = null;
  }
}
