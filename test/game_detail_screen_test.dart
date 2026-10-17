import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/state/app_stores.dart';
import 'package:checkpoint/screens/game_detail/game_detail_screen.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/app_theme.dart';
import 'package:checkpoint/utils/navigation.dart';
import 'package:checkpoint/widgets/empty_state.dart';
import 'package:checkpoint/widgets/platform_widgets.dart';

import 'support/fakes.dart';

/// The game detail screen on top of fake data sources.
void main() {
  late FakeRepository repo;
  late AppStores stores;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repo = FakeRepository();
    stores = AppStores(
      repository: repo,
      authService: FakeAuthService(),
      connectivity: FakeConnectivity(),
    );
  });

  Future<void> start(WidgetTester tester, Widget home) async {
    await tester.runAsync(stores.initialize);
    await tester.pumpWidget(
      AppStoresScope(
        stores: stores,
        child: MaterialApp(theme: buildTheme(), home: home),
      ),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      stores.dispose();
    });
  }

  testWidgets(
    'an id that matches no game shows "Game not found", not a blank or red screen',
    (tester) async {
      await start(tester, const GameDetailScreen(gameId: 'no-such-game'));

      expect(tester.takeException(), isNull);
      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.text('Game not found'), findsOneWidget);
    },
  );

  testWidgets(
    'openGame with an unknown or empty id lands on the same screen and can go back',
    (tester) async {
      await start(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                TextButton(
                  onPressed: () => openGame(context, 'no-such-game'),
                  child: const Text('open unknown'),
                ),
                TextButton(
                  onPressed: () => openGame(context, ''),
                  child: const Text('open empty'),
                ),
              ],
            ),
          ),
        ),
      );

      for (final button in ['open unknown', 'open empty']) {
        await tester.tap(find.text(button));
        await tester.pumpAndSettle();
        expect(find.text('Game not found'), findsOneWidget, reason: button);

        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.text('Game not found'), findsNothing, reason: button);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a game IGDB gave no release date for shows no year', (
    tester,
  ) async {
    repo.popular = [testGame('g1', status: null, cover: false, year: 0)];
    await start(tester, const GameDetailScreen(gameId: 'g1'));

    expect(tester.takeException(), isNull);
    expect(find.text('Game g1'), findsWidgets);
    expect(find.textContaining('Released'), findsNothing);
  });

  testWidgets('a game with a release date shows its year', (tester) async {
    repo.popular = [testGame('g1', status: null, cover: false, year: 2020)];
    await start(tester, const GameDetailScreen(gameId: 'g1'));

    expect(tester.takeException(), isNull);
    expect(find.text('Released 2020'), findsOneWidget);
  });

  group('"Played on" choices', () {
    // Only the "Played on" chips: the game's own platform badge is a Text too.
    Finder chip(GamePlatform p) => find.descendant(of: find.byType(PlatformChips), matching: find.text(p.label));

    testWidgets(
      'a mobile-only game offers Mobile, not Steam Deck or Emulator',
      (tester) async {
        repo.popular = [
          testGame(
            'g1',
            title: 'Dream League Soccer',
            status: null,
            cover: false,
            platforms: const [GamePlatform.mobile],
          ),
        ];
        await start(tester, const GameDetailScreen(gameId: 'g1'));
        await tester.scrollUntilVisible(
          chip(GamePlatform.mobile),
          300,
          scrollable: find.byType(Scrollable).first,
        );

        expect(tester.takeException(), isNull);
        expect(chip(GamePlatform.mobile), findsOneWidget);
        expect(chip(GamePlatform.steamDeck), findsNothing);
        expect(chip(GamePlatform.emulator), findsNothing);
      },
    );

    testWidgets('a PC and console game offers Steam Deck and Emulator', (
      tester,
    ) async {
      repo.popular = [
        testGame(
          'g1',
          status: null,
          cover: false,
          platforms: const [GamePlatform.pc, GamePlatform.nswitch],
        ),
      ];
      await start(tester, const GameDetailScreen(gameId: 'g1'));
      await tester.scrollUntilVisible(
        chip(GamePlatform.steamDeck),
        300,
        scrollable: find.byType(Scrollable).first,
      );

      expect(chip(GamePlatform.steamDeck), findsOneWidget);
      expect(chip(GamePlatform.emulator), findsOneWidget);
    });
  });

  group('wishlist', () {
    setUp(() {
      // Signed in: the wishlist is a part of the library.
      stores = AppStores(
        repository: repo,
        authService: FakeAuthService(testUser('u1')),
        connectivity: FakeConnectivity(),
      );
    });

    Future<void> openGameScreen(WidgetTester tester, String id) async {
      await start(tester, GameDetailScreen(gameId: id));
      await tester.pumpAndSettle();
    }

    Finder add() => find.byTooltip('Add to wishlist');
    Finder remove() => find.byTooltip('Remove from wishlist');

    testWidgets('a game that is not in the library can be bookmarked, at once and with an undo', (
      tester,
    ) async {
      repo.popular = [testGame('g1', status: null, cover: false)];
      await openGameScreen(tester, 'g1');
      expect(add(), findsOneWidget);
      expect(remove(), findsNothing);

      await tester.tap(add());
      await tester.pumpAndSettle();

      expect(stores.library.maybeGame('g1')!.status, GameStatus.wishlist);
      expect(remove(), findsOneWidget); // the bookmark is filled now
      expect(add(), findsNothing);
      expect(find.text('Added Game g1 to your wishlist'), findsOneWidget);
      expect(repo.writes.any((w) => w.startsWith('game:g1:GameStatus.wishlist')), isTrue);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(stores.library.maybeGame('g1')!.status, isNull);
      expect(add(), findsOneWidget);
    });

    testWidgets('a wishlisted game can be taken off the wishlist', (tester) async {
      repo.library = [testGame('g1', status: GameStatus.wishlist, cover: false, hours: 0)];
      await openGameScreen(tester, 'g1');
      expect(remove(), findsOneWidget);

      await tester.tap(remove());
      await tester.pumpAndSettle();

      expect(stores.library.maybeGame('g1')!.status, isNull);
      expect(find.text('Removed Game g1 from your wishlist'), findsOneWidget);
      expect(repo.writes, contains('delete:g1'));
      expect(tester.takeException(), isNull); // the page stays; no "Game not found"
      expect(find.text('Game not found'), findsNothing);
    });

    testWidgets(
      'a game being played keeps both buttons: the bookmark is dimmed and explains, the status stays',
      (tester) async {
        repo.library = [testGame('g1', status: GameStatus.playing, cover: false)];
        await openGameScreen(tester, 'g1');

        expect(add(), findsNothing);
        expect(remove(), findsNothing);
        expect(find.byTooltip('Already in your library'), findsOneWidget);
        expect(find.byTooltip('Add to favorites'), findsOneWidget);

        await tester.tap(find.byTooltip('Already in your library'));
        await tester.pumpAndSettle();

        expect(find.text('Game g1 is already in your library as Playing'), findsOneWidget);
        expect(stores.library.maybeGame('g1')!.status, GameStatus.playing);
        expect(repo.writes.where((w) => w.startsWith('game:g1')), isEmpty);
      },
    );

    testWidgets('a wishlisted game can be a favorite too', (tester) async {
      repo.library = [testGame('g1', status: GameStatus.wishlist, cover: false)];
      await openGameScreen(tester, 'g1');

      expect(find.byTooltip('Add to favorites'), findsOneWidget);
    });

    testWidgets('signed out there is no bookmark', (tester) async {
      stores = AppStores(
        repository: repo,
        authService: FakeAuthService(),
        connectivity: FakeConnectivity(),
      );
      repo.popular = [testGame('g1', status: null, cover: false)];
      await openGameScreen(tester, 'g1');

      expect(add(), findsNothing);
    });

    testWidgets('a game that is not in the library has both the bookmark and the heart at the top', (
      tester,
    ) async {
      repo.popular = [testGame('g1', status: null, cover: false)];
      await openGameScreen(tester, 'g1');

      expect(add(), findsOneWidget);
      expect(find.byTooltip('Add to favorites'), findsOneWidget);
      // Both are in the app bar, next to each other and on the same row.
      expect(
        tester.getCenter(add()).dy,
        tester.getCenter(find.byTooltip('Add to favorites')).dy,
      );
      expect(
        tester.getCenter(add()).dx,
        lessThan(tester.getCenter(find.byTooltip('Add to favorites')).dx),
      );
    });

    testWidgets('the status actions no longer repeat "Add to Wishlist"', (
      tester,
    ) async {
      repo.popular = [testGame('g1', status: null, cover: false)];
      await openGameScreen(tester, 'g1');
      await tester.scrollUntilVisible(
        find.text('Start Playing'),
        300,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('Start Playing'), findsOneWidget);
      expect(find.text('Add to Wishlist'), findsNothing);
    });

    testWidgets('the heart on a game that is not in the library adds it, as a favorite', (
      tester,
    ) async {
      repo.popular = [testGame('g1', status: null, cover: false)];
      await openGameScreen(tester, 'g1');

      await tester.tap(find.byTooltip('Add to favorites'));
      await tester.pumpAndSettle();

      final game = stores.library.maybeGame('g1')!;
      expect(game.isFavorite, isTrue);
      expect(game.status, GameStatus.playing); // the same default as a rating
      expect(repo.writes.any((w) => w.startsWith('game:g1')), isTrue);
      expect(find.byTooltip('Remove from favorites'), findsOneWidget);
    });

    testWidgets('the heart on a wishlisted game keeps it on the wishlist', (
      tester,
    ) async {
      repo.library = [testGame('g1', status: GameStatus.wishlist, cover: false)];
      await openGameScreen(tester, 'g1');

      await tester.tap(find.byTooltip('Add to favorites'));
      await tester.pumpAndSettle();

      final game = stores.library.maybeGame('g1')!;
      expect(game.isFavorite, isTrue);
      expect(game.status, GameStatus.wishlist);
    });

    testWidgets('there is no limit, unlike favorites', (tester) async {
      repo.popular = [
        for (var i = 0; i < 7; i++) testGame('g$i', status: null, cover: false),
      ];
      await tester.runAsync(stores.initialize);

      for (var i = 0; i < 7; i++) {
        await stores.library.addToLibrary('g$i', GameStatus.wishlist);
      }

      expect(stores.library.count(GameStatus.wishlist), 7);
      expect(stores.library.notice, isNull);
      addTearDown(stores.dispose);
    });
  });
}
