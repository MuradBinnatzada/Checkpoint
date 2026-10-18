import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:checkpoint/app/app_shell.dart';
import 'package:checkpoint/app/nav_tab.dart';
import 'package:checkpoint/models/filter_options.dart';
import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/game_attributes.dart';
import 'package:checkpoint/models/game_details.dart';
import 'package:checkpoint/models/results_page.dart';
import 'package:checkpoint/screens/game_detail/game_detail_screen.dart';
import 'package:checkpoint/services/game_api_service.dart';
import 'package:checkpoint/state/app_stores.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/app_theme.dart';

import 'support/fakes.dart';

/// Answers every search with one game, notes what was asked, and gives the
/// details of any game as [testDetails].
class _FilterApi extends GameApiService {
  final List<({String query, FilterOptions filters})> searches = [];

  @override
  Future<ResultsPage<Game>?> searchGames(
    String query, {
    FilterOptions filters = FilterOptions.none,
    int offset = 0,
    int limit = GameApiService.searchPageSize,
  }) async {
    searches.add((query: query, filters: filters));
    return ResultsPage([
      testGame('r1', title: 'Result One', status: null),
    ], hasMore: false);
  }

  @override
  Future<GameDetails?> fetchDetails(int igdbId) async =>
      testDetails(igdbId: igdbId);
}

