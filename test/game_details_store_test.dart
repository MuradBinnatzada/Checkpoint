import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/game_details.dart';
import 'package:checkpoint/state/game_details_store.dart';
import 'package:checkpoint/state/load_status.dart';

import 'support/fakes.dart';

void main() {
  late FakeDetailsApi api;
  late List<(String, GameDetails)> delivered;
  late GameDetailsStore store;
  late Game skyrim;

  setUp(() {
    api = FakeDetailsApi()..answer = (id) => testDetails(igdbId: id);
    delivered = [];
    store = GameDetailsStore(
      apiService: api,
      onLoaded: (id, details) => delivered.add((id, details)),
    );
    skyrim = testGame('g1', igdbId: 472, status: null);
  });

  tearDown(() => store.dispose());

  test('nothing is asked until a screen asks', () {
    expect(store.viewOf('g1').status, LoadStatus.idle);
    expect(api.calls, isEmpty);
  });

  test(
    'loads a game by its IGDB id and hands the details to the library',
    () async {
      final loading = store.load(skyrim);
      expect(store.viewOf('g1').status, LoadStatus.loading);
      await loading;

      final view = store.viewOf('g1');
      expect(api.calls, [472]);
      expect(view.status, LoadStatus.ready);
      expect(view.details!.platforms, [
        GamePlatform.pc,
        GamePlatform.ps3,
        GamePlatform.xbox360,
      ]);
      expect(delivered, hasLength(1));
      expect(delivered.single.$1, 'g1');
      expect(delivered.single.$2.igdbId, 472);
    },
  );

  test('a game already loaded is not asked for again, unless forced', () async {
    await store.load(skyrim);
    await store.load(skyrim);
    expect(api.calls, hasLength(1));

    await store.load(skyrim, force: true);
    expect(api.calls, hasLength(2));
  });

  test('two screens asking at once share one request', () async {
    api.gate = Completer<void>();

    final first = store.load(skyrim);
    final second = store.load(skyrim);
    api.gate!.complete();
    await Future.wait([first, second]);

    expect(api.calls, hasLength(1));
  });

  test('a game without an IGDB id is never asked for', () async {
    await store.load(testGame('legacy', igdbId: null, status: null));

    expect(api.calls, isEmpty);
    expect(store.viewOf('legacy').status, LoadStatus.idle);
  });

  test('a failed request is "failed", and asking again can fix it', () async {
    api.answer = (id) => null;
    await store.load(skyrim);
    expect(store.viewOf('g1').status, LoadStatus.failed);
    expect(delivered, isEmpty);

    api.answer = (id) => testDetails(igdbId: id);
    await store.load(skyrim);

    expect(store.viewOf('g1').status, LoadStatus.ready);
  });

  test('details already held stay when asking again fails', () async {
    await store.load(skyrim);
    api.answer = (id) => null;

    await store.load(skyrim, force: true);

    expect(store.viewOf('g1').status, LoadStatus.ready);
    expect(store.viewOf('g1').details, isNotNull);
  });

  test(
    'a similar game can be found by id, so tapping it opens its screen',
    () async {
      expect(store.similarGameById('similar-1'), isNull);

      await store.load(skyrim);

      final similar = store.similarGameById('similar-1')!;
      expect(similar.title, 'Oblivion');
      expect(similar.inLibrary, isFalse);
      expect(store.similarGameById('nope'), isNull);
    },
  );

  test('listeners hear about the loading and the answer', () async {
    var notified = 0;
    store.addListener(() => notified++);

    await store.load(skyrim);

    expect(notified, 2);
  });

  test('keeps the games opened last and forgets the oldest', () async {
    final small = GameDetailsStore(apiService: api, capacity: 2);
    addTearDown(small.dispose);
    for (final id in ['a', 'b', 'c']) {
      await small.load(testGame(id, status: null));
    }

    expect(small.viewOf('a').status, LoadStatus.idle);
    expect(small.viewOf('b').status, LoadStatus.ready);
    expect(small.viewOf('c').status, LoadStatus.ready);
  });

  test(
    'an answer that arrives after the store was disposed is ignored',
    () async {
      final gone = GameDetailsStore(apiService: api);
      api.gate = Completer<void>();
      final loading = gone.load(skyrim);
      gone.dispose();
      api.gate!.complete();

      // Notifying a disposed ChangeNotifier would throw.
      await expectLater(loading, completes);
    },
  );
}
