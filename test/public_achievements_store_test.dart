import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;

import 'package:checkpoint/models/achievement.dart';
import 'package:checkpoint/models/achievement_summary.dart';
import 'package:checkpoint/state/auth_store.dart';
import 'package:checkpoint/state/load_status.dart';
import 'package:checkpoint/state/public_achievements_store.dart';

import 'support/fakes.dart';

void main() {
  late FakeRepository repo;
  late FakeAuthService authService;
  late AuthStore auth;
  late PublicAchievementsStore store;

  const summary = GameAchievementSummary(
    gameId: 'g1',
    title: 'Hades',
    unlocked: 12,
    total: 40,
  );
  const first = Achievement(
    name: 'First blood',
    description: 'Win a fight',
    iconUrl: '',
    unlocked: true,
  );

  setUp(() {
    debugPrint = (String? message, {int? wrapWidth}) {};
    SharedPreferences.setMockInitialValues({});
    repo = FakeRepository();
    authService = FakeAuthService(testUser('u1'));
    auth = AuthStore(authService)..initialize();
    store = PublicAchievementsStore(repository: repo, auth: auth)..initialize();
    repo.achievementSummaries['m1'] = [summary];
    repo.memberAchievements[('m1', 'g1')] = [first];
  });

  tearDown(() {
    debugPrint = debugPrintThrottled;
    store.dispose();
    auth.dispose();
  });

  test('nothing is fetched until a viewer asks', () {
    expect(store.totalsOf('m1').status, LoadStatus.idle);
    expect(store.summaryOf('m1').status, LoadStatus.idle);
    expect(store.gameOf('m1', 'g1').status, LoadStatus.idle);
    expect(repo.memberReads, isEmpty);
  });

  test('markCleared shows no achievements at once and forgets the games', () async {
    await store.loadTotals('m1');
    await store.loadSummary('m1');
    await store.loadGame('m1', 'g1');
    await store.loadSummary('m2');
    expect(store.totalsOf('m1').totals.total, 40);
    var notified = 0;
    store.addListener(() => notified++);
    final reads = repo.memberReads.length;

    store.markCleared('m1');

    expect(notified, 1);
    expect(store.totalsOf('m1').status, LoadStatus.ready);
    expect(store.totalsOf('m1').totals.isEmpty, isTrue);
    expect(store.summaryOf('m1').status, LoadStatus.idle);
    expect(store.gameOf('m1', 'g1').status, LoadStatus.idle);
    // Someone else's are not touched, and nothing was asked of the server.
    expect(store.summaryOf('m2').status, LoadStatus.ready);
    expect(repo.memberReads.length, reads);
  });

  group('the totals', () {
    test('are one small read, added up over the games', () async {
      repo.achievementSummaries['m1'] = [
        summary,
        const GameAchievementSummary(
          gameId: 'g2',
          title: 'Celeste',
          unlocked: 8,
          total: 8,
        ),
      ];

      await store.loadTotals('m1');

      final view = store.totalsOf('m1');
      expect(view.status, LoadStatus.ready);
      expect(view.totals.unlocked, 20);
      expect(view.totals.total, 48);
      expect(view.totals.games, 2);
      expect(view.totals.completedGames, 1);
      expect(view.totals.allUnlocked, isFalse);
      // No per-game progress and no achievement was asked for.
      expect(repo.memberReads, ['achievement-totals:m1']);
      expect(store.summaryOf('m1').status, LoadStatus.idle);
    });

    test('are "all unlocked" only when nothing is left locked', () {
      expect(const AchievementTotals(unlocked: 5, total: 5).allUnlocked, isTrue);
      expect(const AchievementTotals(unlocked: 4, total: 5).allUnlocked, isFalse);
      // No achievements at all is not "all of them".
      expect(const AchievementTotals().allUnlocked, isFalse);
      expect(const AchievementTotals().isEmpty, isTrue);
    });

    test('are asked for once, unless forced', () async {
      await store.loadTotals('m1');
      await store.loadTotals('m1');
      expect(repo.memberReads, ['achievement-totals:m1']);

      await store.loadTotals('m1', force: true);
      expect(repo.memberReads, hasLength(2));
    });

    test('a member with none gets empty, ready totals', () async {
      await store.loadTotals('m2');

      expect(store.totalsOf('m2').status, LoadStatus.ready);
      expect(store.totalsOf('m2').totals.isEmpty, isTrue);
    });

    test('a failure is "failed", and a refresh that fails keeps the count', () async {
      repo.failAchievementTotals = true;
      await store.loadTotals('m1');
      expect(store.totalsOf('m1').status, LoadStatus.failed);

      repo.failAchievementTotals = false;
      await store.loadTotals('m1');
      expect(store.totalsOf('m1').status, LoadStatus.ready);

      repo.failAchievementTotals = true;
      await store.loadTotals('m1', force: true);
      expect(store.totalsOf('m1').status, LoadStatus.ready);
      expect(store.totalsOf('m1').totals.total, 40);
    });
  });

  group('the summary', () {
    test('is fetched on request', () async {
      await store.loadSummary('m1');

      final view = store.summaryOf('m1');
      expect(view.status, LoadStatus.ready);
      expect(view.games.single.title, 'Hades');
      expect(view.games.single.progress, closeTo(0.3, 1e-9));
      expect(repo.memberReads, ['achievements:m1']);
    });

    test('is asked for once, unless forced', () async {
      await store.loadSummary('m1');
      await store.loadSummary('m1');
      expect(repo.memberReads, ['achievements:m1']);

      await store.loadSummary('m1', force: true);
      expect(repo.memberReads, ['achievements:m1', 'achievements:m1']);
    });

    test('a member with none gets an empty, ready summary', () async {
      await store.loadSummary('m2');

      expect(store.summaryOf('m2').status, LoadStatus.ready);
      expect(store.summaryOf('m2').games, isEmpty);
    });

    test('a failure is "failed" and loading again recovers', () async {
      repo.failAchievementReads = true;
      await store.loadSummary('m1');
      expect(store.summaryOf('m1').status, LoadStatus.failed);

      repo.failAchievementReads = false;
      await store.loadSummary('m1');
      expect(store.summaryOf('m1').status, LoadStatus.ready);
    });

    test('a refresh that fails keeps what was loaded', () async {
      await store.loadSummary('m1');
      repo.failAchievementReads = true;

      await store.loadSummary('m1', force: true);

      expect(store.summaryOf('m1').status, LoadStatus.ready);
      expect(store.summaryOf('m1').games, hasLength(1));
    });

    test('works for the signed-in member\'s own id too', () async {
      repo.achievementSummaries['u1'] = [summary];

      await store.loadSummary('u1');

      expect(store.summaryOf('u1').games, hasLength(1));
    });
  });

  group('one game', () {
    test('is fetched on request, and not with the summary', () async {
      await store.loadSummary('m1');
      expect(repo.memberReads.where((r) => r == 'achievements:m1:g1'), isEmpty);

      await store.loadGame('m1', 'g1');

      final view = store.gameOf('m1', 'g1');
      expect(view.status, LoadStatus.ready);
      expect(view.achievements!.single.name, 'First blood');
    });

    test('is asked for once, unless forced', () async {
      await store.loadGame('m1', 'g1');
      await store.loadGame('m1', 'g1');
      expect(repo.memberReads, ['achievements:m1:g1']);

      await store.loadGame('m1', 'g1', force: true);
      expect(repo.memberReads, hasLength(2));
    });

    test('a game with nothing stored is fetched from Steam, and stored', () async {
      repo.steamAchievements[('m1', 'other')] = [first];

      await store.loadGame('m1', 'other');

      final view = store.gameOf('m1', 'other');
      expect(view.status, LoadStatus.ready);
      expect(view.achievements, [first]);
      expect(view.error, isNull);
      expect(repo.memberReads, ['achievements:m1:other', 'steam:m1:other']);
      expect(repo.memberAchievements[('m1', 'other')], [first]);
    });

    test('a stored list that matches the counts is used as is', () async {
      repo.memberAchievements[('m1', 'g1')] = [
        first,
        const Achievement(name: 'B', description: '', iconUrl: '', unlocked: false),
      ];

      await store.loadGame(
        'm1',
        'g1',
        expected: const GameAchievementSummary(gameId: 'g1', title: 'Hades', unlocked: 1, total: 2),
      );

      expect(store.gameOf('m1', 'g1').achievements, hasLength(2));
      expect(repo.memberReads, ['achievements:m1:g1']);
    });

    test('a stored list older than the counts is fetched again, and the counts follow', () async {
      final fresh = [
        for (var i = 0; i < 40; i++)
          Achievement(name: 'A$i', description: '', iconUrl: '', unlocked: i < 13),
      ];
      repo.steamAchievements[('m1', 'g1')] = fresh;
      Object? handedOn;
      store.dispose();
      store = PublicAchievementsStore(
        repository: repo,
        auth: auth,
        onGameFetched: (userId, gameId, list) => handedOn = (userId, gameId, list.length),
      )..initialize();
      await store.loadSummary('m1'); // Hades: 12 / 40, but one unlocked is stored

      await store.loadGame('m1', 'g1', expected: store.summaryOf('m1').games.single);

      expect(repo.memberReads, contains('steam:m1:g1'));
      expect(store.gameOf('m1', 'g1').achievements, hasLength(40));
      // The profile now agrees with the list.
      expect(store.summaryOf('m1').games.single.unlocked, 13);
      expect(handedOn, ('m1', 'g1', 40));
    });

    test('when Steam fails, a stored list is still shown, with the reason', () async {
      repo.steamAchievementsError = const FunctionException(
        status: 429,
        details: {'code': 'STEAM_RATE_LIMITED', 'retry_after': 60},
      );

      await store.loadGame('m1', 'g1');
      final kept = store.gameOf('m1', 'g1');
      expect(kept.status, LoadStatus.ready);
      expect(kept.achievements, [first]);
      expect(kept.error, isNull);

      await store.loadGame('m1', 'g1', force: true);
      final view = store.gameOf('m1', 'g1');
      expect(view.status, LoadStatus.ready);
      expect(view.achievements, [first]);
      expect(view.error, startsWith('Steam is limiting requests right now.'));
    });

    test('with nothing stored, a Steam failure is "failed", worded for whose it is', () async {
      repo.steamAchievementsError = const FunctionException(
        status: 403,
        details: {'code': 'STEAM_PROFILE_PRIVATE'},
      );

      await store.loadGame('m1', 'none');
      await store.loadGame('u1', 'none');

      expect(store.gameOf('m1', 'none').status, LoadStatus.failed);
      expect(store.gameOf('m1', 'none').error, startsWith('Their Steam game details are private'));
      expect(store.gameOf('u1', 'none').error, startsWith('Your Steam game details are private'));
    });

    test('a failure is "failed" for that game only', () async {
      await store.loadGame('m1', 'g1');
      repo.failAchievementReads = true;
      await store.loadGame('m1', 'g2');

      expect(store.gameOf('m1', 'g2').status, LoadStatus.failed);
      expect(store.gameOf('m1', 'g1').status, LoadStatus.ready);
    });
  });

  test('after a Steam sync, what is held of that member is read again', () async {
    await store.loadTotals('m1');
    await store.loadSummary('m1');
    await store.loadGame('m1', 'g1');
    await store.loadSummary('m2');
    repo.memberReads.clear();

    store.refreshAfterSync('m1');
    await pumpEventQueue();

    expect(repo.memberReads, unorderedEquals(['achievement-totals:m1', 'achievements:m1']));
    // Still on screen meanwhile, and the game's list is asked for again when opened.
    expect(store.summaryOf('m1').status, LoadStatus.ready);
    expect(store.gameOf('m1', 'g1').status, LoadStatus.idle);
  });

    test('everything is dropped when the account changes', () async {
    await store.loadTotals('m1');
    await store.loadSummary('m1');
    await store.loadGame('m1', 'g1');

    authService.emit(testUser('u2'));
    await pumpEventQueue();

    expect(store.totalsOf('m1').status, LoadStatus.idle);
    expect(store.summaryOf('m1').status, LoadStatus.idle);
    expect(store.gameOf('m1', 'g1').status, LoadStatus.idle);
  });
}
