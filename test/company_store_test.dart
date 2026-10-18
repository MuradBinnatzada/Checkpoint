import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:checkpoint/models/company.dart';
import 'package:checkpoint/models/filter_options.dart';
import 'package:checkpoint/models/results_page.dart';
import 'package:checkpoint/state/company_store.dart';
import 'package:checkpoint/state/load_status.dart';

import 'support/fakes.dart';

void main() {
  late FakeCompanyApi api;
  late DateTime clock;
  late CompanyStore store;
  const valve = 56;
  const all = (valve, CompanyRole.any, DiscoverSort.popular);
  const published = (valve, CompanyRole.publisher, DiscoverSort.popular);

  setUp(() {
    api = FakeCompanyApi();
    clock = DateTime.utc(2026, 10, 18, 12);
    store = CompanyStore(apiService: api, now: () => clock);
  });

  tearDown(() => store.dispose());

  List<String> ids(CompanyGamesKey key) => [
    for (final g in store.games(key)) g.game.id,
  ];

  group('the company', () {
    test('loads once, showing it loading in between', () async {
      expect(store.viewOf(valve).status, LoadStatus.idle);
      api.gate = Completer<void>();
      final done = store.load(valve);
      expect(store.viewOf(valve).status, LoadStatus.loading);

      api.gate!.complete();
      await done;
      await store.load(valve);

      expect(store.viewOf(valve).status, LoadStatus.ready);
      expect(store.viewOf(valve).company?.name, 'Company 56');
      expect(api.companyCalls, [valve]);
    });

    test(
      'a failed load says so, and a failed refresh keeps what was shown',
      () async {
        api.company = (id) => null;
        await store.load(valve);
        expect(store.viewOf(valve).status, LoadStatus.failed);

        api.company = (id) => Company(id: id, name: 'Valve');
        await store.load(valve);
        expect(store.viewOf(valve).company?.name, 'Valve');

        api.company = (id) => null;
        await store.load(valve, force: true);
        expect(store.viewOf(valve).status, LoadStatus.ready);
        expect(store.viewOf(valve).company?.name, 'Valve');
      },
    );
  });

  group('its games', () {
    test('each role and order is its own list', () async {
      await store.loadGames(all);
      await store.loadGames(published);

      expect(ids(all), ['56-any-1', '56-any-2']);
      expect(ids(published), ['56-publisher-1', '56-publisher-2']);
      expect(store.isGamesLoaded(all), isTrue);
      expect(
        store.isGamesLoaded((
          valve,
          CompanyRole.developer,
          DiscoverSort.popular,
        )),
        isFalse,
      );
    });

    test('a fresh list is not fetched again, a stale one is', () async {
      await store.loadGames(all);
      await store.loadGames(all);
      expect(api.gameCalls, hasLength(1));

      clock = clock.add(const Duration(hours: 1));
      await store.loadGames(all);
      expect(api.gameCalls, hasLength(2));
    });

    test(
      'pages append without repeats, from the IGDB hits fetched so far',
      () async {
        api.games = (key, offset) => offset == 0
            // Three hits, one of them left out for its role.
            ? ResultsPage(
                [companyGame('a'), companyGame('b')],
                hasMore: true,
                fetched: 3,
              )
            : ResultsPage([companyGame('b'), companyGame('c')], hasMore: false);
        await store.loadGames(all);
        expect(store.hasMoreGames(all), isTrue);

        await store.loadMoreGames(all);

        expect(ids(all), ['a', 'b', 'c']);
        expect(api.gameCalls.last, (all, 3));
        expect(store.hasMoreGames(all), isFalse);
      },
    );

    test('a page of nothing but listed games stops the paging', () async {
      api.games = (key, offset) =>
          ResultsPage([companyGame('a')], hasMore: true);
      await store.loadGames(all);
      await store.loadMoreGames(all);

      expect(ids(all), ['a']);
      expect(store.hasMoreGames(all), isFalse);
    });

    test('a failed next page can be retried', () async {
      api.games = (key, offset) =>
          offset == 0 ? ResultsPage([companyGame('a')], hasMore: true) : null;
      await store.loadGames(all);
      await store.loadMoreGames(all);
      expect(store.loadMoreGamesFailed(all), isTrue);

      api.games = (key, offset) =>
          ResultsPage([companyGame('b')], hasMore: false);
      await store.loadMoreGames(all);
      expect(store.loadMoreGamesFailed(all), isFalse);
      expect(ids(all), ['a', 'b']);
    });

    test('a refresh drops a next page still on its way', () async {
      api.games = (key, offset) => ResultsPage([
        companyGame(offset == 0 ? 'first' : 'next'),
      ], hasMore: true);
      await store.loadGames(all);
      api.gate = Completer<void>();
      final more = store.loadMoreGames(all);
      final refresh = store.refreshGames(all);
      api.gate!.complete();
      await Future.wait([more, refresh]);

      expect(ids(all), ['first']);
    });

    test(
      'a failed first page says so; a game of a loaded list is found by id',
      () async {
        api.games = (key, offset) => null;
        await store.loadGames(all);
        expect(store.gamesFailed(all), isTrue);
        expect(store.games(all), isEmpty);

        await store.loadGames(published);
        expect(store.gameById('56-publisher-1'), isNull);

        api.games = (key, offset) =>
            ResultsPage([companyGame('portal')], hasMore: false);
        await store.loadGames(all);
        expect(store.gamesFailed(all), isFalse);
        expect(store.gameById('portal')?.id, 'portal');
        expect(store.gameById('missing'), isNull);
      },
    );
  });
}
