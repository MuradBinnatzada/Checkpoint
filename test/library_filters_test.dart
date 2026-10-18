import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:checkpoint/app/app_shell.dart';
import 'package:checkpoint/app/nav_tab.dart';
import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/game_attributes.dart';
import 'package:checkpoint/state/app_stores.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/app_theme.dart';

import 'support/fakes.dart';

/// The filters of the Library tab, in the real app shell on fake data sources.
void main() {
  late FakeRepository repo;
  late FakeAuthService authService;
  late AppStores stores;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repo = FakeRepository()
      ..library = [
        testGame('a', title: 'Alpha', cover: false, genres: ['RPG']),
        testGame('b', title: 'Bravo', cover: false, genres: ['Shooter']),
        testGame('c', title: 'Charlie', cover: false, genres: ['RPG']),
      ]
      // Charlie's catalog row was never filled in from IGDB.
      ..libraryAttributes = {
        'a': const GameAttributes(
          themes: ['Horror', 'Fantasy'],
          gameModes: ['Single player'],
          developers: ['Studio One'],
        ),
        'b': const GameAttributes(
          themes: ['Horror'],
          gameModes: ['Co-op'],
          developers: ['Studio Two'],
        ),
      };
    authService = FakeAuthService(testUser('u1'));
    stores = AppStores(
      repository: repo,
      authService: authService,
      connectivity: FakeConnectivity(),
    );
  });

  Future<void> start(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(stores.initialize);
    await tester.pumpWidget(
      AppStoresScope(
        stores: stores,
        child: MaterialApp(theme: buildTheme(), home: const AppShell()),
      ),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      stores.dispose();
    });
    stores.nav.select(NavTab.library);
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Opens the filter sheet and waits for the details to arrive.
  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Filter'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> closeSheet(WidgetTester tester) async {
    await tester.tapAt(const Offset(10, 10)); // the barrier above the sheet
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets(
    'the sheet lists the platform, the genres and only the values the library has',
    (tester) async {
      await start(tester);
      await openSheet(tester);

      expect(find.text('Platform'), findsOneWidget);
      expect(find.text('Genres'), findsOneWidget);
      expect(find.text('RPG (2)'), findsOneWidget);
      expect(find.text('Shooter (1)'), findsOneWidget);
      expect(find.text('Themes'), findsOneWidget);
      expect(find.text('Horror (2)'), findsOneWidget);
      expect(find.text('Fantasy (1)'), findsOneWidget);
      expect(find.text('Game modes'), findsOneWidget);
      expect(find.text('Developers'), findsOneWidget);
      expect(find.text('Studio One (1)'), findsOneWidget);
      // No game has a perspective, an engine or a publisher: nothing to offer.
      expect(find.text('Perspectives'), findsNothing);
      expect(find.text('Engines'), findsNothing);
      expect(find.text('Publishers'), findsNothing);
    },
  );

  testWidgets('says how many games have no IGDB details yet', (tester) async {
    await start(tester);
    await openSheet(tester);

    expect(
      find.textContaining('IGDB details are not saved for 1 of 3 games yet'),
      findsOneWidget,
    );
  });

  testWidgets(
    'picking a value narrows the library, shows what is picked and says what it leaves out',
    (tester) async {
      await start(tester);
      expect(find.text('ALPHA'), findsWidgets);
      expect(find.text('CHARLIE'), findsWidgets);

      await openSheet(tester);
      await tester.tap(find.text('Horror (2)'));
      await tester.pump();
      expect(find.text('Showing 2 of 3 games'), findsOneWidget);

      await closeSheet(tester);

      expect(find.text('ALPHA'), findsWidgets);
      expect(find.text('BRAVO'), findsWidgets);
      expect(
        find.text('CHARLIE'),
        findsNothing,
      ); // never filled in: can't match
      // The pick is on screen as a chip, the button is badged with it, and the
      // library says why a game is missing.
      expect(find.widgetWithText(InputChip, 'Horror'), findsOneWidget);
      expect(
        find.descendant(of: find.byType(Badge), matching: find.text('1')),
        findsOneWidget,
      );
      expect(
        find.text(
          '1 game has no IGDB details yet, so these filters leave it out.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('values of one kind add up, kinds narrow each other down', (
    tester,
  ) async {
    await start(tester);
    await openSheet(tester);

    await tester.tap(find.text('Fantasy (1)'));
    await tester.tap(find.text('Co-op (1)'));
    await tester.pump();
    // Fantasy is Alpha's, Co-op is Bravo's: both kinds have to match.
    expect(find.text('Showing 0 of 3 games'), findsOneWidget);

    await tester.tap(find.text('Horror (2)'));
    await tester.pump();
    // Horror or Fantasy, and Co-op: Bravo.
    expect(find.text('Showing 1 of 3 games'), findsOneWidget);

    await closeSheet(tester);
    expect(find.text('BRAVO'), findsWidgets);
    expect(find.text('ALPHA'), findsNothing);
  });

  testWidgets('the genre filter works without any IGDB details', (
    tester,
  ) async {
    repo.libraryAttributes = {};
    await start(tester);
    await openSheet(tester);

    expect(find.text('Genres'), findsOneWidget);
    expect(find.text('Themes'), findsNothing); // nothing known yet
    expect(
      find.textContaining(
        'IGDB details are not saved for any of your games yet',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('RPG (2)'));
    await tester.pump();
    await closeSheet(tester);

    expect(find.text('ALPHA'), findsWidgets);
    expect(find.text('CHARLIE'), findsWidgets);
    expect(find.text('BRAVO'), findsNothing);
    // A genre is on the game itself: no game is left out for lack of details.
    expect(find.textContaining('no IGDB details yet'), findsNothing);
  });

  testWidgets('removing a chip, or clearing all, brings the games back', (
    tester,
  ) async {
    await start(tester);
    await openSheet(tester);
    await tester.tap(find.text('Horror (2)'));
    await tester.tap(find.text('Single player (1)'));
    await tester.pump();
    await closeSheet(tester);
    expect(find.text('BRAVO'), findsNothing);

    await tester.tap(find.byTooltip('Remove Single player'));
    await tester.pump();
    expect(find.text('BRAVO'), findsWidgets);

    await tester.tap(find.byTooltip('Remove Horror'));
    await tester.pump();
    expect(find.text('CHARLIE'), findsWidgets);
    expect(find.byType(InputChip), findsNothing);
  });

  testWidgets('a filter that matches nothing says so and can be cleared', (
    tester,
  ) async {
    await start(tester);
    await openSheet(tester);
    await tester.tap(find.text('Fantasy (1)'));
    await tester.tap(find.text('Co-op (1)'));
    await tester.pump();
    await closeSheet(tester);

    expect(find.text('No games match these filters'), findsWidgets);
    await tester.tap(find.text('Clear filters').first);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('ALPHA'), findsWidgets);
    expect(find.text('No games match these filters'), findsNothing);
  });

  testWidgets(
    'the platform is picked in the same sheet, and alone it reads "No games on ..."',
    (tester) async {
      repo.library = [
        testGame(
          'a',
          title: 'Alpha',
          cover: false,
          platforms: [GamePlatform.pc],
        ),
        testGame(
          'b',
          title: 'Bravo',
          cover: false,
          platforms: [GamePlatform.ps4],
          playedOn: GamePlatform.ps4,
        ),
      ];
      await start(tester);
      await openSheet(tester);

      await tester.tap(find.text('PS4'));
      await tester.pump();
      expect(find.text('Showing 1 of 2 games'), findsOneWidget);
      await closeSheet(tester);

      expect(find.text('BRAVO'), findsWidgets);
      expect(find.text('ALPHA'), findsNothing);
      expect(find.widgetWithText(InputChip, 'PS4'), findsOneWidget);

      stores.libraryView.setTabIndex(
        GameStatus.values.indexOf(GameStatus.completed) + 1,
      );
      await tester.pump(); // the tab slides over on the frames after this one
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('No completed games on PS4'), findsWidgets);
      await tester.tap(find.text('Clear filter').first);
      await tester.pump(const Duration(milliseconds: 400));
      expect(stores.libraryView.platformFilter, isNull);
    },
  );

  testWidgets(
    'when the details cannot be loaded the sheet says so, and Retry loads them',
    (tester) async {
      repo.attributesDown = true;
      await start(tester);
      await openSheet(tester);

      expect(find.textContaining('Could not load themes'), findsOneWidget);
      expect(find.text('Themes'), findsNothing);
      expect(
        find.text('Genres'),
        findsOneWidget,
      ); // what the library holds still works

      repo.attributesDown = false;
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('Could not load themes'), findsNothing);
      expect(find.text('Themes'), findsOneWidget);
    },
  );

  testWidgets('a long list shows its first values and unfolds on request', (
    tester,
  ) async {
    repo.libraryAttributes = {
      'a': GameAttributes(
        developers: [
          for (var i = 0; i < 12; i++) 'Dev ${i.toString().padLeft(2, '0')}',
        ],
      ),
    };
    await start(tester);
    await openSheet(tester);

    expect(find.text('Dev 00 (1)'), findsOneWidget);
    expect(find.text('Dev 11 (1)'), findsNothing);

    await tester.tap(find.text('Show all 12'));
    await tester.pump();

    expect(find.text('Dev 11 (1)'), findsOneWidget);
    expect(find.text('Show fewer'), findsOneWidget);
  });

  testWidgets('opening a tab from Home clears the filters', (tester) async {
    await start(tester);
    await openSheet(tester);
    await tester.tap(find.text('Horror (2)'));
    await tester.pump();
    await closeSheet(tester);

    stores.libraryView.openTab(null);
    await tester.pump();

    expect(find.byType(InputChip), findsNothing);
    expect(find.text('CHARLIE'), findsWidgets);
  });

  testWidgets(
    'opening the sheet again after a game was filled in reads the details again',
    (tester) async {
      await start(tester);
      await openSheet(tester);
      expect(find.text('Horror (2)'), findsOneWidget);
      await closeSheet(tester);
      expect(repo.attributeReads, 1);

      repo.libraryAttributes['c'] = const GameAttributes(themes: ['Horror']);
      stores.library.applyDetails('c', testDetails());
      await openSheet(tester);

      expect(repo.attributeReads, 2);
      expect(find.text('Horror (3)'), findsOneWidget);
    },
  );
}
