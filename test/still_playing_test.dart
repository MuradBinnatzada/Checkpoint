import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:checkpoint/models/achievement.dart';
import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/library_stats.dart';
import 'package:checkpoint/screens/game_detail/game_detail_screen.dart';
import 'package:checkpoint/services/local_cache.dart';
import 'package:checkpoint/state/app_stores.dart';
import 'package:checkpoint/state/auth_store.dart';
import 'package:checkpoint/state/library_store.dart';
import 'package:checkpoint/state/profile_store.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/app_theme.dart';
import 'package:checkpoint/widgets/status_pill.dart';

import 'support/fakes.dart';

/// Silences what the stores log for the rest of the test.
void _quiet() {
  final print = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {};
  addTearDown(() => debugPrint = print);
}

/// A completed game the member still plays: it stays Completed and is listed
/// under Playing too. And the game screen's achievements, which show the
/// progress and open the list in a dialog.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the data', () {
    test('only a completed game is still played', () {
      final finished = testGame('a', status: GameStatus.completed);
      final still = finished.copyWith(stillPlaying: true);

      expect(finished.isPlaying, isFalse);
      expect(still.isPlaying, isTrue);
      expect(still.isListedUnder(GameStatus.completed), isTrue);
      expect(still.isListedUnder(GameStatus.playing), isTrue);
      expect(still.isListedUnder(GameStatus.toPlay), isFalse);
      // A stray flag on another status means nothing.
      final dropped = testGame(
        'b',
        status: GameStatus.dropped,
      ).copyWith(stillPlaying: true);
      expect(dropped.isPlaying, isFalse);
      expect(dropped.isListedUnder(GameStatus.playing), isFalse);
    });

    test('the flag is kept in the saved copy and by the other copies', () {
      final still = testGame(
        'a',
        status: GameStatus.completed,
      ).copyWith(stillPlaying: true);

      expect(Game.fromJson(still.toJson()).stillPlaying, isTrue);
      expect(still.withCompletedAt(null).stillPlaying, isTrue);
      expect(still.withBackdrop(null).stillPlaying, isTrue);
      expect(still.withCompletionTime(null).stillPlaying, isTrue);
      expect(still.withoutUserState().stillPlaying, isFalse);
      // A copy saved before there was a flag reads as not still playing.
      final old = testGame('b', status: GameStatus.completed).toJson()
        ..remove('stillPlaying');
      expect(Game.fromJson(old).stillPlaying, isFalse);
    });

    test('the profile counts it for Completed and Playing both', () {
      final stats = LibraryStats.of([
        testGame(
          'a',
          status: GameStatus.completed,
        ).copyWith(stillPlaying: true),
        testGame('b', status: GameStatus.completed),
        testGame('c'),
      ]);

      expect(stats.games, 3);
      expect(stats.count(GameStatus.completed), 2);
      expect(stats.count(GameStatus.playing), 2);
    });
  });

  group('in the library', () {
    late FakeRepository repo;
    late LocalCache cache;
    late AuthStore auth;
    late ProfileStore profile;
    late LibraryStore library;

    setUp(() async {
      _quiet();
      repo = FakeRepository()
        ..library = [
          testGame('a', status: GameStatus.completed),
          testGame('b'),
        ];
      cache = LocalCache();
      auth = AuthStore(FakeAuthService(testUser('u1')));
      await auth.initialize();
      profile = ProfileStore(repository: repo, auth: auth, cache: cache);
      library = LibraryStore(
        repository: repo,
        auth: auth,
        profile: profile,
        cache: cache,
        connectivity: FakeConnectivity(),
      );
      await library.initialize();
      await pumpEventQueue();
    });

    tearDown(() {
      library.dispose();
      profile.dispose();
      auth.dispose();
    });

    Game game(String id) => library.libraryGames.firstWhere((g) => g.id == id);

    test(
      'is saved, and listed under Playing while it stays Completed',
      () async {
        await library.setStillPlaying('a', true);

        expect(game('a').status, GameStatus.completed);
        expect(game('a').stillPlaying, isTrue);
        expect(repo.stillPlayingSent['a'], isTrue);
        expect(library.count(GameStatus.playing), 2);
        expect(library.count(GameStatus.completed), 1);
        expect([
          for (final g in library.playingNow()) g.id,
        ], containsAll(['a', 'b']));
      },
    );

    test('is only for a completed game', () async {
      await library.setStillPlaying('b', true);

      expect(game('b').stillPlaying, isFalse);
      expect(repo.writes, isEmpty);
    });

    test('goes with any other status, and comes back with an undo', () async {
      await library.setStillPlaying('a', true);
      await library.setStatus('a', GameStatus.dropped);
      expect(game('a').stillPlaying, isFalse);
      expect(repo.stillPlayingSent['a'], isFalse);

      // Completed again from elsewhere: finished with, unless told otherwise.
      await library.setStatus('a', GameStatus.completed);
      expect(game('a').stillPlaying, isFalse);

      await library.setStatus('a', GameStatus.completed, stillPlaying: true);
      expect(game('a').stillPlaying, isTrue);
      expect(repo.stillPlayingSent['a'], isTrue);
    });

    test('a game marked completed is not still played', () async {
      await library.setStatus('b', GameStatus.completed);

      expect(game('b').stillPlaying, isFalse);
      expect(library.count(GameStatus.playing), 0);
    });

    test('logging time on it keeps it as it is', () async {
      await library.setStillPlaying('a', true);
      await library.logSession(gameId: 'a', hours: 1);

      expect(game('a').status, GameStatus.completed);
      expect(game('a').stillPlaying, isTrue);
    });
  });

  group('on the game\'s screen', () {
    late FakeRepository repo;
    late AppStores stores;

    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
    }

    Future<void> open(WidgetTester tester, Game game) async {
      tester.view.physicalSize = const Size(800, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      repo.library = [game];
      stores = AppStores(
        repository: repo,
        authService: FakeAuthService(testUser('u1')),
        connectivity: FakeConnectivity(),
        apiService: FakeDetailsApi(),
      );
      await tester.runAsync(stores.initialize);
      await tester.pumpWidget(
        AppStoresScope(
          stores: stores,
          child: MaterialApp(
            theme: buildTheme(),
            home: GameDetailScreen(gameId: game.id),
          ),
        ),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        stores.dispose();
      });
      await tester.pumpAndSettle();
      await settle(tester);
    }

    setUp(() => repo = FakeRepository());

    Game hades({GameStatus status = GameStatus.completed}) =>
        testGame('g1', title: 'Hades', status: status, cover: false);

    Finder pill(GameStatus status) =>
        find.byWidgetPredicate((w) => w is StatusPill && w.status == status);

    testWidgets(
      'a completed game can be kept under Playing, and stays Completed',
      (tester) async {
        await open(tester, hades());
        expect(find.text('Start Playing'), findsNothing);
        expect(pill(GameStatus.playing), findsNothing);

        await tester.tap(find.text('Still playing'));
        await settle(tester);

        expect(repo.stillPlayingSent['g1'], isTrue);
        expect(pill(GameStatus.completed), findsOneWidget);
        expect(pill(GameStatus.playing), findsOneWidget);
        expect(find.text('Listed under Playing too'), findsOneWidget);

        await tester.tap(find.text('Drop'));
        await settle(tester);
        expect(find.text('Still playing'), findsNothing);
        expect(repo.stillPlayingSent['g1'], isFalse);

        // Undo brings back Completed, still played.
        await tester.tap(find.text('Undo'));
        await settle(tester);
        expect(pill(GameStatus.playing), findsOneWidget);
        expect(repo.stillPlayingSent['g1'], isTrue);
      },
    );

    testWidgets('a game being played offers Start Playing, not the switch', (
      tester,
    ) async {
      await open(tester, hades(status: GameStatus.toPlay));

      expect(find.text('Start Playing'), findsOneWidget);
      expect(find.text('Still playing'), findsNothing);
    });

    testWidgets(
      'achievements show the progress, and the list opens in a dialog',
      (tester) async {
        repo.memberAchievements[('u1', 'g1')] = [
          for (var i = 0; i < 10; i++)
            Achievement(
              name: 'Achievement $i',
              description: '',
              iconUrl: '',
              unlocked: i < 3,
            ),
        ];
        await open(tester, hades());

        expect(find.text('3 / 10'), findsOneWidget);
        expect(find.text('(30%)'), findsOneWidget);
        expect(find.text('Achievement 0'), findsNothing);

        await tester.ensureVisible(find.text('Show achievements'));
        await tester.tap(find.text('Show achievements'));
        await tester.pumpAndSettle();

        expect(find.byType(Dialog), findsOneWidget);
        expect(find.text('3 / 10 unlocked'), findsOneWidget);
        expect(find.text('Achievement 0'), findsOneWidget);
        expect(find.text('Search achievements'), findsOneWidget);
        // Steam isn't connected here, so there is nothing to refresh from.
        expect(find.byTooltip('Refresh from Steam'), findsNothing);

        await tester.tap(find.text('Locked 7'));
        await tester.pumpAndSettle();
        expect(find.text('Achievement 0'), findsNothing);
        expect(find.text('Achievement 9'), findsOneWidget);

        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsNothing);
      },
    );
  });
}
