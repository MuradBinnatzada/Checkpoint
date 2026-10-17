import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthException, User;

import 'package:checkpoint/models/connected_service.dart';
import 'package:checkpoint/screens/profile/edit_profile_screen.dart';
import 'package:checkpoint/screens/settings/settings_screen.dart';
import 'package:checkpoint/state/app_stores.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/app_theme.dart';

import 'support/fakes.dart';

/// Settings: Account, Security and Privacy, as a sidebar on a wide window and a
/// row of chips on a phone; Account holds the accounts to connect and, at the
/// bottom, the account deletion.
void main() {
  late FakeRepository repo;
  late FakeAuthService authService;
  late AppStores stores;

  User googleUser() => User(
    id: 'u1',
    appMetadata: const {'provider': 'google'},
    userMetadata: const {},
    aud: 'authenticated',
    createdAt: '2026-01-01T00:00:00Z',
    email: 'ada@example.com',
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repo = FakeRepository();
    authService = FakeAuthService(googleUser());
    stores = AppStores(
      repository: repo,
      authService: authService,
      connectivity: FakeConnectivity(),
    );
  });

  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(400, 900),
    SettingsSection section = SettingsSection.account,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(stores.initialize);
    await tester.pumpWidget(
      AppStoresScope(
        stores: stores,
        child: MaterialApp(
          theme: buildTheme(),
          // Opened over a first screen, the way the Profile tab opens it.
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SettingsScreen(initialSection: section),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      stores.dispose();
    });
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  double top(WidgetTester tester, Finder finder) =>
      tester.getTopLeft(finder.first).dy;

  /// A phone tall enough to have the whole Connect accounts box on screen.
  const tall = Size(400, 1800);

  /// Lets what the stores do after a tap (saving to the device and the server)
  /// finish: that runs outside the test's fake clock.
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
  }

  /// The row of the Connect accounts box that lists [label].
  Finder rowOf(String label) =>
      find.ancestor(of: find.text(label), matching: find.byType(Row)).first;

  Finder connectButton(String label) => find.descendant(
    of: rowOf(label),
    matching: find.widgetWithText(TextButton, 'Connect'),
  );

  group('the sections', () {
    testWidgets('are chips across the head of a phone screen', (tester) async {
      await open(tester);

      for (final label in ['Account', 'Security', 'Privacy']) {
        expect(
          find.widgetWithText(ChoiceChip, label),
          findsOneWidget,
          reason: label,
        );
      }
      expect(find.byType(ListTile), findsNothing);
      // Account is first.
      expect(find.text('Signed in as'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Security'));
      await tester.pumpAndSettle();
      expect(find.text('Signed in as'), findsNothing);
      expect(find.text('Sign-in'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Privacy'));
      await tester.pumpAndSettle();
      expect(find.text('Visible to other signed-in members'), findsOneWidget);
      expect(find.text('Private to you'), findsOneWidget);
    });

    testWidgets('are a sidebar on a wide window', (tester) async {
      await open(tester, size: const Size(1100, 800));

      expect(find.byType(ChoiceChip), findsNothing);
      for (final label in ['Account', 'Security', 'Privacy']) {
        expect(
          find.widgetWithText(ListTile, label),
          findsOneWidget,
          reason: label,
        );
      }
      // The sidebar is to the left of what it shows.
      expect(
        tester.getTopLeft(find.widgetWithText(ListTile, 'Account')).dx,
        lessThan(tester.getTopLeft(find.text('Signed in as')).dx),
      );

      await tester.tap(find.widgetWithText(ListTile, 'Privacy'));
      await tester.pumpAndSettle();
      expect(find.text('Visible to other signed-in members'), findsOneWidget);
      expect(find.text('Signed in as'), findsNothing);
    });

    testWidgets('can be opened on a given section', (tester) async {
      await open(tester, section: SettingsSection.security);

      expect(find.text('Sign-in'), findsOneWidget);
      expect(find.text('Signed in as'), findsNothing);
    });
  });

  group('Account', () {
    testWidgets('says who is signed in', (tester) async {
      await open(tester);

      expect(find.text('Ada'), findsOneWidget);
      expect(find.text('@ada'), findsOneWidget);
      expect(find.text('ada@example.com'), findsOneWidget);
    });

    testWidgets('has the account deletion at the very bottom', (tester) async {
      await open(tester, size: tall);

      final delete = find.widgetWithText(OutlinedButton, 'Delete account');
      await tester.ensureVisible(delete);
      expect(delete, findsOneWidget);
      for (final above in [
        find.text('Edit profile'),
        find.text('Connect accounts'),
        find.widgetWithText(OutlinedButton, 'Sign out'),
      ]) {
        expect(top(tester, above), lessThan(top(tester, delete)));
      }
    });

    testWidgets(
      'Edit profile opens the editor, which no longer deletes accounts',
      (tester) async {
        await open(tester);

        await tester.tap(find.text('Edit profile'));
        await tester.pumpAndSettle();

        expect(find.byType(EditProfileScreen), findsOneWidget);
        expect(find.text('Delete account'), findsNothing);
        expect(find.byIcon(Icons.delete_forever_rounded), findsNothing);
      },
    );

    testWidgets('Sign out signs out and leaves Settings', (tester) async {
      await open(tester, size: tall);

      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(OutlinedButton, 'Sign out'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();

      expect(stores.auth.isLoggedIn, isFalse);
      expect(find.byType(SettingsScreen), findsNothing);
    });
  });

  group('Connect accounts', () {
    testWidgets(
      'lists every service under Game profiles and Social media, with Connect on each',
      (tester) async {
        await open(tester, size: tall);

        expect(find.text('GAME PROFILES'), findsOneWidget);
        expect(find.text('SOCIAL MEDIA'), findsOneWidget);
        for (final s in ConnectedService.values) {
          expect(find.text(s.label), findsOneWidget, reason: s.label);
          expect(connectButton(s.label), findsOneWidget, reason: s.label);
        }
        expect(
          find.text('Not connected'),
          findsNWidgets(ConnectedService.values.length),
        );
        // Nothing to sync without a Steam account.
        expect(find.text('Sync Library'), findsNothing);
      },
    );

    testWidgets('connecting Instagram asks for the username and saves it', (
      tester,
    ) async {
      await open(tester, size: tall);

      await tester.tap(connectButton('Instagram'));
      await tester.pumpAndSettle();
      expect(find.text('Connect Instagram'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '@ada.plays');
      await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
      await tester.pumpAndSettle();
      await settle(tester);

      expect(stores.profile.isConnected(ConnectedService.instagram), isTrue);
      expect(stores.profile.instagramId, 'ada.plays');
      expect(repo.savedInstagramId, 'ada.plays');
      expect(find.text('@ada.plays'), findsOneWidget);
      expect(find.byTooltip('Open Instagram profile'), findsOneWidget);
    });

    testWidgets(
      'a username the service does not allow is refused in the dialog',
      (tester) async {
        await open(tester, size: tall);

        await tester.tap(connectButton('Twitch'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'not a name');
        await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
        await tester.pumpAndSettle();

        expect(find.text("That isn't a valid Twitch username"), findsOneWidget);
        expect(stores.profile.isConnected(ConnectedService.twitch), isFalse);

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(stores.profile.isConnected(ConnectedService.twitch), isFalse);
      },
    );

    testWidgets(
      'a connected service can be renamed and disconnected from its menu',
      (tester) async {
        // On the server already, as if connected on this or another device.
        repo
          ..connectedServices = {ConnectedService.psn}
          ..savedPsnId = 'ps_user';
        await open(tester, size: tall);
        expect(find.text('ps_user'), findsOneWidget);

        await tester.tap(
          find.descendant(
            of: rowOf('PSN'),
            matching: find.byIcon(Icons.more_vert_rounded),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Change username'));
        await tester.pumpAndSettle();
        expect(find.text('Change PSN username'), findsOneWidget);
        await tester.enterText(find.byType(TextField), 'new_name');
        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        await tester.pumpAndSettle();
        await settle(tester);
        expect(stores.profile.psnId, 'new_name');
        expect(repo.savedPsnId, 'new_name');

        await tester.tap(
          find.descendant(
            of: rowOf('PSN'),
            matching: find.byIcon(Icons.more_vert_rounded),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Disconnect'));
        await tester.pumpAndSettle();
        expect(find.text('Disconnect PSN?'), findsOneWidget);
        await tester.tap(find.widgetWithText(FilledButton, 'Disconnect'));
        await tester.pumpAndSettle();
        await settle(tester);

        expect(stores.profile.isConnected(ConnectedService.psn), isFalse);
        expect(repo.connectedServices, isEmpty);
        expect(connectButton('PSN'), findsOneWidget);
      },
    );

    testWidgets('cancelling the disconnect keeps the account', (tester) async {
      repo.steamId = '76561198000000000';
      await open(tester, size: tall);

      await tester.tap(
        find.descendant(
          of: rowOf('Steam'),
          matching: find.byIcon(Icons.more_vert_rounded),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Disconnect'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(stores.profile.steamConnected, isTrue);
      expect(repo.steamId, '76561198000000000');
    });

    testWidgets('connecting Steam saves the ID and brings the sync button', (
      tester,
    ) async {
      await open(tester, size: tall);
      expect(find.text('Sync Library'), findsNothing);

      await tester.tap(connectButton('Steam'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '76561198000000000');
      await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
      await tester.pumpAndSettle();
      await settle(tester);

      expect(repo.steamId, '76561198000000000');
      expect(stores.profile.steamConnected, isTrue);
      expect(find.text('Sync Library'), findsOneWidget);
      // The sync button belongs to the game profiles, above Social media.
      expect(
        top(tester, find.text('Sync Library')),
        lessThan(top(tester, find.text('SOCIAL MEDIA'))),
      );
    });
  });

  group('Security', () {
    testWidgets(
      'shows how the account signs in and where its password is managed',
      (tester) async {
        await open(tester, section: SettingsSection.security);

        expect(find.text('Google'), findsOneWidget);
        expect(find.text('ada@example.com'), findsOneWidget);
        expect(find.text('Manage your Google Account'), findsOneWidget);
      },
    );

    testWidgets('signs out the other devices and keeps this one', (
      tester,
    ) async {
      await open(tester, section: SettingsSection.security);

      await tester.runAsync(() async {
        await tester.tap(find.text('Sign out other devices'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();

      expect(authService.signOutOthersCalls, 1);
      expect(stores.auth.isLoggedIn, isTrue);
      expect(find.text('Signed out of your other devices'), findsOneWidget);
    });

    testWidgets('says so when that fails', (tester) async {
      authService.signOutOthersError = AuthException('Session expired');
      await open(tester, section: SettingsSection.security);

      await tester.runAsync(() async {
        await tester.tap(find.text('Sign out other devices'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();

      expect(find.text('Session expired'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Sign out other devices'),
            )
            .onPressed,
        isNotNull,
      );
    });
  });

  group('Privacy', () {
    testWidgets('lists what other members see and what stays private', (
      tester,
    ) async {
      await open(tester, section: SettingsSection.privacy);

      for (final text in [
        'Profile',
        'Library',
        'Recent activity',
        'Connected accounts',
        'Email address',
        'Purchase prices',
        'Session notes',
      ]) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
      expect(find.textContaining('Instagram and Twitch'), findsOneWidget);
    });
  });
}
