import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:checkpoint/models/connected_service.dart';
import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/public_profile.dart';
import 'package:checkpoint/state/auth_store.dart';
import 'package:checkpoint/state/profile_store.dart';
import 'package:checkpoint/state/public_profile_store.dart';

import 'support/fakes.dart';

void main() {
  late FakeRepository repo;
  late FakeAuthService authService;
  late AuthStore auth;
  late PublicProfileStore store;
  late DateTime clock;

  Game owned(String id, {bool favorite = false, double rating = 4}) =>
      testGame(id, favorite: favorite, cover: false).copyWith(rating: rating);

  setUp(() {
    debugPrint = (String? message, {int? wrapWidth}) {};
    SharedPreferences.setMockInitialValues({});
    clock = DateTime.utc(2026, 10, 17, 12);
    repo = FakeRepository();
    authService = FakeAuthService(testUser('u1'));
    auth = AuthStore(authService)..initialize();
    store = PublicProfileStore(repository: repo, auth: auth, now: () => clock)
      ..initialize();
  });

  tearDown(() {
    debugPrint = debugPrintThrottled;
    store.dispose();
    auth.dispose();
  });

  int reads(String what) => repo.memberReads.where((r) => r == what).length;

  group('loading a profile', () {
    test('is "loading" until it is asked for', () {
      expect(store.viewOf('m1').status, PublicProfileStatus.loading);
      expect(repo.memberReads, isEmpty);
    });

    test('loads the header, the counts and the three game sections', () async {
      repo.memberGames['m1'] = [
        owned('fav', favorite: true, rating: 5),
        owned('rated', rating: 3),
        owned('plain', rating: 0),
      ];

      await store.load('m1');

      final view = store.viewOf('m1');
      expect(view.status, PublicProfileStatus.ready);
      expect(view.profile!.name, 'Member One');
      expect(view.profile!.steamConnected, isTrue);
      expect(view.profile!.connectedServices, {ConnectedService.steam});
      expect(view.stats!.followers, 5);
      expect(view.stats!.games, 3);
      expect(view.favorites.map((g) => g.id), ['fav']);
      expect(view.rated.map((g) => g.id), ['fav', 'rated']);
      expect(view.library.map((g) => g.id), ['fav', 'rated', 'plain']);
      expect(view.libraryTotal, 3);
      expect(view.libraryHasMore, isFalse);
    });

    test('leaves the signed-in member\'s own ProfileStore alone', () async {
      final own = ProfileStore(repository: repo, auth: auth);
      addTearDown(own.dispose);
      await own.initialize();
      await pumpEventQueue();
      final before = (own.profile.name, own.followingCount, own.followersCount);

      await store.load('m1');

      expect(store.viewOf('m1').profile!.name, 'Member One');
      expect(own.profile.name, 'Ada');
      expect((
        own.profile.name,
        own.followingCount,
        own.followersCount,
      ), before);
    });

    test('asks for nothing about achievements', () async {
      await store.load('m1');

      expect(
        repo.memberReads.where((r) => r.startsWith('achievements')),
        isEmpty,
      );
    });

    test('says so when there is no such member', () async {
      await store.load('ghost');

      expect(store.viewOf('ghost').status, PublicProfileStatus.notFound);
    });

    test('a failed load is "failed", and loading again recovers', () async {
      repo.failProfileReads = true;
      await store.load('m1');
      expect(store.viewOf('m1').status, PublicProfileStatus.failed);

      repo.failProfileReads = false;
      await store.load('m1');
      expect(store.viewOf('m1').status, PublicProfileStatus.ready);
    });

    test('two screens asking at once share one request', () async {
      repo.profileGate = Completer<void>();

      final first = store.load('m1');
      final second = store.load('m1');
      repo.profileGate!.complete();
      await Future.wait([first, second]);

      expect(reads('profile:m1'), 1);
    });
  });

  group('the cache', () {
    test('opening a profile again does not ask the server', () async {
      await store.load('m1');
      await store.load('m1');

      expect(reads('profile:m1'), 1);
    });

    test(
      'a profile older than the cache lifetime is shown while it is refreshed',
      () async {
        await store.load('m1');
        clock = clock.add(const Duration(minutes: 6));
        repo.members['m1'] = const PublicProfile(
          id: 'm1',
          name: 'Renamed',
          handle: '@member_one',
        );
        repo.profileGate = Completer<void>();
        final statuses = <PublicProfileStatus>[];
        store.addListener(() => statuses.add(store.viewOf('m1').status));

        final refresh = store.load('m1');
        await pumpEventQueue();
        expect(
          store.viewOf('m1').profile!.name,
          'Member One',
        ); // still on screen
        repo.profileGate!.complete();
        await refresh;

        expect(store.viewOf('m1').profile!.name, 'Renamed');
        expect(
          statuses,
          everyElement(PublicProfileStatus.ready),
        ); // never blanked
      },
    );

    test('force fetches again whatever the age', () async {
      await store.load('m1');
      await store.load('m1', force: true);

      expect(reads('profile:m1'), 2);
    });

    test(
      'a refresh that fails keeps the copy and says it may be out of date',
      () async {
        await store.load('m1');
        repo.failProfileReads = true;

        await store.load('m1', force: true);

        final view = store.viewOf('m1');
        expect(view.status, PublicProfileStatus.ready);
        expect(view.profile!.name, 'Member One');
        expect(view.refreshFailed, isTrue);
      },
    );

    test('keeps only the most recently opened profiles', () async {
      store.dispose();
      store = PublicProfileStore(
        repository: repo,
        auth: auth,
        capacity: 2,
        now: () => clock,
      )..initialize();
      for (final id in ['a', 'b', 'c']) {
        repo.members[id] = PublicProfile(id: id, name: id, handle: '@$id');
        await store.load(id);
      }

      expect(store.viewOf('a').status, PublicProfileStatus.loading); // dropped
      expect(store.viewOf('b').status, PublicProfileStatus.ready);
      expect(store.viewOf('c').status, PublicProfileStatus.ready);
    });

    test(
      'is dropped when another account signs in, and after sign-out',
      () async {
        repo.memberGames['m1'] = [owned('g1')];
        await store.load('m1');
        expect(store.gameById('g1'), isNotNull);

        authService.emit(testUser('u2'));
        await pumpEventQueue();

        expect(store.viewOf('m1').status, PublicProfileStatus.loading);
        expect(store.gameById('g1'), isNull);

        await store.load('m1');
        authService.emit(null);
        await pumpEventQueue();
        expect(store.viewOf('m1').status, PublicProfileStatus.loading);
      },
    );

    test(
      'is kept when the same account is announced again (token refresh)',
      () async {
        await store.load('m1');

        authService.emit(testUser('u1'));
        await pumpEventQueue();

        expect(store.viewOf('m1').status, PublicProfileStatus.ready);
      },
    );

    test(
      'an answer that arrives after the account changed is dropped',
      () async {
        repo.profileGate = Completer<void>();
        final loading = store.load('m1');
        await pumpEventQueue();

        authService.emit(testUser('u2'));
        await pumpEventQueue();
        repo.profileGate!.complete();
        await loading;

        expect(store.viewOf('m1').status, PublicProfileStatus.loading);
      },
    );
  });

  group('the library', () {
    setUp(() {
      repo.memberGames['m1'] = [
        for (var i = 0; i < 70; i++) owned('g$i', rating: 0),
      ];
    });

    test('comes a page at a time, until the total is reached', () async {
      await store.load('m1');
      var view = store.viewOf('m1');
      expect(view.library, hasLength(30));
      expect(view.libraryTotal, 70);
      expect(view.libraryHasMore, isTrue);

      await store.loadMoreLibrary('m1');
      expect(store.viewOf('m1').library, hasLength(60));

      await store.loadMoreLibrary('m1');
      view = store.viewOf('m1');
      expect(view.library.map((g) => g.id), [
        for (var i = 0; i < 70; i++) 'g$i',
      ]);
      expect(view.libraryHasMore, isFalse);

      await store.loadMoreLibrary('m1'); // nothing left: no request
      expect(reads('library:m1:70'), 0);
    });

    test('two calls at once fetch one page', () async {
      await store.load('m1');

      await Future.wait([
        store.loadMoreLibrary('m1'),
        store.loadMoreLibrary('m1'),
      ]);

      expect(reads('library:m1:30'), 1);
      expect(store.viewOf('m1').library, hasLength(60));
    });

    test('a failed page can be retried', () async {
      await store.load('m1');
      repo.failProfileReads = true;

      await store.loadMoreLibrary('m1');
      expect(store.viewOf('m1').loadMoreLibraryFailed, isTrue);
      expect(store.viewOf('m1').library, hasLength(30));

      repo.failProfileReads = false;
      await store.loadMoreLibrary('m1');
      expect(store.viewOf('m1').loadMoreLibraryFailed, isFalse);
      expect(store.viewOf('m1').library, hasLength(60));
    });

    test(
      'stops asking when the server has fewer games than the count said',
      () async {
        repo.stats['m1'] = const PublicProfileStats(
          followers: 0,
          following: 0,
          viewerFollows: false,
          games: 90, // 20 of these were removed since
        );
        await store.load('m1');
        await store.loadMoreLibrary('m1');
        await store.loadMoreLibrary('m1');
        expect(store.viewOf('m1').library, hasLength(70));

        await store.loadMoreLibrary('m1'); // an empty page
        expect(store.viewOf('m1').libraryHasMore, isFalse);
        final asked = reads('library:m1:70');

        await store.loadMoreLibrary('m1');
        expect(reads('library:m1:70'), asked);
      },
    );
  });

  group('followersFor', () {
    test(
      'counts the viewer\'s own follow or unfollow since the page was read',
      () async {
        await store.load('m1'); // 5 followers, the viewer does not follow
        final view = store.viewOf('m1');

        expect(view.followersFor(viewerFollows: false), 5);
        expect(view.followersFor(viewerFollows: true), 6);
      },
    );

    test(
      'when the viewer already followed, unfollowing takes one off',
      () async {
        repo.stats['m1'] = const PublicProfileStats(
          followers: 5,
          following: 0,
          viewerFollows: true,
          games: 0,
        );
        await store.load('m1');
        final view = store.viewOf('m1');

        expect(view.followersFor(viewerFollows: true), 5);
        expect(view.followersFor(viewerFollows: false), 4);
      },
    );
  });

  group('gameById', () {
    test(
      'finds a game from a loaded profile without the owner\'s own state',
      () async {
        repo.memberGames['m1'] = [owned('g1', favorite: true, rating: 5)];
        await store.load('m1');

        final game = store.gameById('g1')!;

        expect(game.title, 'Game g1');
        expect(game.status, isNull);
        expect(game.rating, 0);
        expect(game.hoursPlayed, 0);
        expect(game.isFavorite, isFalse);
        expect(store.gameById('missing'), isNull);
      },
    );
  });
}
