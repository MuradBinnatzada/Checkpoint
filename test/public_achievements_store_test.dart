import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    expect(store.summaryOf('m1').status, LoadStatus.idle);
    expect(store.gameOf('m1', 'g1').status, LoadStatus.idle);
    expect(repo.memberReads, isEmpty);
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

    test('nothing stored for the game reads as an empty list', () async {
      await store.loadGame('m1', 'other');

      final view = store.gameOf('m1', 'other');
      expect(view.status, LoadStatus.ready);
      expect(view.achievements, isEmpty);
    });

    test('a failure is "failed" for that game only', () async {
      await store.loadGame('m1', 'g1');
      repo.failAchievementReads = true;
      await store.loadGame('m1', 'g2');

      expect(store.gameOf('m1', 'g2').status, LoadStatus.failed);
      expect(store.gameOf('m1', 'g1').status, LoadStatus.ready);
    });
  });

  test('everything is dropped when the account changes', () async {
    await store.loadSummary('m1');
    await store.loadGame('m1', 'g1');

    authService.emit(testUser('u2'));
    await pumpEventQueue();

    expect(store.summaryOf('m1').status, LoadStatus.idle);
    expect(store.gameOf('m1', 'g1').status, LoadStatus.idle);
  });
}
