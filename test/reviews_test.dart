import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/game_friends.dart';
import 'package:checkpoint/screens/game_detail/game_detail_screen.dart';
import 'package:checkpoint/state/app_stores.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/app_theme.dart';

import 'support/fakes.dart';

/// Short reviews next to ratings: your own on a game's screen, and those of the
/// members you follow in its Friends panel.
void main() {
  late FakeRepository repo;
  late AppStores stores;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repo = FakeRepository()..library = [testGame('g1', title: 'Hades', cover: false)];
    stores = AppStores(
      repository: repo,
      authService: FakeAuthService(testUser('u1')),
      connectivity: FakeConnectivity(),
      apiService: FakeDetailsApi(),
    );
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(stores.initialize);
    await tester.pumpWidget(
      AppStoresScope(
        stores: stores,
        child: MaterialApp(theme: buildTheme(), home: const GameDetailScreen(gameId: 'g1')),
      ),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      stores.dispose();
    });
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
  }

  testWidgets('a review is written, shown under the rating, and removed', (tester) async {
    await open(tester);

    await tester.tap(find.text('Add a short review'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '  The best roguelike.  ');
    await tester.pump();
    await tester.tap(find.text('Save review'));
    await settle(tester);

    expect(repo.reviews['g1'], 'The best roguelike.');
    expect(find.text('The best roguelike.'), findsOneWidget);

    await tester.tap(find.text('The best roguelike.'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove review'));
    await settle(tester);

    expect(repo.reviews['g1'], '');
    expect(find.text('Add a short review'), findsOneWidget);
  });

  test('a review longer than the limit is cut to it', () async {
    await stores.initialize();
    await stores.library.setReview('g1', 'x' * 700);
    expect(stores.library.gameById('g1').review, hasLength(500));
    stores.dispose();
  });

  testWidgets('the reviews of the members you follow are in the Friends panel', (tester) async {
    repo.friendsWithGame['g1'] = GameFriends(
      friends: [
        FriendWithGame(member: testMember('m1', name: 'Bo'), status: GameStatus.completed, rating: 4.5, review: 'Loved every run.'),
        FriendWithGame(member: testMember('m2', name: 'Cy'), status: GameStatus.playing),
      ],
      totals: const {GameStatus.completed: 1, GameStatus.playing: 1},
    );
    await open(tester);

    expect(find.text('Reviews'), findsOneWidget);
    expect(find.text('Loved every run.'), findsOneWidget);
    expect(find.text('Bo'), findsOneWidget);
  });
}
