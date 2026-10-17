import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:checkpoint/services/local_cache.dart';
import 'package:checkpoint/services/pending_edits.dart';
import 'package:checkpoint/state/auth_store.dart';
import 'package:checkpoint/state/library_store.dart';
import 'package:checkpoint/state/profile_store.dart';

import 'support/fakes.dart';

void main() {
  late FakeRepository repo;
  late FakeAuthService authService;
  late FakeConnectivity network;
  late LocalCache cache;
  late AuthStore auth;
  late ProfileStore profile;

  ProfileStore newProfile() => ProfileStore(
    repository: repo,
    auth: auth,
    cache: cache,
    connectivity: network,
  );

  final followsStorage = PendingEditsStorage(PendingScope.follows);

  setUp(() async {
    debugPrint = (String? message, {int? wrapWidth}) {};
    SharedPreferences.setMockInitialValues({});
    repo = FakeRepository();
    authService = FakeAuthService(testUser('u1'));
    network = FakeConnectivity();
    cache = LocalCache();
    auth = AuthStore(authService);
    await auth.initialize();
    profile = newProfile();
  });

  tearDown(() {
    debugPrint = debugPrintThrottled;
    profile.dispose();
    auth.dispose();
  });

  /// Signed in and loaded (following `friend-1`), then the connection drops.
  Future<void> startOffline() async {
    await profile.initialize();
    await pumpEventQueue();
    repo.offline = true;
  }

  test('a follow made offline is kept on screen and sent when the connection comes back', () async {
    await startOffline();

    await profile.toggleFollow('x');

    expect(profile.isFollowing('x'), isTrue);
    expect(profile.followingCount, 2);
    expect(profile.pendingCount, 1);
    expect(profile.notice, queuedNotice);
    expect(repo.writes, isEmpty);
    profile.clearNotice();

    repo.offline = false;
    network.controller.add(true);
    await pumpEventQueue();

    expect(repo.writes, ['follow:x']);
    expect(profile.pendingCount, 0);
    expect(profile.isFollowing('x'), isTrue);
    expect(profile.notice, isNull);
  });

  test('an unfollow made offline is sent when the connection comes back', () async {
    await startOffline();

    await profile.toggleFollow('friend-1');

    expect(profile.isFollowing('friend-1'), isFalse);
    expect(profile.pendingCount, 1);

    repo.offline = false;
    network.controller.add(true);
    await pumpEventQueue();

    expect(repo.writes, ['unfollow:friend-1']);
    expect(profile.isFollowing('friend-1'), isFalse);
    expect(profile.pendingCount, 0);
  });

  test('a follow followed by an unfollow cancels out and sends nothing', () async {
    await startOffline();

    await profile.toggleFollow('x');
    await profile.toggleFollow('x');
    await profile.toggleFollow('friend-1');
    await profile.toggleFollow('friend-1');
    await pumpEventQueue();

    expect(profile.isFollowing('x'), isFalse);
    expect(profile.isFollowing('friend-1'), isTrue);
    expect(profile.pendingCount, 0);
    expect((await followsStorage.read('u1')).isEmpty, isTrue);

    repo.offline = false;
    network.controller.add(true);
    await pumpEventQueue();
    expect(repo.writes, isEmpty);
  });

  test('toggling a queued follow does not jump ahead of the queue', () async {
    await startOffline();
    await profile.toggleFollow('x');
    repo.offline = false; // reads and writes work again, but nothing has flushed

    await profile.toggleFollow('x'); // undoes the queued follow

    expect(repo.writes, isEmpty);
    expect(profile.isFollowing('x'), isFalse);
    expect(profile.pendingCount, 0);
  });

  test('a follow made while the queue is being sent goes after it', () async {
    await startOffline();
    await profile.toggleFollow('x');
    repo.offline = false;
    repo.followGate = Completer<void>();

    final replay = profile.flushPending(); // the follow of x is now in flight
    await pumpEventQueue();
    final undo = profile.toggleFollow('x'); // taps unfollow right away
    await pumpEventQueue();
    expect(profile.isFollowing('x'), isFalse); // shown at once
    expect(repo.writes, isEmpty); // but not sent ahead of the follow

    repo.followGate!.complete();
    await Future.wait([replay, undo]);
    await pumpEventQueue();

    expect(repo.writes, ['follow:x', 'unfollow:x']);
    expect(repo.following, {'friend-1'});
    expect(profile.isFollowing('x'), isFalse);
    expect(profile.pendingCount, 0);
  });

  test('a refresh while follows are waiting does not undo them', () async {
    await profile.initialize();
    await pumpEventQueue();
    repo.writesDown = true; // reads work, the follow can't be sent
    await profile.toggleFollow('x');
    await profile.toggleFollow('friend-1');

    await profile.refresh();
    await pumpEventQueue();

    expect(profile.isFollowing('x'), isTrue);
    expect(profile.isFollowing('friend-1'), isFalse);
    expect(profile.pendingCount, 2);
  });

  test('the saved copy never holds a follow the server has not accepted', () async {
    await profile.initialize();
    await pumpEventQueue();
    repo.writesDown = true;
    await profile.toggleFollow('x');

    await profile.refresh(); // fetches and saves what the server returned
    await pumpEventQueue();

    final saved = (await cache.readSocial('u1'))!.value;
    expect(saved.followingIds, {'friend-1'});
    expect(profile.isFollowing('x'), isTrue);
  });

  test('queued follows survive the app being closed', () async {
    await startOffline();
    await profile.toggleFollow('x');
    await profile.toggleFollow('friend-1');
    await pumpEventQueue();
    profile.dispose();

    profile = newProfile(); // the app opened again, still offline
    await profile.initialize();

    expect(profile.pendingCount, 2);
    expect(profile.isFollowing('x'), isTrue);
    expect(profile.isFollowing('friend-1'), isFalse);
  });

  test('saved follows show even when nothing else is saved', () async {
    await followsStorage.write('u1', PendingEdits()..putFollow('x', following: true));
    repo.offline = true;

    await profile.initialize();

    expect(profile.isFollowing('x'), isTrue);
    expect(profile.followingCount, 1);
    expect(profile.pendingCount, 1);
  });

  test('follows saved by an earlier run are sent once the app gets online', () async {
    await followsStorage.write('u1', PendingEdits()..putFollow('x', following: true));
    repo.offline = true;
    await profile.initialize(); // the load fails: nothing is on screen from the server

    repo.offline = false;
    network.controller.add(true);
    await pumpEventQueue();

    expect(repo.writes, ['follow:x']);
    expect(profile.pendingCount, 0);
    expect(profile.isFollowing('x'), isTrue);
    expect(profile.followersCount, 3); // and the reload went through
  });

  test('another account does not see or send the first one\'s queued follows', () async {
    await startOffline();
    await profile.toggleFollow('x');
    await pumpEventQueue();

    authService.emit(testUser('u2'));
    await pumpEventQueue();
    expect(profile.pendingCount, 0);
    expect(profile.isFollowing('x'), isFalse);

    repo.offline = false;
    network.controller.add(true);
    await pumpEventQueue();
    expect(repo.writes, isEmpty);
    // Still waiting for when the first account signs in again.
    expect(await followsStorage.read('u1').then((e) => e.follows), {'x': true});
  });

  group('a follow the server answers', () {
    test('by refusing it is reverted with a notice', () async {
      await profile.initialize();
      await pumpEventQueue();
      repo.rejectWrites = true;

      await profile.toggleFollow('x');

      expect(profile.isFollowing('x'), isFalse);
      expect(profile.notice, 'Could not follow that user.');
      expect(profile.pendingCount, 0);
    });

    test('by refusing an unfollow puts the follow back', () async {
      await profile.initialize();
      await pumpEventQueue();
      repo.rejectWrites = true;

      await profile.toggleFollow('friend-1');

      expect(profile.isFollowing('friend-1'), isTrue);
      expect(profile.notice, 'Could not unfollow that user.');
      expect(profile.pendingCount, 0);
    });

    test('by refusing it later drops it with a notice', () async {
      await startOffline();
      await profile.toggleFollow('x');
      profile.clearNotice();
      repo.offline = false;
      repo.rejectWrites = true;

      await profile.flushPending();
      await pumpEventQueue();

      expect(profile.pendingCount, 0);
      expect(profile.notice, 'Some offline follow changes could not be saved.');
      expect(profile.isFollowing('x'), isFalse);
    });

    test('with "already following" counts as sent', () async {
      await startOffline();
      await profile.toggleFollow('x');
      profile.clearNotice();
      repo.following.add('x'); // e.g. followed from another device meanwhile
      repo.offline = false;

      await profile.flushPending();
      await pumpEventQueue();

      expect(profile.pendingCount, 0);
      expect(profile.notice, isNull);
      expect(profile.isFollowing('x'), isTrue);
    });

    test('by not being reachable keeps the rest queued', () async {
      await startOffline();
      await profile.toggleFollow('x');
      await profile.toggleFollow('y');

      await profile.flushPending(); // still offline

      expect(repo.writes, isEmpty);
      expect(profile.pendingCount, 2);
    });
  });

  group('app started offline with an expired session', () {
    setUp(() async {
      authService = FakeAuthService()
        ..persistedId = 'u1'
        ..restoreWorks = true;
      profile.dispose();
      auth.dispose();
      auth = AuthStore(authService);
      await auth.initialize();
      profile = newProfile();
    });

    test('queues follows instead of sending them', () async {
      await profile.initialize();
      expect(auth.isSessionPending, isTrue);

      await profile.toggleFollow('x');

      expect(profile.isFollowing('x'), isTrue);
      expect(profile.pendingCount, 1);
      expect(repo.writes, isEmpty);
    });

    test('restoring the session sends them', () async {
      await profile.initialize();
      await profile.toggleFollow('x');

      await auth.restoreSession();
      await pumpEventQueue();

      expect(auth.isSessionPending, isFalse);
      expect(repo.writes, ['follow:x']);
      expect(profile.pendingCount, 0);
      expect(profile.isFollowing('x'), isTrue);
    });
  });

  group('library and follows queued together', () {
    late LibraryStore library;

    setUp(() async {
      repo.library = [testGame('a'), testGame('b')];
      library = LibraryStore(
        repository: repo,
        auth: auth,
        profile: profile,
        cache: cache,
        connectivity: network,
      );
      await profile.initialize();
      await library.initialize();
      await pumpEventQueue();
      repo.offline = true;
      await library.setRating('a', 3);
      await profile.toggleFollow('x');
      await pumpEventQueue();
    });

    tearDown(() => library.dispose());

    test('each is saved under its own key', () async {
      final libraryEdits = await PendingEditsStorage().read('u1');
      final followEdits = await followsStorage.read('u1');

      expect(libraryEdits.games.keys, ['a']);
      expect(libraryEdits.follows, isEmpty);
      expect(followEdits.follows, {'x': true});
      expect(followEdits.games, isEmpty);
    });

    test('finishing the library\'s queue leaves the follows saved', () async {
      repo.offline = false;
      await library.flushPending(); // empties the library's entry, deleting its key
      await pumpEventQueue();

      expect(library.pendingCount, 0);
      expect(profile.pendingCount, 1); // never sent: only the library was flushed
      expect((await followsStorage.read('u1')).follows, {'x': true});
    });

    test('finishing the follows leaves the library\'s queue saved', () async {
      repo.offline = false;
      await profile.flushPending();
      await pumpEventQueue();

      expect(profile.pendingCount, 0);
      expect(library.pendingCount, 1);
      expect((await PendingEditsStorage().read('u1')).games.keys, ['a']);
    });
  });
}
