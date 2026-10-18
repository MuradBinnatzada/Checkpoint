import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:checkpoint/models/game_details.dart';
import 'package:checkpoint/state/catalog_backfill.dart';

import 'support/fakes.dart';

void main() {
  late FakeRepository repo;
  late FakeBackfillApi api;
  late List<List<GameDetails>> applied;
  late List<Duration> waited;

  /// Holds the next wait until completed, when set.
  Completer<void>? waitGate;

  setUp(() {
    debugPrint = (String? message, {int? wrapWidth}) {};
    repo = FakeRepository();
    api = FakeBackfillApi();
    applied = [];
    waited = [];
    waitGate = null;
  });

  tearDown(() => debugPrint = debugPrintThrottled);

  CatalogBackfill backfill({int batchSize = 2, int maxWaits = 5}) =>
      CatalogBackfill(
        repository: repo,
        apiService: api,
        onUpdates: applied.add,
        batchSize: batchSize,
        pause: const Duration(seconds: 2),
        maxWaits: maxWaits,
        wait: (delay) async {
          waited.add(delay);
          await waitGate?.future;
        },
      );

  List<int> idsOf(List<GameDetails> games) => [for (final g in games) g.igdbId];

  test('sends the games still to do in small batches, a pause apart, and hands each answer on', () async {
    repo.unsyncedIgdbIds = [1, 2, 3, 4, 5];
    final runner = backfill()..start('u1');
    expect(runner.isRunning, isTrue);
    await pumpEventQueue();

    expect(api.calls, [
      [1, 2],
      [3, 4],
      [5],
    ]);
    expect(
      [for (final batch in applied) idsOf(batch)],
      [
        [1, 2],
        [3, 4],
        [5],
      ],
    );
    expect(applied.first.first.platforms, FakeBackfillApi.backfilledPlatforms);
    // A pause between two batches, none after the last.
    expect(waited, [const Duration(seconds: 2), const Duration(seconds: 2)]);
    expect(runner.isRunning, isFalse);
  });

  test('asks nothing of IGDB when every game is filled in', () async {
    backfill().start('u1');
    await pumpEventQueue();

    expect(repo.unsyncedReads, 1);
    expect(api.calls, isEmpty);
    expect(applied, isEmpty);
  });

  test('a batch the server filled in nothing for is not handed on', () async {
    repo.unsyncedIgdbIds = [1];
    api.answer = (ids) => const CatalogBackfillResult([]);
    backfill().start('u1');
    await pumpEventQueue();

    expect(api.calls, [
      [1],
    ]);
    expect(applied, isEmpty);
  });

  test('when IGDB is limiting requests it waits as long as told, then sends the same batch again', () async {
    repo.unsyncedIgdbIds = [1, 2, 3];
    var limited = true;
    api.answer = (ids) {
      if (ids.first == 3 && limited) {
        limited = false;
        return const CatalogBackfillResult.failed(
          retryAfter: Duration(seconds: 42),
        );
      }
      return CatalogBackfillResult([
        for (final id in ids) GameDetails(igdbId: id),
      ]);
    };
    backfill().start('u1');
    await pumpEventQueue();

    expect(api.calls, [
      [1, 2],
      [3],
      [3],
    ]);
    expect(waited, [const Duration(seconds: 2), const Duration(seconds: 42)]);
    expect(
      [for (final batch in applied) idsOf(batch)],
      [
        [1, 2],
        [3],
      ],
    );
  });

  test('gives up until the next load when the limit does not pass', () async {
    repo.unsyncedIgdbIds = [1, 2, 3];
    api.answer = (ids) =>
        const CatalogBackfillResult.failed(retryAfter: Duration(seconds: 5));
    final runner = backfill(maxWaits: 2)..start('u1');
    await pumpEventQueue();

    expect(api.calls, hasLength(3)); // the first try and two waits
    expect(waited, [const Duration(seconds: 5), const Duration(seconds: 5)]);
    expect(applied, isEmpty);
    expect(runner.isRunning, isFalse);
  });

  test('a very long retry_after is waited in one bounded go', () async {
    repo.unsyncedIgdbIds = [1];
    var calls = 0;
    api.answer = (ids) => calls++ == 0
        ? const CatalogBackfillResult.failed(retryAfter: Duration(hours: 6))
        : const CatalogBackfillResult([]);
    backfill().start('u1');
    await pumpEventQueue();

    expect(waited, [CatalogBackfill.maxRetryAfter]);
    expect(api.calls, hasLength(2));
  });

  test('stops at a failure that waiting does not fix', () async {
    repo.unsyncedIgdbIds = [1, 2, 3];
    api.answer = (ids) => const CatalogBackfillResult.failed();
    final runner = backfill()..start('u1');
    await pumpEventQueue();

    expect(api.calls, [
      [1, 2],
    ]);
    expect(waited, isEmpty);
    expect(runner.isRunning, isFalse);
  });

  test('stops when the games to do cannot be listed', () async {
    repo.unsyncedIgdbIds = [1];
    repo.offline = true;
    final runner = backfill()..start('u1');
    await pumpEventQueue();

    expect(api.calls, isEmpty);
    expect(runner.isRunning, isFalse);
  });

  test('stop drops the answer in flight and sends nothing more', () async {
    repo.unsyncedIgdbIds = [1, 2, 3];
    api.gate = Completer<void>();
    final runner = backfill()..start('u1');
    await pumpEventQueue();
    expect(api.calls, hasLength(1));

    runner.stop();
    api.gate!.complete();
    await pumpEventQueue();

    expect(applied, isEmpty);
    expect(api.calls, hasLength(1));
    expect(runner.isRunning, isFalse);
  });

  test('stop during a rate-limit wait sends nothing more', () async {
    repo.unsyncedIgdbIds = [1];
    api.answer = (ids) =>
        const CatalogBackfillResult.failed(retryAfter: Duration(seconds: 30));
    waitGate = Completer<void>();
    final runner = backfill()..start('u1');
    await pumpEventQueue();
    expect(waited, [const Duration(seconds: 30)]);

    runner.stop();
    waitGate!.complete();
    await pumpEventQueue();

    expect(api.calls, hasLength(1));
  });

  test('started again for the same user while running, it makes one more pass when done', () async {
    repo.unsyncedIgdbIds = [1];
    api.gate = Completer<void>();
    final runner = backfill()..start('u1');
    await pumpEventQueue();

    // A Steam sync imported another game meanwhile.
    repo.unsyncedIgdbIds = [2];
    runner
      ..start('u1')
      ..start('u1');
    api.gate!.complete();
    await pumpEventQueue();

    expect(repo.unsyncedReads, 2);
    expect(api.calls, [
      [1],
      [2],
    ]);
    expect(runner.isRunning, isFalse);
  });

  test('started for another user, the first run stops', () async {
    repo.unsyncedIgdbIds = [1, 2, 3];
    api.gate = Completer<void>();
    final runner = backfill()..start('u1');
    await pumpEventQueue();

    repo.unsyncedIgdbIds = [9];
    runner.start('u2');
    api.gate!.complete();
    await pumpEventQueue();

    // u1's batch in flight is dropped and its later ones never sent.
    expect(api.calls, [
      [1, 2],
      [9],
    ]);
    expect(
      [for (final batch in applied) idsOf(batch)],
      [
        [9],
      ],
    );
  });
}
