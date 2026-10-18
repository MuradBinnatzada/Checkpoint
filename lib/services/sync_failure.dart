import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:checkpoint/services/connection_failure.dart';

/// What went wrong with a Steam sync, as named by the Edge Functions in the
/// `code` field of a failed response (and in `delayed.code` of a sync that only
/// got part of the way). Keep the wire names in sync with `ErrorCode` in
/// supabase/functions/sync-steam, sync-achievements and igdb-handler.
///
/// [delayed] marks the codes that fix themselves: the sync is worth trying
/// again shortly, and nothing the user does will change the outcome. The others
/// need the user (a private Steam profile) or the app's owner (missing secrets).
enum SyncFailureCode {
  // Retry later.
  steamRateLimited('STEAM_RATE_LIMITED', 'Steam is limiting requests right now.', delayed: true),
  steamUnavailable('STEAM_UNAVAILABLE', 'Steam is not responding right now.', delayed: true),
  igdbRateLimited('IGDB_RATE_LIMITED', 'The game database is busy right now.', delayed: true),
  igdbUnavailable('IGDB_UNAVAILABLE', 'The game database is not responding right now.', delayed: true),
  syncPartial('SYNC_PARTIAL', 'Some games will be matched on your next sync.', delayed: true),
  serverBusy('SERVER_BUSY', 'The sync service is busy right now.', delayed: true),
  offline('OFFLINE', 'Could not reach the server. Check your connection.', delayed: true),

  // Needs the user.
  unauthenticated('UNAUTHENTICATED', 'Your session expired. Sign in again to sync.'),
  noSteamId('NO_STEAM_ID', 'Connect your Steam account first to sync your library.'),
  steamProfilePrivate(
    'STEAM_PROFILE_PRIVATE',
    'Your Steam game details are private. Set "Game details" to Public in your '
        'Steam privacy settings, then try again.',
  ),
  gameNotLinked('GAME_NOT_LINKED', 'This game is not linked to a Steam app yet. Sync your Steam library first.'),
  notInLibrary('NOT_IN_LIBRARY', 'That game is not in your library.'),
  achievementsHidden('ACHIEVEMENTS_HIDDEN', 'This member keeps their achievements private.'),

  // Needs the owner, or a bug.
  notConfigured('NOT_CONFIGURED', 'Syncing is not available right now.'),
  steamError('STEAM_ERROR', 'Steam returned an unexpected response.'),
  igdbError('IGDB_ERROR', 'The game database returned an unexpected response.'),
  badRequest('BAD_REQUEST', 'The sync request was not valid.'),
  internal('INTERNAL', 'Something went wrong on our side.'),
  unknown('UNKNOWN', 'Could not sync your Steam library.');

  const SyncFailureCode(this.wire, this.message, {this.delayed = false});

  /// The string the Edge Functions send.
  final String wire;

  /// What to tell the user. Written here rather than taken from the server's
  /// `error` text, so it can be reworded (and later translated) without a deploy.
  final String message;

  /// Trying again later is expected to work; see the enum comment.
  final bool delayed;

  /// The code for [wire], or null when it is not one this app knows.
  static SyncFailureCode? fromWire(Object? wire) {
    for (final code in values) {
      if (code.wire == wire) return code;
    }
    return null;
  }
}

/// A Steam sync that did not complete, or completed only in part.
class SyncFailure {
  const SyncFailure(this.code, {this.retryAfter});

  final SyncFailureCode code;

  /// How long the server asked us to wait before trying again, when it said.
  final Duration? retryAfter;

  /// The sync is "delayed": try again later, nothing is wrong with the account.
  bool get isDelayed => code.delayed;

  /// Safe to show to the user.
  String get message {
    final wait = retryAfter;
    if (!isDelayed || wait == null || code == SyncFailureCode.offline) {
      return code.message;
    }
    return '${code.message} Try again ${_in(wait)}.';
  }

  /// Sorts any error thrown while calling a sync Edge Function.
  ///
  /// The functions answer a failure with `{ error, code, retry_after? }`; a
  /// reply without a code (the gateway timing out, an old deploy) is classified
  /// by its HTTP status instead.
  factory SyncFailure.from(Object error) {
    if (error is FunctionsFetchException || (error is FunctionException && error.status == 0)) {
      return const SyncFailure(SyncFailureCode.offline);
    }
    if (error is FunctionException) {
      final body = error.details;
      final fromBody = body is Map ? _fromBody(body) : null;
      if (fromBody != null) return fromBody;
      final status = error.status;
      if (status == 408 || status == 429 || status >= 500) {
        return const SyncFailure(SyncFailureCode.serverBusy);
      }
      return const SyncFailure(SyncFailureCode.unknown);
    }
    if (isConnectionFailure(error)) return const SyncFailure(SyncFailureCode.offline);
    return const SyncFailure(SyncFailureCode.unknown);
  }

  /// The `delayed` part of a successful `sync-steam` reply: what the response
  /// says IGDB could not do this time. Null when the sync was complete (or the
  /// reply has no such part, as from a function deployed before it existed).
  static SyncFailure? fromDelayed(Object? data) {
    final delayed = data is Map ? data['delayed'] : null;
    if (delayed is! Map) return null;
    return _fromBody(delayed) ?? const SyncFailure(SyncFailureCode.syncPartial);
  }

  static SyncFailure? _fromBody(Map<dynamic, dynamic> body) {
    final code = SyncFailureCode.fromWire(body['code']);
    if (code == null) return null;
    final seconds = body['retry_after'];
    return SyncFailure(
      code,
      retryAfter: seconds is num && seconds > 0
          ? Duration(seconds: seconds.ceil())
          : null,
    );
  }

  /// "in a minute", "in 5 minutes", "in about an hour".
  static String _in(Duration wait) {
    if (wait.inSeconds < 90) return 'in a minute';
    if (wait.inMinutes < 60) return 'in ${wait.inMinutes} minutes';
    return 'in about an hour';
  }

  @override
  String toString() => 'SyncFailure(${code.wire}, retryAfter: $retryAfter)';
}
