import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:checkpoint/models/game_attributes.dart';
import 'package:checkpoint/state/auth_store.dart';
import 'package:checkpoint/state/library_attributes_store.dart';
import 'package:checkpoint/state/load_status.dart';

import 'support/fakes.dart';

void main() {
  late FakeRepository repo;
  late FakeAuthService authService;
  late AuthStore auth;
  late LibraryAttributesStore store;

  setUp(() {
    // The store logs the failures it handles; these tests cause some.
    debugPrint = (String? message, {int? wrapWidth}) {};
    SharedPreferences.setMockInitialValues({});
    repo = FakeRepository()
      ..libraryAttributes = {
        'a': const GameAttributes(themes: ['Horror'], developers: ['Studio']),
      };
    authService = FakeAuthService(testUser('u1'));
    auth = AuthStore(authService)..initialize();
    store = LibraryAttributesStore(repository: repo, auth: auth)..initialize();
  });

  tearDown(() {
    debugPrint = debugPrintThrottled;
    store.dispose();
    auth.dispose();
  });

  test('nothing is read until somebody asks', () {
    expect(store.status, LoadStatus.idle);
    expect(store.of('a'), isNull);
    expect(store.knows('a'), isFalse);
    expect(repo.attributeReads, 0);
  });

  test('the first ask reads the details once; later asks reuse them', () async {
    await store.ensureLoaded();
    await store.ensureLoaded();

    expect(store.status, LoadStatus.ready);
    expect(store.of('a')!.themes, ['Horror']);
    expect(store.of('a')!.developers, ['Studio']);
    expect(repo.attributeReads, 1);
  });

  test('a game the server has no details for is not known', () async {
    repo.libraryAttributes['empty'] = const GameAttributes();
    await store.ensureLoaded();

    expect(store.knows('a'), isTrue);
    expect(store.knows('empty'), isTrue); // looked up, IGDB had nothing
    expect(store.knows('never'), isFalse);
  });

  test('asks while a read is running share it', () async {
    repo.attributesGate = Completer<void>();

    final first = store.ensureLoaded();
    final second = store.ensureLoaded();
    await pumpEventQueue();
    expect(store.status, LoadStatus.loading);
    repo.attributesGate!.complete();
    await Future.wait([first, second]);

    expect(repo.attributeReads, 1);
    expect(store.status, LoadStatus.ready);
  });

  test('notifies when a read starts and when it ends', () async {
    var notified = 0;
    store.addListener(() => notified++);

    await store.ensureLoaded();

    expect(notified, 2); // loading, ready
  });

  test('a failed read shows as failed and the next ask tries again', () async {
    repo.offline = true;
    await store.ensureLoaded();
    expect(store.status, LoadStatus.failed);

    repo.offline = false;
    await store.ensureLoaded();

    expect(store.status, LoadStatus.ready);
    expect(store.of('a'), isNotNull);
    expect(repo.attributeReads, 2);
  });

  test('details rows get filled in meanwhile: marked stale, the next ask reads again', () async {
    await store.ensureLoaded();
    repo.libraryAttributes['b'] = const GameAttributes(themes: ['Fantasy']);
    await store.ensureLoaded();
    expect(store.knows('b'), isFalse); // nothing said they changed

    store.markStale();
    await store.ensureLoaded();

    expect(store.knows('b'), isTrue);
    expect(repo.attributeReads, 2);
    await store.ensureLoaded();
    expect(repo.attributeReads, 2); // current again
  });

  test('the details it holds stay on screen while a stale read runs', () async {
    await store.ensureLoaded();
    store.markStale();
    repo.attributesGate = Completer<void>();

    final reading = store.ensureLoaded();
    await pumpEventQueue();

    expect(store.status, LoadStatus.ready);
    expect(store.of('a'), isNotNull);
    repo.attributesGate!.complete();
    await reading;
  });

  test(
    'a stale read that fails keeps what it had and is tried again',
    () async {
      await store.ensureLoaded();
      store.markStale();
      repo.offline = true;
      await store.ensureLoaded();

      expect(store.status, LoadStatus.ready);
      expect(store.of('a'), isNotNull);

      repo.offline = false;
      await store.ensureLoaded();
      expect(repo.attributeReads, 3);
    },
  );

  test(
    'marking stale before the first read changes nothing: it reads anyway',
    () async {
      store.markStale();
      await store.ensureLoaded();
      await store.ensureLoaded();

      expect(repo.attributeReads, 1);
    },
  );

  test(
    'rows filled in while a read is running are not lost: it reads once more',
    () async {
      repo.attributesGate = Completer<void>();
      final reading = store.ensureLoaded();
      await pumpEventQueue();

      store.markStale(); // the answer on its way may predate this
      repo.attributesGate!.complete();
      await reading;
      repo.attributesGate = null;
      await store.ensureLoaded();

      expect(repo.attributeReads, 2);
    },
  );

  test('another account never sees the previous one\'s details', () async {
    await store.ensureLoaded();
    expect(store.knows('a'), isTrue);

    repo.libraryAttributes = {};
    authService.emit(testUser('u2'));
    await pumpEventQueue();

    expect(store.status, LoadStatus.idle);
    expect(store.knows('a'), isFalse);
    await store.ensureLoaded();
    expect(store.status, LoadStatus.ready);
    expect(store.knows('a'), isFalse);
  });

  test('an answer that arrives after the account changed is dropped', () async {
    repo.attributesGate = Completer<void>();
    final reading = store.ensureLoaded();
    await pumpEventQueue();

    authService.emit(testUser('u2'));
    await pumpEventQueue();
    repo.attributesGate!.complete();
    await reading;

    expect(store.status, LoadStatus.idle);
    expect(store.knows('a'), isFalse);
  });

  test('without a signed-in member there is nothing to read', () async {
    authService.emit(null);
    await pumpEventQueue();

    await store.ensureLoaded();

    expect(repo.attributeReads, 0);
    expect(store.status, LoadStatus.idle);
  });
}