/// The Discover tab's filters, and the tags of a game's screen that open them, in
/// the real app shell on fake data sources.
void main() {
  late FakeRepository repo;
  late _FilterApi api;
  late AppStores stores;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repo = FakeRepository()
      ..library = [
        testGame(
          'g1',
          title: 'Skyrim',
          igdbId: 472,
          cover: false,
          genres: ['Role-playing (RPG)'],
        ),
      ];
    api = _FilterApi();
    stores = AppStores(
      repository: repo,
      authService: FakeAuthService(testUser('u1')),
      connectivity: FakeConnectivity(),
      apiService: api,
    );
  });

  Future<void> start(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 4000);
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
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// A screen closing or opening: its transition runs longer than [settle].
  Future<void> settleRoute(WidgetTester tester) async {
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
  }

  group('the Discover filter sheet', () {
    Future<void> openSheet(WidgetTester tester) async {
      stores.nav.select(NavTab.search);
      await settle(tester);
      await tester.tap(find.byTooltip('Filter'));
      await settle(tester);
    }

    testWidgets('lists the kinds, and asks nothing until it is closed', (
      tester,
    ) async {
      await start(tester);
      await openSheet(tester);

      for (final title in [
        'Sort by',
        'Genres',
        'Game modes',
        'Platforms',
        'Themes',
        'Release year',
      ]) {
        expect(find.text(title), findsOneWidget, reason: title);
      }
      await tester.tap(find.text('Horror'));
      await tester.tap(find.text('Co-op'));
      await tester.pump();
      expect(find.text('2 filters picked'), findsOneWidget);
      expect(api.searches, isEmpty);

      await tester.tap(find.text('Show results'));
      await settle(tester);

      final expected = FilterOptions(
        attributes: {
          GameAttribute.theme: ['Horror'],
          GameAttribute.gameMode: ['Co-operative'],
        },
      );
      expect(api.searches.single, (query: '', filters: expected));
      expect(stores.search.activeFilters, expected);
      // The games, what they are filtered by, and the badge.
      expect(find.text('Result One'), findsOneWidget);
      expect(find.widgetWithText(InputChip, 'Horror'), findsOneWidget);
      expect(find.widgetWithText(InputChip, 'Co-op'), findsOneWidget);
      expect(
        find.descendant(of: find.byType(Badge), matching: find.text('2')),
        findsOneWidget,
      );
    });

    testWidgets('closing it by dragging it away applies it too', (
      tester,
    ) async {
      await start(tester);
      await openSheet(tester);
      await tester.tap(find.text('Newest'));
      await tester.tap(find.text('Shooter'));
      await tester.pump();

      await tester.tapAt(const Offset(10, 10)); // the barrier above the sheet
      await settle(tester);

      expect(
        api.searches.single.filters,
        FilterOptions.only(
          GameAttribute.genre,
          'Shooter',
        ).withSort(DiscoverSort.newest),
      );
    });

    testWidgets(
      'a removed chip searches again; the last one brings back Browse by',
      (tester) async {
        await start(tester);
        await openSheet(tester);
        await tester.tap(find.text('Horror'));
        await tester.tap(find.text('PS5'));
        await tester.tap(find.text('Show results'));
        await settle(tester);

        await tester.tap(find.byTooltip('Remove Horror'));
        await settle(tester);
        expect(
          api.searches.last.filters,
          FilterOptions(platforms: [GamePlatform.ps5]),
        );

        await tester.tap(find.byTooltip('Remove PS5'));
        await settle(tester);
        expect(api.searches, hasLength(2)); // nothing left to ask
        expect(find.text('Browse by'.toUpperCase()), findsOneWidget);
        expect(find.byType(InputChip), findsNothing);
      },
    );

    testWidgets('filters narrow a typed search, in IGDB relevance order', (
      tester,
    ) async {
      await start(tester);
      stores.nav.select(NavTab.search);
      await settle(tester);
      await tester.enterText(find.byType(TextField), 'zelda');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await settle(tester);
      expect(api.searches.single.query, 'zelda');

      await tester.tap(find.byTooltip('Filter'));
      await settle(tester);
      expect(
        find.textContaining('A search is ordered by relevance'),
        findsOneWidget,
      );
      await tester.tap(find.text('Horror'));
      await tester.tap(find.text('Show results'));
      await settle(tester);

      expect(api.searches.last, (
        query: 'zelda',
        filters: FilterOptions.only(GameAttribute.theme, 'Horror'),
      ));
    });

    testWidgets('Clear all lets go of everything in the sheet', (tester) async {
      await start(tester);
      await openSheet(tester);
      await tester.tap(find.text('Horror'));
      await tester.tap(find.text('1990s'));
      await tester.pump();
      expect(find.text('2 filters picked'), findsOneWidget);

      await tester.tap(find.text('Clear all'));
      await tester.pump();
      expect(find.textContaining('Browse IGDB by genre'), findsOneWidget);

      await tester.tap(find.text('Show results'));
      await settle(tester);
      expect(api.searches, isEmpty);
    });
  });

  group('tags on a game\'s screen', () {
    Future<void> openGame(WidgetTester tester) async {
      await start(tester);
      stores.nav.select(NavTab.library);
      await settle(tester);
      tester
          .state<NavigatorState>(find.byType(Navigator).first)
          .push(
            MaterialPageRoute<void>(
              builder: (_) => const GameDetailScreen(gameId: 'g1'),
            ),
          );
      await settle(tester);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await settle(tester);
    }

    testWidgets('a theme opens Discover on the games that have it', (
      tester,
    ) async {
      await openGame(tester);
      final fantasy = find.widgetWithText(ActionChip, 'Fantasy');
      await tester.ensureVisible(fantasy);
      await tester.tap(fantasy);
      await settleRoute(tester);

      expect(find.byType(GameDetailScreen), findsNothing);
      expect(stores.nav.index, NavTab.search);
      final filters = FilterOptions.only(GameAttribute.theme, 'Fantasy');
      expect(stores.search.activeFilters, filters);
      expect(api.searches.single, (query: '', filters: filters));
      expect(find.widgetWithText(InputChip, 'Fantasy'), findsOneWidget);
      expect(find.text('Result One'), findsOneWidget);
    });

    testWidgets('a genre and a game mode do too; an engine is only a label', (
      tester,
    ) async {
      await openGame(tester);

      expect(
        find.widgetWithText(ActionChip, 'Role-playing (RPG)'),
        findsOneWidget,
      );
      expect(find.widgetWithText(ActionChip, 'Single player'), findsOneWidget);
      expect(find.widgetWithText(ActionChip, 'Creation Engine'), findsNothing);
      expect(find.widgetWithText(Chip, 'Creation Engine'), findsOneWidget);

      final single = find.widgetWithText(ActionChip, 'Single player');
      await tester.ensureVisible(single);
      await tester.tap(single);
      await settleRoute(tester);

      expect(
        stores.search.activeFilters,
        FilterOptions.only(GameAttribute.gameMode, 'Single player'),
      );
      expect(find.widgetWithText(InputChip, 'Single-player'), findsOneWidget);
    });

    testWidgets('what was typed in Discover gives way to the tag', (
      tester,
    ) async {
      await start(tester);
      stores.nav.select(NavTab.search);
      await settle(tester);
      await tester.enterText(find.byType(TextField), 'zelda');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await settle(tester);

      tester
          .state<NavigatorState>(find.byType(Navigator).first)
          .push(
            MaterialPageRoute<void>(
              builder: (_) => const GameDetailScreen(gameId: 'g1'),
            ),
          );
      await settle(tester);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await settle(tester);
      final rpg = find.widgetWithText(ActionChip, 'Role-playing (RPG)');
      await tester.ensureVisible(rpg);
      await tester.tap(rpg);
      await settleRoute(tester);

      expect(api.searches.last, (
        query: '',
        filters: FilterOptions.only(GameAttribute.genre, 'Role-playing (RPG)'),
      ));
      final box = tester.widget<TextField>(find.byType(TextField));
      expect(box.controller!.text, isEmpty);
      expect(find.widgetWithText(InputChip, 'RPG'), findsOneWidget);
    });
  });
}
