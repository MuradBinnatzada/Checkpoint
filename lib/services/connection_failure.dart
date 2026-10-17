import 'package:supabase_flutter/supabase_flutter.dart';

/// Thrown instead of calling the server while there is no live session: the
/// server would refuse anything sent now, so the edit is queued like any offline
/// one (see `AuthStore.requireSession`).
class SessionPending implements Exception {
  const SessionPending();
}

/// Whether [e] means "the server could not be reached or is struggling" (the
/// edit is worth retrying) rather than "the server refused it" (it is not).
/// The stores that queue edits for later share this, so they sort failures the
/// same way.
bool isConnectionFailure(Object e) {
  if (e is SessionPending || e is AuthRetryableFetchException) return true;
  if (e is PostgrestException) {
    // An HTTP status (three digits) rather than a Postgres error code (five
    // characters, which can also be all digits): 5xx and "try again" statuses.
    final code = e.code ?? '';
    final status = code.length == 3 ? int.tryParse(code) : null;
    return status != null && (status >= 500 || status == 408 || status == 429);
  }
  return e is! AuthException &&
      e is! StorageException &&
      e is! FunctionException;
}
