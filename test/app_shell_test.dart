import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:checkpoint/app/app_shell.dart';
import 'package:checkpoint/app/nav_tab.dart';
import 'package:checkpoint/services/local_cache.dart';
import 'package:checkpoint/state/app_stores.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/app_theme.dart';

import 'support/fakes.dart';

/// Renders the real app shell (all four tabs) on top of fake data sources.
void main() {
  late FakeRepository repo;
  late FakeAuthService authService;
  late AppStores stores;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repo = FakeRepository();
    authService = FakeAuthService();
    stores = AppStores(repository: repo, authService: authService);
  });

  Future<void> start(WidgetTester tester) async {
    // As in the app: the stores start before the first frame.
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
  }

  testWidgets('shows the saved library with an offline banner when the server is down', (tester) async {
    await tester.runAsync(() async {
      final cache = LocalCache();
      await cache.writeLibrary('u1', [
        testGame('a', title: 'Saved Alpha', cover: false),
        testGame('b', title: 'Saved Bravo', cover: false),
      ]);
    });
    authService.user = testUser('u1');
    repo.offline = true;
    await start(tester);

    stores.nav.select(NavTab.library);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('SAVED ALPHA'), findsWidgets);
    expect(find.text('SAVED BRAVO'), findsWidgets);
    expect(find.textContaining('Can\'t reach Checkpoint'), findsOneWidget);
    expect(find.text('Could not load library'), findsNothing);
  });

  testWidgets('shows a load error, not a banner, when there is nothing saved', (tester) async {
    authService.user = testUser('u1');
    repo.offline = true;
    await start(tester);

    stores.nav.select(NavTab.library);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Could not load library'), findsWidgets);
    expect(find.textContaining('Can\'t reach Checkpoint'), findsNothing);
  });

  testWidgets('the banner goes away once Retry reaches the server', (tester) async {
    await tester.runAsync(() async {
      await LocalCache().writeLibrary('u1', [testGame('a', title: 'Saved Alpha', cover: false)]);
    });
    authService.user = testUser('u1');
    repo.offline = true;
    await start(tester);
    stores.nav.select(NavTab.library);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Can\'t reach Checkpoint'), findsOneWidget);

    repo.offline = false;
    repo.library = [testGame('a', title: 'Fresh Alpha', cover: false)];
    await tester.tap(find.text('Retry').first);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('Can\'t reach Checkpoint'), findsNothing);
    expect(find.text('FRESH ALPHA'), findsWidgets);
  });

  testWidgets('every tab builds for a signed-out visitor', (tester) async {
    await start(tester);

    for (final tab in [NavTab.search, NavTab.library, NavTab.profile, NavTab.home]) {
      stores.nav.select(tab);
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      // Library and Profile sit behind the log-in overlay.
      expect(
        find.text('Log in to track games'),
        tab == NavTab.library || tab == NavTab.profile ? findsOneWidget : findsNothing,
      );
    }
  });
}
