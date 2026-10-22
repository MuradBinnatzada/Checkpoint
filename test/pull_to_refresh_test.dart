import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:checkpoint/models/browse.dart';
import 'package:checkpoint/models/game_list.dart';
import 'package:checkpoint/screens/game_detail/game_detail_screen.dart';
import 'package:checkpoint/screens/home/home_screen.dart';
import 'package:checkpoint/screens/library/library_screen.dart';
import 'package:checkpoint/screens/lists/list_screen.dart';
import 'package:checkpoint/screens/profile/profile_screen.dart';
import 'package:checkpoint/services/game_api_service.dart';
import 'package:checkpoint/state/app_stores.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/app_theme.dart';

import 'support/fakes.dart';

/// Pulling a screen down at its top reads what it shows again: the library for
/// the tabs made from it, and what a screen reads on its own as well.
void main() {
  late FakeRepository repo;
  late AppStores stores;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repo = FakeRepository();
  });

  Future<void> open(
    WidgetTester tester,
    Widget home, {
    GameApiService? api,
  }) async {
    // Phone-sized: how far a pull has to go is a share of the screen's height.
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    stores = AppStores(
      repository: repo,
      authService: FakeAuthService(testUser('u1')),
      connectivity: FakeConnectivity(),
      apiService: api ?? FakeBrowseApi(),
    );
    await tester.runAsync(stores.initialize);
    await tester.pumpWidget(
      AppStoresScope(
        stores: stores,
        child: MaterialApp(
          theme: buildTheme(),
          home: Scaffold(body: home),
        ),
      ),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      stores.dispose();
    });
    await tester.pumpAndSettle();
  }

  /// Drags the page down from its top, the way a thumb does, and lets what the
  /// pull asked for come back.
  Future<void> pull(WidgetTester tester) async {
    await tester.fling(
      find.byType(RefreshIndicator).first,
      const Offset(0, 400),
      1000,
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Home reads the library, the feed and the popular list again', (
    tester,
  ) async {
    final browseApi = FakeBrowseApi();
    await open(tester, const HomeScreen(), api: browseApi);
    final fetches = repo.libraryFetches;
    expect(find.text('Celeste'), findsNothing);
    expect(repo.feedReads, 1);
    expect(browseApi.callsFor(BrowseMode.popular), 1);

    repo.library = [testGame('g1', title: 'Celeste', cover: false)];
    await pull(tester);

    expect(repo.libraryFetches, fetches + 1);
    expect(repo.feedReads, 2);
    expect(browseApi.callsFor(BrowseMode.popular), 2);
    expect(find.text('Celeste'), findsWidgets);
  });

  testWidgets('the Library tab shows a game added elsewhere after a pull', (
    tester,
  ) async {
    repo.library = [testGame('g1', title: 'Hades', cover: false)];
    await open(tester, const LibraryScreen());
    expect(find.text('HADES'), findsWidgets);
    expect(find.text('CELESTE'), findsNothing);

    repo.library = [
      testGame('g1', title: 'Hades', cover: false),
      testGame('g2', title: 'Celeste', cover: false),
    ];
    await pull(tester);

    expect(find.text('CELESTE'), findsWidgets);
  });

  testWidgets('an empty Library tab can be pulled too', (tester) async {
    await open(tester, const LibraryScreen());
    expect(find.text('Your library is empty'), findsOneWidget);

    repo.library = [testGame('g1', title: 'Celeste', cover: false)];
    await pull(tester);

    expect(find.text('Your library is empty'), findsNothing);
    expect(find.text('CELESTE'), findsWidgets);
  });

  testWidgets('the Profile tab reads the library again', (tester) async {
    repo.library = [testGame('g1', title: 'Hades', cover: false)];
    await open(tester, const ProfileScreen());
    final fetches = repo.libraryFetches;

    await pull(tester);

    expect(repo.libraryFetches, fetches + 1);
  });

  testWidgets(
    'a game\'s screen reads the game and what is said about it again',
    (tester) async {
      final detailsApi = FakeDetailsApi();
      repo.library = [
        testGame('g1', title: 'Skyrim', igdbId: 472, cover: false),
      ];
      await open(tester, const GameDetailScreen(gameId: 'g1'), api: detailsApi);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
      final fetches = repo.libraryFetches;
      expect(detailsApi.calls, [472]);

      await pull(tester);

      expect(detailsApi.calls, [472, 472]);
      expect(repo.libraryFetches, fetches + 1);
    },
  );

  testWidgets('a list shows what was added to it elsewhere after a pull', (
    tester,
  ) async {
    repo.library = [
      testGame('g1', title: 'Hades', cover: false),
      testGame('g2', title: 'Celeste', cover: false),
    ];
    repo.lists['l1'] = GameList(
      id: 'l1',
      ownerId: 'u1',
      title: 'Cozy',
      games: [testGame('g1', title: 'Hades', cover: false)],
    );
    await open(tester, const ListScreen(listId: 'l1'));
    await tester.runAsync(() => stores.lists.load());
    await tester.pumpAndSettle();
    expect(find.text('Hades'), findsOneWidget);
    expect(find.text('Celeste'), findsNothing);

    repo.lists['l1'] = repo.lists['l1']!.copyWith(
      games: [
        testGame('g1', title: 'Hades', cover: false),
        testGame('g2', title: 'Celeste', cover: false),
      ],
    );
    await pull(tester);

    expect(find.text('Celeste'), findsOneWidget);
  });
}
