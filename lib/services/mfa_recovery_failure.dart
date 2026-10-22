import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:checkpoint/l10n/l10n.dart';
import 'package:checkpoint/services/connection_failure.dart';

// What to tell the user when making or using two-factor backup codes failed.
// Keyed off the `code` the `mfa-recovery` Edge Function sends (see `ErrorCode`
// there), never off its error text, so the wording can change without a
// deploy. Safe to show.

/// The `code` of a failed `mfa-recovery` call, or null.
String? mfaRecoveryErrorCode(Object error) {
  if (error is! FunctionException) return null;
  final body = error.details;
  final code = body is Map ? body['code'] : null;
  return code is String ? code : null;
}

/// Making new backup codes: right after two-factor is turned on, or Settings >
/// Security > New backup codes. The codes the account had keep working when it
/// fails.
String backupCodesMessage(Object error) {
  if (error is FunctionException) {
    final code = mfaRecoveryErrorCode(error);
    if (code == 'UNAUTHENTICATED' || error.status == 401) {
      return L10n.current.backupCodesSessionExpired;
    }
    if (code == 'MFA_REQUIRED') {
      return L10n.current.backupCodesMfaRequired;
    }
    if (code == 'TWO_FACTOR_OFF') {
      return L10n.current.backupCodesTwoFactorOff;
    }
    if (code == 'RATE_LIMITED' || error.status == 429) {
      return '${L10n.current.backupCodesTooMany} ${_tryAgainIn(error)}';
    }
    // Status 0: the request never got an answer (FunctionsFetchException).
    if (error.status == 0) return _unreachable;
    if (error.status == 408 || error.status >= 500) {
      return L10n.current.serverBusy;
    }
    return _couldNotMake;
  }
  if (error is StateError) return L10n.current.backupCodesSignIn;
  if (error is! FormatException && isConnectionFailure(error)) {
    return _unreachable;
  }
  return _couldNotMake;
}

/// Using a backup code at the two-factor prompt. A code that was refused is
/// still unused.
String backupCodeMessage(Object error) {
  if (error is FunctionException) {
    final code = mfaRecoveryErrorCode(error);
    if (code == 'INVALID_CODE') {
      return L10n.current.backupCodeInvalid;
    }
    if (code == 'UNAUTHENTICATED' || error.status == 401) return _signInAgain;
    if (code == 'RATE_LIMITED' || error.status == 429) {
      return '${L10n.current.tooManyTries} ${_tryAgainIn(error)}';
    }
    if (error.status == 0) return _unreachable;
    if (error.status == 408 || error.status >= 500) {
      return L10n.current.serverBusy;
    }
    return _couldNotCheck;
  }
  if (error is! FormatException && isConnectionFailure(error)) {
    return _unreachable;
  }
  // The code was right, but the session could not be refreshed with it.
  if (error is AuthException) return _signInAgain;
  return _couldNotCheck;
}

/// "Try again in N minutes." from the `retry_after` seconds the function sends.
String _tryAgainIn(FunctionException error) {
  final body = error.details;
  final seconds = body is Map ? body['retry_after'] : null;
  if (seconds is! num || seconds <= 0) return L10n.current.tryAgainLater;
  final minutes = (seconds / 60).ceil();
  return minutes == 1
      ? L10n.current.tryAgainInAMinute
      : L10n.current.tryAgainInMinutes(minutes);
}

String get _unreachable => L10n.current.serverUnreachable;
String get _signInAgain => L10n.current.signInExpired;
String get _couldNotMake => L10n.current.backupCodesMakeFailed;
String get _couldNotCheck => L10n.current.backupCodeCheckFailed;
