import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:checkpoint/services/connection_failure.dart';

/// What to tell the user when deleting the account failed. Keyed off the `code`
/// the `delete-account` Edge Function sends (see `ErrorCode` there), never off its
/// error text, so the wording can change without a deploy. Safe to show.
///
/// Every failure leaves the account usable and the deletion safe to try again:
/// the function removes the sign-in last.
String deleteAccountMessage(Object error) {
  if (error is FunctionException) {
    final body = error.details;
    final code = body is Map ? body['code'] : null;
    if (code == 'UNAUTHENTICATED' || error.status == 401) {
      return 'Your session expired. Sign in again, then delete your account.';
    }
    if (code == 'MFA_REQUIRED') {
      return 'Sign in again with your two-factor code, then delete your account.';
    }
    // Status 0: the request never got an answer (FunctionsFetchException).
    if (error.status == 0) return _unreachable;
    if (error.status == 408 || error.status == 429 || error.status >= 500) {
      return 'The server is busy right now. Your account was not deleted. Try again in a moment.';
    }
    return _generic;
  }
  if (error is StateError) return 'Sign in to delete your account.';
  if (isConnectionFailure(error)) return _unreachable;
  return _generic;
}

const _unreachable = 'Could not reach the server. Check your connection and try again.';
const _generic = 'Could not delete your account. Please try again.';
