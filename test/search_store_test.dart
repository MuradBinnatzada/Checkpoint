import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:checkpoint/app/nav_tab.dart';
import 'package:checkpoint/models/filter_options.dart';
import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/game_attributes.dart';
import 'package:checkpoint/models/results_page.dart';
import 'package:checkpoint/services/game_api_service.dart';
import 'package:checkpoint/state/auth_store.dart';
import 'package:checkpoint/state/nav_store.dart';
import 'package:checkpoint/state/search_store.dart';

import 'support/fakes.dart';

/// Serves two pages of results for any query, and notes what was asked. [gate]
/// holds every answer until completed, to have a request in flight.
class FakeGameApi extends GameApiService {
  final List<({String query, FilterOptions filters, int offset})> calls = [];
  Completer<void>? gate;

  @override
  Future<ResultsPage<Game>?> searchGames(
    String query, {
    FilterOptions filters = FilterOptions.none,
    int offset = 0,
    int limit = GameApiService.searchPageSize,
  }) async {
    calls.add((query: query, filters: filters, offset: offset));
    await gate?.future;
    if (offset == 0) {
      return ResultsPage([testGame('g1', status: null), testGame('g2', status: null)], hasMore: true);
    }
    return ResultsPage([testGame('g2', status: null), testGame('g3', status: null)], hasMore: false);
  }
}

void main() {
  late FakeAuthService authService;
  late AuthStore auth;
  late NavStore nav;
  late SearchStore search;
  late FakeGameApi api;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    authService = FakeAuthService(testUser('u1'));
    auth = AuthStore(authService)..initialize();
    nav = NavStore();
    search = SearchStore(
      repository: FakeRepository(),
      auth: auth,
      nav: nav,
      apiService: api = FakeGameApi(),
    );
    await search.initialize();
  });

  tearDown(() {
    search.dispose();
    nav.dispose();
    auth.dispose();
  });

  test('loads a page, appends the next without repeating a game, and finds a result by id', () async {
    await search.searchExternalGames('zelda');
    expect([for (final g in search.searchResults) g.id], ['g1', 'g2']);
    expect(search.searchHasMore, isTrue);
    expect(search.resultById('g2'), isNotNull);
    expect(search.resultById('missing'), isNull);

    await search.loadMoreSearchResults();
    expect([for (final g in search.searchResults) g.id], ['g1', 'g2', 'g3']);
    expect(search.searchHasMore, isFalse);
  });

  test('leaving the Search tab drops the results', () async {
    await search.searchExternalGames('zelda');
    expect(search.searchResults, isNotEmpty);

    nav.select(NavTab.library);

    expect(search.searchResults, isEmpty);
    expect(search.searchHasMore, isFalse);
  });

  test('remembers recent searches, newest first, without repeats', () async {
    await search.addRecentSearch('zelda');
    await search.addRecentSearch('mario');
    await search.addRecentSearch('ZELDA');

    expect(search.recentSearches, ['ZELDA', 'mario']);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('recent_searches'), ['ZELDA', 'mario']);
  });

  test('another account starts with a fresh member search', () async {
    await search.findUsers('');
    expect(search.userResults, hasLength(1));
    expect(search.userSearchStale, isFalse);

    authService.emit(testUser('u2'));
    await pumpEventQueue();

    expect(search.userResults, isEmpty);
    expect(search.userSearchStale, isTrue);
  });

  group('filters', () {
    final horror = FilterOptions.only(GameAttribute.theme, 'Horror');

    test('narrow the search and its next pages', () async {
      await search.setFilter(horror, triggerSearch: false);
      expect(api.calls, isEmpty); // nothing to search yet
      expect(search.activeFilters, horror);

      await search.searchExternalGames('zelda');
      expect(api.calls.single, (query: 'zelda', filters: horror, offset: 0));

      // Picked without searching again: the next page still belongs to the
      // results on screen.
      await search.setFilter(FilterOptions.none, triggerSearch: false);
      await search.loadMoreSearchResults();
      expect(api.calls.last, (query: 'zelda', filters: horror, offset: 2));
    });

    test('with no text, list the games matching them; with none, the list goes', () async {
      await search.setFilter(horror);
      expect(api.calls.single, (query: '', filters: horror, offset: 0));
      expect(search.searchTerm, '');
      expect([for (final g in search.searchResults) g.id], ['g1', 'g2']);
      expect(search.recentSearches, isEmpty); // not a search anyone typed

      await search.loadMoreSearchResults();
      expect(api.calls.last.offset, 2);

      await search.setFilter(FilterOptions.none);
      expect(api.calls, hasLength(2)); // nothing to ask
      expect(search.searchResults, isEmpty);
      expect(search.searchHasMore, isFalse);
    });

    test('changing them searches again for the same text, without remembering it again', () async {
      await search.searchExternalGames('zelda');
      await search.addRecentSearch('mario');

      await search.setFilter(horror);

      expect(api.calls.last, (query: 'zelda', filters: horror, offset: 0));
      expect(search.recentSearches, ['mario', 'zelda']);
    });

    test('the same filters again ask nothing', () async {
      await search.setFilter(horror);
      await search.setFilter(FilterOptions.only(GameAttribute.theme, 'Horror'));
      expect(api.calls, hasLength(1));
    });

    test('the first page is loading until it arrives', () async {
      api.gate = Completer<void>();
      final pending = search.setFilter(horror);
      expect(search.searchLoading, isTrue);

      api.gate!.complete();
      await pending;
      expect(search.searchLoading, isFalse);
      expect(search.searchResults, hasLength(2));
    });

    test('a tag sent through NavStore replaces the search with its filters', () async {
      await search.searchExternalGames('zelda');
      nav.select(NavTab.library);
      final shooter = FilterOptions.only(GameAttribute.genre, 'Shooter');

      nav.switchTab(NavTab.search, discoverFilters: shooter);
      await pumpEventQueue();

      expect(nav.index, NavTab.search);
      expect(search.activeFilters, shooter);
      expect(search.searchTerm, '');
      expect(search.browseRequests, 1);
      expect(api.calls.last, (query: '', filters: shooter, offset: 0));
      expect(search.searchResults, hasLength(2));
      expect(nav.takeDiscoverFilters(), isNull); // handed over once
    });

    test('a tag tapped while on the Search tab still opens its filters', () async {
      nav.select(NavTab.search);
      await search.setFilter(horror);

      final coop = FilterOptions.only(GameAttribute.gameMode, 'Co-operative');
      nav.switchTab(NavTab.search, discoverFilters: coop);
      await pumpEventQueue();

      expect(search.activeFilters, coop);
      expect(api.calls.last.filters, coop);
    });

    test('leaving the Search tab drops the filters with the results', () async {
      nav.select(NavTab.search);
      await search.setFilter(horror);

      nav.select(NavTab.library);

      expect(search.activeFilters, FilterOptions.none);
      expect(search.searchResults, isEmpty);
    });
  });
}
