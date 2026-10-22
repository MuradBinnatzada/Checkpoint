import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/news.dart';
import 'package:checkpoint/screens/home/home_screen.dart';
import 'package:checkpoint/services/news_api_service.dart';
import 'package:checkpoint/state/app_stores.dart';
import 'package:checkpoint/state/auth_store.dart';
import 'package:checkpoint/state/load_status.dart';
import 'package:checkpoint/state/news_store.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/app_theme.dart';

import 'support/fakes.dart';

/// An article of the function's answer.
Map<String, Object?> articleJson(
  int i, {
  String source = 'ign',
  String? image = 'https://img.example.com/a.jpg',
  int? appId,
}) => {
  'id': '$source:$i',
  'title': 'Headline $i',
  'summary': 'The start of story $i, which goes on for a while.',
  'url': 'https://news.example.com/$i',
  'image_url': image,
  'source_id': source,
  'source_name': source.toUpperCase(),
  'published_at': 1792000000 - i * 60,
  'app_id': ?appId,
};

NewsArticle article(int i, {String source = 'ign', int? appId}) =>
    NewsArticle.fromJson(articleJson(i, source: source, appId: appId))!;

/// Answers the news requests from lists the test sets, and notes what was asked.
/// [gate] holds every answer until completed, to have a request in flight.
class FakeNewsApi extends NewsApiService {
  /// What each outlet has ("" is the list of all of them), newest first.
  Map<String, List<NewsArticle>> byOutlet = {
    '': [for (var i = 0; i < 25; i++) article(i)],
  };
  List<NewsArticle> steam = [];
  List<NewsSource> outlets = const [
    NewsSource('ign', 'IGN'),
    NewsSource('rps', 'Rock Paper Shotgun'),
  ];
  bool fail = false;
  Completer<void>? gate;

  final List<({String? source, int offset})> latestCalls = [];
  final List<List<int>> steamCalls = [];

  @override
  Future<NewsPage?> latest({
    String? sourceId,
    int offset = 0,
    int limit = NewsApiService.pageSize,
  }) async {
    latestCalls.add((source: sourceId, offset: offset));
    await gate?.future;
    if (fail) return null;
    final all = byOutlet[sourceId ?? ''] ?? const <NewsArticle>[];
    final page = all.skip(offset).take(limit).toList();
    return NewsPage(page, sources: outlets, hasMore: page.length >= limit);
  }

  @override
  Future<List<NewsArticle>?> steamNews(
    List<int> appIds, {
    int limit = 30,
  }) async {
    steamCalls.add(appIds);
    await gate?.future;
    return fail ? null : steam;
  }
}

