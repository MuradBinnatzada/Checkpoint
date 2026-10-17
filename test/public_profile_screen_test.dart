import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:checkpoint/models/achievement.dart';
import 'package:checkpoint/models/achievement_summary.dart';
import 'package:checkpoint/models/connected_service.dart';
import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/public_profile.dart';
import 'package:checkpoint/screens/game_detail/game_detail_screen.dart';
import 'package:checkpoint/screens/profile/follow_list_screen.dart';
import 'package:checkpoint/screens/profile/profile_screen.dart';
import 'package:checkpoint/screens/profile/public_profile_screen.dart';
import 'package:checkpoint/state/app_stores.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/app_theme.dart';

import 'support/fakes.dart';

/// Another member's profile, their follower lists and their achievements, on the
/// real screens over fake data sources.
void main() {
  late FakeRepository repo;
  late FakeAuthService authService;
  late AppStores stores;

  Game owned(
    String id,
    String title, {
    bool favorite = false,
    double rating = 4,
  }) => testGame(
    id,
    title: title,
    favorite: favorite,
    cover: false,
  ).copyWith(rating: rating);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repo = FakeRepository();
    authService = FakeAuthService(testUser('u1'));
    stores = AppStores(
      repository: repo,
      authService: authService,
      connectivity: FakeConnectivity(),
    );
    repo.members['m2'] = const PublicProfile(
      id: 'm2',
      name: 'Second',
      handle: '@second',
    );
    repo.members['u1'] = const PublicProfile(
      id: 'u1',
      name: 'Ada',
      handle: '@ada',
    );
    repo.memberGames['m1'] = [
      owned('fav', 'Favourite Quest', favorite: true, rating: 5),
      owned('rated', 'Rated Rogue', rating: 3),
      owned('plain', 'Plain Platformer', rating: 0),
    ];
    repo.followersOf['m1'] = [testMember('f1', name: 'Follower One')];
    repo.followingOf['m1'] = [testMember('m2', name: 'Second')];
    repo.achievementSummaries['m1'] = [
      const GameAchievementSummary(
        gameId: 'fav',
        title: 'Favourite Quest',
        unlocked: 1,
        total: 2,
      ),
    ];
    repo.memberAchievements[('m1', 'fav')] = [
      const Achievement(
        name: 'Hidden Gem',
        description: 'Found it',
        iconUrl: '',
        unlocked: true,
      ),
      const Achievement(
        name: 'Locked One',
        description: 'Not yet',
        iconUrl: '',
        unlocked: false,
      ),
    ];
  });

  Future<void> open(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(800, 3200);
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
    await tester.pumpAndSettle();
  }

  group('the profile', () {
    testWidgets(
      'shows who they are, their counts, their services and their games',
      (tester) async {
        await open(tester, const PublicProfileScreen(userId: 'm1'));

        expect(find.text('Member One'), findsOneWidget);
        expect(find.text('@member_one'), findsOneWidget);
        expect(find.text('5'), findsOneWidget); // followers
        expect(find.text('Followers'), findsOneWidget);
        expect(find.text('Following'), findsWidgets);
        expect(
          find.text('Steam'),
          findsOneWidget,
        ); // the connected-account chip
        expect(find.text('Favorite Games'), findsOneWidget);
        expect(find.text('Rated Games'), findsOneWidget);
        expect(find.text('Library'), findsOneWidget);
        // The favorite and the rated game are in more than one section.
        expect(find.text('Favourite Quest'), findsWidgets);
        expect(find.text('Rated Rogue'), findsWidgets);
        expect(find.text('Plain Platformer'), findsOneWidget); // library only
      },
    );

    testWidgets('shows the name from the tapped row while it loads', (
      tester,
    ) async {
      await tester.runAsync(stores.initialize);
      repo.profileGate = Completer<void>(); // the profile never answers
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        AppStoresScope(
          stores: stores,
          child: MaterialApp(
            theme: buildTheme(),
            home: PublicProfileScreen(
              userId: 'm1',
              preview: testMember('m1', name: 'Preview Pat'),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Preview Pat'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      stores.dispose();
    });

    testWidgets('a member with PSN connected shows a PSN chip, and only the services they connected', (
      tester,
    ) async {
      repo.members['m4'] = const PublicProfile(
        id: 'm4',
        name: 'Console Fan',
        handle: '@console_fan',
        services: {ConnectedService.psn, ConnectedService.nintendo},
      );
      await open(tester, const PublicProfileScreen(userId: 'm4'));

      // What a screen reader announces for each chip.
      Finder announced(String label) => find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == label,
      );
      expect(announced('PSN connected'), findsOneWidget);
      expect(find.text('PSN'), findsOneWidget);
      expect(announced('Nintendo connected'), findsOneWidget);
      expect(find.text('Nintendo'), findsOneWidget);
      // Not connected, so no chip; and the panel is not the empty one.
      expect(find.text('Steam'), findsNothing);
      expect(find.text('Xbox'), findsNothing);
      expect(find.text('Discord'), findsNothing);
      expect(announced('Xbox connected'), findsNothing);
      expect(find.text('No connected accounts.'), findsNothing);
    });

    testWidgets('Steam and the other services sit side by side, Steam first', (
      tester,
    ) async {
      repo.members['m5'] = const PublicProfile(
        id: 'm5',
        name: 'Everything',
        handle: '@everything',
        steamConnected: true,
        services: {ConnectedService.xbox, ConnectedService.discord},
      );
      await open(tester, const PublicProfileScreen(userId: 'm5'));

      for (final label in ['Steam', 'Discord', 'Xbox']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('PSN'), findsNothing);
      final steam = tester.getTopLeft(find.text('Steam')).dx;
      final discord = tester.getTopLeft(find.text('Discord')).dx;
      final xbox = tester.getTopLeft(find.text('Xbox')).dx;
      expect(steam, lessThan(discord));
      expect(discord, lessThan(xbox));
    });

    testWidgets('a member without connected services or games says so', (
      tester,
    ) async {
      repo.members['m3'] = const PublicProfile(
        id: 'm3',
        name: 'Newbie',
        handle: '@newbie',
      );
      await open(tester, const PublicProfileScreen(userId: 'm3'));

      expect(find.text('No connected accounts.'), findsOneWidget);
      expect(find.text('No favorites picked yet.'), findsOneWidget);
      expect(find.text('No rated games yet.'), findsOneWidget);
      expect(find.text('Nothing in their library yet.'), findsOneWidget);
    });

    testWidgets('a deleted member shows "Profile not found"', (tester) async {
      await open(tester, const PublicProfileScreen(userId: 'ghost'));

      expect(find.text('Profile not found'), findsOneWidget);
    });

    testWidgets('a failed load offers a retry that works', (tester) async {
      repo.failProfileReads = true;
      await open(tester, const PublicProfileScreen(userId: 'm1'));
      expect(find.text('Could not load this profile'), findsOneWidget);

      repo.failProfileReads = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(find.text('Member One'), findsOneWidget);
    });

    testWidgets(
      'Follow becomes Following and moves the follower count at once',
      (tester) async {
        await open(tester, const PublicProfileScreen(userId: 'm1'));
        expect(find.text('5'), findsOneWidget);

        await tester.tap(find.widgetWithText(FilledButton, 'Follow'));
        await tester.pumpAndSettle();

        expect(repo.writes, ['follow:m1']);
        expect(
          find.widgetWithText(OutlinedButton, 'Following'),
          findsOneWidget,
        );
        expect(find.text('6'), findsOneWidget);
        expect(find.text('5'), findsNothing);

        await tester.tap(find.widgetWithText(OutlinedButton, 'Following'));
        await tester.pumpAndSettle();

        expect(find.text('5'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'Follow'), findsOneWidget);
      },
    );

    testWidgets('your own page has no Follow button', (tester) async {
      await open(tester, const PublicProfileScreen(userId: 'u1'));

      expect(find.text('This is you'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Follow'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Following'), findsNothing);
    });

    testWidgets(
      'a game opened from their profile is the catalog game, not their copy',
      (tester) async {
        await open(tester, const PublicProfileScreen(userId: 'm1'));

        await tester.tap(find.text('Plain Platformer'));
        await tester.pumpAndSettle();

        expect(find.byType(GameDetailScreen), findsOneWidget);
        expect(find.text('Game not found'), findsNothing);
        expect(find.text('Not in your library'), findsOneWidget);
        expect(find.text('Your rating'), findsOneWidget);
        // Their 4-star rating, hours and status are theirs, not the viewer's.
        expect(find.text('4 / 5'), findsNothing);
      },
    );
  });

  group('follower and following lists', () {
    testWidgets('the counts open the lists', (tester) async {
      await open(tester, const PublicProfileScreen(userId: 'm1'));

      await tester.tap(find.text('Followers'));
      await tester.pumpAndSettle();
      expect(find.byType(FollowListScreen), findsOneWidget);
      expect(find.text('Follower One'), findsOneWidget);
      expect(repo.memberReads, contains('followers:m1:0'));

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Following').first);
      await tester.pumpAndSettle();
      expect(find.text('Second'), findsOneWidget);
    });

    testWidgets('a member in a list opens their profile', (tester) async {
      await open(tester, const PublicProfileScreen(userId: 'm1'));
      await tester.tap(find.text('Following').first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Second'));
      await tester.pumpAndSettle();

      expect(find.byType(PublicProfileScreen), findsOneWidget);
      expect(find.text('@second'), findsWidgets);
    });

    testWidgets('an empty list says so', (tester) async {
      await open(tester, const PublicProfileScreen(userId: 'm1'));
      repo.followersOf['m1'] = [];

      await tester.tap(find.text('Followers'));
      await tester.pumpAndSettle();

      expect(find.text('No followers yet'), findsOneWidget);
    });

    testWidgets('a list that fails to load offers a retry', (tester) async {
      await open(tester, const PublicProfileScreen(userId: 'm1'));
      repo.failFollowLists = true;

      await tester.tap(find.text('Followers'));
      await tester.pumpAndSettle();
      expect(find.text('Could not load followers'), findsOneWidget);

      repo.failFollowLists = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Follower One'), findsOneWidget);
    });

    testWidgets('you are listed without a Follow button', (tester) async {
      repo.followersOf['m1'] = [
        testMember('u1', name: 'Ada'),
        testMember('f1', name: 'Follower One'),
      ];
      await open(tester, const PublicProfileScreen(userId: 'm1'));

      await tester.tap(find.text('Followers'));
      await tester.pumpAndSettle();

      expect(find.text('You'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Follow'),
        findsOneWidget,
      ); // only Follower One
    });
  });

  group('your own profile', () {
    testWidgets('the Followers and Following counts open your lists', (
      tester,
    ) async {
      repo.followersOf['u1'] = [testMember('f9', name: 'Fan Nine')];
      await open(tester, const Scaffold(body: ProfileScreen()));

      await tester.tap(find.text('Followers'));
      await tester.pumpAndSettle();

      expect(find.byType(FollowListScreen), findsOneWidget);
      expect(find.text('Fan Nine'), findsOneWidget);
      expect(repo.memberReads, contains('followers:u1:0'));
    });
  });

  group('achievements', () {
    Future<void> scrollToAchievements(WidgetTester tester) async {
      await tester.scrollUntilVisible(
        find.text('View Achievements'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
    }

    testWidgets(
      'stay locked, and unrequested, until "View Achievements" is pressed',
      (tester) async {
        await open(tester, const PublicProfileScreen(userId: 'm1'));
        await scrollToAchievements(tester);

        expect(find.text('View Achievements'), findsOneWidget);
        expect(find.text('Favourite Quest · 1 / 2'), findsNothing);
        expect(
          repo.memberReads.where((r) => r.startsWith('achievements')),
          isEmpty,
        );
      },
    );

    testWidgets(
      'the button fetches the progress, and opening a game fetches its achievements',
      (tester) async {
        await open(tester, const PublicProfileScreen(userId: 'm1'));
        await scrollToAchievements(tester);

        await tester.tap(find.text('View Achievements'));
        await tester.pumpAndSettle();

        expect(repo.memberReads.where((r) => r.startsWith('achievements')), [
          'achievements:m1',
        ]);
        expect(find.text('1 / 2 · 50%'), findsOneWidget);
        expect(find.text('Hidden Gem'), findsNothing); // not fetched yet

        await tester.tap(find.text('1 / 2 · 50%'));
        await tester.pumpAndSettle();

        expect(repo.memberReads, contains('achievements:m1:fav'));
        expect(find.text('Hidden Gem'), findsOneWidget);
        expect(find.text('Locked One'), findsOneWidget);
      },
    );

    testWidgets('a failure offers to try again', (tester) async {
      repo.failAchievementReads = true;
      await open(tester, const PublicProfileScreen(userId: 'm1'));
      await scrollToAchievements(tester);

      await tester.tap(find.text('View Achievements'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Could not load achievements'),
        findsOneWidget,
      );

      repo.failAchievementReads = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('1 / 2 · 50%'), findsOneWidget);
    });

    testWidgets('a member without any says so', (tester) async {
      repo.achievementSummaries['m1'] = [];
      await open(tester, const PublicProfileScreen(userId: 'm1'));
      await scrollToAchievements(tester);

      await tester.tap(find.text('View Achievements'));
      await tester.pumpAndSettle();

      expect(find.text('No achievements to show yet.'), findsOneWidget);
    });

    testWidgets('your own profile has the same locked section', (tester) async {
      repo.achievementSummaries['u1'] = [
        const GameAchievementSummary(
          gameId: 'fav',
          title: 'Mine',
          unlocked: 2,
          total: 4,
        ),
      ];
      await open(tester, const Scaffold(body: ProfileScreen()));
      await scrollToAchievements(tester);
      expect(
        repo.memberReads.where((r) => r.startsWith('achievements')),
        isEmpty,
      );

      await tester.tap(find.text('View Achievements'));
      await tester.pumpAndSettle();

      expect(repo.memberReads, contains('achievements:u1'));
      expect(find.text('2 / 4 · 50%'), findsOneWidget);
    });
  });
}
