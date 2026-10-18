import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:checkpoint/models/filter_options.dart';
import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/social_user.dart';
import 'package:checkpoint/services/checkpoint_repository.dart';
import 'package:checkpoint/services/game_api_service.dart';
import 'package:checkpoint/state/auth_store.dart';
import 'package:checkpoint/state/nav_store.dart';

/// The Search tab: games from IGDB, members from the database, and the recent
/// searches. Results are paged, one request at a time, as the lists are scrolled.
/// Nothing here is cached for offline use: a search is a live question.
///
/// The game search can be narrowed by [activeFilters] (genres, game modes,
/// themes, platforms, release years). With filters and no search text, the
/// results are the games matching the filters, in their sort order: what a tag
/// tapped on a game's screen opens (see [NavStore.switchTab]).
class SearchStore extends ChangeNotifier {
  SearchStore({
    required this._repository,
    required this._auth,
    required this._nav,
    GameApiService? apiService,
  }) : _apiService = apiService ?? GameApiService();

  final CheckpointRepository _repository;
  final AuthStore _auth;
  final NavStore _nav;
  final GameApiService _apiService;

  StreamSubscription<User?>? _authSubscription;
  String? _userId;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _recentSearches = List<String>.of(prefs.getStringList('recent_searches') ?? const []);
    _userId = _auth.user?.id;
    _authSubscription = _auth.userChanges.listen(_onUser);
    _nav.addListener(_onNavChanged);
  }

  @override
  void dispose() {
    unawaited(_authSubscription?.cancel());
    _nav.removeListener(_onNavChanged);
    super.dispose();
  }

  /// Leaving the Search tab drops its results and its filters. Being sent to it
  /// with filters browses by them.
  void _onNavChanged() {
    final requested = _nav.takeDiscoverFilters();
    if (requested != null) {
      unawaited(browseBy(requested));
      return;
    }
    clearSearch();
    if (_activeFilters != FilterOptions.none) {
      _activeFilters = FilterOptions.none;
      notifyListeners();
    }
  }

  /// A different account (or signing out) must not see the previous account's
  /// member results: the list leaves out that account's own row, and isn't theirs.
  void _onUser(User? user) {
    if (user?.id == _userId) return;
    _userId = user?.id;
    _resetUserSearch();
    notifyListeners();
  }

  // ---- Recent searches ----

  List<String> _recentSearches = [];
  List<String> get recentSearches => List.unmodifiable(_recentSearches);

  static const _maxRecentSearches = 10;

  /// Puts [query] at the top of the recent searches (dropping any earlier copy,
  /// ignoring case) and keeps only the newest [_maxRecentSearches].
  Future<void> addRecentSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    _recentSearches
      ..removeWhere((e) => e.toLowerCase() == q.toLowerCase())
      ..insert(0, q);
    if (_recentSearches.length > _maxRecentSearches) {
      _recentSearches.removeRange(_maxRecentSearches, _recentSearches.length);
    }
    notifyListeners();

    // Save recent searches to device
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('recent_searches', _recentSearches);
  }

  // ---- Filters ----

  FilterOptions _activeFilters = FilterOptions.none;

  /// What the game search is narrowed down by, and the order of a filtered list
  /// without search text.
  FilterOptions get activeFilters => _activeFilters;

  /// Narrows the game search down by [filter]. With [triggerSearch] the results
  /// are fetched again for it: the current search text narrowed by [filter], or
  /// with no text the games matching it (with nothing picked either, the results
  /// are dropped). Without, the results stay as they are until the next search.
  Future<void> setFilter(
    FilterOptions filter, {
    bool triggerSearch = true,
  }) async {
    if (filter == _activeFilters &&
        (!triggerSearch || filter == _resultsFilters)) {
      return;
    }
    _activeFilters = filter;
    notifyListeners();
    if (triggerSearch) await _search(_searchTerm, remember: false);
  }

  int _browseRequests = 0;

  /// How many times [browseBy] replaced the search with filters. The Search
  /// screen empties its search box when this goes up.
  int get browseRequests => _browseRequests;

  /// Drops the search text and shows the games matching [filters].
  Future<void> browseBy(FilterOptions filters) async {
    _browseRequests++;
    _activeFilters = filters;
    notifyListeners();
    await _search('', remember: false);
  }

  // ---- Game search paging ----
  // [searchExternalGames] loads the first page; [loadMoreSearchResults] appends
  // the next ones as the results list is scrolled.
  List<Game> _searchResults = [];
  String _searchTerm = '';
  // The filters [_searchResults] were fetched with: the next pages use them too,
  // even when [_activeFilters] changed without a new search.
  FilterOptions _resultsFilters = FilterOptions.none;
  bool _searchLoading = false;
  int _searchNextOffset = 0; // IGDB hits consumed so far: where the next page starts
  bool _searchHasMore = false;
  bool _searchLoadingMore = false;
  bool _searchLoadMoreFailed = false;

  // Bumped by every search and by [clearSearch], so a response that arrives
  // after the box was emptied (or after a newer search started) is dropped
  // instead of bringing stale results back.
  int _searchSeq = 0;

  List<Game> get searchResults => _searchResults;

  /// The text of the search on screen (trimmed); empty for none, or for a list
  /// of games matching the filters alone.
  String get searchTerm => _searchTerm;

  /// The first page of a search is being fetched.
  bool get searchLoading => _searchLoading;

  /// A search result by id, for opening or adding a game that isn't in the
  /// library yet.
  Game? resultById(String id) {
    for (final g in _searchResults) {
      if (g.id == id) return g;
    }
    return null;
  }

  /// IGDB may have more results than [searchResults] holds.
  bool get searchHasMore => _searchHasMore;

  /// The next page is being fetched.
  bool get searchLoadingMore => _searchLoadingMore;

  /// The last attempt to fetch the next page failed; [loadMoreSearchResults]
  /// retries it.
  bool get searchLoadMoreFailed => _searchLoadMoreFailed;

  /// Searches IGDB for [query], narrowed by [activeFilters], and remembers
  /// [query] as a recent search. An empty [query] lists the games matching the
  /// filters, or, with none picked, drops the results.
  Future<void> searchExternalGames(String query) =>
      _search(query, remember: true);

  Future<void> _search(String query, {required bool remember}) async {
    final term = query.trim();
    if (remember) unawaited(addRecentSearch(term));
    final filters = _activeFilters;
    if (term.isEmpty && filters.isEmpty) {
      clearSearch();
      return;
    }
    final seq = ++_searchSeq;
    _searchTerm = term;
    _resultsFilters = filters;
    // Paging belongs to the previous search. Switch it off now, so a scroll
    // while this request is in flight can't append the old term's next page.
    _searchHasMore = false;
    _searchLoadingMore = false;
    _searchLoadMoreFailed = false;
    _searchLoading = true;
    notifyListeners();
    final page = await _apiService.searchGames(term, filters: filters);
    if (seq != _searchSeq) return;
    _searchLoading = false;
    // A failed request shows as "no results", as it did before paging.
    _searchResults = page?.items ?? const [];
    _searchNextOffset = page?.fetched ?? 0;
    _searchHasMore = page?.hasMore ?? false;
    notifyListeners();
  }

  /// Fetches the next page of the current game search and appends it. Safe to
  /// call whenever: the results list calls it each time its end scrolls into
  /// view, and it does nothing unless there is a next page and none is loading.
  Future<void> loadMoreSearchResults() async {
    if (!_searchHasMore || _searchLoadingMore) return;
    if (_searchTerm.isEmpty && _resultsFilters.isEmpty) return;
    final seq = _searchSeq;
    _searchLoadingMore = true;
    _searchLoadMoreFailed = false;
    notifyListeners();

    final page = await _apiService.searchGames(
      _searchTerm,
      filters: _resultsFilters,
      offset: _searchNextOffset,
    );
    // A newer search (or clearSearch) took over and already reset the flags.
    if (seq != _searchSeq) return;
    _searchLoadingMore = false;
    if (page == null) {
      _searchLoadMoreFailed = true;
    } else {
      final seen = {for (final g in _searchResults) g.id};
      final fresh = [
        for (final g in page.items)
          if (seen.add(g.id)) g,
      ];
      _searchResults = [..._searchResults, ...fresh];
      _searchNextOffset += page.fetched;
      // A page of nothing but games already listed means the source is not
      // advancing (an igdb-handler deployed before it learned `offset` answers
      // every page alike). Stop there instead of asking for the same page forever.
      _searchHasMore = page.hasMore && !(page.items.isNotEmpty && fresh.isEmpty);
    }
    notifyListeners();
  }

  /// Drops the current search results (search box emptied, or the user left
  /// the Search tab) and discards any search still in flight. The filters stay.
  void clearSearch() {
    _searchSeq++;
    final changed = _searchResults.isNotEmpty ||
        _searchLoading ||
        _searchHasMore ||
        _searchLoadingMore ||
        _searchLoadMoreFailed;
    _searchResults = [];
    _searchTerm = '';
    _resultsFilters = FilterOptions.none;
    _searchLoading = false;
    _searchNextOffset = 0;
    _searchHasMore = false;
    _searchLoadingMore = false;
    _searchLoadMoreFailed = false;
    if (changed) notifyListeners();
  }

  // ---- Member search paging (Users tab) ----
  // Done on the server: the member list can't be downloaded up front once
  // signups are open. [findUsers] loads the first page for a query (empty means
  // everyone: "Suggested people"); [loadMoreUsers] appends the next ones.
  List<SocialUser> _userResults = const [];
  String _userQuery = '';
  int _userNextOffset = 0;
  int _userSeq = 0; // bumped by every search and reset, like _searchSeq
  bool _userSearchStale = true; // not searched yet for this account
  bool _userLoading = false;
  bool _userHasMore = false;
  bool _userLoadingMore = false;
  bool _userLoadMoreFailed = false;

  List<SocialUser> get userResults => _userResults;

  /// The Users tab has not loaded anything for the signed-in account yet (first
  /// visit, or the account changed). The tab calls [findUsers] when it sees this.
  bool get userSearchStale => _userSearchStale;

  /// The first page of a member search is being fetched.
  bool get userLoading => _userLoading;
  bool get userHasMore => _userHasMore;
  bool get userLoadingMore => _userLoadingMore;
  bool get userLoadMoreFailed => _userLoadMoreFailed;

  /// Forgets the member results: after sign-out, or when another account signs in.
  void _resetUserSearch() {
    _userSeq++;
    _userResults = const [];
    _userQuery = '';
    _userNextOffset = 0;
    _userSearchStale = true;
    _userLoading = false;
    _userHasMore = false;
    _userLoadingMore = false;
    _userLoadMoreFailed = false;
  }

  /// Searches members by name or @handle and replaces the results with the first
  /// page. An empty [query] lists everyone.
  Future<void> findUsers(String query) async {
    final seq = ++_userSeq;
    final current = _auth.user;
    final term = query.trim();
    _userSearchStale = false;
    _userHasMore = false;
    _userLoadingMore = false;
    _userLoadMoreFailed = false;
    if (current == null) {
      // Members are visible to signed-in users only.
      _userResults = const [];
      _userQuery = term;
      _userNextOffset = 0;
      _userLoading = false;
      notifyListeners();
      return;
    }

    _userLoading = true;
    notifyListeners();
    try {
      final page = await _repository.searchSocialUsers(current.id, query: term);
      if (seq != _userSeq) return;
      _userResults = List.unmodifiable(page.items);
      _userNextOffset = page.fetched;
      _userHasMore = page.hasMore;
    } catch (e, st) {
      if (seq != _userSeq) return;
      debugPrint('Member search failed: $e\n$st');
      _userResults = const [];
      _userNextOffset = 0;
    }
    _userQuery = term;
    _userLoading = false;
    notifyListeners();
  }

  /// Fetches the next page of the current member search and appends it. Safe to
  /// call whenever, like [loadMoreSearchResults].
  Future<void> loadMoreUsers() async {
    final current = _auth.user;
    if (current == null || _userLoading || _userLoadingMore || !_userHasMore) {
      return;
    }
    final seq = _userSeq;
    _userLoadingMore = true;
    _userLoadMoreFailed = false;
    notifyListeners();
    try {
      final page = await _repository.searchSocialUsers(
        current.id,
        query: _userQuery,
        offset: _userNextOffset,
      );
      if (seq != _userSeq) return;
      final seen = {for (final u in _userResults) u.id};
      _userResults = List.unmodifiable([
        ..._userResults,
        for (final u in page.items)
          if (seen.add(u.id)) u,
      ]);
      _userNextOffset += page.fetched;
      _userHasMore = page.hasMore;
    } catch (e, st) {
      if (seq != _userSeq) return;
      debugPrint('Loading more members failed: $e\n$st');
      _userLoadMoreFailed = true;
    }
    _userLoadingMore = false;
    notifyListeners();
  }
}