void main() {
  group('NewsArticle', () {
    test('reads what game-news sends', () {
      final a = NewsArticle.fromJson(articleJson(3, appId: 570))!;

      expect(a.id, 'ign:3');
      expect(a.title, 'Headline 3');
      expect(a.summary, startsWith('The start of story 3'));
      expect(a.url, Uri.parse('https://news.example.com/3'));
      expect(a.imageUrl, Uri.parse('https://img.example.com/a.jpg'));
      expect(a.sourceId, 'ign');
      expect(a.sourceName, 'IGN');
      expect(
        a.publishedAt,
        DateTime.fromMillisecondsSinceEpoch(1791999820000, isUtc: true),
      );
      expect(a.appId, 570);
    });

    test('an article is sparse where the outlet was', () {
      final a = NewsArticle.fromJson({
        'id': 'x:1',
        'title': ' Just a headline ',
        'url': 'https://a.example.com/1',
        'published_at': 1792000000,
      })!;

      expect(a.title, 'Just a headline');
      expect(a.summary, '');
      expect(a.imageUrl, isNull);
      expect(a.sourceName, '');
      expect(a.appId, isNull);
    });

    test('no title, no https link or no date is no article, and a picture that is not https is dropped', () {
      Map<String, Object?> with_(String key, Object? value) => {
        ...articleJson(1),
        key: value,
      };

      expect(NewsArticle.fromJson(with_('title', ' ')), isNull);
      expect(
        NewsArticle.fromJson(with_('url', 'http://a.example.com/1')),
        isNull,
      );
      expect(NewsArticle.fromJson(with_('url', 'javascript:alert(1)')), isNull);
      expect(NewsArticle.fromJson(with_('published_at', null)), isNull);
      expect(NewsArticle.fromJson(with_('published_at', 0)), isNull);
      expect(NewsArticle.fromJson(with_('id', null)), isNull);
      expect(NewsArticle.fromJson('nope'), isNull);
      expect(
        NewsArticle.fromJson(
          with_('image_url', 'http://img.example.com/a.jpg'),
        )!.imageUrl,
        isNull,
      );
    });
  });

  group('NewsPage', () {
    test(
      'reads the articles and the outlets, and a full page may have another',
      () {
        final page = NewsPage.fromResponse({
          'articles': [
            articleJson(1),
            articleJson(2),
            {'title': 'broken'},
          ],
          'sources': [
            {'id': 'ign', 'name': 'IGN'},
            {'id': 'rps'},
          ],
        }, limit: 3)!;

        expect(page.articles, hasLength(2));
        expect([for (final s in page.sources) s.id], ['ign']);
        expect(page.hasMore, isTrue);
        expect(
          NewsPage.fromResponse({'articles': []}, limit: 3)!.hasMore,
          isFalse,
        );
      },
    );

    test('an error is no page', () {
      expect(
        NewsPage.fromResponse({
          'error': 'x',
          'code': 'RATE_LIMITED',
        }, limit: 20),
        isNull,
      );
      expect(NewsPage.fromResponse(null, limit: 20), isNull);
      expect(NewsPage.fromResponse({'articles': 'no'}, limit: 20), isNull);
    });
  });

  group('newsAppIds', () {
    test('the games being played first, then the most played, each app once, at most ten', () {
      final games = [
        testGame('a', status: GameStatus.completed, hours: 90, steamAppId: 1),
        testGame('b', status: GameStatus.playing, hours: 5, steamAppId: 2),
        testGame('c', status: GameStatus.playing, hours: 20, steamAppId: 3),
        testGame('d', status: GameStatus.completed, hours: 10, steamAppId: 4),
        testGame(
          'e',
          status: GameStatus.completed,
          hours: 99,
          steamAppId: null,
        ),
        testGame('f', status: null, hours: 0, steamAppId: 6),
        testGame('g', status: GameStatus.completed, hours: 1, steamAppId: 3),
      ];

      expect(newsAppIds(games), [3, 2, 1, 4]);
      expect(newsAppIds(games, limit: 2), [3, 2]);
      expect(newsAppIds(const []), isEmpty);
      expect(
        newsAppIds([
          for (var i = 1; i <= 15; i++)
            testGame('g$i', steamAppId: i, hours: i.toDouble()),
        ]),
        hasLength(10),
      );
    });
  });

  group('NewsStore', () {
    late FakeAuthService authService;
    late AuthStore auth;
    late FakeNewsApi api;
    late NewsStore store;
    late DebugPrintCallback originalDebugPrint;

    setUp(() {
      originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {};
      SharedPreferences.setMockInitialValues({});
      authService = FakeAuthService(testUser('u1'));
      auth = AuthStore(authService)..initialize();
      api = FakeNewsApi();
      store = NewsStore(auth: auth, api: api)..initialize();
    });

    tearDown(() {
      debugPrint = originalDebugPrint;
      store.dispose();
      auth.dispose();
    });

    test('nothing is asked until the screen asks, or signed out', () async {
      expect(store.latestStatus, LoadStatus.idle);
      expect(api.latestCalls, isEmpty);

      authService.emit(null);
      await pumpEventQueue();
      await store.loadLatest();
      await store.loadMyGames([1]);

      expect(api.latestCalls, isEmpty);
      expect(api.steamCalls, isEmpty);
    });

    test('loads the first page and the outlets', () async {
      await store.loadLatest();

      expect(store.latestStatus, LoadStatus.ready);
      expect(store.latest, hasLength(20));
      expect(store.hasMore, isTrue);
      expect([for (final s in store.sources) s.id], ['ign', 'rps']);
    });

    test(
      'what was fetched lately is shown again without asking, unless forced',
      () async {
        await store.loadLatest();
        await store.loadLatest();
        expect(api.latestCalls, hasLength(1));

        await store.loadLatest(force: true);
        expect(api.latestCalls, hasLength(2));
      },
    );

    test(
      'appends the next page after the articles held, without repeats',
      () async {
        await store.loadLatest();

        await store.loadMoreLatest();

        expect(store.latest, hasLength(25));
        expect(store.hasMore, isFalse);
        expect(api.latestCalls.last.offset, 20);
        expect({for (final a in store.latest) a.id}, hasLength(25));
      },
    );

    test('a page with nothing new stops the paging', () async {
      api.byOutlet = {
        '': [for (var i = 0; i < 20; i++) article(i)],
      };
      await store.loadLatest();
      expect(store.hasMore, isTrue);

      await store.loadMoreLatest();

      expect(store.latest, hasLength(20));
      expect(store.hasMore, isFalse);
    });

    test('a failed page can be tried again', () async {
      await store.loadLatest();
      api.fail = true;

      await store.loadMoreLatest();
      expect(store.loadMoreFailed, isTrue);
      expect(store.hasMore, isTrue);

      api.fail = false;
      await store.loadMoreLatest();
      expect(store.loadMoreFailed, isFalse);
      expect(store.latest, hasLength(25));
    });

    test(
      'a failed first read is failed; a failed refresh keeps what was shown',
      () async {
        api.fail = true;
        await store.loadLatest();
        expect(store.latestStatus, LoadStatus.failed);

        api.fail = false;
        await store.loadLatest();
        expect(store.latestStatus, LoadStatus.ready);

        api.fail = true;
        await store.loadLatest(force: true);
        expect(store.latestStatus, LoadStatus.ready);
        expect(store.latest, hasLength(20));
      },
    );

    test('one outlet narrows the list, and the other outlet\'s news is gone while it loads', () async {
      api.byOutlet = {
        '': [for (var i = 0; i < 5; i++) article(i)],
        'rps': [for (var i = 0; i < 3; i++) article(100 + i, source: 'rps')],
      };
      await store.loadLatest();
      api.gate = Completer<void>();

      final switching = store.setSource('rps');
      expect(store.latest, isEmpty);
      expect(
        store.latestStatus,
        LoadStatus.idle.index == 0 ? store.latestStatus : LoadStatus.idle,
      );
      api.gate!.complete();
      await switching;

      expect(store.sourceId, 'rps');
      expect([for (final a in store.latest) a.sourceId], ['rps', 'rps', 'rps']);
      expect(api.latestCalls.last.source, 'rps');

      await store.setSource(null);
      expect(store.latest, hasLength(5));
    });

    test('an answer overtaken by another outlet is dropped', () async {
      api.byOutlet = {
        '': [article(1)],
        'rps': [article(2, source: 'rps')],
      };
      api.gate = Completer<void>();

      final first = store.loadLatest();
      final second = store.setSource('rps');
      api.gate!.complete();
      await Future.wait([first, second]);

      expect([for (final a in store.latest) a.sourceId], ['rps']);
    });

    test(
      'Steam\'s news is asked for the games given, and nothing for none',
      () async {
        api.steam = [article(1, source: 'steam', appId: 570)];

        await store.loadMyGames(const []);
        expect(store.myGamesStatus, LoadStatus.ready);
        expect(store.myGames, isEmpty);
        expect(api.steamCalls, isEmpty);

        await store.loadMyGames([570, 730]);
        expect(api.steamCalls, [
          [570, 730],
        ]);
        expect(store.myGames.single.appId, 570);

        // The same games, lately: not asked again. Other games: asked.
        await store.loadMyGames([570, 730]);
        expect(api.steamCalls, hasLength(1));
        await store.loadMyGames([570]);
        expect(api.steamCalls, hasLength(2));
      },
    );

    test(
      'a failed read of Steam\'s news is failed, and the next one clears it',
      () async {
        api.fail = true;
        await store.loadMyGames([570]);
        expect(store.myGamesStatus, LoadStatus.failed);

        api.fail = false;
        await store.loadMyGames([570]);
        expect(store.myGamesStatus, LoadStatus.ready);
      },
    );

    test('another account drops everything', () async {
      await store.loadLatest();
      await store.loadMyGames([570]);

      authService.emit(testUser('u2'));
      await pumpEventQueue();

      expect(store.latestStatus, LoadStatus.idle);
      expect(store.latest, isEmpty);
      expect(store.sources, isEmpty);
      expect(store.myGamesStatus, LoadStatus.idle);
    });
  });

  group('on screen', () {
    late FakeRepository repo;
    late FakeNewsApi api;
    late AppStores stores;

    AppStores makeStores({bool signedIn = true}) => AppStores(
      repository: repo,
      authService: FakeAuthService(signedIn ? testUser('u1') : null),
      connectivity: FakeConnectivity(),
      apiService: FakeBrowseApi(),
      newsApi: api,
    );

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      repo = FakeRepository()
        ..library = [
          testGame(
            'g1',
            title: 'Counter-Strike',
            steamAppId: 730,
            cover: false,
          ),
          testGame(
            'g2',
            title: 'No Steam Here',
            steamAppId: null,
            cover: false,
          ),
        ];
      // Fewer than a page: the list has no next page to ask for by itself.
      api = FakeNewsApi()..byOutlet = {'': [for (var i = 0; i < 5; i++) article(i)]};
      stores = makeStores();
    });

    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
    }

    Future<void> openHome(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(stores.initialize);
      await tester.pumpWidget(
        AppStoresScope(
          stores: stores,
          child: MaterialApp(theme: buildTheme(), home: const Scaffold(body: HomeScreen())),
        ),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        stores.dispose();
      });
      await settle(tester);
    }

    Future<void> openNews(WidgetTester tester) async {
      await openHome(tester);
      await tester.tap(find.text('Game news'));
      await settle(tester);
    }

    Future<void> tapChip(WidgetTester tester, String label) async {
      await tester.ensureVisible(find.text(label));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await settle(tester);
    }

    testWidgets(
      'Home has a Game news button under the greeting that opens the news',
      (tester) async {
        await openHome(tester);

        expect(find.text('Game news'), findsOneWidget);
        expect(find.text('Headlines from the gaming press'), findsOneWidget);
        // Nothing is fetched until the button is tapped.
        expect(api.latestCalls, isEmpty);

        await tester.tap(find.text('Game news'));
        await settle(tester);

        expect(api.latestCalls, hasLength(1));
        expect(find.text('Headline 0'), findsOneWidget);
        expect(find.text('Latest'), findsOneWidget);
        expect(find.text('My games'), findsOneWidget);
      },
    );

    testWidgets(
      'the latest news shows the outlet, the headline and the start of the story',
      (tester) async {
        await openNews(tester);

        expect(find.textContaining('IGN · '), findsWidgets);
        expect(find.text('Headline 0'), findsOneWidget);
        expect(
          find.text('The start of story 0, which goes on for a while.'),
          findsOneWidget,
        );
      },
    );

    testWidgets('a chip narrows the news to one outlet', (tester) async {
      api.byOutlet = {
        '': [article(1), article(2, source: 'rps')],
        'rps': [article(2, source: 'rps')],
      };
      await openNews(tester);
      expect(find.text('Headline 1'), findsOneWidget);

      await tapChip(tester, 'Rock Paper Shotgun');

      expect(api.latestCalls.last.source, 'rps');
      expect(find.text('Headline 1'), findsNothing);
      expect(find.text('Headline 2'), findsOneWidget);

      await tapChip(tester, 'All outlets');
      expect(find.text('Headline 1'), findsOneWidget);
    });

    testWidgets('a failed load says so and can be tried again', (tester) async {
      api.fail = true;
      await openNews(tester);
      expect(find.text('Couldn’t load the news'), findsOneWidget);

      api.fail = false;
      await tester.tap(find.text('Try again'));
      await settle(tester);

      expect(find.text('Headline 0'), findsOneWidget);
    });

    testWidgets('no news at all says so', (tester) async {
      api.byOutlet = {'': []};
      await openNews(tester);

      expect(find.text('No news right now'), findsOneWidget);
    });

    testWidgets(
      'My games lists Steam\'s news for the library, each with its game',
      (tester) async {
        api.steam = [article(7, source: 'steam', appId: 730)];
        await openNews(tester);

        await tester.tap(find.text('My games'));
        await settle(tester);

        expect(api.steamCalls, [
          [730],
        ]);
        expect(find.text('Headline 7'), findsOneWidget);
        expect(
          find.textContaining('Counter-Strike · STEAM · '),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'My games with no Steam game explains where the news comes from',
      (tester) async {
        repo.library = [
          testGame(
            'g2',
            title: 'No Steam Here',
            steamAppId: null,
            cover: false,
          ),
        ];
        await openNews(tester);

        await tester.tap(find.text('My games'));
        await settle(tester);

        expect(find.text('No Steam games yet'), findsOneWidget);
        expect(api.steamCalls, isEmpty);
      },
    );

    testWidgets('My games with nothing new says so', (tester) async {
      api.steam = [];
      await openNews(tester);

      await tester.tap(find.text('My games'));
      await settle(tester);

      expect(find.text('Nothing new for your games'), findsOneWidget);
    });

    testWidgets('signed out, the news asks for a login and asks nothing', (
      tester,
    ) async {
      stores = makeStores(signedIn: false);
      await openNews(tester);

      expect(find.text('Log in to read the news'), findsOneWidget);
      expect(api.latestCalls, isEmpty);
    });
  });
}
