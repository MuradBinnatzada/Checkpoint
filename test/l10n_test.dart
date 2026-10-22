import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:checkpoint/app/app_shell.dart';
import 'package:checkpoint/app/checkpoint_app.dart';
import 'package:checkpoint/app/nav_tab.dart';
import 'package:checkpoint/l10n/l10n.dart';
import 'package:checkpoint/models/company.dart';
import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/game_details.dart';
import 'package:checkpoint/models/milestone.dart';
import 'package:checkpoint/screens/company/company_screen.dart';
import 'package:checkpoint/screens/game_detail/game_detail_screen.dart';
import 'package:checkpoint/screens/settings/settings_screen.dart';
import 'package:checkpoint/state/app_stores.dart';
import 'package:checkpoint/state/appearance_store.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/utils/formatters.dart';

import 'support/fakes.dart';

/// The app's languages: app_en.arb is the template, every other file a
/// translation of it (see l10n.yaml).
Map<String, Map<String, dynamic>> readArbFiles() => {
  for (final file in Directory('lib/l10n').listSync().whereType<File>())
    if (file.path.endsWith('.arb'))
      file.uri.pathSegments.last:
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
};

/// Whether [message] uses the placeholder [name]: as text, or as what a plural
/// or a select is on.
bool uses(String message, String name) =>
    message.contains('{$name}') || message.contains('{$name,');

