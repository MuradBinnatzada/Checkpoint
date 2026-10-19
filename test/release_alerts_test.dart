import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:checkpoint/app/app_shell.dart';
import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/release_alerts.dart';
import 'package:checkpoint/state/app_stores.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/app_theme.dart';

import 'support/fakes.dart';

void main() {
  final today = DateTime(2026, 10, 19);
  Game wish(String id, DateTime? released, {GameStatus status = GameStatus.wishlist}) =>
      testGame(id, title: 'Game $id', status: status, cover: false).copyWith(releaseDate: released);

  test('wishlist games just out come first, then the upcoming ones, soonest first', () {
    final alerts = releaseAlerts([
      wish('soon', DateTime(2026, 10, 24)),
      wish('today', DateTime(2026, 10, 19)),
      wish('last-week', DateTime(2026, 10, 12)),
      wish('yesterday', DateTime(2026, 10, 18)),
      wish('far', DateTime(2027, 3, 1)),
      wish('long-ago', DateTime(2026, 9, 1)),
      wish('no-date', null),
      wish('owned', DateTime(2026, 10, 20), status: GameStatus.toPlay),
      wish('next-month', DateTime(2026, 11, 20)),
    ], today: today);

    expect([for (final a in alerts) (a.game.id, a.daysAway)], [
      ('today', 0),
      ('yesterday', -1),
      ('last-week', -7),
      ('soon', 5),
      ('next-month', 32),
    ]);
  });

  test('says when, in words', () {
    expect(releaseLabel(0), 'Out today');
    expect(releaseLabel(-3), 'Out now');
    expect(releaseLabel(1), 'Out tomorrow');
    expect(releaseLabel(12), 'Out in 12 days');
  });

  testWidgets('a wishlist game that came out is announced once, and shown on Home', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final now = DateTime.now();
    final repo = FakeRepository()
      ..library = [
        // Calendar days, not 24-hour steps: a daylight saving change may be in between.
        wish('w1', DateTime(now.year, now.month, now.day - 2)),
        wish('w2', DateTime(now.year, now.month, now.day + 10)),
      ];
    AppStores newStores() => AppStores(
      repository: repo,
      authService: FakeAuthService(testUser('u1')),
      connectivity: FakeConnectivity(),
      apiService: FakeBrowseApi(),
    );

    Future<AppStores> start() async {
      final stores = newStores();
      await tester.runAsync(stores.initialize);
      await tester.pumpWidget(AppStoresScope(
        stores: stores,
        child: MaterialApp(theme: buildTheme(), home: const AppShell()),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      return stores;
    }

    var stores = await start();
    expect(find.text('Game w1 from your wishlist is out now'), findsOneWidget);
    expect(find.text('Wishlist Releases'), findsOneWidget);
    expect(find.textContaining('Out in 10 days'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    stores.dispose();

    // The app opened again: not announced a second time.
    stores = await start();
    expect(find.text('Game w1 from your wishlist is out now'), findsNothing);
    expect(find.text('Wishlist Releases'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    stores.dispose();
  });
}
