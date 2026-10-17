import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/state/auth_store.dart';
import 'package:checkpoint/state/load_status.dart';
import 'package:checkpoint/state/public_library_store.dart';

import 'support/fakes.dart';

void main() {
  late FakeRepository repo;
  late FakeAuthService authService;
  late AuthStore auth;
  late PublicLibraryStore store;
  late DateTime clock;

  Game owned(String id, {double rating = 4}) =>
      testGame(id, cover: false).copyWith(rating: rating);

  int reads() => repo.memberReads.where((r) => r == 'library:m1').length;

  setUp(() {
    debugPrint = (String? message, {int? wrapWidth}) {};
    SharedPreferences.setMockInitialValues({});
    clock = DateTime.utc(2026, 10, 17, 12);
    repo = FakeRepository();
    authService = FakeAuthService(testUser('u1'));
    auth = AuthStore(authService)..initialize();
    store = PublicLibraryStore(repository: repo, auth: auth, now: () => clock)
      ..initialize();
    repo.memberGames['m1'] = [owned('a'), owned('b', rating: 0)];
  });

  tearDown(() {
    debugPrint = debugPrintThrottled;
    store.dispose();
    auth.dispose();
  });

  test('nothing is fetched until the Library screen asks', () {
    expect(store.viewOf('m1').status, LoadStatus.idle);
    expect(repo.memberReads, isEmpty);
  });

  test(
    'loads the whole library, each game with its owner\'s rating and hours',
    () async {
      await store.load('m1');

      final view = store.viewOf('m1');
      expect(view.status, LoadStatus.ready);
      expect(view.games.map((g) => g.id), ['a', 'b']);
      expect(view.games.first.rating, 4);
    },
  );

  test(
    'is asked for once while it is fresh, and again once it is stale or forced',
    () async {
      await store.load('m1');
      await store.load('m1');
      expect(reads(), 1);

      await store.load('m1', force: true);
      expect(reads(), 2);

      clock = clock.add(const Duration(minutes: 6));
      await store.load('m1');
      expect(reads(), 3);
    },
  );

  test('two screens asking at once share one request', () async {
    repo.memberLibraryGate = Completer<void>();

    final first = store.load('m1');
    final second = store.load('m1');
    repo.memberLibraryGate!.complete();
    await Future.wait([first, second]);

    expect(reads(), 1);
  });

  test('a failure is "failed", loading again recovers, and a failed refresh keeps the copy', () async {
    repo.failMemberLibrary = true;
    await store.load('m1');
    expect(store.viewOf('m1').status, LoadStatus.failed);

    repo.failMemberLibrary = false;
    await store.load('m1');
    expect(store.viewOf('m1').status, LoadStatus.ready);

    repo.failMemberLibrary = true;
    await store.load('m1', force: true);
    expect(store.viewOf('m1').status, LoadStatus.ready);
    expect(store.viewOf('m1').games, hasLength(2));
  });

  test('gameById gives the catalog game, without the owner\'s state', () async {
    await store.load('m1');

    final game = store.gameById('a')!;

    expect(game.title, 'Game a');
    expect(game.status, isNull);
    expect(game.rating, 0);
    expect(game.hoursPlayed, 0);
    expect(store.gameById('zzz'), isNull);
  });

  test('is dropped when the account changes, and an answer for the old account is ignored', () async {
    await store.load('m1');
    authService.emit(testUser('u2'));
    await pumpEventQueue();
    expect(store.viewOf('m1').status, LoadStatus.idle);
    expect(store.gameById('a'), isNull);

    repo.memberLibraryGate = Completer<void>();
    final slow = store.load('m1');
    await pumpEventQueue();
    authService.emit(testUser('u3'));
    await pumpEventQueue();
    repo.memberLibraryGate!.complete();
    await slow;

    expect(store.viewOf('m1').status, LoadStatus.idle);
  });

  test('keeps only the most recently opened libraries', () async {
    store.dispose();
    store = PublicLibraryStore(repository: repo, auth: auth, capacity: 1)
      ..initialize();
    repo.memberGames['m2'] = [owned('x')];

    await store.load('m1');
    await store.load('m2');

    expect(store.viewOf('m1').status, LoadStatus.idle);
    expect(store.viewOf('m2').status, LoadStatus.ready);
  });
}