void main() {
  group('the translations', () {
    final files = readArbFiles();
    final template = files['app_en.arb']!;
    final keys = [
      for (final k in template.keys)
        if (!k.startsWith('@')) k,
    ];

    test(
      'every language the app lists has an .arb file, and the other way round',
      () {
        expect({
          for (final l in L10n.supportedLocales) 'app_${l.languageCode}.arb',
        }, files.keys.toSet());
      },
    );

    for (final MapEntry(key: file, value: arb) in files.entries) {
      if (file == 'app_en.arb') continue;

      test('$file translates every message', () {
        expect([
          for (final k in keys)
            if (arb[k] is! String) k,
        ], isEmpty);
        expect(
          [
            for (final k in arb.keys)
              if (!k.startsWith('@') && !template.containsKey(k)) k,
          ],
          isEmpty,
          reason: 'messages app_en.arb no longer has',
        );
      });

      test('$file keeps every placeholder of the English', () {
        final wrong = <String>[];
        for (final key in keys) {
          final meta = template['@$key'];
          final names = meta is Map && meta['placeholders'] is Map
              ? (meta['placeholders'] as Map).keys.cast<String>()
              : RegExp(r'\{(\w+)\}')
                    .allMatches(template[key] as String)
                    .map((m) => m.group(1)!);
          final translated = arb[key];
          if (translated is! String) continue;
          for (final name in names) {
            if (uses(template[key] as String, name) != uses(translated, name)) {
              wrong.add('$key: {$name}');
            }
          }
        }
        expect(wrong, isEmpty);
      });
    }
  });

  group('the app in Russian', () {
    late FakeRepository repo;
    late FakeAuthService authService;
    late FakeDetailsApi detailsApi;
    late AppStores stores;
    final navigator = GlobalKey<NavigatorState>();

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      repo = FakeRepository()
        ..library = [
          testGame('g1', title: 'Skyrim', igdbId: 472, cover: false),
          testGame(
            'g2',
            title: 'Celeste',
            status: GameStatus.completed,
            cover: false,
          ),
          testGame(
            'g3',
            title: 'Hades',
            status: GameStatus.toPlay,
            cover: false,
          ),
          testGame(
            'g4',
            title: 'Outer Wilds',
            status: GameStatus.wishlist,
            cover: false,
          ),
        ];
      authService = FakeAuthService(testUser('u1'));
      detailsApi = FakeDetailsApi()
        ..answer = (id) => const GameDetails(
          igdbId: 472,
          genres: ['Role-playing (RPG)'],
          themes: ['Fantasy', 'Open world'],
          gameModes: ['Single player'],
          perspectives: ['First person', 'Third person'],
          developers: ['Bethesda Game Studios'],
          publishers: ['Bethesda Softworks'],
          storyline: 'The dragons are back.',
          translation: IgdbTranslation(
            language: 'ru',
            summary: 'Драконы вернулись.',
            storyline: 'Драконы вернулись.',
          ),
        );
      stores = AppStores(
        repository: repo,
        authService: authService,
        connectivity: FakeConnectivity(),
        apiService: detailsApi,
      );
    });

    tearDown(() => L10n.use(L10n.english));

    /// The real app's MaterialApp in Russian, on a small phone, with no text
    /// too wide for it: an overflow fails the test.
    Future<void> start(WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(stores.initialize);
      await tester.pumpWidget(
        AppStoresScope(
          stores: stores,
          child: AppearanceApp(
            appearance: AppearanceStore(locale: const Locale('ru')),
            navigatorKey: navigator,
            home: const AppShell(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        stores.dispose();
      });
    }

    Future<void> push(WidgetTester tester, Widget screen) async {
      unawaited(
        navigator.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => screen),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
    }

    testWidgets('every tab, and the strings outside widgets, are in Russian', (
      tester,
    ) async {
      await start(tester);
      expect(find.text('Главная'), findsOneWidget);
      expect(find.text('Записать игру'), findsOneWidget);
      // What stores, models and formatters say follows the language too.
      expect(L10n.current.localeName, 'ru');
      expect(GameStatus.toPlay.label, 'В планах');
      expect(milestoneById('library_10')!.title, 'Начало полки');
      expect(fmtThousands(1280), '1 280');
      expect(fmtMonthDay(DateTime(2026, 10, 14)), '14 окт.');

      for (final tab in [
        NavTab.search,
        NavTab.discussions,
        NavTab.library,
        NavTab.profile,
        NavTab.home,
      ]) {
        stores.nav.select(tab);
        await tester.pump(const Duration(milliseconds: 400));
      }
      stores.nav.select(NavTab.library);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Моя библиотека'), findsWidgets);
    });

    testWidgets(
      "a game's screen shows IGDB's texts translated, with the original a tap away",
      (tester) async {
        await start(tester);
        await push(tester, const GameDetailScreen(gameId: 'g1'));
        await tester.pump(const Duration(milliseconds: 400));

        final original = find.text('Показать оригинал');
        await tester.ensureVisible(original);
        await tester.pump();
        expect(find.text('Переведено DeepL'), findsOneWidget);
        expect(find.text('Драконы вернулись.'), findsNWidgets(2));
        expect(find.text('Ролевая игра (RPG)'), findsOneWidget);
        expect(find.text('От первого лица'), findsOneWidget);

        await tester.tap(original);
        await tester.pump();
        expect(find.text('The dragons are back.'), findsOneWidget);
        expect(find.text('Показать перевод'), findsOneWidget);
      },
    );

    testWidgets("a company's page is About the company, not the game", (
      tester,
    ) async {
      stores = AppStores(
        repository: repo,
        authService: authService,
        connectivity: FakeConnectivity(),
        apiService: FakeCompanyApi()
          ..company = (id) => Company(
            id: id,
            name: 'Bethesda Softworks',
            description: 'Publisher of The Elder Scrolls.',
            publishedCount: 120,
            developedCount: 0,
          ),
      );
      await start(tester);
      await push(
        tester,
        const CompanyScreen(companyId: 1, name: 'Bethesda Softworks'),
      );
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('О компании'), findsOneWidget);
      expect(find.text('Об игре'), findsNothing);
    });

    testWidgets('every section of Settings fits', (tester) async {
      await start(tester);
      for (final section in SettingsSection.values) {
        await push(tester, SettingsScreen(initialSection: section));
        expect(find.text('Настройки'), findsOneWidget);
        navigator.currentState!.pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
      }
    });

    testWidgets('picking English in Settings switches the whole app back', (
      tester,
    ) async {
      await start(tester);
      await push(
        tester,
        const SettingsScreen(initialSection: SettingsSection.appearance),
      );
      await tester.tap(find.text('Русский'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('English'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Settings'), findsOneWidget);
      expect(L10n.current.localeName, 'en');
      expect(GameStatus.toPlay.label, 'To Play');
      expect((await AppearanceStore.load()).locale, const Locale('en'));
    });
  });
}

void unawaitedPush(NavigatorState navigator, Widget screen) {
  navigator.push(MaterialPageRoute<void>(builder: (_) => screen));
}
