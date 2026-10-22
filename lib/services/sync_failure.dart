import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:checkpoint/l10n/l10n.dart';
import 'package:checkpoint/services/connection_failure.dart';

/// What went wrong with a Steam sync, as named by the Edge Functions in the
/// `code` field of a failed response (and in `delayed.code` of a sync that only
/// got part of the way). Keep the wire names in sync with `ErrorCode` in
/// supabase/functions/sync-steam, sync-achievements, igdb-handler and
/// steam-link (which also sends them back as `steam_link` on its return
/// address).
///
/// [delayed] marks the codes that fix themselves: the sync is worth trying
/// again shortly, and nothing the user does will change the outcome. The others
/// need the user (a private Steam profile) or the app's owner (missing secrets).
enum SyncFailureCode {
  // Retry later.
  steamRateLimited('STEAM_RATE_LIMITED', delayed: true),
  steamUnavailable('STEAM_UNAVAILABLE', delayed: true),
  igdbRateLimited('IGDB_RATE_LIMITED', delayed: true),
  igdbUnavailable('IGDB_UNAVAILABLE', delayed: true),
  syncPartial('SYNC_PARTIAL', delayed: true),
  serverBusy('SERVER_BUSY', delayed: true),
  rateLimited('RATE_LIMITED', delayed: true),
  offline('OFFLINE', delayed: true),

  // Needs the user.
  unauthenticated('UNAUTHENTICATED'),
  mfaRequired('MFA_REQUIRED'),
  noSteamId('NO_STEAM_ID'),
  steamProfilePrivate('STEAM_PROFILE_PRIVATE'),
  gameNotLinked('GAME_NOT_LINKED'),
  notInLibrary('NOT_IN_LIBRARY'),
  achievementsHidden('ACHIEVEMENTS_HIDDEN'),
  steamLinkCancelled('STEAM_LINK_CANCELLED'),
  steamLinkExpired('STEAM_LINK_EXPIRED'),
  steamLinkInvalid('STEAM_LINK_INVALID'),

  // Needs the owner, or a bug.
  notConfigured('NOT_CONFIGURED'),
  steamError('STEAM_ERROR'),
  igdbError('IGDB_ERROR'),
  badRequest('BAD_REQUEST'),
  internal('INTERNAL'),
  unknown('UNKNOWN');

  const SyncFailureCode(this.wire, {this.delayed = false});

  /// The string the Edge Functions send.
  final String wire;

  /// What to tell the user, in the app's language. Written here rather than
  /// taken from the server's `error` text, so it can be reworded and translated
  /// without a deploy.
  String get message {
    final l10n = L10n.current;
    return switch (this) {
      steamRateLimited => l10n.syncErrorSteamRateLimited,
      steamUnavailable => l10n.syncErrorSteamUnavailable,
      igdbRateLimited => l10n.syncErrorIgdbRateLimited,
      igdbUnavailable => l10n.syncErrorIgdbUnavailable,
      syncPartial => l10n.syncErrorSyncPartial,
      serverBusy => l10n.syncErrorServerBusy,
      rateLimited => l10n.syncErrorRateLimited,
      offline => l10n.syncErrorOffline,
      unauthenticated => l10n.syncErrorUnauthenticated,
      mfaRequired => l10n.syncErrorMfaRequired,
      noSteamId => l10n.syncErrorNoSteamId,
      steamProfilePrivate => l10n.syncErrorSteamProfilePrivate,
      gameNotLinked => l10n.syncErrorGameNotLinked,
      notInLibrary => l10n.syncErrorNotInLibrary,
      achievementsHidden => l10n.syncErrorAchievementsHidden,
      steamLinkCancelled => l10n.syncErrorSteamLinkCancelled,
      steamLinkExpired => l10n.syncErrorSteamLinkExpired,
      steamLinkInvalid => l10n.syncErrorSteamLinkInvalid,
      notConfigured => l10n.syncErrorNotConfigured,
      steamError => l10n.syncErrorSteamError,
      igdbError => l10n.syncErrorIgdbError,
      badRequest => l10n.syncErrorBadRequest,
      internal => l10n.syncErrorInternal,
      unknown => l10n.syncErrorUnknown,
    };
  }

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
    return '${code.message} ${_tryAgain(wait)}';
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

  /// "Try again in a minute.", "Try again in 5 minutes.", "Try again in about
  /// an hour."
  static String _tryAgain(Duration wait) {
    if (wait.inSeconds < 90) return L10n.current.tryAgainInAMinute;
    if (wait.inMinutes < 60) return L10n.current.tryAgainInMinutes(wait.inMinutes);
    return L10n.current.tryAgainInAnHour;
  }

  @override
  String toString() => 'SyncFailure(${code.wire}, retryAfter: $retryAfter)';
}
