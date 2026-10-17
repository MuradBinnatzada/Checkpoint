import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:checkpoint/services/sync_failure.dart';

void main() {
  group('SyncFailure.from', () {
    test('reads the code and the wait from the function\'s reply', () {
      final failure = SyncFailure.from(
        const FunctionException(
          status: 429,
          details: {'error': 'Steam is limiting requests', 'code': 'STEAM_RATE_LIMITED', 'retry_after': 300},
        ),
      );

      expect(failure.code, SyncFailureCode.steamRateLimited);
      expect(failure.isDelayed, isTrue);
      expect(failure.retryAfter, const Duration(minutes: 5));
      expect(failure.message, 'Steam is limiting requests right now. Try again in 5 minutes.');
    });

    test('every code the functions send maps to a code of its own', () {
      // Keep this list in step with `ErrorCode` in supabase/functions/*/index.ts.
      const sent = [
        'UNAUTHENTICATED', 'NO_STEAM_ID', 'STEAM_PROFILE_PRIVATE', 'STEAM_RATE_LIMITED',
        'STEAM_UNAVAILABLE', 'STEAM_ERROR', 'IGDB_RATE_LIMITED', 'IGDB_UNAVAILABLE',
        'IGDB_ERROR', 'NOT_CONFIGURED', 'INTERNAL', 'GAME_NOT_LINKED', 'NOT_IN_LIBRARY',
        'BAD_REQUEST', 'SYNC_PARTIAL',
      ];
      for (final wire in sent) {
        expect(SyncFailureCode.fromWire(wire), isNotNull, reason: wire);
      }
      expect(SyncFailureCode.values.map((c) => c.wire).toSet(), hasLength(SyncFailureCode.values.length));
    });

    test('only the errors that fix themselves count as delayed', () {
      bool delayed(String code) => SyncFailure.from(FunctionException(status: 500, details: {'code': code})).isDelayed;

      for (final code in ['STEAM_RATE_LIMITED', 'STEAM_UNAVAILABLE', 'IGDB_RATE_LIMITED', 'IGDB_UNAVAILABLE']) {
        expect(delayed(code), isTrue, reason: code);
      }
      for (final code in ['STEAM_PROFILE_PRIVATE', 'NO_STEAM_ID', 'UNAUTHENTICATED', 'NOT_CONFIGURED', 'INTERNAL']) {
        expect(delayed(code), isFalse, reason: code);
      }
    });

    test('a private profile tells the user what to change, and offers no retry time', () {
      final failure = SyncFailure.from(
        const FunctionException(status: 403, details: {'code': 'STEAM_PROFILE_PRIVATE', 'error': 'private'}),
      );

      expect(failure.isDelayed, isFalse);
      expect(failure.message, contains('Game details'));
      expect(failure.message, isNot(contains('Try again in')));
    });

    test('a reply without a code is sorted by its HTTP status', () {
      for (final status in [408, 429, 500, 502, 503, 504, 546]) {
        final failure = SyncFailure.from(FunctionException(status: status, details: 'upstream timeout'));
        expect(failure.code, SyncFailureCode.serverBusy, reason: '$status');
        expect(failure.isDelayed, isTrue);
      }
      expect(
        SyncFailure.from(const FunctionException(status: 400, details: {'error': 'old text'})).code,
        SyncFailureCode.unknown,
      );
    });

    test('an unknown code is not trusted', () {
      final failure = SyncFailure.from(
        const FunctionException(status: 418, details: {'code': 'TEAPOT', 'retry_after': 10}),
      );

      expect(failure.code, SyncFailureCode.unknown);
      expect(failure.isDelayed, isFalse);
    });

    test('a request that never reached the server is "offline", whatever the exception', () {
      expect(SyncFailure.from(const FunctionsFetchException(details: 'socket closed')).code, SyncFailureCode.offline);
      expect(SyncFailure.from(Exception('network down')).code, SyncFailureCode.offline);
      expect(SyncFailure.from(AuthRetryableFetchException(message: 'x')).code, SyncFailureCode.offline);
      expect(SyncFailure.from(const FunctionsFetchException(details: 'x')).isDelayed, isTrue);
    });

    test('a refused sign-in is not "offline"', () {
      final failure = SyncFailure.from(const AuthException('bad token'));

      expect(failure.code, SyncFailureCode.unknown);
      expect(failure.isDelayed, isFalse);
    });

    test('formats the wait, ignoring nonsense', () {
      String message(Object? retryAfter) => SyncFailure.from(
        FunctionException(status: 503, details: {'code': 'IGDB_UNAVAILABLE', 'retry_after': retryAfter}),
      ).message;

      expect(message(30), endsWith('Try again in a minute.'));
      expect(message(180), endsWith('Try again in 3 minutes.'));
      expect(message(3600), endsWith('Try again in about an hour.'));
      expect(message(0), 'The game database is not responding right now.');
      expect(message(-5), 'The game database is not responding right now.');
      expect(message('soon'), 'The game database is not responding right now.');
      expect(message(null), 'The game database is not responding right now.');
    });
  });

  group('SyncFailure.fromDelayed', () {
    test('a complete sync has nothing delayed', () {
      expect(SyncFailure.fromDelayed({'success': true, 'delayed': null}), isNull);
    });

    test('a reply from a function that predates the field has nothing delayed', () {
      expect(SyncFailure.fromDelayed({'success': true, 'summary': {}}), isNull);
      expect(SyncFailure.fromDelayed(null), isNull);
      expect(SyncFailure.fromDelayed('ok'), isNull);
    });

    test('reads why IGDB left games for later', () {
      final failure = SyncFailure.fromDelayed({
        'success': true,
        'delayed': {'code': 'IGDB_RATE_LIMITED', 'message': 'busy', 'retry_after': 60, 'deferred': 12},
      })!;

      expect(failure.code, SyncFailureCode.igdbRateLimited);
      expect(failure.isDelayed, isTrue);
      expect(failure.retryAfter, const Duration(seconds: 60));
    });

    test('games left over without an IGDB error are still a delayed sync', () {
      final failure = SyncFailure.fromDelayed({
        'delayed': {'code': 'SYNC_PARTIAL', 'retry_after': null, 'deferred': 40},
      })!;

      expect(failure.code, SyncFailureCode.syncPartial);
      expect(failure.isDelayed, isTrue);
      expect(failure.message, 'Some games will be matched on your next sync.');
    });

    test('a code from a newer function still reads as a delayed sync', () {
      final failure = SyncFailure.fromDelayed({
        'delayed': {'code': 'SOMETHING_NEW', 'deferred': 3},
      })!;

      expect(failure.code, SyncFailureCode.syncPartial);
    });
  });
}
