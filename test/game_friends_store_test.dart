import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/game_friends.dart';
import 'package:checkpoint/state/auth_store.dart';
import 'package:checkpoint/state/game_friends_store.dart';
import 'package:checkpoint/state/load_status.dart';

import 'support/fakes.dart';

void main() {
  late FakeRepository repo;
  late FakeAuthService authService;
  late AuthStore auth;
  late GameFriendsStore store;

  setUp(() {
    debugPrint = (String? message, {int? wrapWidth}) {};
    SharedPreferences.setMockInitialValues({});
    repo = FakeRepository();
    authService = FakeAuthService(testUser('u1'));
    auth = AuthStore(authService)..initialize();
    store = GameFriendsStore(repository: repo, auth: auth)..initialize();
    repo.friendsWithGame['g1'] = testGameFriends([
      testFriend('a', GameStatus.completed, rating: 4),
      testFriend('b', GameStatus.playing),
    ]);
  });

  tearDown(() {
    debugPrint = debugPrintThrottled;
    store.dispose();
    auth.dispose();
  });

  test('nothing is fetched until a game screen asks', () {
    expect(store.viewOf('g1').status, LoadStatus.idle);
    expect(repo.friendReads, isEmpty);
  });

  test('loads who has the game, by status', () async {
    await store.load('g1');

    final view = store.viewOf('g1');
    expect(view.status, LoadStatus.ready);
    expect(view.friends.membersOf(FriendGroup.completed).single.member.id, 'a');
    expect(view.friends.membersOf(FriendGroup.playing).single.member.id, 'b');
    expect(view.friends.countOf(FriendGroup.wantToPlay), 0);
    expect(view.friends.isEmpty, isFalse);
  });

  test('a game none of them has is ready and empty', () async {
    await store.load('g2');

    expect(store.viewOf('g2').status, LoadStatus.ready);
    expect(store.viewOf('g2').friends.isEmpty, isTrue);
  });

  test('signed out, nothing is asked', () async {
    authService.emit(null);
    await pumpEventQueue();
    await store.load('g1');

    expect(repo.friendReads, isEmpty);
    expect(store.viewOf('g1').status, LoadStatus.idle);
  });

  test(
    'asks again each time the screen opens, showing the copy held meanwhile',
    () async {
      await store.load('g1');
      repo.friendsWithGame['g1'] = testGameFriends([
        testFriend('c', GameStatus.wishlist),
      ]);
      repo.friendsGate = Completer<void>();

      final again = store.load('g1');
      expect(store.viewOf('g1').status, LoadStatus.ready);
      expect(
        store.viewOf('g1').friends.membersOf(FriendGroup.completed),
        isNotEmpty,
      );

      repo.friendsGate!.complete();
      await again;
      expect(repo.friendReads, ['g1', 'g1']);
      expect(store.viewOf('g1').friends.countOf(FriendGroup.completed), 0);
      expect(store.viewOf('g1').friends.countOf(FriendGroup.wantToPlay), 1);
    },
  );

  test('two screens asking at once share one request', () async {
    repo.friendsGate = Completer<void>();

    final first = store.load('g1');
    final second = store.load('g1');
    expect(store.viewOf('g1').status, LoadStatus.loading);
    repo.friendsGate!.complete();
    await Future.wait([first, second]);

    expect(repo.friendReads, ['g1']);
  });

  test(
    'a failed first read is failed; a failed refresh keeps what was shown',
    () async {
      repo.failFriendsReads = true;
      await store.load('g1');
      expect(store.viewOf('g1').status, LoadStatus.failed);

      repo.failFriendsReads = false;
      await store.load('g1');
      expect(store.viewOf('g1').status, LoadStatus.ready);

      repo.failFriendsReads = true;
      await store.load('g1');
      expect(store.viewOf('g1').status, LoadStatus.ready);
      expect(store.viewOf('g1').friends.isEmpty, isFalse);
    },
  );

  test('another account signing in drops it, and an answer for the last one is ignored', () async {
    await store.load('g1');
    repo.friendsGate = Completer<void>();
    final late = store.load('g1');

    authService.emit(testUser('u2'));
    await pumpEventQueue();
    expect(store.viewOf('g1').status, LoadStatus.idle);

    repo.friendsGate!.complete();
    await late;
    expect(store.viewOf('g1').status, LoadStatus.idle);
  });

  group('GameFriends', () {
    test('"Want to play" is To Play and Wishlist together, rated first, then newest', () {
      final friends = testGameFriends(
        [
          testFriend('old', GameStatus.toPlay, added: DateTime.utc(2026, 1)),
          testFriend('new', GameStatus.wishlist, added: DateTime.utc(2026, 5)),
          testFriend('undated', GameStatus.wishlist),
          testFriend(
            'rated',
            GameStatus.toPlay,
            rating: 3,
            added: DateTime.utc(2025, 1),
          ),
          testFriend('gone', GameStatus.dropped),
        ],
        totals: {
          GameStatus.toPlay: 7,
          GameStatus.wishlist: 2,
          GameStatus.dropped: 1,
        },
      );

      expect(
        friends.membersOf(FriendGroup.wantToPlay).map((f) => f.member.id),
        ['rated', 'new', 'old', 'undated'],
      );
      // The counts are the server's, which can be more than were sent.
      expect(friends.countOf(FriendGroup.wantToPlay), 9);
      expect(friends.countOf(FriendGroup.completed), 0);
    });

    test('only Dropped counts as nothing to show', () {
      final friends = testGameFriends([testFriend('gone', GameStatus.dropped)]);

      expect(friends.isEmpty, isTrue);
    });
  });
}
