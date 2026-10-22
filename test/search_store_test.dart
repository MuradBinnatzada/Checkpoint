import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:checkpoint/app/nav_tab.dart';
import 'package:checkpoint/models/company.dart';
import 'package:checkpoint/models/filter_options.dart';
import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/game_attributes.dart';
import 'package:checkpoint/models/results_page.dart';
import 'package:checkpoint/models/studio_filters.dart';
import 'package:checkpoint/services/game_api_service.dart';
import 'package:checkpoint/state/auth_store.dart';
import 'package:checkpoint/state/nav_store.dart';
import 'package:checkpoint/state/search_store.dart';

import 'support/fakes.dart';

/// Serves two pages of results for any query, and a page with a studio named
/// after any studio search ([companies] null: the studio search fails; [studioHasMore]
/// says a next page exists), and notes what was asked. [gate] holds every answer
/// until completed, to have a request in flight.
class FakeGameApi extends GameApiService {
  final List<({String query, FilterOptions filters, int offset})> calls = [];
  final List<String> companyCalls = [];
  final List<({String query, StudioFilters filters, int offset})> studioCalls = [];
  List<CompanySummary>? Function(String query, int offset)? companies = (query, offset) => [
    CompanySummary(id: query.length + offset, name: 'Studio $query'),
  ];
  bool studioHasMore = false;
  Completer<void>? gate;

  @override
  Future<ResultsPage<CompanySummary>?> searchCompanies(
    String query, {
    StudioFilters filters = StudioFilters.none,
    int offset = 0,
    int limit = GameApiService.searchPageSize,
  }) async {
    companyCalls.add(query);
    studioCalls.add((query: query, filters: filters, offset: offset));
    await gate?.future;
    final found = companies?.call(query, offset);
    return found == null ? null : ResultsPage(found, hasMore: studioHasMore);
  }

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

  test('leaving the Search tab drops the results, and has its search box emptied', () async {
    await search.searchExternalGames('zelda');
    expect(search.searchResults, isNotEmpty);
    final resetsBefore = search.searchBoxResets;

    nav.select(NavTab.library);

    expect(search.searchResults, isEmpty);
    expect(search.searchHasMore, isFalse);
    expect(search.searchTerm, '');
    expect(search.searchBoxResets, resetsBefore + 1);
  });

