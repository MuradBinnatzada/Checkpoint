import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthChangeEvent, AuthException, User;

import 'package:checkpoint/app/app_shell.dart';
import 'package:checkpoint/app/auth_gate.dart';
import 'package:checkpoint/app/new_password_screen.dart';
import 'package:checkpoint/app/second_factor_gate.dart';
import 'package:checkpoint/app/sign_in_panel.dart';
import 'package:checkpoint/screens/settings/settings_screen.dart';
import 'package:checkpoint/screens/settings/two_factor_setup_screen.dart';
import 'package:checkpoint/services/auth_service.dart';
import 'package:checkpoint/state/app_stores.dart';
import 'package:checkpoint/state/auth_store.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/app_theme.dart';
import 'package:checkpoint/widgets/qr_code_view.dart';

import 'support/fakes.dart';

/// Two-factor authentication (an authenticator app): the code a sign-in still
/// owes, the prompt over the whole app, and turning it on and off in Settings.
void main() {
  User emailUser([String id = 'u1']) => User(
    id: id,
    appMetadata: const {'provider': 'email'},
    userMetadata: const {},
    aud: 'authenticated',
    createdAt: '2026-01-01T00:00:00Z',
    email: 'ada@example.com',
  );

  /// Lets the store take in an auth event.
  Future<void> events() => Future<void>.delayed(Duration.zero);

  group('AuthStore', () {
    late FakeAuthService service;
    late AuthStore auth;
    late List<String?> announced;

    setUp(() async {
      service = FakeAuthService()..twoFactorOn = true;
      auth = AuthStore(service);
      announced = [];
      auth.userChanges.listen((user) => announced.add(user?.id));
      await auth.initialize();
    });

    tearDown(() => auth.dispose());

    test(
      'a sign-in that owes its code counts as no one until the code is right',
      () async {
        await auth.signInWithEmail('ada@example.com', 'pw');
        await events();

        expect(auth.needsSecondFactor, isTrue);
        expect(auth.waitingEmail, isNull); // testUser has no address
        expect(auth.isLoggedIn, isFalse);
        expect(auth.user, isNull);
        expect(announced, [null]);

        await expectLater(
          auth.verifySecondFactor('000000'),
          throwsA(
            isA<AuthException>().having(
              (e) => e.code,
              'code',
              'mfa_verification_failed',
            ),
          ),
        );
        await events();
        expect(auth.isLoggedIn, isFalse);

        await auth.verifySecondFactor('123456');
        await events();

        expect(auth.needsSecondFactor, isFalse);
        expect(auth.isLoggedIn, isTrue);
        expect(auth.user?.id, 'u1');
        expect(auth.hasTwoFactor, isTrue);
        expect(announced, [null, 'u1']);
        expect(service.twoFactorCalls, ['verify:000000', 'verify:123456']);
      },
    );

    test('signing out while the code is owed ends the wait', () async {
      await auth.signInWithGoogle();
      await events();
      expect(auth.needsSecondFactor, isTrue);

      await auth.logOut();
      await events();

      expect(auth.needsSecondFactor, isFalse);
      expect(auth.isLoggedIn, isFalse);
      expect(service.user, isNull);
    });

    test('an account without two-factor is signed in straight away', () async {
      service.twoFactorOn = false;
      await auth.signInWithApple();
      await events();

      expect(auth.needsSecondFactor, isFalse);
      expect(auth.isLoggedIn, isTrue);
      expect(auth.hasTwoFactor, isFalse);
      expect(announced, ['u1']);
    });

    test('a verified code is not asked for again on a token refresh', () async {
      await auth.signInWithEmail('ada@example.com', 'pw');
      await auth.verifySecondFactor('123456');
      await events();

      service.emit(service.user, event: AuthChangeEvent.tokenRefreshed);
      await events();

      expect(auth.needsSecondFactor, isFalse);
      expect(auth.isLoggedIn, isTrue);
    });

    test('a reset link asks for the new password after the code', () async {
      service.openResetLink(emailUser());
      await events();

      expect(auth.needsSecondFactor, isTrue);
      expect(auth.waitingEmail, 'ada@example.com');
      expect(auth.isRecoveringPassword, isFalse);

      await auth.verifySecondFactor('123456');
      await events();

      expect(auth.isLoggedIn, isTrue);
      expect(auth.isRecoveringPassword, isTrue);
    });

    test('turning it on and off follows the account', () async {
      service.twoFactorOn = false;
      await auth.signInWithEmail('ada@example.com', 'pw');
      await events();
      expect(auth.hasTwoFactor, isFalse);

      final setup = await auth.enrollTwoFactor();
      expect(setup.factorId, 'factor-1');
      expect(auth.hasTwoFactor, isFalse);

      await auth.confirmTwoFactor(setup.factorId, '123456');
      await events();
      expect(auth.hasTwoFactor, isTrue);
      expect(auth.isLoggedIn, isTrue);
      expect(auth.needsSecondFactor, isFalse);

      await auth.disableTwoFactor();
      await events();
      expect(auth.hasTwoFactor, isFalse);
      expect(service.twoFactorCalls, [
        'enroll',
        'confirm:factor-1:123456',
        'disable',
      ]);
    });

    test('a session restored at aal1 waits for its code', () async {
      final restored = FakeAuthService(emailUser())..twoFactorOn = true;
      final store = AuthStore(restored);
      addTearDown(store.dispose);
      await store.initialize();

      expect(store.needsSecondFactor, isTrue);
      expect(store.waitingEmail, 'ada@example.com');
      expect(store.isLoggedIn, isFalse);
      expect(store.isSessionPending, isFalse);
    });
  });

  group('A saved session', () {
    String jwt(Map<String, Object?> claims) {
      String part(Object value) =>
          base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
      return '${part({'alg': 'HS256', 'typ': 'JWT'})}.${part(claims)}.c2ln';
    }

    Map<String, Object?> session({
      required String aal,
      List<String> factors = const [],
    }) => {
      'access_token': jwt({'sub': 'u1', 'aal': aal}),
      'user': {
        'id': 'u1',
        'factors': [
          for (final status in factors)
            {'id': 'f-$status', 'factor_type': 'totp', 'status': status},
        ],
      },
    };

    test('owes its code only when two-factor is on and it is not aal2', () {
      expect(
        AuthService.owesSecondFactor(
          session(aal: 'aal1', factors: ['verified']),
        ),
        isTrue,
      );
      expect(
        AuthService.owesSecondFactor(
          session(aal: 'aal2', factors: ['verified']),
        ),
        isFalse,
      );
      expect(AuthService.owesSecondFactor(session(aal: 'aal1')), isFalse);
      // An unfinished setup doesn't turn it on.
      expect(
        AuthService.owesSecondFactor(
          session(aal: 'aal1', factors: ['unverified']),
        ),
        isFalse,
      );
    });

    test('with two-factor on, a token that cannot be read owes it', () {
      final broken = session(aal: 'aal2', factors: ['verified'])
        ..['access_token'] = 'not-a-jwt';
      expect(AuthService.owesSecondFactor(broken), isTrue);
      final missing = session(aal: 'aal2', factors: ['verified'])
        ..remove('access_token');
      expect(AuthService.owesSecondFactor(missing), isTrue);
    });
  });

  group('The app', () {
    late FakeAuthService authService;
    late AppStores stores;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      authService = FakeAuthService()..twoFactorOn = true;
      stores = AppStores(
        repository: FakeRepository(),
        authService: authService,
        connectivity: FakeConnectivity(),
        // Home asks IGDB for what is popular.
        apiService: FakeBrowseApi(),
      );
    });

    /// The shell with the gate where CheckpointApp puts it: over the Navigator.
    Future<void> start(WidgetTester tester) async {
      await tester.runAsync(stores.initialize);
      await tester.pumpWidget(
        AppStoresScope(
          stores: stores,
          child: MaterialApp(
            theme: buildTheme(),
            builder: (context, child) => SecondFactorGate(child: child!),
            home: const AppShell(),
          ),
        ),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        stores.dispose();
      });
    }

    /// Lets the stores take in an auth event, and a screen slide in or out.
    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
    }

    Future<void> enterCode(WidgetTester tester, String code) async {
      await tester.enterText(
        find.widgetWithText(TextField, '6-digit code'),
        code,
      );
      await settle(tester);
    }

    testWidgets(
      'asks for the code over everything after a sign-in, and lets the app in',
      (tester) async {
        await start(tester);
        authService.emit(emailUser());
        await settle(tester);

        expect(find.byType(SecondFactorScreen), findsOneWidget);
        expect(
          find.textContaining('for Checkpoint (ada@example.com)'),
          findsOneWidget,
        );
        // The shell is still there underneath, hidden.
        expect(find.byType(AppShell, skipOffstage: false), findsOneWidget);
        expect(find.byType(NavigationBar), findsNothing);
        expect(stores.auth.isLoggedIn, isFalse);

        // Six digits are sent as soon as they are in.
        await enterCode(tester, '654321');
        expect(find.textContaining("That code didn't work"), findsOneWidget);
        expect(find.byType(SecondFactorScreen), findsOneWidget);

        await enterCode(tester, '123456');

        expect(authService.twoFactorCalls, ['verify:654321', 'verify:123456']);
        expect(find.byType(SecondFactorScreen), findsNothing);
        expect(find.byType(NavigationBar), findsOneWidget);
        expect(stores.auth.isLoggedIn, isTrue);
      },
    );

    testWidgets('only takes digits, and checks the length before sending', (
      tester,
    ) async {
      await start(tester);
      authService.emit(emailUser());
      await settle(tester);

      await tester.enterText(
        find.widgetWithText(TextField, '6-digit code'),
        '12a3',
      );
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '123',
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Verify'));
      await settle(tester);

      expect(
        find.text('Enter the 6-digit code from your authenticator app.'),
        findsOneWidget,
      );
      expect(authService.twoFactorCalls, isEmpty);
    });

    testWidgets('signing out from the prompt works', (tester) async {
      await start(tester);
      authService.emit(emailUser());
      await settle(tester);

      await tester.tap(find.widgetWithText(TextButton, 'Sign out'));
      await settle(tester);

      expect(find.byType(SecondFactorScreen), findsNothing);
      expect(authService.user, isNull);
      expect(stores.auth.isLoggedIn, isFalse);
      expect(find.byType(NavigationBar), findsOneWidget);
    });

    testWidgets(
      'covers the sign-in screen, which closes once the code is right',
      (tester) async {
        await start(tester);
        unawaited(logIn(tester.element(find.byType(AppShell))));
        await settle(tester);
        expect(find.byType(SignInScreen), findsOneWidget);

        await tester.runAsync(() => stores.auth.signInWithGoogle());
        await settle(tester);

        expect(find.byType(SecondFactorScreen), findsOneWidget);
        expect(find.byType(SignInScreen), findsNothing);
        expect(find.byType(SignInScreen, skipOffstage: false), findsOneWidget);

        await enterCode(tester, '123456');

        expect(find.byType(SecondFactorScreen), findsNothing);
        expect(find.byType(SignInScreen, skipOffstage: false), findsNothing);
        expect(stores.auth.isLoggedIn, isTrue);
      },
    );

    testWidgets('a reset link asks for the code, then the new password', (
      tester,
    ) async {
      await start(tester);
      authService.openResetLink(emailUser());
      await settle(tester);

      expect(find.byType(SecondFactorScreen), findsOneWidget);

      await enterCode(tester, '123456');

      expect(find.byType(SecondFactorScreen), findsNothing);
      expect(find.byType(NewPasswordScreen), findsOneWidget);
    });
  });

  group('Settings > Security', () {
    late FakeAuthService authService;
    late AppStores stores;
    late List<MethodCall> clipboard;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      authService = FakeAuthService(emailUser());
      stores = AppStores(
        repository: FakeRepository(),
        authService: authService,
        connectivity: FakeConnectivity(),
      );
    });

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      clipboard = [];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') clipboard.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.runAsync(stores.initialize);
      await tester.pumpWidget(
        AppStoresScope(
          stores: stores,
          child: MaterialApp(
            theme: buildTheme(),
            home: const SettingsScreen(
              initialSection: SettingsSection.security,
            ),
          ),
        ),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        stores.dispose();
      });
      await tester.pumpAndSettle();
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
    }

    Finder twoFactorSwitch() =>
        find.widgetWithText(SwitchListTile, 'Authenticator app');

    bool switchedOn(WidgetTester tester) =>
        tester.widget<SwitchListTile>(twoFactorSwitch()).value;

    testWidgets(
      'turning it on shows a QR code and the key, and checks the first code',
      (tester) async {
        await open(tester);
        expect(switchedOn(tester), isFalse);

        await tester.tap(twoFactorSwitch());
        await settle(tester);

        expect(find.byType(TwoFactorSetupScreen), findsOneWidget);
        final qr = tester.widget<QrCodeView>(find.byType(QrCodeView));
        expect(qr.data, FakeAuthService.setup.uri);
        // The key in groups of four.
        expect(
          find.text('JBSW Y3DP EHPK 3PXP JBSW Y3DP EHPK 3PXP'),
          findsOneWidget,
        );

        await tester.tap(find.byTooltip('Copy setup key'));
        await settle(tester);
        expect(clipboard.single.arguments, {
          'text': FakeAuthService.setup.secret,
        });
        expect(find.text('Setup key copied'), findsOneWidget);

        await tester.enterText(
          find.widgetWithText(TextField, '6-digit code'),
          '111111',
        );
        await settle(tester);
        expect(find.textContaining("That code didn't work"), findsOneWidget);
        expect(stores.auth.hasTwoFactor, isFalse);

        await tester.enterText(
          find.widgetWithText(TextField, '6-digit code'),
          '123456',
        );
        await settle(tester);

        expect(find.byType(TwoFactorSetupScreen), findsNothing);
        expect(find.text('Two-factor authentication is on'), findsOneWidget);
        expect(stores.auth.hasTwoFactor, isTrue);
        expect(switchedOn(tester), isTrue);
        expect(authService.twoFactorCalls, [
          'enroll',
          'confirm:factor-1:111111',
          'confirm:factor-1:123456',
        ]);
      },
    );

    testWidgets('leaving the setup drops the unfinished factor', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(twoFactorSwitch());
      await settle(tester);

      await tester.tap(find.byTooltip('Close'));
      await settle(tester);

      expect(find.byType(TwoFactorSetupScreen), findsNothing);
      expect(authService.twoFactorCalls, ['enroll', 'cancel:factor-1']);
      expect(switchedOn(tester), isFalse);
    });

    testWidgets('a setup that cannot start says why and can be tried again', (
      tester,
    ) async {
      authService.twoFactorError = const AuthException(
        'MFA enroll is disabled for TOTP',
        code: 'mfa_totp_enroll_not_enabled',
      );
      await open(tester);
      await tester.tap(twoFactorSwitch());
      await settle(tester);

      expect(
        find.text("Two-factor authentication isn't available right now."),
        findsOneWidget,
      );

      authService.twoFactorError = null;
      await tester.tap(find.text('Try again'));
      await settle(tester);
      expect(find.byType(QrCodeView), findsOneWidget);
    });

    testWidgets('turning it off asks first', (tester) async {
      authService
        ..twoFactorOn = true
        ..aal2 = true;
      await open(tester);
      expect(switchedOn(tester), isTrue);

      await tester.tap(twoFactorSwitch());
      await settle(tester);
      expect(find.text('Turn off two-factor authentication?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(authService.twoFactorCalls, isEmpty);
      expect(switchedOn(tester), isTrue);

      await tester.tap(twoFactorSwitch());
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Turn off'));
      await settle(tester);

      expect(authService.twoFactorCalls, ['disable']);
      expect(find.text('Two-factor authentication is off'), findsOneWidget);
      expect(switchedOn(tester), isFalse);
    });
  });
}
