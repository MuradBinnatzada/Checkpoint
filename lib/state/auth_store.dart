import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:checkpoint/services/auth_service.dart';
import 'package:checkpoint/services/connection_failure.dart';

/// Who is signed in. Owns the Supabase session and the sign-in / sign-out calls,
/// and nothing else: the stores that hold a user's data ([ProfileStore],
/// [LibraryStore], [SearchStore]) follow [userChanges] and load or drop their
/// data when the account changes.
class AuthStore extends ChangeNotifier {
  AuthStore(this._service);

  final AuthService _service;

  User? _user;
  bool _sessionPending = false;
  StreamSubscription<AuthState>? _subscription;
  final StreamController<User?> _changes = StreamController<User?>.broadcast();

  /// The signed-in user, or `null` when signed out. While [isSessionPending] it
  /// is a stand-in that has only the account's id.
  User? get user => _user;
  bool get isLoggedIn => _user != null;

  /// The device has a saved session for this account, but it could not be
  /// refreshed (the app started offline with an expired access token), so there
  /// is no live session yet. The data stores show what is saved on the device and
  /// queue edits instead of calling the server; [restoreSession] ends the state.
  bool get isSessionPending => _sessionPending;

  /// Emits the current user (`null` = signed out) on every auth event: sign-in,
  /// sign-out, token refresh, profile update. Unlike [addListener], this includes
  /// events for the same account, which the data stores treat as "refresh your
  /// data" rather than "a different person is here" (they compare ids).
  Stream<User?> get userChanges => _changes.stream;

  /// Reads the session Supabase restored from disk and starts following changes.
  /// Call once, before the stores that listen to [userChanges] call theirs.
  Future<void> initialize() async {
    _user = _service.currentUser;
    if (_user != null) notifyListeners();
    _subscription = _service.changes.listen((state) {
      final next = state.session?.user;
      final accountChanged = next?.id != _user?.id;
      _sessionPending = false;
      _user = next;
      // Widgets watching this store care who is signed in, not about the hourly
      // token refresh, so they are told only when the account changes.
      if (accountChanged) notifyListeners();
      _changes.add(next);
    }, onError: (Object e) => debugPrint('Auth stream error: $e'));

    if (_user == null) {
      final savedId = await _service.persistedUserId();
      if (savedId != null && _user == null) {
        _user = User(
          id: savedId,
          appMetadata: const {},
          userMetadata: const {},
          aud: 'authenticated',
          createdAt: '',
        );
        _sessionPending = true;
        notifyListeners();
      }
    }
  }

  /// Tries to turn a [isSessionPending] session into a live one. Returns whether
  /// there is a live session now; on success [userChanges] announces it.
  Future<bool> restoreSession() async {
    if (!_sessionPending) return true;
    return _service.restoreSession();
  }

  /// Throws [SessionPending] while there is no live session, for the stores to
  /// call before a request: the server would refuse it, so the edit is queued
  /// like any other made while the server can't be reached.
  void requireSession() {
    if (_sessionPending) throw const SessionPending();
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    unawaited(_changes.close());
    super.dispose();
  }

  Future<void> signInWithEmail(String email, String password) =>
      _service.signInWithEmail(email, password);

  Future<bool> signUpWithEmail(
    String email,
    String password, {
    String? displayName,
  }) => _service.signUpWithEmail(email, password, displayName: displayName);

  Future<void> signInWithGoogle() => _service.signInWithGoogle();

  Future<void> logIn() => signInWithGoogle();

  Future<void> logOut() async {
    if (_sessionPending) {
      // No live session to end: just forget the saved one.
      await _service.discardPersistedSession();
      _sessionPending = false;
      _user = null;
      notifyListeners();
      _changes.add(null);
      return;
    }
    await _service.signOut();
  }

  String messageFor(Object e) => AuthService.messageFor(e);
}
