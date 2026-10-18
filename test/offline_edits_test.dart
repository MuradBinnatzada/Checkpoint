import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:checkpoint/models/game.dart';
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
  late LibraryStore library;

  LibraryStore newLibrary() => LibraryStore(
    repository: repo,
    auth: auth,
    profile: profile,
    cache: cache,
    connectivity: network,
  );

  setUp(() async {
    debugPrint = (String? message, {int? wrapWidth}) {};
    SharedPreferences.setMockInitialValues({});
    repo = FakeRepository()..library = [testGame('a'), testGame('b')];
    authService = FakeAuthService(testUser('u1'));
    network = FakeConnectivity();
    cache = LocalCache();
    auth = AuthStore(authService);
    await auth.initialize();
    profile = ProfileStore(repository: repo, auth: auth, cache: cache);
    library = newLibrary();
  });

  tearDown(() {
    debugPrint = debugPrintThrottled;
    library.dispose();
    profile.dispose();
    auth.dispose();
  });

  Game game(String id) => library.libraryGames.firstWhere((g) => g.id == id);

  test('an edit made offline is sent when the connection comes back', () async {
    await library.initialize();
    await pumpEventQueue();
    repo.offline = true;

    await library.setRating('a', 3);

    expect(library.pendingCount, 1);
    expect(game('a').rating, 3);
    expect(library.isOffline, isTrue);
    expect(repo.writes, isEmpty);

    repo.offline = false;
    repo.library = [testGame('a'), testGame('b')];
    network.controller.add(true);
    await pumpEventQueue();

    expect(repo.writes, ['game:a:GameStatus.playing:3.0']);
    expect(library.pendingCount, 0);
    expect(library.isOffline, isFalse);
  });

  test('a refresh while edits are waiting does not undo them', () async {
    await library.initialize();
    await pumpEventQueue();
    repo.offline = true;
    await library.setRating('a', 3);
    repo.offline = false; // reads work again, but nothing has flushed yet

    // e.g. the realtime stream asking for a refetch: the server still has 4.5.
    await library.refresh();
    expect(game('a').rating, isNotNull);
    // The refresh itself flushes the queue, so the edit ends up on the server.
    await pumpEventQueue();
    expect(repo.writes, contains('game:a:GameStatus.playing:3.0'));
    expect(library.pendingCount, 0);
  });

  test('queued edits survive the app being closed', () async {
    await library.initialize();
    await pumpEventQueue();
    repo.offline = true;
    await library.setRating('a', 3);
    await library.removeFromLibrary('b');
    await pumpEventQueue();
    library.dispose();

    library = newLibrary(); // the app opened again, still offline
    await library.initialize();

    expect(library.pendingCount, 2);
    expect(library.libraryGames.map((g) => g.id), ['a']);
    expect(library.libraryGames.single.rating, 3);
    expect(library.isOffline, isTrue);
  });

  test('a session logged offline keeps the time it was logged, not the time it was sent', () async {
    await library.initialize();
    await pumpEventQueue();
    repo.offline = true;
    await library.logSession(gameId: 'a', hours: 2);
    final loggedAt = library.logsFor('a').single.timestamp;

    await Future<void>.delayed(const Duration(milliseconds: 5));
    repo.offline = false;
    await library.flushPending();

    expect(repo.writes, contains('log:a:2.0'));
    expect(repo.logTimes, hasLength(1));
    expect(repo.logTimes.single!.isAtSameMomentAs(loggedAt), isTrue);
  });

  test('a game removed while offline keeps its sessions hidden after a restart', () async {
    repo.logs = [testLog('l1', 'b')];
    await library.initialize();
    await pumpEventQueue();
    repo.offline = true;
    await library.removeFromLibrary('b');
    await pumpEventQueue();
    library.dispose();

    library = newLibrary(); // the saved copy still has the game's sessions
    await library.initialize();

    expect(library.libraryGames.map((g) => g.id), ['a']);
    expect(library.logsFor('b'), isEmpty);
    expect(library.recentActivity(), isEmpty);
  });

  test('queued changes go out as deletes, then games, then sessions', () async {
    await library.initialize();
    await pumpEventQueue();
    repo.offline = true;
    await library.logSession(gameId: 'a', hours: 2);
    await library.removeFromLibrary('b');
    expect(library.logsFor('a'), hasLength(1));

    repo.offline = false;
    await library.flushPending();

    expect(repo.writes, [
      'delete:b',
      'game:a:GameStatus.playing:4.5',
      'log:a:2.0',
    ]);
    expect(library.pendingCount, 0);
  });

  test('stops at the first thing the server cannot be reached for and keeps the rest', () async {
    await library.initialize();
    await pumpEventQueue();
    repo.offline = true;
    await library.setRating('a', 3);
    await library.removeFromLibrary('b');

    await library.flushPending(); // still offline

    expect(repo.writes, isEmpty);
    expect(library.pendingCount, 2);
  });

  test('an edit the server refuses is reverted, not queued', () async {
    await library.initialize();
    await pumpEventQueue();
    repo.rejectWrites = true;

    await library.setRating('a', 3);

    expect(library.notice, 'Could not save that game update.');
    expect(library.pendingCount, 0);
  });

  test('a delete the server refuses says so and brings the game back', () async {
    repo.logs = [testLog('l1', 'b')];
    await library.initialize();
    await pumpEventQueue();
    repo.rejectWrites = true;

    await library.removeFromLibrary('b');

    expect(library.notice, 'Could not remove that game.');
    expect(library.pendingCount, 0);
    // The server still has it: the library is read again (after its debounce).
    await Future<void>.delayed(const Duration(milliseconds: 350));
    expect(library.libraryGames.map((g) => g.id), containsAll(['a', 'b']));
    expect(library.logsFor('b'), hasLength(1));
  });

  test('a queued edit the server later refuses is dropped with a notice', () async {
    await library.initialize();
    await pumpEventQueue();
    repo.offline = true;
    await library.setRating('a', 3);
    repo.offline = false;
    repo.rejectWrites = true;

    await library.flushPending();

    expect(library.pendingCount, 0);
    expect(library.notice, 'Some offline changes could not be saved.');
  });

  test('losing the connection marks the library as saved-copy', () async {
    await library.initialize();
    await pumpEventQueue();
    expect(library.isOffline, isFalse);

    network.controller.add(false);
    await pumpEventQueue();

    expect(library.isOffline, isTrue);
  });

  test('a repeat auth event right after loading does not fetch the library again', () async {
    await library.initialize();
    await pumpEventQueue();
    final fetches = repo.libraryFetches;

    authService.emit(testUser('u1')); // token refresh, app resume...
    await pumpEventQueue();

    expect(repo.libraryFetches, fetches);
  });

  group('app started offline with an expired session', () {
    setUp(() async {
      authService = FakeAuthService()..persistedId = 'u1';
      auth.dispose();
      auth = AuthStore(authService);
      await auth.initialize();
      profile = ProfileStore(repository: repo, auth: auth, cache: cache);
      library.dispose();
      library = newLibrary();
      await cache.writeLibrary('u1', [testGame('a'), testGame('b')]);
    });

    test('shows the saved library without calling the server', () async {
      expect(auth.isSessionPending, isTrue);
      expect(auth.isLoggedIn, isTrue);

      await library.initialize();

      expect(library.libraryGames.map((g) => g.id), ['a', 'b']);
      expect(library.isOffline, isTrue);
      expect(library.loadError, isNull);
      expect(repo.libraryFetches, 0);
    });

    test('queues edits instead of sending them', () async {
      await library.initialize();

      await library.setRating('a', 3);

      expect(library.pendingCount, 1);
      expect(repo.writes, isEmpty);
    });

    test('restoring the session loads the library and sends the queue', () async {
      authService.restoreWorks = true;
      await library.initialize();
      await library.setRating('a', 3);

      network.controller.add(true);
      await pumpEventQueue();

      expect(authService.restoreCalls, 1);
      expect(auth.isSessionPending, isFalse);
      expect(repo.libraryFetches, greaterThan(0));
      expect(repo.writes, contains('game:a:GameStatus.playing:3.0'));
      expect(library.pendingCount, 0);
      expect(library.isOffline, isFalse);
    });

    test('a failed restore keeps the saved library', () async {
      await library.initialize();

      await library.refresh();

      expect(authService.restoreCalls, 1);
      expect(auth.isSessionPending, isTrue);
      expect(library.libraryGames, hasLength(2));
    });

    test('logging out forgets the saved session', () async {
      await auth.logOut();

      expect(auth.isLoggedIn, isFalse);
      expect(authService.persistedId, isNull);
    });
  });

  test('pending edits round-trip through storage', () async {
    final edits = PendingEdits()
      ..putGame(testGame('a'))
      ..markRemoved('b')
      ..logs.add(
        PendingLog(
          localId: 'local-1',
          gameId: 'a',
          hours: 1.5,
          platform: GamePlatform.pc,
          note: 'n',
          timestamp: DateTime.utc(2026, 1, 1),
        ),
      );
    final storage = PendingEditsStorage();
    await storage.write('u1', edits);

    final read = await storage.read('u1');
    expect(read.games.keys, ['a']);
    expect(read.removed, {'b'});
    expect(read.logs.single.localId, 'local-1');

    await storage.write('u1', PendingEdits());
    expect((await storage.read('u1')).isEmpty, isTrue);
  });

  group('pending follows', () {
    test('keep only the last choice per person', () {
      final edits = PendingEdits()
        ..putFollow('x', following: true)
        ..putFollow('y', following: false);
      expect(edits.follows, {'x': true, 'y': false});
      expect(edits.count, 2);

      edits
        ..putFollow('x', following: false) // undoes the queued follow
        ..putFollow('y', following: false);
      expect(edits.follows, {'y': false});

      edits.putFollow('x', following: false); // nothing queued for x: this is new
      expect(edits.follows, {'x': false, 'y': false});
    });

    test('round-trip through JSON with the rest of the edits', () {
      final edits = PendingEdits()
        ..putGame(testGame('a'))
        ..putFollow('x', following: true)
        ..putFollow('y', following: false);

      final read = PendingEdits.fromJson(
        Map<String, dynamic>.from(jsonDecode(jsonEncode(edits.toJson())) as Map),
      );

      expect(read.follows, {'x': true, 'y': false});
      expect(read.games.keys, ['a']);
      expect(read.count, 3);
    });

    test('each scope is saved under its own key and only holds its own part', () async {
      final edits = PendingEdits()
        ..putGame(testGame('a'))
        ..markRemoved('b')
        ..putFollow('x', following: true);
      final library = PendingEditsStorage();
      final follows = PendingEditsStorage(PendingScope.follows);

      await library.write('u1', edits);
      await follows.write('u1', edits);

      final libraryRead = await library.read('u1');
      expect(libraryRead.games.keys, ['a']);
      expect(libraryRead.removed, {'b'});
      expect(libraryRead.follows, isEmpty);
      final followsRead = await follows.read('u1');
      expect(followsRead.follows, {'x': true});
      expect(followsRead.games, isEmpty);
      expect(followsRead.removed, isEmpty);
    });

    test('an empty scope deletes only its own key', () async {
      final edits = PendingEdits()
        ..putGame(testGame('a'))
        ..putFollow('x', following: true);
      final library = PendingEditsStorage();
      final follows = PendingEditsStorage(PendingScope.follows);
      await library.write('u1', edits);
      await follows.write('u1', edits);

      // The library's queue is done; the follows are not.
      await library.write('u1', PendingEdits());
      expect((await library.read('u1')).isEmpty, isTrue);
      expect((await follows.read('u1')).follows, {'x': true});

      await follows.write('u1', PendingEdits());
      expect((await follows.read('u1')).isEmpty, isTrue);
    });

    test('edits saved before follows existed are still found', () async {
      SharedPreferences.setMockInitialValues({
        'pending.v1.u1': jsonEncode({
          'games': <Object>[],
          'removed': ['b'],
          'logs': <Object>[],
        }),
      });

      final read = await PendingEditsStorage().read('u1');

      expect(read.removed, {'b'});
      expect(read.follows, isEmpty);
    });
  });
}
