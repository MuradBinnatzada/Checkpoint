import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:checkpoint/models/achievement.dart';
import 'package:checkpoint/models/achievement_summary.dart';
import 'package:checkpoint/models/activity_entry.dart';
import 'package:checkpoint/models/connected_service.dart';
import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/public_profile.dart';
import 'package:checkpoint/screens/game_detail/game_detail_screen.dart';
import 'package:checkpoint/screens/profile/follows_screen.dart';
import 'package:checkpoint/screens/profile/profile_screen.dart';
import 'package:checkpoint/screens/profile/public_library_screen.dart';
import 'package:checkpoint/screens/profile/public_profile_screen.dart';
import 'package:checkpoint/state/app_stores.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/app_theme.dart';
import 'package:checkpoint/widgets/connected_account_icons.dart';
import 'package:checkpoint/widgets/count_stat.dart';

import 'support/fakes.dart';

/// Another member's profile, their follower lists, their library and their
/// achievements, on the real screens over fake data sources.
void main() {
  late FakeRepository repo;
  late FakeAuthService authService;
  late AppStores stores;

  Game owned(
    String id,
    String title, {
    bool favorite = false,
    double rating = 4,
    GameStatus status = GameStatus.playing,
    double hours = 10,
  }) => testGame(
    id,
    title: title,
    favorite: favorite,
    cover: false,
    status: status,
    hours: hours,
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
    repo.members['m1'] = PublicProfile(
      id: 'm1',
      name: 'Member One',
      handle: '@member_one',
      bio: 'Speedrunner and soulslike enjoyer.',
      steamConnected: true,
      steamId: '76561198000000000',
      services: {
        ConnectedService.discord,
        ConnectedService.nintendo,
        ConnectedService.instagram,
        ConnectedService.twitch,
      },
      discordId: 'member#1',
      instagramId: 'member.one',
      twitchId: 'memberone',
      joined: DateTime.utc(2026, 3, 4),
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
      owned(
        'fav',
        'Favourite Quest',
        favorite: true,
        rating: 5,
        status: GameStatus.completed,
        hours: 40,
      ),
      owned(
        'rated',
        'Rated Rogue',
        rating: 3,
        status: GameStatus.playing,
        hours: 12,
      ),
      owned(
        'plain',
        'Plain Platformer',
        rating: 0,
        status: GameStatus.toPlay,
        hours: 0,
      ),
      owned(
        'wish',
        'Wished Wonder',
        rating: 0,
        status: GameStatus.wishlist,
        hours: 0,
      ),
    ];
    repo.memberActivity['m1'] = [
      ActivityEntry(
        game: testGame(
          'rated',
          title: 'Rated Rogue',
          status: null,
          cover: false,
        ),
        hours: 2.5,
        platform: GamePlatform.pc,
        at: DateTime.now().subtract(const Duration(hours: 5)),
      ),
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
    tester.view.physicalSize = const Size(800, 4200);
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

  Future<void> openProfile(WidgetTester tester, [String userId = 'm1']) =>
      open(tester, PublicProfileScreen(userId: userId));

  double top(WidgetTester tester, Finder finder) =>
      tester.getTopLeft(finder.first).dy;

  group('the profile', () {
    testWidgets(
      'shows who they are: name, handle, member since, bio and the linked services',
      (tester) async {
        await openProfile(tester);

        expect(find.text('Member One'), findsOneWidget);
        expect(find.text('@member_one'), findsOneWidget);
        expect(find.text('Member since Mar 2026'), findsOneWidget);
        expect(find.text('Speedrunner and soulslike enjoyer.'), findsOneWidget);
      },
    );

    testWidgets(
      'shows the connected accounts as small icons above the bio: game profiles, then social media',
      (tester) async {
        await openProfile(tester);

        // Tapping an icon opens the account (Discord copies the username).
        expect(find.byTooltip('Open Steam profile'), findsOneWidget);
        expect(find.byTooltip('Copy Discord username'), findsOneWidget);
        expect(find.byTooltip('Open Instagram profile'), findsOneWidget);
        expect(find.byTooltip('Open Twitch channel'), findsOneWidget);
        // Nintendo is connected but has nothing to open; PSN and Xbox are not connected.
        expect(find.byTooltip('Nintendo'), findsOneWidget);
        expect(find.byTooltip('PSN'), findsNothing);
        expect(find.byTooltip('Xbox'), findsNothing);
        // Icons only: no box, no names, nothing to change.
        expect(find.text('Connected accounts'), findsNothing);
        expect(find.text('GAME PROFILES'), findsNothing);
        expect(find.text('memberone'), findsNothing);
        expect(find.text('Connect'), findsNothing);
        expect(find.text('Sync Library'), findsNothing);

        // One row, game profiles first.
        final icons = [
          find.byTooltip('Open Steam profile'),
          find.byTooltip('Nintendo'),
          find.byTooltip('Copy Discord username'),
          find.byTooltip('Open Instagram profile'),
          find.byTooltip('Open Twitch channel'),
        ];
        final lefts = [for (final i in icons) tester.getTopLeft(i).dx];
        expect(lefts, orderedEquals([...lefts]..sort()));
        for (final i in icons) {
          expect(top(tester, i), top(tester, icons.first));
        }
        // Under the name, above the bio.
        expect(top(tester, find.text('Member One')), lessThan(top(tester, icons.first)));
        expect(
          top(tester, icons.first),
          lessThan(top(tester, find.text('Speedrunner and soulslike enjoyer.'))),
        );
      },
    );

    testWidgets(
      'lays the page out in order: favorites, recent activity, playtime, boxes, hours, ratings, achievements, menu last',
      (tester) async {
        await openProfile(tester);

        final order = [
          top(tester, find.text('Favorite Games')),
          top(tester, find.text('Recent activity')),
          top(tester, find.textContaining('Total Playtime')),
          top(tester, find.text('Playing').first),
          top(tester, find.text('Hours by platform')),
          top(tester, find.text('Ratings')),
          top(tester, find.text('Achievements')),
          top(tester, find.text('View Achievements')),
          top(tester, find.text('Wishlist')),
        ];
        expect(order, orderedEquals([...order]..sort()));
        // The follow button comes before all of it, where Edit Profile is on yours.
        expect(
          top(tester, find.widgetWithText(FilledButton, 'Follow')),
          lessThan(order.first),
        );
      },
    );

    testWidgets(
      'shows their numbers: playtime, the four boxes, hours per platform, ratings',
      (tester) async {
        await openProfile(tester);

        expect(find.text('Total Playtime: 52 hours'), findsOneWidget);
        // Playing 1, Completed 1, To Play 1, Dropped 0.
        expect(find.text('1'), findsWidgets);
        expect(find.text('0'), findsOneWidget);
        expect(find.text('52 h'), findsOneWidget); // all on PC
        // Average of 5 and 3, and how many are rated.
        expect(find.text('4.0'), findsOneWidget);
        expect(find.text('2 rated'), findsOneWidget);
      },
    );

    testWidgets(
      'shows the latest sessions, and a tapped one opens the game as the catalog has it',
      (tester) async {
        await openProfile(tester);

        expect(find.text('2.5 h · PC'), findsOneWidget);
        expect(find.text('5h ago'), findsOneWidget);

        await tester.tap(find.text('2.5 h · PC'));
        await tester.pumpAndSettle();

        expect(find.byType(GameDetailScreen), findsOneWidget);
        expect(find.text('Game not found'), findsNothing);
        expect(find.text('Not in your library'), findsOneWidget);
      },
    );

    testWidgets(
      'a member with no bio, no services and no games says what is missing, without a gap',
      (tester) async {
        repo.members['m3'] = const PublicProfile(
          id: 'm3',
          name: 'Newbie',
          handle: '@newbie',
        );
        await openProfile(tester, 'm3');

        expect(find.text('No favorites picked yet.'), findsOneWidget);
        expect(find.text('No sessions logged yet.'), findsOneWidget);
        expect(find.text('No hours logged yet.'), findsOneWidget);
        expect(find.text('No rated games yet.'), findsOneWidget);
        expect(find.text('Total Playtime: 0 hours'), findsOneWidget);
        expect(find.byType(ConnectedAccountIcons), findsNothing);
        expect(find.byTooltip('Open Steam profile'), findsNothing);
      },
    );

    testWidgets('the Discord icon copies the username', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await openProfile(tester);

      await tester.tap(find.byTooltip('Copy Discord username'));
      await tester.pump();

      expect(copied, 'member#1');
      expect(find.text('Discord username copied to clipboard'), findsOneWidget);
    });

    testWidgets('a service without a saved name is shown but not tappable', (
      tester,
    ) async {
      repo.members['m1'] = const PublicProfile(
        id: 'm1',
        name: 'Member One',
        handle: '@member_one',
        services: {ConnectedService.psn},
      );
      await openProfile(tester);

      expect(find.byTooltip('PSN'), findsOneWidget);
      expect(find.byTooltip('Open PSN profile'), findsNothing);
    });

    testWidgets('a name that is not one Instagram allows gets no link', (
      tester,
    ) async {
      repo.members['m1'] = const PublicProfile(
        id: 'm1',
        name: 'Member One',
        handle: '@member_one',
        services: {ConnectedService.instagram},
        instagramId: '../explore/tags',
      );
      await openProfile(tester);

      expect(find.byTooltip('Instagram'), findsOneWidget);
      expect(find.byTooltip('Open Instagram profile'), findsNothing);
    });

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

    testWidgets('a deleted member shows "Profile not found"', (tester) async {
      await openProfile(tester, 'ghost');

      expect(find.text('Profile not found'), findsOneWidget);
    });

    testWidgets('a failed load offers a retry that works', (tester) async {
      repo.failProfileReads = true;
      await openProfile(tester);
      expect(find.text('Could not load this profile'), findsOneWidget);

      repo.failProfileReads = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(find.text('Member One'), findsOneWidget);
    });

    testWidgets(
      'Follow becomes Following and moves the follower count at once',
      (tester) async {
        await openProfile(tester);
        // The count over the "Followers" label (the menu row below shows it too).
        Finder followers(String count) => find.descendant(
          of: find.widgetWithText(CountStat, 'Followers'),
          matching: find.text(count),
        );
        expect(followers('5'), findsOneWidget);

        await tester.tap(find.widgetWithText(FilledButton, 'Follow'));
        await tester.pumpAndSettle();

        expect(repo.writes, ['follow:m1']);
        expect(
          find.widgetWithText(OutlinedButton, 'Following'),
          findsOneWidget,
        );
        expect(followers('6'), findsOneWidget);
        expect(find.text('6'), findsWidgets); // and in the menu row

        await tester.tap(find.widgetWithText(OutlinedButton, 'Following'));
        await tester.pumpAndSettle();

        expect(followers('5'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'Follow'), findsOneWidget);
      },
    );

    testWidgets('your own page has no Follow button', (tester) async {
      await openProfile(tester, 'u1');

      expect(find.text('This is you'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Follow'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Following'), findsNothing);
    });
  });

  group('the boxes and the menu open their library', () {
    testWidgets(
      'a box opens it on that status, with the games of that status only',
      (tester) async {
        await openProfile(tester);

        await tester.tap(find.text('Completed'));
        await tester.pumpAndSettle();

        expect(find.byType(PublicLibraryScreen), findsOneWidget);
        expect(find.text('Library'), findsWidgets);
      expect(find.text('Member One'), findsOneWidget); // whose it is, under the title
        expect(find.text('FAVOURITE QUEST'), findsOneWidget);
        expect(find.text('RATED ROGUE'), findsNothing);
        expect(find.text('Search in Completed'), findsOneWidget);
      },
    );

    testWidgets(
      'the library has a tab per status with counts, and "All" shows every game',
      (tester) async {
        await open(
          tester,
          const PublicLibraryScreen(userId: 'm1', ownerName: 'Member One'),
        );

        for (final label in [
          'All',
          'Playing',
          'To Play',
          'Completed',
          'Dropped',
          'Wishlist',
        ]) {
          expect(
            find.widgetWithText(Tab, label),
            findsOneWidget,
            reason: label,
          );
        }
        for (final title in [
          'FAVOURITE QUEST',
          'RATED ROGUE',
          'PLAIN PLATFORMER',
          'WISHED WONDER',
        ]) {
          expect(find.text(title), findsOneWidget, reason: title);
        }

        await tester.tap(find.widgetWithText(Tab, 'Wishlist'));
        await tester.pumpAndSettle();
        expect(find.text('WISHED WONDER'), findsOneWidget);
        expect(find.text('FAVOURITE QUEST'), findsNothing);
      },
    );

    testWidgets(
      'the search box narrows the games, and says so when nothing matches',
      (tester) async {
        await open(
          tester,
          const PublicLibraryScreen(userId: 'm1', ownerName: 'Member One'),
        );

        await tester.enterText(find.byType(TextField), 'rogue');
        await tester.pumpAndSettle();
        expect(find.text('RATED ROGUE'), findsOneWidget);
        expect(find.text('FAVOURITE QUEST'), findsNothing);

        await tester.enterText(find.byType(TextField), 'zzz');
        await tester.pumpAndSettle();
        expect(find.text('No matches for "zzz"'), findsOneWidget);

        await tester.tap(find.text('Clear search'));
        await tester.pumpAndSettle();
        expect(find.text('FAVOURITE QUEST'), findsOneWidget);
      },
    );

    testWidgets(
      'the menu rows open the library: Wishlist on its tab, Top rated sorted by rating',
      (tester) async {
        await openProfile(tester);

        await tester.tap(find.text('Wishlist').last);
        await tester.pumpAndSettle();
        expect(find.text('Search in Wishlist'), findsOneWidget);
        expect(find.text('WISHED WONDER'), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();

        await tester.tap(find.text('Top rated'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Sorted by Rating'), findsOneWidget);
      },
    );

    testWidgets(
      'a game opened from their library is the catalog game, not their copy',
      (tester) async {
        await open(
          tester,
          const PublicLibraryScreen(userId: 'm1', ownerName: 'Member One'),
        );

        await tester.tap(find.text('PLAIN PLATFORMER'));
        await tester.pumpAndSettle();

        expect(find.byType(GameDetailScreen), findsOneWidget);
        expect(find.text('Game not found'), findsNothing);
        expect(find.text('Not in your library'), findsOneWidget);
        expect(find.text('4 / 5'), findsNothing); // their rating is theirs
      },
    );

    testWidgets('a library that cannot be loaded offers a retry', (
      tester,
    ) async {
      repo.failMemberLibrary = true;
      await open(
        tester,
        const PublicLibraryScreen(userId: 'm1', ownerName: 'Member One'),
      );
      expect(find.text('Could not load this library'), findsOneWidget);

      repo.failMemberLibrary = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('FAVOURITE QUEST'), findsOneWidget);
    });

    testWidgets(
      'the member\'s library does not touch the arrangement of yours',
      (tester) async {
        await open(
          tester,
          const PublicLibraryScreen(
            userId: 'm1',
            ownerName: 'Member One',
            initialStatus: GameStatus.wishlist,
          ),
        );

        expect(
          stores.libraryView.selectedStatus,
          isNull,
        ); // your Library tab stays on All
      },
    );
  });

  group('followers and following', () {
    testWidgets(
      'the counts open one screen on the tab that was tapped, with both counts',
      (tester) async {
        await openProfile(tester);

        await tester.tap(find.text('Followers').first);
        await tester.pumpAndSettle();

        expect(find.byType(FollowsScreen), findsOneWidget);
        expect(find.widgetWithText(Tab, '5 followers'), findsOneWidget);
        expect(find.widgetWithText(Tab, '2 following'), findsOneWidget);
        expect(find.text('Follower One'), findsOneWidget);
        expect(repo.memberReads, contains('followers:m1:0'));
        expect(
          repo.memberReads,
          isNot(contains('following:m1:0')),
        ); // not asked until shown

        await tester.tap(find.widgetWithText(Tab, '2 following'));
        await tester.pumpAndSettle();
        expect(find.text('Second'), findsOneWidget);
        expect(repo.memberReads, contains('following:m1:0'));
      },
    );

    testWidgets('tapping Following opens on the Following tab', (tester) async {
      await openProfile(tester);

      await tester.tap(find.text('Following').first);
      await tester.pumpAndSettle();

      expect(find.text('Second'), findsOneWidget);
      expect(find.text('Follower One'), findsNothing);
    });

    testWidgets('a member in a list opens their profile', (tester) async {
      await openProfile(tester);
      await tester.tap(find.text('Following').first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Second'));
      await tester.pumpAndSettle();

      expect(find.byType(PublicProfileScreen), findsOneWidget);
      expect(find.text('@second'), findsWidgets);
    });

    testWidgets('an empty list says so', (tester) async {
      await openProfile(tester);
      repo.followersOf['m1'] = [];

      await tester.tap(find.text('Followers').first);
      await tester.pumpAndSettle();

      expect(find.text('No followers yet'), findsOneWidget);
    });

    testWidgets('a list that fails to load offers a retry', (tester) async {
      await openProfile(tester);
      repo.failFollowLists = true;

      await tester.tap(find.text('Followers').first);
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
      await openProfile(tester);

      await tester.tap(find.text('Followers').first);
      await tester.pumpAndSettle();

      expect(find.text('You'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Follow'),
        findsOneWidget,
      ); // only Follower One
    });
  });

  group('your own profile', () {
    Future<void> openOwn(WidgetTester tester) =>
        open(tester, const Scaffold(body: ProfileScreen()));

    testWidgets(
      'the Followers count opens your lists on that tab, with your counts',
      (tester) async {
        repo.followersOf['u1'] = [testMember('f9', name: 'Fan Nine')];
        await openOwn(tester);

        await tester.tap(find.text('Followers').first);
        await tester.pumpAndSettle();

        expect(find.byType(FollowsScreen), findsOneWidget);
        expect(find.text('Fan Nine'), findsOneWidget);
        expect(find.widgetWithText(Tab, '3 followers'), findsOneWidget);
        expect(find.widgetWithText(Tab, '1 following'), findsOneWidget);
        expect(repo.memberReads, contains('followers:u1:0'));
      },
    );

    testWidgets('the Following count opens your following list', (
      tester,
    ) async {
      repo.followingOf['u1'] = [testMember('f1', name: 'Friend One')];
      await openOwn(tester);

      await tester.tap(find.text('Following').first);
      await tester.pumpAndSettle();

      expect(find.text('Friend One'), findsOneWidget);
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

    Iterable<String> reads(String prefix) =>
        repo.memberReads.where((r) => r.startsWith(prefix));

    testWidgets(
      'the count is there at once; the games and their achievements wait for a tap',
      (tester) async {
        await openProfile(tester);
        await scrollToAchievements(tester);

        expect(find.text('1'), findsWidgets);
        expect(find.text('/ 2 unlocked'), findsOneWidget);
        expect(find.text('View Achievements'), findsOneWidget);
        expect(reads('achievement-totals'), ['achievement-totals:m1']);
        // Neither the per-game progress nor a single achievement was fetched.
        expect(reads('achievements'), isEmpty);
        expect(find.text('1 / 2 · 50%'), findsNothing);
      },
    );

    testWidgets(
      'the button fetches the progress, and opening a game fetches its achievements',
      (tester) async {
        await openProfile(tester);
        await scrollToAchievements(tester);

        await tester.tap(find.text('View Achievements'));
        await tester.pumpAndSettle();

        expect(reads('achievements'), ['achievements:m1']);
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
      await openProfile(tester);
      await scrollToAchievements(tester);
      expect(find.text('/ 2 unlocked'), findsOneWidget); // the count is fine

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

    testWidgets(
      'without the count (offline, or the function is missing) the button still works',
      (tester) async {
        repo.failAchievementTotals = true;
        await openProfile(tester);
        await scrollToAchievements(tester);
        expect(find.textContaining('unlocked'), findsNothing);

        await tester.tap(find.text('View Achievements'));
        await tester.pumpAndSettle();

        expect(find.text('1 / 2 · 50%'), findsOneWidget);
      },
    );

    testWidgets('a member without any says so, with no button', (tester) async {
      repo.achievementSummaries['m1'] = [];
      await openProfile(tester);
      await tester.scrollUntilVisible(
        find.text('No achievements to show yet.'),
        300,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('No achievements to show yet.'), findsOneWidget);
      expect(find.text('View Achievements'), findsNothing);
    });

    // The glow is a box with a shadow; nothing else on the page has one.
    Finder glow() => find.byWidgetPredicate(
      (w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration! as BoxDecoration).boxShadow?.isNotEmpty == true,
    );

    testWidgets('a count with something still locked does not glow', (
      tester,
    ) async {
      await openProfile(tester);
      await scrollToAchievements(tester);
      await tester.tap(find.text('View Achievements'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Every achievement unlocked'), findsNothing);
      expect(glow(), findsNothing);
    });

    testWidgets('all of them unlocked: the count glows, and so does the game', (
      tester,
    ) async {
      repo.achievementSummaries['m1'] = [
        const GameAchievementSummary(
          gameId: 'fav',
          title: 'Favourite Quest',
          unlocked: 2,
          total: 2,
        ),
      ];
      await openProfile(tester);
      await scrollToAchievements(tester);
      expect(find.textContaining('Every achievement unlocked'), findsOneWidget);
      expect(glow(), findsOneWidget); // the count

      await tester.tap(find.text('View Achievements'));
      await tester.pumpAndSettle();

      expect(find.text('2 / 2 · 100%'), findsOneWidget);
      expect(glow(), findsNWidgets(2)); // the count and the finished game
    });

    testWidgets('your own profile has the same count and button', (
      tester,
    ) async {
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
      expect(find.text('/ 4 unlocked'), findsOneWidget);
      expect(reads('achievements'), isEmpty);

      await tester.tap(find.text('View Achievements'));
      await tester.pumpAndSettle();

      expect(repo.memberReads, contains('achievements:u1'));
      expect(find.text('2 / 4 · 50%'), findsOneWidget);
    });
  });
}