  group('studio search', () {
    List<String> names() => [for (final c in search.companyResults) c.name];

    test('finds studios, and an emptied box drops them without asking', () async {
      await search.findCompanies(' valve ');
      expect(names(), ['Studio valve']);
      expect(search.companyQuery, 'valve');

      await search.findCompanies('');
      expect(search.companyResults, isEmpty);
      expect(api.companyCalls, ['valve']);
    });

    test('an answer overtaken by a newer search is dropped', () async {
      api.gate = Completer<void>();
      final first = search.findCompanies('val');
      expect(search.companyLoading, isTrue);
      final second = search.findCompanies('valve');
      api.gate!.complete();
      await Future.wait([first, second]);

      expect(names(), ['Studio valve']);
      expect(search.companyLoading, isFalse);
    });

    test('a failed search says so, and the next one clears it', () async {
      api.companies = (query, offset) => null;
      await search.findCompanies('valve');
      expect(search.companyFailed, isTrue);
      expect(search.companyResults, isEmpty);

      api.companies = (query, offset) => [CompanySummary(id: 56, name: 'Valve')];
      await search.findCompanies('valve');
      expect(search.companyFailed, isFalse);
      expect(names(), ['Valve']);
    });

    test('leaving the Search tab drops the studios and their filters', () async {
      await search.filterStudios(StudioFilters(countries: [392]), 'valve');
      expect(search.studioFilters.countries, {392});

      nav.select(NavTab.library);

      expect(search.companyResults, isEmpty);
      expect(search.companyQuery, '');
      expect(search.studioFilters, StudioFilters.none);
    });

    group('filters', () {
      final japanDevelopers = StudioFilters(
        role: CompanyRole.developer,
        countries: [392],
        founded: const YearRange.decade(1980),
      );

      test('with no name, the studios matching them are listed', () async {
        await search.filterStudios(japanDevelopers, '');

        expect(api.studioCalls.single.query, '');
        expect(api.studioCalls.single.filters, japanDevelopers);
        expect(search.studioFilters, japanDevelopers);
        expect(search.companyResults, isNotEmpty);
        expect(search.companyLoading, isFalse);
      });

      test('narrow a search by name', () async {
        await search.findCompanies('nin');
        await search.filterStudios(japanDevelopers, 'nin');

        expect(api.studioCalls.map((c) => (c.query, c.filters)), [
          ('nin', StudioFilters.none),
          ('nin', japanDevelopers),
        ]);
      });

      test('nothing picked and an empty box ask nothing, and drop the results', () async {
        await search.filterStudios(japanDevelopers, '');
        expect(search.companyResults, isNotEmpty);

        await search.filterStudios(japanDevelopers.cleared(), '');

        expect(search.companyResults, isEmpty);
        expect(api.studioCalls, hasLength(1));
      });

      test('only the order picked is no filter: it asks nothing either', () async {
        await search.filterStudios(StudioFilters(sort: StudioSort.name), '');

        expect(api.studioCalls, isEmpty);
        expect(search.companyResults, isEmpty);
      });
    });

    group('paging', () {
      test('appends the next page after the studios fetched so far, without repeats', () async {
        api.studioHasMore = true;
        api.companies = (query, offset) => offset == 0
            ? [CompanySummary(id: 1, name: 'One'), CompanySummary(id: 2, name: 'Two')]
            : [CompanySummary(id: 2, name: 'Two'), CompanySummary(id: 3, name: 'Three')];
        final filters = StudioFilters(countries: [752]);

        await search.filterStudios(filters, '');
        expect(search.companyHasMore, isTrue);
        await search.loadMoreCompanies();

        expect(names(), ['One', 'Two', 'Three']);
        expect(api.studioCalls.last.offset, 2);
        expect(api.studioCalls.last.filters, filters);
      });

      test('stops when the last page has no studio that is new', () async {
        api.studioHasMore = true;
        api.companies = (query, offset) => [CompanySummary(id: 1, name: 'One')];

        await search.filterStudios(StudioFilters(countries: [752]), '');
        await search.loadMoreCompanies();

        expect(names(), ['One']);
        expect(search.companyHasMore, isFalse);
      });

      test('a failed page can be tried again', () async {
        api.studioHasMore = true;
        await search.filterStudios(StudioFilters(countries: [752]), '');

        api.companies = (query, offset) => null;
        await search.loadMoreCompanies();
        expect(search.companyLoadMoreFailed, isTrue);
        expect(search.companyHasMore, isTrue);
        expect(names(), hasLength(1));

        api.companies = (query, offset) => [CompanySummary(id: 99, name: 'Later')];
        await search.loadMoreCompanies();
        expect(search.companyLoadMoreFailed, isFalse);
        expect(names(), hasLength(2));
      });

      test('a new search drops the page still on its way', () async {
        api.studioHasMore = true;
        await search.filterStudios(StudioFilters(countries: [752]), '');
        api.gate = Completer<void>();

        final more = search.loadMoreCompanies();
        expect(search.companyLoadingMore, isTrue);
        final fresh = search.filterStudios(StudioFilters(countries: [392]), '');
        api.gate!.complete();
        await Future.wait([more, fresh]);

        expect(search.studioFilters.countries, {392});
        expect(search.companyLoadingMore, isFalse);
        expect(names(), hasLength(1));
      });
    });
  });

  test('a search run while typing is not remembered', () async {
    await search.searchExternalGames('elden rin', remember: false);
    expect(api.calls.single.query, 'elden rin');
    expect(search.searchTerm, 'elden rin');
    expect(search.recentSearches, isEmpty);

    await search.searchExternalGames('elden ring');
    expect(search.recentSearches, ['elden ring']);
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
      final resetsBefore = search.searchBoxResets;
      final shooter = FilterOptions.only(GameAttribute.genre, 'Shooter');

      nav.switchTab(NavTab.search, discoverFilters: shooter);
      await pumpEventQueue();

      expect(nav.index, NavTab.search);
      expect(search.activeFilters, shooter);
      expect(search.searchTerm, '');
      expect(search.searchBoxResets, greaterThan(resetsBefore));
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
