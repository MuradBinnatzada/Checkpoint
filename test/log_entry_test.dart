import 'package:flutter_test/flutter_test.dart';

import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/log_entry.dart';

import 'support/fakes.dart';

Map<String, dynamic> logJson([Map<String, dynamic> overrides = const {}]) => {
  'id': 'l1',
  'gameId': 'g1',
  'timestamp': '2026-02-03T04:05:06Z',
  'hours': 1.5,
  'platform': 'ps5',
  'note': 'boss fight',
  ...overrides,
};

void main() {
  group('LogEntry.fromJson', () {
    test('reads back what toJson wrote', () {
      final log = testLog('l1', 'g1');
      final read = LogEntry.fromJson(log.toJson());

      expect(read.id, 'l1');
      expect(read.gameId, 'g1');
      expect(read.timestamp.toUtc(), log.timestamp.toUtc());
      expect(read.hours, log.hours);
      expect(read.platform, log.platform);
      expect(read.note, log.note);
    });

    test('a missing note is an empty one', () {
      expect(LogEntry.fromJson(logJson({'note': null})).note, '');
      expect(LogEntry.fromJson(logJson()..remove('note')).note, '');
    });

    test('a platform it does not know is PC', () {
      expect(
        LogEntry.fromJson(logJson({'platform': 'atari2600'})).platform,
        GamePlatform.pc,
      );
      expect(
        LogEntry.fromJson(logJson({'platform': null})).platform,
        GamePlatform.pc,
      );
    });

    test('whole hours are fine', () {
      expect(LogEntry.fromJson(logJson({'hours': 2})).hours, 2.0);
    });

    test('the emulator keeps its stored name', () {
      final log = LogEntry.fromJson(logJson({'platform': 'retro'}));

      expect(log.platform, GamePlatform.emulator);
      expect(log.toJson()['platform'], 'retro');
    });

    test('a missing or unreadable required field throws, so the offline cache drops the entry', () {
      expect(
        () => LogEntry.fromJson(logJson({'id': null})),
        throwsA(isA<TypeError>()),
      );
      expect(
        () => LogEntry.fromJson(logJson({'gameId': null})),
        throwsA(isA<TypeError>()),
      );
      expect(
        () => LogEntry.fromJson(logJson({'hours': null})),
        throwsA(isA<TypeError>()),
      );
      expect(
        () => LogEntry.fromJson(logJson({'timestamp': null})),
        throwsA(isA<TypeError>()),
      );
      expect(
        () => LogEntry.fromJson(logJson({'timestamp': 'yesterday'})),
        throwsFormatException,
      );
    });
  });
}
