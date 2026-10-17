import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:checkpoint/models/library_stats.dart';
import 'package:checkpoint/theme/app_theme.dart';
import 'package:checkpoint/widgets/ratings_panel.dart';
import 'package:checkpoint/widgets/star_rating.dart';

/// The ratings chart of a profile: bars that stay quiet until tapped.
void main() {
  // Two games at half a star and one at a star (the first bar holds all three),
  // two at 4.5 and three at 5.
  final stats = LibraryStats(
    ratingCounts: {0.5: 2, 1: 1, 4.5: 2, 5: 3},
    ratedCount: 8,
    averageRating: 3.4,
  );

  Future<void> show(WidgetTester tester, LibraryStats stats) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(body: RatingsPanel(stats: stats)),
      ),
    );
  }

  // The bars are the only tappable things in the panel (the star row of the
  // average is read-only), lowest rating first.
  Finder bar(int i) => find
      .descendant(
        of: find.byType(RatingsPanel),
        matching: find.byType(GestureDetector),
      )
      .at(i);

  testWidgets('counts how the ratings spread: 9 bars from 1 star to 5', (
    tester,
  ) async {
    await show(tester, stats);

    expect(
      find.descendant(
        of: find.byType(RatingsPanel),
        matching: find.byType(GestureDetector),
      ),
      findsNWidgets(9),
    );
    expect(RatingsPanel.bars.first, 1);
    expect(RatingsPanel.bars.last, 5);
    expect(RatingsPanel.countFor(stats, 1), 3); // 0.5 and 1
    expect(RatingsPanel.countFor(stats, 4.5), 2);
    expect(RatingsPanel.countFor(stats, 3), 0);
  });

  testWidgets('the axis reads 1 to 5, and the "8 rated" total stays', (
    tester,
  ) async {
    await show(tester, stats);

    expect(find.text('1'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('½'), findsNothing);
    expect(find.text('8 rated'), findsOneWidget);
  });

  testWidgets('no count is shown until a bar is tapped', (tester) async {
    await show(tester, stats);

    expect(find.textContaining('game'), findsNothing);
    // The numbers that used to sit over the bars are gone.
    expect(find.text('3'), findsNothing);
    expect(find.text('2'), findsNothing);
    // Only the average's stars.
    expect(find.byType(StarRating), findsOneWidget);
  });

  testWidgets('tapping a bar shows its stars and the number of games', (
    tester,
  ) async {
    await show(tester, stats);

    await tester.tap(bar(8)); // 5 stars
    await tester.pump();

    expect(find.text('3 games'), findsOneWidget);
    expect(find.byType(StarRating), findsNWidgets(2)); // average + the bubble
    final bubbleStars = tester.widget<StarRating>(find.byType(StarRating).last);
    expect(bubbleStars.rating, 5);
  });

  testWidgets('a half-star bar shows half stars; one game is "1 game"', (
    tester,
  ) async {
    await show(
      tester,
      LibraryStats(ratingCounts: {3.5: 1}, ratedCount: 1, averageRating: 3.5),
    );

    await tester.tap(bar(5)); // 3.5 stars
    await tester.pump();

    expect(find.text('1 game'), findsOneWidget);
    expect(tester.widget<StarRating>(find.byType(StarRating).last).rating, 3.5);
  });

  testWidgets('a bar nobody picked says 0 games', (tester) async {
    await show(tester, stats);

    await tester.tap(bar(4)); // 3 stars
    await tester.pump();

    expect(find.text('0 games'), findsOneWidget);
  });

  testWidgets(
    'tapping another bar moves the bubble; tapping it again hides it',
    (tester) async {
      await show(tester, stats);

      await tester.tap(bar(8));
      await tester.pump();
      await tester.tap(bar(7)); // 4.5 stars
      await tester.pump();
      expect(find.text('3 games'), findsNothing);
      expect(find.text('2 games'), findsOneWidget);

      await tester.tap(bar(7));
      await tester.pump();
      expect(find.textContaining('game'), findsNothing);
    },
  );

  testWidgets('the first bar holds the half-star ratings and says so', (
    tester,
  ) async {
    await show(tester, stats);

    await tester.tap(bar(0));
    await tester.pump();

    expect(find.text('3 games'), findsOneWidget);
    expect(find.text('≤'), findsOneWidget);
  });

  testWidgets('a member who rated nothing sees no chart', (tester) async {
    await show(tester, const LibraryStats());

    expect(find.text('No rated games yet.'), findsOneWidget);
    expect(find.byType(GestureDetector), findsNothing);
  });

  testWidgets('the bubble stays inside the chart for the bars at either edge', (
    tester,
  ) async {
    // A narrow phone: the chart is about 200 px wide, the bubble over half of it.
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await show(tester, stats);
    final chart = tester.getRect(find.byType(RatingsPanel));

    for (final i in [0, 8]) {
      await tester.tap(bar(i));
      await tester.pump();
      final bubble = tester.getRect(find.byType(StarRating).last);
      expect(bubble.left, greaterThanOrEqualTo(chart.left));
      expect(bubble.right, lessThanOrEqualTo(chart.right));
      expect(tester.takeException(), isNull);
      await tester.tap(bar(i)); // off again
      await tester.pump();
    }
  });
}
