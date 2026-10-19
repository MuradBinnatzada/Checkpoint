import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/log_entry.dart';
import 'package:checkpoint/screens/game_detail/game_detail_screen.dart';
import 'package:checkpoint/state/app_stores.dart';
import 'package:checkpoint/state/auth_store.dart';
import 'package:checkpoint/state/play_timer_store.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/app_theme.dart';
import 'package:checkpoint/widgets/play_timer_widgets.dart';

import 'support/fakes.dart';

void main() {
  group('PlayTimerStore', () {
    late FakeAuthService authService;
    late AuthStore auth;
    late DateTime now;

    PlayTimerStore newTimers() => PlayTimerStore(auth: auth, clock: () => now);

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      now = DateTime(2026, 10, 19, 20);
      authService = FakeAuthService(testUser('u1'));
      auth = AuthStore(authService);
      await auth.initialize();
    });

    tearDown(() => auth.dispose());

    test('runs from when it was started, and is still running after the app reopens', () async {
      final timers = newTimers();
      await timers.initialize();
      timers.start('g1');
      now = now.add(const Duration(minutes: 95));

      expect(timers.isRunningFor('g1'), isTrue);
      expect(timers.elapsed, const Duration(minutes: 95));
      timers.dispose();
      await pumpEventQueue();

      final reopened = newTimers();
      await reopened.initialize();
      expect(reopened.running!.gameId, 'g1');
      expect(reopened.elapsed, const Duration(minutes: 95));

      reopened.clear();
      reopened.dispose();
      await pumpEventQueue();
      final again = newTimers();
      await again.initialize();
      expect(again.running, isNull);
      again.dispose();
    });

    test('belongs to the account: another one signing in sees its own', () async {
      final timers = newTimers();
      await timers.initialize();
      timers.start('g1');
      await pumpEventQueue();

      authService.emit(testUser('u2'));
      await pumpEventQueue();
      expect(timers.running, isNull);

      authService.emit(testUser('u1'));
      await pumpEventQueue();
      expect(timers.running!.gameId, 'g1');

      authService.emit(null);
      await pumpEventQueue();
      expect(timers.running, isNull);
      timers.start('g2'); // signed out: nothing to start it for
      expect(timers.running, isNull);
      timers.dispose();
    });

    test('a session from the timer is in tenths of an hour, between a tenth and one sitting', () {
      expect(timerHours(const Duration(minutes: 95), maxHours: 24), 1.6);
      expect(timerHours(const Duration(seconds: 20), maxHours: 24), 0.1);
      expect(timerHours(const Duration(hours: 30), maxHours: 24), 24);
    });
  });

  group('on screen', () {
    late FakeRepository repo;
    late AppStores stores;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      repo = FakeRepository()
        ..library = [testGame('g1', title: 'Hades', hours: 10, cover: false)]
        ..logs = [
          LogEntry(
            id: 's1',
            gameId: 'g1',
            timestamp: DateTime.now().subtract(const Duration(days: 2)),
            hours: 2,
            platform: GamePlatform.pc,
            note: 'first run',
          ),
        ];
      stores = AppStores(
        repository: repo,
        authService: FakeAuthService(testUser('u1')),
        connectivity: FakeConnectivity(),
        apiService: FakeDetailsApi(),
      );
    });

    Future<void> openGame(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(stores.initialize);
      await tester.pumpWidget(
        AppStoresScope(
          stores: stores,
          child: MaterialApp(
            theme: buildTheme(),
            home: const Scaffold(
              body: GameDetailScreen(gameId: 'g1'),
              bottomNavigationBar: PlayTimerBar(),
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

    testWidgets('Start timer shows the bar; Stop logs the time as a session', (tester) async {
      await openGame(tester);

      await tester.tap(find.text('Start timer'));
      await tester.pump();
      expect(stores.playTimer.isRunningFor('g1'), isTrue);
      expect(find.byType(PlayTimerBar), findsOneWidget);
      expect(find.text('Stop'), findsOneWidget);
      final startedAt = stores.playTimer.running!.startedAt;

      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();
      expect(find.text('Log your timer'), findsOneWidget);
      expect(find.widgetWithText(TextField, '0.1'), findsOneWidget);

      await tester.ensureVisible(find.text('Save session'));
      await tester.tap(find.text('Save session'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pumpAndSettle();

      expect(repo.writes, contains('log:g1:0.1'));
      expect(repo.logTimes.last, startedAt);
      expect(stores.playTimer.running, isNull);
      expect(find.text('Stop'), findsNothing);
    });

    testWidgets('Discard timer stops it without logging anything', (tester) async {
      await openGame(tester);
      await tester.tap(find.text('Start timer'));
      await tester.pump();
      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Discard timer'));
      await tester.tap(find.text('Discard timer'));
      await tester.pumpAndSettle();

      expect(stores.playTimer.running, isNull);
      expect(repo.writes.where((w) => w.startsWith('log:')), isEmpty);
    });

    testWidgets('a session opens for editing, and a deleted one comes back with Undo', (tester) async {
      await openGame(tester);

      await tester.tap(find.text('+2 h on PC'));
      await tester.pumpAndSettle();
      expect(find.text('Edit session'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Hours played'), '3.5');
      await tester.pump();
      await tester.tap(find.text('Save changes'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pumpAndSettle();

      expect(repo.writes, contains('edit-log:s1:3.5'));
      expect(stores.library.gameById('g1').hoursPlayed, 11.5);
      expect(find.text('+3.5 h on PC'), findsOneWidget);

      await tester.tap(find.text('+3.5 h on PC'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Delete session'));
      await tester.tap(find.text('Delete session'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pumpAndSettle();

      expect(repo.writes, contains('delete-log:s1'));
      expect(find.text('Recent sessions'), findsNothing);
      expect(stores.library.gameById('g1').hoursPlayed, 8);

      await tester.tap(find.text('Undo'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pumpAndSettle();
      expect(repo.writes.last, 'log:g1:3.5');
      expect(stores.library.gameById('g1').hoursPlayed, 11.5);
    });
  });
}
