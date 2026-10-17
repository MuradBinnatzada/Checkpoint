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
}
