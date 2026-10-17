import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:checkpoint/models/browse.dart';
import 'package:checkpoint/models/results_page.dart';
import 'package:checkpoint/state/browse_store.dart';

import 'support/fakes.dart';

void main() {
  late FakeBrowseApi api;
  late DateTime clock;
  late BrowseStore store;

  setUp(() {
    api = FakeBrowseApi();
    clock = DateTime.utc(2026, 10, 17, 12);
    store = BrowseStore(
      apiService: api,
      staleAfter: const Duration(minutes: 30),
      now: () => clock,
    );
  });

  tearDown(() => store.dispose());

  List<String> ids(BrowseMode mode) => [for (final e in store.entries(mode)) e.game.id];

  group('loading', () {
    test('a list is empty and not loaded until it is asked for', () {
      for (final mode in BrowseMode.values) {
        expect(store.entries(mode), isEmpty);
        expect(store.isLoaded(mode), isFalse);
        expect(store.isLoading(mode), isFalse);
        expect(store.hasFailed(mode), isFalse);
        expect(store.hasMore(mode), isFalse);
      }
      expect(api.calls, isEmpty);
    });

    test('load fetches the first page and shows it loading in between', () async {
      api.gate = Completer<void>();
      final done = store.load(BrowseMode.popular);

      expect(store.isLoading(BrowseMode.popular), isTrue);
      expect(store.entries(BrowseMode.popular), isEmpty);
      expect(store.isLoaded(BrowseMode.popular), isFalse);

      api.gate!.complete();
      await done;

      expect(store.isLoading(BrowseMode.popular), isFalse);
      expect(store.isLoaded(BrowseMode.popular), isTrue);
      expect(ids(BrowseMode.popular), ['popular-1', 'popular-2']);
      expect(api.calls, [(BrowseMode.popular, 0)]);
    });

    test('each list has its own state', () async {
      api.gate = Completer<void>();
      final done = store.load(BrowseMode.topRated);

      expect(store.isLoading(BrowseMode.topRated), isTrue);
      expect(store.isLoading(BrowseMode.popular), isFalse);
      expect(store.isLoading(BrowseMode.newReleases), isFalse);

      api.gate!.complete();
      await done;
      await store.load(BrowseMode.newReleases);

      expect(ids(BrowseMode.topRated), ['topRated-1', 'topRated-2']);
      expect(ids(BrowseMode.newReleases), ['newReleases-1', 'newReleases-2']);
      expect(store.entries(BrowseMode.popular), isEmpty);
      expect(store.isLoaded(BrowseMode.popular), isFalse);
    });

    test('asking again while the first page is on its way does not send a second request', () async {
      api.gate = Completer<void>();
      final first = store.load(BrowseMode.popular);
      final second = store.load(BrowseMode.popular);
      final third = store.refresh(BrowseMode.popular);

      api.gate!.complete();
      await Future.wait([first, second, third]);

      expect(api.callsFor(BrowseMode.popular), 1);
    });

    test('notifies when a load starts and when it ends', () async {
      var notified = 0;
      store.addListener(() => notified++);

      await store.load(BrowseMode.popular);

      expect(notified, 2);
    });
  });

  group('cache', () {
    test('a fresh list is not fetched again', () async {
      await store.load(BrowseMode.popular);
      clock = clock.add(const Duration(minutes: 29));

      await store.load(BrowseMode.popular);
      await store.load(BrowseMode.popular);

      expect(api.callsFor(BrowseMode.popular), 1);
      expect(ids(BrowseMode.popular), ['popular-1', 'popular-2']);
    });

    test('a stale list is fetched again, and stays on screen until the new one arrives', () async {
      await store.load(BrowseMode.newReleases);
      clock = clock.add(const Duration(minutes: 30));

      api.gate = Completer<void>();
      api.answer = (mode, offset) => ResultsPage([testEntry('fresh-1')], hasMore: false);
      final done = store.load(BrowseMode.newReleases);

      expect(store.isLoading(BrowseMode.newReleases), isTrue);
      expect(ids(BrowseMode.newReleases), ['newReleases-1', 'newReleases-2']);

      api.gate!.complete();
      await done;

      expect(ids(BrowseMode.newReleases), ['fresh-1']);
      expect(api.callsFor(BrowseMode.newReleases), 2);

      // The clock restarted with the new page.
      clock = clock.add(const Duration(minutes: 29));
      await store.load(BrowseMode.newReleases);
      expect(api.callsFor(BrowseMode.newReleases), 2);
    });

    test('refresh fetches again even when the list is fresh', () async {
      await store.load(BrowseMode.popular);
      api.answer = (mode, offset) => ResultsPage([testEntry('fresh-1')], hasMore: false);

      await store.refresh(BrowseMode.popular);

      expect(ids(BrowseMode.popular), ['fresh-1']);
      expect(api.callsFor(BrowseMode.popular), 2);
    });

    test('a list IGDB had nothing for is asked for again the next time', () async {
      api.answer = (mode, offset) => ResultsPage<BrowseEntry>(const [], hasMore: false);
      await store.load(BrowseMode.popular);
      expect(store.isLoaded(BrowseMode.popular), isTrue);
      expect(store.entries(BrowseMode.popular), isEmpty);

      await store.load(BrowseMode.popular);

      expect(api.callsFor(BrowseMode.popular), 2);
    });
  });

  group('failures', () {
    test('a failed first page is reported, and load tries again', () async {
      api.answer = (mode, offset) => null;
      await store.load(BrowseMode.topRated);

      expect(store.hasFailed(BrowseMode.topRated), isTrue);
      expect(store.isLoading(BrowseMode.topRated), isFalse);
      expect(store.isLoaded(BrowseMode.topRated), isFalse);
      expect(store.entries(BrowseMode.topRated), isEmpty);

      api.answer = (mode, offset) => ResultsPage([testEntry('g1')], hasMore: false);
      final retry = store.load(BrowseMode.topRated);
      expect(store.hasFailed(BrowseMode.topRated), isFalse); // the retry is on its way
      await retry;

      expect(ids(BrowseMode.topRated), ['g1']);
      expect(store.hasFailed(BrowseMode.topRated), isFalse);
    });

    test('a failure in one list leaves the others alone', () async {
      await store.load(BrowseMode.popular);
      api.answer = (mode, offset) => null;
      await store.load(BrowseMode.topRated);

      expect(store.hasFailed(BrowseMode.topRated), isTrue);
      expect(store.hasFailed(BrowseMode.popular), isFalse);
      expect(ids(BrowseMode.popular), ['popular-1', 'popular-2']);
    });

    test('a refresh that fails keeps the games already on screen', () async {
      await store.load(BrowseMode.popular);
      api.answer = (mode, offset) => null;

      await store.refresh(BrowseMode.popular);

      expect(store.hasFailed(BrowseMode.popular), isFalse);
      expect(ids(BrowseMode.popular), ['popular-1', 'popular-2']);
    });

    test('a stale list whose refresh failed is tried again the next time', () async {
      await store.load(BrowseMode.popular);
      clock = clock.add(const Duration(hours: 1));
      api.answer = (mode, offset) => null;
      await store.load(BrowseMode.popular);

      api.answer = (mode, offset) => ResultsPage([testEntry('fresh-1')], hasMore: false);
      await store.load(BrowseMode.popular);

      expect(ids(BrowseMode.popular), ['fresh-1']);
    });
  });

  group('paging', () {
    ResultsPage<BrowseEntry>? twoPages(BrowseMode mode, int offset) => switch (offset) {
      0 => ResultsPage([testEntry('g1'), testEntry('g2')], hasMore: true),
      2 => ResultsPage([testEntry('g2'), testEntry('g3')], hasMore: false),
      _ => null,
    };

    test('loadMore appends the next page without repeating a game', () async {
      api.answer = twoPages;
      await store.load(BrowseMode.popular);
      expect(store.hasMore(BrowseMode.popular), isTrue);

      await store.loadMore(BrowseMode.popular);

      expect(ids(BrowseMode.popular), ['g1', 'g2', 'g3']);
      expect(store.hasMore(BrowseMode.popular), isFalse);
      expect(api.calls, [(BrowseMode.popular, 0), (BrowseMode.popular, 2)]);
    });

    test('the next page starts after every hit the last one consumed, even those left out', () async {
      api.answer = (mode, offset) => offset == 0
          ? ResultsPage([testEntry('g1')], hasMore: true, fetched: 5) // 4 hits had no usable id
          : ResultsPage([testEntry('g2')], hasMore: false, fetched: 1);
      await store.load(BrowseMode.popular);
      await store.loadMore(BrowseMode.popular);

      expect(api.calls.last, (BrowseMode.popular, 5));
    });

    test('loadMore shows loading in between, and only one runs at a time', () async {
      api.answer = twoPages;
      await store.load(BrowseMode.popular);

      api.gate = Completer<void>();
      final first = store.loadMore(BrowseMode.popular);
      final second = store.loadMore(BrowseMode.popular);
      expect(store.isLoadingMore(BrowseMode.popular), isTrue);
      expect(ids(BrowseMode.popular), ['g1', 'g2']);

      api.gate!.complete();
      await Future.wait([first, second]);

      expect(store.isLoadingMore(BrowseMode.popular), isFalse);
      expect(api.callsFor(BrowseMode.popular), 2);
    });

    test('a failed next page keeps the list and can be retried', () async {
      api.answer = (mode, offset) => offset == 0 ? twoPages(mode, 0) : null;
      await store.load(BrowseMode.popular);
      await store.loadMore(BrowseMode.popular);

      expect(store.loadMoreFailed(BrowseMode.popular), isTrue);
      expect(store.isLoadingMore(BrowseMode.popular), isFalse);
      expect(store.hasMore(BrowseMode.popular), isTrue);
      expect(ids(BrowseMode.popular), ['g1', 'g2']);

      api.answer = twoPages;
      await store.loadMore(BrowseMode.popular);

      expect(store.loadMoreFailed(BrowseMode.popular), isFalse);
      expect(ids(BrowseMode.popular), ['g1', 'g2', 'g3']);
    });

    test('loadMore does nothing when there is no next page', () async {
      await store.load(BrowseMode.popular);

      await store.loadMore(BrowseMode.popular);

      expect(api.callsFor(BrowseMode.popular), 1);
    });

    test('a source that keeps answering the same page ends the list instead of looping', () async {
      api.answer = (mode, offset) => ResultsPage([testEntry('g1'), testEntry('g2')], hasMore: true);
      await store.load(BrowseMode.popular);

      await store.loadMore(BrowseMode.popular);

      expect(ids(BrowseMode.popular), ['g1', 'g2']);
      expect(store.hasMore(BrowseMode.popular), isFalse);
    });

    test('a refresh drops the next page that was still on its way', () async {
      api.answer = twoPages;
      await store.load(BrowseMode.popular);

      // The next page is slow; the refresh is answered first.
      final slowNextPage = Completer<void>();
      api.gate = slowNextPage;
      final next = store.loadMore(BrowseMode.popular);

      final refreshAnswer = Completer<void>();
      api.gate = refreshAnswer;
      api.answer = (mode, offset) => offset == 0
          ? ResultsPage([testEntry('fresh-1')], hasMore: true)
          : twoPages(mode, offset);
      final refresh = store.refresh(BrowseMode.popular);
      expect(store.isLoadingMore(BrowseMode.popular), isFalse);

      refreshAnswer.complete();
      await refresh;
      expect(ids(BrowseMode.popular), ['fresh-1']);

      slowNextPage.complete();
      await next;

      // The old list's next page (g2, g3, no more after it) did not land.
      expect(ids(BrowseMode.popular), ['fresh-1']);
      expect(store.hasMore(BrowseMode.popular), isTrue);
      expect(store.isLoadingMore(BrowseMode.popular), isFalse);
    });
  });

  group('gameById', () {
    test('finds a game in any loaded list, and nothing else', () async {
      await store.load(BrowseMode.popular);
      await store.load(BrowseMode.newReleases);

      expect(store.gameById('popular-2')?.title, 'Game popular-2');
      expect(store.gameById('newReleases-1')?.title, 'Game newReleases-1');
      expect(store.gameById('topRated-1'), isNull);
      expect(store.gameById('missing'), isNull);
    });
  });
}
