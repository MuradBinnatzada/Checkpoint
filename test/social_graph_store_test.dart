import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:checkpoint/state/auth_store.dart';
import 'package:checkpoint/state/load_status.dart';
import 'package:checkpoint/state/social_graph_store.dart';

import 'support/fakes.dart';

void main() {
  late FakeRepository repo;
  late FakeAuthService authService;
  late AuthStore auth;
  late SocialGraphStore store;

  List<String> ids(String userId, FollowListKind kind) => [
    for (final u in store.listOf(userId, kind).users) u.id,
  ];

  setUp(() {
    debugPrint = (String? message, {int? wrapWidth}) {};
    SharedPreferences.setMockInitialValues({});
    repo = FakeRepository();
    authService = FakeAuthService(testUser('u1'));
    auth = AuthStore(authService)..initialize();
    store = SocialGraphStore(repository: repo, auth: auth)..initialize();
    repo.followersOf['m1'] = [for (var i = 0; i < 35; i++) testMember('f$i')];
    repo.followingOf['m1'] = [testMember('x'), testMember('y')];
  });

  tearDown(() {
    debugPrint = debugPrintThrottled;
    store.dispose();
    auth.dispose();
  });

  test('a list is empty and idle until it is asked for', () {
    final view = store.listOf('m1', FollowListKind.followers);

    expect(view.status, LoadStatus.idle);
    expect(view.users, isEmpty);
    expect(repo.memberReads, isEmpty);
  });

  test(
    'loads the first page of followers, then the rest as it is scrolled',
    () async {
      await store.load('m1', FollowListKind.followers);
      var view = store.listOf('m1', FollowListKind.followers);
      expect(view.status, LoadStatus.ready);
      expect(view.users, hasLength(30));
      expect(view.hasMore, isTrue);

      await store.loadMore('m1', FollowListKind.followers);

      view = store.listOf('m1', FollowListKind.followers);
      expect(ids('m1', FollowListKind.followers), [
        for (var i = 0; i < 35; i++) 'f$i',
      ]);
      expect(view.hasMore, isFalse);
      expect(repo.memberReads, ['followers:m1:0', 'followers:m1:30']);
    },
  );

  test('followers and following are separate lists, per member', () async {
    await store.load('m1', FollowListKind.followers);
    await store.load('m1', FollowListKind.following);
    repo.followingOf['u1'] = [testMember('z')];
    await store.load('u1', FollowListKind.following);

    expect(store.listOf('m1', FollowListKind.followers).users, hasLength(30));
    expect(ids('m1', FollowListKind.following), ['x', 'y']);
    expect(ids('u1', FollowListKind.following), ['z']);
    expect(
      store.listOf('u1', FollowListKind.followers).status,
      LoadStatus.idle,
    );
  });

  test('an empty list is ready, not failed', () async {
    await store.load('nobody', FollowListKind.followers);

    final view = store.listOf('nobody', FollowListKind.followers);
    expect(view.status, LoadStatus.ready);
    expect(view.users, isEmpty);
  });

  test('loadMore does nothing before the first page, on the last page, or twice at once', () async {
    await store.loadMore('m1', FollowListKind.followers);
    expect(repo.memberReads, isEmpty);

    await store.load('m1', FollowListKind.following);
    await store.loadMore(
      'm1',
      FollowListKind.following,
    ); // 2 < 30: no next page
    expect(repo.memberReads, ['following:m1:0']);

    await store.load('m1', FollowListKind.followers);
    await Future.wait([
      store.loadMore('m1', FollowListKind.followers),
      store.loadMore('m1', FollowListKind.followers),
    ]);
    expect(repo.memberReads.where((r) => r == 'followers:m1:30'), hasLength(1));
  });

  test('a page that repeats a member does not list them twice', () async {
    repo.followersOf['m1'] = [for (var i = 0; i < 30; i++) testMember('f$i')];
    await store.load('m1', FollowListKind.followers);
    // Someone followed in between, so the next page starts with a member already shown.
    repo.followersOf['m1'] = [testMember('new'), ...repo.followersOf['m1']!];

    await store.loadMore('m1', FollowListKind.followers);

    final shown = ids('m1', FollowListKind.followers);
    expect(shown.toSet(), hasLength(shown.length));
    expect(shown, contains('f29'));
  });

  group('failures', () {
    test(
      'a list that cannot be loaded is "failed", and loading again recovers',
      () async {
        repo.failFollowLists = true;
        await store.load('m1', FollowListKind.followers);
        expect(
          store.listOf('m1', FollowListKind.followers).status,
          LoadStatus.failed,
        );

        repo.failFollowLists = false;
        await store.load('m1', FollowListKind.followers);
        expect(
          store.listOf('m1', FollowListKind.followers).status,
          LoadStatus.ready,
        );
      },
    );

    test('a page that fails keeps the list and can be retried', () async {
      await store.load('m1', FollowListKind.followers);
      repo.failFollowLists = true;

      await store.loadMore('m1', FollowListKind.followers);
      var view = store.listOf('m1', FollowListKind.followers);
      expect(view.loadMoreFailed, isTrue);
      expect(view.users, hasLength(30));

      repo.failFollowLists = false;
      await store.loadMore('m1', FollowListKind.followers);
      view = store.listOf('m1', FollowListKind.followers);
      expect(view.loadMoreFailed, isFalse);
      expect(view.users, hasLength(35));
    });

    test('opening a list again shows the copy held while it refreshes, and keeps it if that fails', () async {
      await store.load('m1', FollowListKind.following);
      final statuses = <LoadStatus>[];
      store.addListener(() {
        statuses.add(store.listOf('m1', FollowListKind.following).status);
      });

      repo.failFollowLists = true;
      await store.load('m1', FollowListKind.following);

      expect(ids('m1', FollowListKind.following), ['x', 'y']);
      expect(statuses.where((s) => s != LoadStatus.ready), isEmpty);
    });

    test('a refresh replaces the list with the server\'s', () async {
      await store.load('m1', FollowListKind.following);
      repo.followingOf['m1'] = [testMember('y')]; // x was unfollowed

      await store.load('m1', FollowListKind.following);

      expect(ids('m1', FollowListKind.following), ['y']);
    });
  });

  group('accounts', () {
    test('lists are dropped when another account signs in', () async {
      await store.load('m1', FollowListKind.followers);

      authService.emit(testUser('u2'));
      await pumpEventQueue();

      expect(
        store.listOf('m1', FollowListKind.followers).status,
        LoadStatus.idle,
      );
    });

    test('an answer for the previous account is dropped', () async {
      repo.followListGate = Completer<void>();
      final slow = store.load('m1', FollowListKind.followers);
      await pumpEventQueue();
      expect(
        store.listOf('m1', FollowListKind.followers).status,
        LoadStatus.loading,
      );

      authService.emit(testUser('u2'));
      await pumpEventQueue();
      repo.followListGate!.complete();
      await slow;

      expect(
        store.listOf('m1', FollowListKind.followers).status,
        LoadStatus.idle,
      );
    });
  });
}
