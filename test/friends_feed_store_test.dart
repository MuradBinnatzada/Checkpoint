import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:checkpoint/models/friend_activity.dart';
import 'package:checkpoint/state/auth_store.dart';
import 'package:checkpoint/state/friends_feed_store.dart';
import 'package:checkpoint/state/load_status.dart';

import 'support/fakes.dart';

void main() {
  late FakeRepository repo;
  late FakeAuthService authService;
  late AuthStore auth;
  late FriendsFeedStore store;
  late DateTime now;

  setUp(() {
    debugPrint = (String? message, {int? wrapWidth}) {};
    SharedPreferences.setMockInitialValues({});
    now = DateTime.utc(2026, 10, 19, 12);
    repo = FakeRepository()
      ..followingActivity = [
        testActivity('a', 'g1', FriendActivityKind.session, hours: 2),
        testActivity('b', 'g2', FriendActivityKind.completed, rating: 4),
      ];
    authService = FakeAuthService(testUser('u1'));
    auth = AuthStore(authService)..initialize();
    store = FriendsFeedStore(repository: repo, auth: auth, now: () => now)
      ..initialize();
  });

  tearDown(() {
    debugPrint = debugPrintThrottled;
    store.dispose();
    auth.dispose();
  });

  test('nothing is fetched until Home asks', () {
    expect(store.status, LoadStatus.idle);
    expect(store.items, isEmpty);
    expect(repo.feedReads, 0);
  });

  test('loads what the members you follow did, in the order sent', () async {
    await store.load();

    expect(store.status, LoadStatus.ready);
    expect(store.items.map((i) => i.member.id), ['a', 'b']);
    expect(store.items.first.kind, FriendActivityKind.session);
    expect(store.items.first.hours, 2);
    expect(store.items.last.rating, 4);
  });

  test(
    'following nobody, or nobody did anything, is ready and empty',
    () async {
      repo.followingActivity = [];

      await store.load();

      expect(store.status, LoadStatus.ready);
      expect(store.items, isEmpty);
    },
  );

  test('signed out, nothing is asked', () async {
    authService.emit(null);
    await pumpEventQueue();
    await store.load();

    expect(repo.feedReads, 0);
    expect(store.status, LoadStatus.idle);
  });

  test('signing out drops it', () async {
    await store.load();

    authService.emit(null);
    await pumpEventQueue();

    expect(store.items, isEmpty);
    expect(store.status, LoadStatus.idle);
    expect(store.gameById('g1'), isNull);
  });

  test(
    'asks once while fresh, again once stale, showing the copy held meanwhile',
    () async {
      await store.load();
      await store.load();
      expect(repo.feedReads, 1);

      now = now.add(store.cacheLifetime);
      repo.followingActivity = [
        testActivity('c', 'g3', FriendActivityKind.rated, rating: 3),
      ];
      repo.feedGate = Completer<void>();
      final again = store.load();
      expect(store.status, LoadStatus.ready);
      expect(store.items.map((i) => i.member.id), ['a', 'b']);

      repo.feedGate!.complete();
      await again;
      expect(repo.feedReads, 2);
      expect(store.items.single.member.id, 'c');
    },
  );

  test('force asks whatever the age', () async {
    await store.load();
    await store.load(force: true);

    expect(repo.feedReads, 2);
  });

  test('two callers at once share one request', () async {
    repo.feedGate = Completer<void>();

    final first = store.load();
    final second = store.load();
    expect(store.status, LoadStatus.loading);
    repo.feedGate!.complete();
    await Future.wait([first, second]);

    expect(repo.feedReads, 1);
  });

  test('a failed first read is failed and not asked again until stale; a failed refresh keeps what was shown', () async {
    repo.failFeedReads = true;
    await store.load();
    expect(store.status, LoadStatus.failed);
    await store.load();
    expect(repo.feedReads, 1);

    repo.failFeedReads = false;
    now = now.add(store.cacheLifetime);
    await store.load();
    expect(store.status, LoadStatus.ready);

    repo.failFeedReads = true;
    await store.load(force: true);
    expect(store.status, LoadStatus.ready);
    expect(store.items, hasLength(2));
  });

  test('another account signing in drops it, and an answer for the last one is ignored', () async {
    await store.load();
    repo.feedGate = Completer<void>();
    final late = store.load(force: true);

    authService.emit(testUser('u2'));
    await pumpEventQueue();
    expect(store.status, LoadStatus.idle);
    expect(store.items, isEmpty);

    repo.feedGate!.complete();
    await late;
    expect(store.status, LoadStatus.idle);
    expect(store.items, isEmpty);

    // The new account asks for its own, right away.
    repo.feedGate = null;
    await store.load();
    expect(repo.feedReads, 3);
    expect(store.status, LoadStatus.ready);
  });

  test('finds a game of the feed for the game screen', () async {
    expect(store.gameById('g2'), isNull);

    await store.load();

    final game = store.gameById('g2')!;
    expect(game.title, 'Game g2');
    expect(game.status, isNull); // none of the member's state
    expect(store.gameById('nope'), isNull);
  });
}
