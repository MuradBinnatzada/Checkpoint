import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'package:checkpoint/models/browse.dart';
import 'package:checkpoint/models/results_page.dart';
import 'package:checkpoint/screens/home/home_screen.dart';
import 'package:checkpoint/state/app_stores.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/app_theme.dart';

import 'support/fakes.dart';

/// The Home tab's carousel: IGDB's popular list for a signed-in member, the
/// newest catalog games otherwise, and never a made-up figure.
void main() {
  late FakeRepository repo;
  late FakeBrowseApi browseApi;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repo = FakeRepository()
      ..popular = [
        testGame(
          'p1',
          title: 'Fresh Catalog Game',
          status: null,
          cover: false,
          year: 2024,
        ),
      ];
    browseApi = FakeBrowseApi()
      ..answer = (mode, offset) => ResultsPage([
        testEntry('hot-1', title: 'Hot Game', score: 91.6),
      ], hasMore: false);
  });

  Future<void> start(WidgetTester tester, {User? user}) async {
    // Tall enough to have the whole page built.
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final stores = AppStores(
      repository: repo,
      authService: FakeAuthService(user),
      connectivity: FakeConnectivity(),
      apiService: browseApi,
    );
    await tester.runAsync(stores.initialize);
    await tester.pumpWidget(
      AppStoresScope(
        stores: stores,
        child: MaterialApp(
          theme: buildTheme(),
          home: const Scaffold(body: HomeScreen()),
        ),
      ),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      stores.dispose();
    });
    await tester.pumpAndSettle();
  }

  void expectNoMadeUpFigures() {
    expect(find.textContaining('players'), findsNothing);
    expect(find.textContaining('friends playing'), findsNothing);
    expect(find.textContaining('friend playing'), findsNothing);
    expect(find.text('Trending Among Friends'), findsNothing);
  }

  testWidgets(
    'a signed-in member sees what is popular on IGDB, with its score',
    (tester) async {
      await start(tester, user: testUser('u1'));

      expect(browseApi.callsFor(BrowseMode.popular), 1);
      expect(find.text('Popular Right Now'), findsOneWidget);
      expect(find.text('Hot Game'), findsWidgets);
      expect(find.text('92 / 100'), findsOneWidget);
      expect(find.text('Recently Added'), findsNothing);
      expectNoMadeUpFigures();
    },
  );

  testWidgets('a visitor sees the newest catalog games, as what they are', (
    tester,
  ) async {
    await start(tester);

    expect(browseApi.calls, isEmpty); // IGDB answers signed-in members only
    expect(find.text('Recently Added'), findsOneWidget);
    expect(find.text('Fresh Catalog Game'), findsWidgets);
    expect(find.text('2024'), findsOneWidget);
    expectNoMadeUpFigures();
  });

  testWidgets(
    'when IGDB fails the catalog stands in, and it is asked only once',
    (tester) async {
      browseApi.answer = (mode, offset) => null;

      await start(tester, user: testUser('u1'));

      expect(browseApi.callsFor(BrowseMode.popular), 1);
      expect(find.text('Recently Added'), findsOneWidget);
      expect(find.text('Popular Right Now'), findsNothing);
    },
  );
}
