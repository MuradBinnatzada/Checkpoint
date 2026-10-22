import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:checkpoint/l10n/l10n.dart';
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
      return L10n.current.deleteAccountSessionExpired;
    }
    if (code == 'MFA_REQUIRED') {
      return L10n.current.deleteAccountMfaRequired;
    }
    // Status 0: the request never got an answer (FunctionsFetchException).
    if (error.status == 0) return _unreachable;
    if (error.status == 408 || error.status == 429 || error.status >= 500) {
      return L10n.current.deleteAccountServerBusy;
    }
    return _generic;
  }
  if (error is StateError) return L10n.current.deleteAccountSignIn;
  if (isConnectionFailure(error)) return _unreachable;
  return _generic;
}

String get _unreachable => L10n.current.serverUnreachable;
String get _generic => L10n.current.deleteAccountFailed;
