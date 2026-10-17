import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:checkpoint/app/nav_tab.dart';
import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/results_page.dart';
import 'package:checkpoint/services/game_api_service.dart';
import 'package:checkpoint/state/auth_store.dart';
import 'package:checkpoint/state/nav_store.dart';
import 'package:checkpoint/state/search_store.dart';

import 'support/fakes.dart';

/// Serves two pages of results for any query.
class FakeGameApi extends GameApiService {
  @override
  Future<ResultsPage<Game>?> searchGames(
    String query, {
    int offset = 0,
    int limit = GameApiService.searchPageSize,
  }) async {
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

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    authService = FakeAuthService(testUser('u1'));
    auth = AuthStore(authService)..initialize();
    nav = NavStore();
    search = SearchStore(
      repository: FakeRepository(),
      auth: auth,
      nav: nav,
      apiService: FakeGameApi(),
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
}
