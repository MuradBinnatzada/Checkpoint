import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:checkpoint/app/app_shell.dart';
import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/milestone.dart';
import 'package:checkpoint/models/public_profile.dart';
import 'package:checkpoint/models/social_user.dart';
import 'package:checkpoint/screens/profile/milestones_screen.dart';
import 'package:checkpoint/screens/profile/profile_screen.dart';
import 'package:checkpoint/screens/profile/public_profile_screen.dart';
import 'package:checkpoint/state/app_stores.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/app_theme.dart';
import 'package:checkpoint/utils/formatters.dart';
import 'package:checkpoint/widgets/member_tile.dart';
import 'package:checkpoint/widgets/milestone_badge.dart';

import 'support/fakes.dart';

/// Milestones on the real screens, over fake data sources: the profile header
/// and card, every milestone, the flair sheet, member lists and the
/// announcement of new ones.
void main() {
  late FakeRepository repo;
  late FakeAuthService authService;
  late AppStores stores;

  // Noon, so it is the 1st in any time zone.
  final earlier = DateTime.utc(2026, 3, 1, 12);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repo = FakeRepository()
      ..library = [
        // No covers: the image cache needs a plugin the tests don't have.
        testGame(
          'a',
          title: 'Alpha',
          status: GameStatus.completed,
          cover: false,
        ),
        testGame('b', title: 'Bravo', cover: false),
      ];
    authService = FakeAuthService(testUser('u1'));
    stores = AppStores(
      repository: repo,
      authService: authService,
      connectivity: FakeConnectivity(),
      apiService: FakeBrowseApi(),
    );
  });

  Future<void> open(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(800, 4800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(stores.initialize);
    await tester.pumpWidget(
      AppStoresScope(
        stores: stores,
        child: MaterialApp(theme: buildTheme(), home: screen),
      ),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      stores.dispose();
    });
    // The milestones are read once the library is there.
    await tester.runAsync(pumpEventQueue);
    await tester.pumpAndSettle();
  }

  AvatarFrame? frameOf(WidgetTester tester, Finder within) => tester
      .widget<FramedAvatar>(
        find.descendant(of: within, matching: find.byType(FramedAvatar)).first,
      )
      .frame;

  group('your profile', () {
    setUp(() {
      repo.memberMilestones['u1'] = {
        'library_1': earlier,
        'library_10': earlier,
        'library_100': earlier,
      };
      repo.profileFlair = const ProfileFlair(
        frameId: 'bronze',
        titleId: 'library_100',
        showcaseIds: ['library_10', 'library_100'],
      );
    });

    testWidgets(
      'shows your frame, level, title and showcase, and the Milestones card',
      (tester) async {
        await open(tester, const Scaffold(body: ProfileScreen()));

        expect(frameOf(tester, find.byType(ProfileScreen)), AvatarFrame.bronze);
        // 10 + 10 + 50 points.
        expect(find.text('Lv 2'), findsOneWidget);
        expect(find.text('Collector'), findsOneWidget);
        expect(find.text('Milestones'), findsWidgets);
        expect(find.text('3 / ${milestones.length} earned'), findsOneWidget);
        expect(find.text('Level 2'), findsOneWidget);
      },
    );

    testWidgets(
      'See all lists every milestone, with how far along the locked ones are',
      (tester) async {
        await open(tester, const Scaffold(body: ProfileScreen()));

        await tester.tap(find.text('See all'));
        await tester.pumpAndSettle();

        expect(find.byType(MilestonesScreen), findsOneWidget);
        // Two games in the library, 50 for Bookshelf.
        expect(find.text('2 / 50 games'), findsOneWidget);
        expect(find.text(fmtDay(earlier.toLocal())), findsNWidgets(3));
        // The list goes on, a section per category.
        for (final category in MilestoneCategory.values) {
          // The section heading, not a milestone of the same name.
          final heading = find.byWidgetPredicate(
            (w) =>
                w is Text &&
                w.data == category.label &&
                w.style?.fontSize == 17,
          );
          await tester.scrollUntilVisible(
            heading,
            300,
            scrollable: find.byType(Scrollable).last,
          );
          expect(heading, findsOneWidget);
        }
      },
    );

    testWidgets(
      'the flair sheet saves an unlocked frame and offers no locked one',
      (tester) async {
        await open(tester, const MilestonesScreen(userId: 'u1'));

        await tester.tap(find.byTooltip('Frame, title and showcase'));
        await tester.pumpAndSettle();
        expect(find.text('Profile flair'), findsOneWidget);

        // Gold is earned (100 games), Silver isn't.
        await tester.tap(find.text('Silver'));
        await tester.pump();
        await tester.tap(find.text('Gold'));
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        await tester.pumpAndSettle();

        expect(repo.profileFlair.frameId, 'gold');
        expect(stores.profile.flair.frameId, 'gold');
        expect(find.text('Profile flair'), findsNothing);
      },
    );

    testWidgets('a frame the server refuses is put back, with why', (
      tester,
    ) async {
      await open(tester, const MilestonesScreen(userId: 'u1'));
      // Earned on this device's say only: the server has never heard of it.
      repo.memberMilestones['u1']!.remove('library_100');

      await tester.tap(find.byTooltip('Frame, title and showcase'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gold'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('You haven\'t unlocked that yet.'), findsOneWidget);
      expect(stores.profile.flair.frameId, 'bronze');
    });
  });

  testWidgets('another member\'s profile shows their flair and milestones', (
    tester,
  ) async {
    repo.members['m1'] = PublicProfile(
      id: 'm1',
      name: 'Member One',
      handle: '@member_one',
      joined: DateTime.utc(2026, 3, 4),
      flair: const ProfileFlair(
        frameId: 'shield',
        titleId: 'reviews_10',
        showcaseIds: ['two_factor'],
      ),
    );
    repo.memberMilestones['m1'] = {
      'two_factor': earlier,
      'reviews_10': earlier,
    };

    await open(tester, const PublicProfileScreen(userId: 'm1'));

    expect(
      frameOf(tester, find.byType(PublicProfileScreen)),
      AvatarFrame.shield,
    );
    expect(find.text('Critic'), findsOneWidget);
    expect(find.text('2 / ${milestones.length} earned'), findsOneWidget);

    await tester.tap(find.text('See all'));
    await tester.pumpAndSettle();
    expect(find.text('Member One\'s milestones'), findsOneWidget);
    // Nothing of yours: no progress bars on someone else's.
    expect(find.byType(MilestoneProgressBar), findsNothing);
  });

  testWidgets('a member in a list wears their frame and showcase', (
    tester,
  ) async {
    await open(
      tester,
      const Scaffold(
        body: MemberTile(
          user: SocialUser(
            id: 'm1',
            name: 'Member One',
            handle: '@member_one',
            gamesLogged: 0,
            followers: 0,
            flair: ProfileFlair(
              frameId: 'laurel',
              showcaseIds: ['completed_25', 'two_factor'],
            ),
          ),
        ),
      ),
    );

    expect(frameOf(tester, find.byType(MemberTile)), AvatarFrame.laurel);
    expect(find.byType(MilestoneBadge), findsNWidgets(2));
  });

  testWidgets('the app announces a milestone the server just awarded', (
    tester,
  ) async {
    repo.reachable = {'library_1': DateTime.now()};

    await open(tester, const AppShell());

    expect(find.text('Milestone unlocked: First Pick'), findsOneWidget);
    expect(find.widgetWithText(SnackBarAction, 'View'), findsOneWidget);
  });

  testWidgets('what was earned long ago is summed up in one line', (
    tester,
  ) async {
    repo.memberMilestones['u1'] = {
      'library_1': earlier,
      'sessions_1': earlier,
      'member_1m': earlier,
      'rated_1': earlier,
    };

    await open(tester, const AppShell());

    expect(
      find.text('You\'ve earned 4 milestones from your history'),
      findsOneWidget,
    );
  });
}
