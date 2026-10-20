import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:checkpoint/app/checkpoint_app.dart';
import 'package:checkpoint/models/connected_service.dart';
import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/screens/game_detail/game_detail_screen.dart';
import 'package:checkpoint/screens/settings/settings_screen.dart';
import 'package:checkpoint/state/app_stores.dart';
import 'package:checkpoint/state/appearance_store.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/app_theme.dart';
import 'package:checkpoint/theme/palette.dart';

import 'support/fakes.dart';

/// The light and dark themes and their high contrast versions: their contrast,
/// the choices in Settings > Appearance (with the device's own settings) and
/// where they are kept.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the palettes', () {
    for (final p in [
      Palette.dark,
      Palette.light,
      Palette.darkHighContrast,
      Palette.lightHighContrast,
    ]) {
      final name = [
        p.isDark ? 'dark' : 'light',
        if (p.highContrast) 'high contrast',
      ].join(' ');
      final min = p.minContrast;

      test('$name: text reads at $min:1 on the background and panels', () {
        final text = {
          'text': p.text,
          'textSoft': p.textSoft,
          'muted': p.muted,
          'accent': p.accent,
          'electric': p.electric,
          'star': p.star,
          'danger': p.danger,
          'success': p.success,
        };
        for (final MapEntry(:key, :value) in text.entries) {
          for (final ground in [p.background, p.surface]) {
            expect(
              contrastRatio(value, ground),
              greaterThanOrEqualTo(min),
              reason: '$key on $ground',
            );
          }
        }
        for (final value in [p.text, p.textSoft, p.muted, p.accent]) {
          expect(
            contrastRatio(value, p.surfaceHigh),
            greaterThanOrEqualTo(min),
            reason: '$value on surfaceHigh',
          );
        }
        expect(contrastRatio(p.onAccent, p.accent), greaterThanOrEqualTo(min));
      });

      test(
        '$name: status, platform and service colors read on their pills',
        () {
          final colors = [
            for (final s in GameStatus.values) s.color,
            for (final f in PlatformFamily.values) f.color,
            for (final s in ConnectedService.values) s.color,
          ];
          for (final color in colors) {
            final ink = p.legible(color);
            for (final ground in [p.background, p.surface]) {
              final pill = Palette.pill(ink, ground);
              expect(
                contrastRatio(ink, pill),
                greaterThanOrEqualTo(min),
                reason: '$color as $ink on $ground',
              );
            }
            expect(
              contrastRatio(ink, p.surfaceHigh),
              greaterThanOrEqualTo(min),
              reason: '$color as $ink',
            );
          }
        },
      );
    }

    test('the dark theme keeps the colors that already read', () {
      for (final s in GameStatus.values.where((s) => s != GameStatus.dropped)) {
        expect(Palette.dark.legible(s.color), s.color, reason: s.label);
      }
    });

    for (final p in [Palette.light, Palette.lightHighContrast]) {
      test("the light${p.highContrast ? ' high contrast' : ''} theme's status "
          "colors are its own palette's", () {
        expect(p.legible(GameStatus.playing.color), p.accent);
        expect(p.legible(GameStatus.toPlay.color), p.electric);
        expect(p.legible(GameStatus.completed.color), p.success);
        expect(p.legible(GameStatus.dropped.color), p.danger);
        expect(p.legible(GameStatus.wishlist.color), p.star);
      });
    }
  });

  group('the theme choice', () {
    test('follows the device until one is picked', () async {
      final store = await AppearanceStore.load();
      expect(store.themeMode, ThemeMode.system);
    });

    test('is kept on the device', () async {
      final store = AppearanceStore();
      await store.setThemeMode(ThemeMode.light);
      expect((await AppearanceStore.load()).themeMode, ThemeMode.light);

      await store.setThemeMode(ThemeMode.dark);
      expect((await AppearanceStore.load()).themeMode, ThemeMode.dark);
    });

    test('that cannot be read is the device\'s', () async {
      SharedPreferences.setMockInitialValues({'theme_mode': 'sepia'});
      expect((await AppearanceStore.load()).themeMode, ThemeMode.system);
    });

    test(
      'Increase contrast and Reduce motion start off, and are kept',
      () async {
        final store = await AppearanceStore.load();
        expect(store.highContrast, isFalse);
        expect(store.reduceMotion, isFalse);

        await store.setHighContrast(true);
        await store.setReduceMotion(true);
        final reloaded = await AppearanceStore.load();
        expect(reloaded.highContrast, isTrue);
        expect(reloaded.reduceMotion, isTrue);
      },
    );
  });

  group('Settings > Appearance', () {
    late AppStores stores;
    late AppearanceStore appearance;

    setUp(() {
      stores = AppStores(
        repository: FakeRepository(),
        authService: FakeAuthService(testUser('u1')),
        connectivity: FakeConnectivity(),
      );
      appearance = AppearanceStore();
    });

    /// Settings > Appearance in the app's own MaterialApp.
    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(stores.initialize);
      await tester.pumpWidget(
        AppStoresScope(
          stores: stores,
          child: AppearanceApp(
            appearance: appearance,
            home: const SettingsScreen(
              initialSection: SettingsSection.appearance,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        stores.dispose();
      });
    }

    BuildContext screen(WidgetTester tester) =>
        tester.element(find.byType(SettingsScreen));

    Brightness brightness(WidgetTester tester) =>
        Theme.of(screen(tester)).brightness;

    bool highContrast(WidgetTester tester) =>
        screen(tester).palette.highContrast;

    bool reducedMotion(WidgetTester tester) =>
        MediaQuery.disableAnimationsOf(screen(tester));

    SwitchListTile switchTile(WidgetTester tester, String title) => tester
        .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, title));

    testWidgets('lists the device\'s theme first, then light, then dark', (
      tester,
    ) async {
      await open(tester);

      final modes = tester
          .widgetList<RadioListTile<ThemeMode>>(
            find.byType(RadioListTile<ThemeMode>),
          )
          .map((t) => t.value)
          .toList();
      expect(modes, [ThemeMode.system, ThemeMode.light, ThemeMode.dark]);
      expect(find.text('Same as device'), findsOneWidget);
    });

    testWidgets('follows the device by default', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await open(tester);
      expect(brightness(tester), Brightness.light);

      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      expect(brightness(tester), Brightness.dark);
    });

    testWidgets('switches the app to the theme picked, and keeps it', (
      tester,
    ) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await open(tester);

      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();
      expect(appearance.themeMode, ThemeMode.light);
      expect(brightness(tester), Brightness.light);
      expect(
        tester.getSemantics(find.byType(Radio<ThemeMode>).at(1)),
        isSemantics(isChecked: true),
      );
      expect((await AppearanceStore.load()).themeMode, ThemeMode.light);

      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      expect(brightness(tester), Brightness.dark);
      expect((await AppearanceStore.load()).themeMode, ThemeMode.dark);
    });

    testWidgets('Increase contrast switches to the high contrast theme', (
      tester,
    ) async {
      await open(tester);
      expect(highContrast(tester), isFalse);

      await tester.tap(find.text('Increase contrast'));
      await tester.pumpAndSettle();
      expect(appearance.highContrast, isTrue);
      expect(highContrast(tester), isTrue);
      expect(switchTile(tester, 'Increase contrast').value, isTrue);
      expect((await AppearanceStore.load()).highContrast, isTrue);

      await tester.tap(find.text('Increase contrast'));
      await tester.pumpAndSettle();
      expect(highContrast(tester), isFalse);
    });

    testWidgets("the device's high contrast setting turns it on, locked", (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(highContrast: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await open(tester);

      expect(highContrast(tester), isTrue);
      final tile = switchTile(tester, 'Increase contrast');
      expect(tile.value, isTrue);
      expect(tile.onChanged, isNull);
      expect(find.text("On in your device's settings."), findsOneWidget);
    });

    testWidgets('Reduce motion turns the animations off', (tester) async {
      await open(tester);
      expect(reducedMotion(tester), isFalse);

      await tester.tap(find.text('Reduce motion'));
      await tester.pumpAndSettle();
      expect(appearance.reduceMotion, isTrue);
      expect(reducedMotion(tester), isTrue);
      expect(motion(screen(tester), const Duration(seconds: 1)), Duration.zero);
      expect((await AppearanceStore.load()).reduceMotion, isTrue);
    });

    testWidgets("iOS's Reduce Motion turns them off too", (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(reduceMotion: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await open(tester);

      expect(reducedMotion(tester), isTrue);
      final tile = switchTile(tester, 'Reduce motion');
      expect(tile.value, isTrue);
      expect(tile.onChanged, isNull);
    });
  });

  testWidgets(
    'the game header stays dark on the light theme, so its title reads',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repo = FakeRepository()
        ..library = [testGame('g1', title: 'Skyrim', cover: false)];
      final stores = AppStores(
        repository: repo,
        authService: FakeAuthService(testUser('u1')),
        connectivity: FakeConnectivity(),
        apiService: FakeDetailsApi(),
      );
      await tester.runAsync(stores.initialize);
      await tester.pumpWidget(
        AppStoresScope(
          stores: stores,
          child: MaterialApp(
            theme: lightTheme,
            home: const GameDetailScreen(gameId: 'g1'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        stores.dispose();
      });

      // The big title on the art, and the panels below it on the light page.
      final title = find.text('Skyrim').first;
      expect(Theme.of(tester.element(title)).brightness, Brightness.dark);
      final color = DefaultTextStyle.of(tester.element(title)).style.color!;
      expect(contrastRatio(color, Colors.black), greaterThan(15));
      expect(
        Theme.of(tester.element(find.text('Update status'))).brightness,
        Brightness.light,
      );
    },
  );
}
