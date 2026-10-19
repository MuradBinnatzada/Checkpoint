import 'package:supabase_flutter/supabase_flutter.dart';

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
      return 'Your session expired. Sign in again, then make new backup codes.';
    }
    if (code == 'MFA_REQUIRED') {
      return 'Sign in again with the code from your authenticator app, then make new backup codes.';
    }
    if (code == 'TWO_FACTOR_OFF') {
      return 'Turn on two-factor authentication first.';
    }
    if (code == 'RATE_LIMITED' || error.status == 429) {
      return 'You made new backup codes too many times. ${_tryAgainIn(error)}';
    }
    // Status 0: the request never got an answer (FunctionsFetchException).
    if (error.status == 0) return _unreachable;
    if (error.status == 408 || error.status >= 500) {
      return 'The server is busy right now. Try again in a moment.';
    }
    return _couldNotMake;
  }
  if (error is StateError) return 'Sign in to make backup codes.';
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
      return "That backup code didn't work. Check it, or try another one: "
          'each code works only once.';
    }
    if (code == 'UNAUTHENTICATED' || error.status == 401) return _signInAgain;
    if (code == 'RATE_LIMITED' || error.status == 429) {
      return 'Too many tries. ${_tryAgainIn(error)}';
    }
    if (error.status == 0) return _unreachable;
    if (error.status == 408 || error.status >= 500) {
      return 'The server is busy right now. Try again in a moment.';
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
  if (seconds is! num || seconds <= 0) return 'Try again later.';
  final minutes = (seconds / 60).ceil();
  return minutes == 1
      ? 'Try again in a minute.'
      : 'Try again in $minutes minutes.';
}

const _unreachable =
    'Could not reach the server. Check your connection and try again.';
const _signInAgain = 'Your sign-in expired. Sign out and sign in again.';
const _couldNotMake = 'Could not make backup codes. Please try again.';
const _couldNotCheck = 'Could not check that backup code. Please try again.';
