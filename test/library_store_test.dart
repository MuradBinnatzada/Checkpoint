import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/services/local_cache.dart';
import 'package:checkpoint/state/auth_store.dart';
import 'package:checkpoint/state/library_store.dart';
import 'package:checkpoint/state/profile_store.dart';

import 'support/fakes.dart';

void main() {
  late FakeRepository repo;
  late FakeAuthService authService;
  late LocalCache cache;
  late AuthStore auth;
  late ProfileStore profile;
  late LibraryStore library;

  setUp(() {
    // The stores log every failure they handle; these tests cause plenty.
    debugPrint = (String? message, {int? wrapWidth}) {};
    SharedPreferences.setMockInitialValues({});
    repo = FakeRepository();
    authService = FakeAuthService(testUser('u1'));
    cache = LocalCache();
    auth = AuthStore(authService)..initialize();
    profile = ProfileStore(repository: repo, auth: auth, cache: cache);
    library = LibraryStore(
      repository: repo,
      auth: auth,
      profile: profile,
      cache: cache,
    );
  });

  tearDown(() {
    debugPrint = debugPrintThrottled;
    library.dispose();
    profile.dispose();
    auth.dispose();
  });

  List<String> ids(List<Game> games) => [for (final g in games) g.id];

  test('shows the saved library while the server answers, then the fresh one', () async {
    await cache.writeLibrary('u1', [testGame('old')]);
    repo.library = [testGame('new')];
    repo.gate = Completer<void>();

    final loading = library.initialize();
    await pumpEventQueue();

    // The server hasn't answered, but the saved copy is already on screen: no
    // spinner, and a refresh running quietly behind it.
    expect(ids(library.libraryGames), ['old']);
    expect(library.isLoading, isFalse);
    expect(library.isRefreshing, isTrue);
    expect(library.isOffline, isFalse);

    repo.gate!.complete();
    await loading;

    expect(ids(library.libraryGames), ['new']);
    expect(library.isRefreshing, isFalse);
    expect(library.isOffline, isFalse);
    await pumpEventQueue();
    expect(ids((await cache.readLibrary('u1'))!.value), ['new']);
  });

  test('with nothing saved, the first load shows a spinner and then saves the library', () async {
    repo.library = [testGame('a'), testGame('b')];
    repo.logs = [testLog('l1', 'a')];
    repo.gate = Completer<void>();

    final loading = library.initialize();
    await pumpEventQueue();
    expect(library.isLoading, isTrue);

    repo.gate!.complete();
    await loading;
    await pumpEventQueue();

    expect(library.isLoading, isFalse);
    expect(ids(library.libraryGames), ['a', 'b']);
    expect(ids((await cache.readLibrary('u1'))!.value), ['a', 'b']);
    expect((await cache.readLogs('u1'))!.value.single.id, 'l1');
  });

  test('keeps the saved library, and says so, when the server cannot be reached', () async {
    await cache.writeLibrary('u1', [testGame('old')]);
    await cache.writeLogs('u1', [testLog('l1', 'old')]);
    repo.offline = true;

    await library.initialize();

    expect(ids(library.libraryGames), ['old']);
    expect(library.logsFor('old'), hasLength(1));
    expect(library.isOffline, isTrue);
    expect(library.loadError, isNull);
    expect(library.isLoading, isFalse);
    expect(library.lastSyncedAt, isNotNull);
  });

  test('a second auth event during startup does not lose the saved library', () async {
    await cache.writeLibrary('u1', [testGame('old')]);
    repo.offline = true;

    final loading = library.initialize();
    authService.emit(testUser('u1')); // e.g. Supabase's own "signed in" event
    await loading;
    await pumpEventQueue();

    expect(ids(library.libraryGames), ['old']);
    expect(library.isOffline, isTrue);
    expect(library.loadError, isNull);
  });

  test('a failed fetch leaves the saved copy untouched', () async {
    await cache.writeLibrary('u1', [testGame('old')]);
    repo.offline = true;

    await library.initialize();
    await pumpEventQueue();

    expect(ids((await cache.readLibrary('u1'))!.value), ['old']);
  });

  test('with nothing saved and no server, the load fails with an error', () async {
    repo.offline = true;

    await library.initialize();

    expect(library.loadError, isNotNull);
    expect(library.isOffline, isFalse);
    expect(library.isLoading, isFalse);
    expect(library.libraryGames, isEmpty);
  });

  test('recovers when the server comes back', () async {
    await cache.writeLibrary('u1', [testGame('old')]);
    repo.offline = true;
    await library.initialize();
    expect(library.isOffline, isTrue);

    repo.offline = false;
    repo.library = [testGame('new')];
    await library.refresh();

    expect(library.isOffline, isFalse);
    expect(ids(library.libraryGames), ['new']);
  });

  test('another account never sees the first account\'s saved library', () async {
    await cache.writeLibrary('u1', [testGame('mine')]);
    authService.emit(testUser('u2'));
    await pumpEventQueue();
    repo.offline = true;

    await library.initialize();

    expect(library.libraryGames, isEmpty);
    expect(library.loadError, isNotNull);
  });

  test('signing out empties the library and deletes the saved copy', () async {
    repo.library = [testGame('a')];
    await library.initialize();
    await pumpEventQueue();
    expect(await cache.readLibrary('u1'), isNotNull);

    authService.emit(null);
    await pumpEventQueue();

    expect(library.libraryGames, isEmpty);
    expect(await cache.readLibrary('u1'), isNull);
    expect(await cache.readLogs('u1'), isNull);
  });

  test('a signed-out visitor still gets the saved Home carousels offline', () async {
    authService.emit(null);
    await pumpEventQueue();
    await cache.writePopular([testGame('p1', status: null)]);
    repo.offline = true;

    await library.initialize();

    expect(ids(library.popularThisMonth), ['p1']);
    expect(library.loadError, isNull);
  });

  test('removing a game removes it from the saved copy too', () async {
    repo.library = [testGame('a'), testGame('b')];
    await library.initialize();
    await pumpEventQueue();

    await library.removeFromLibrary('a');
    await pumpEventQueue();

    expect(ids(library.libraryGames), ['b']);
    expect(ids((await cache.readLibrary('u1'))!.value), ['b']);
  });

  test('an edit that cannot be saved is reported without hiding the library', () async {
    repo.library = [testGame('a')];
    await library.initialize();
    await pumpEventQueue();
    repo.offline = true;

    await library.setRating('a', 3);

    expect(library.notice, 'Could not save that game update.');
    expect(library.loadError, isNull);
    expect(ids(library.libraryGames), ['a']);
  });

  test('looks a game up in the library, the catalog, then the external source', () async {
    final searched = testGame('searched', status: null);
    final store = LibraryStore(
      repository: repo,
      auth: auth,
      profile: profile,
      cache: cache,
      externalGame: (id) => id == 'searched' ? searched : null,
    );
    addTearDown(store.dispose);
    repo.library = [testGame('a')];
    await store.initialize();

    expect(store.maybeGame('a')!.inLibrary, isTrue);
    expect(store.maybeGame('searched'), same(searched));
    expect(store.maybeGame('nope'), isNull);
  });
}
