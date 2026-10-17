import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:checkpoint/services/auth_service.dart';

/// Who is signed in. Owns the Supabase session and the sign-in / sign-out calls,
/// and nothing else: the stores that hold a user's data ([ProfileStore],
/// [LibraryStore], [SearchStore]) follow [userChanges] and load or drop their
/// data when the account changes.
class AuthStore extends ChangeNotifier {
  AuthStore(this._service);

  final AuthService _service;

  User? _user;
  StreamSubscription<AuthState>? _subscription;
  final StreamController<User?> _changes = StreamController<User?>.broadcast();

  /// The signed-in user, or `null` when signed out.
  User? get user => _user;
  bool get isLoggedIn => _user != null;

  /// Emits the current user (`null` = signed out) on every auth event: sign-in,
  /// sign-out, token refresh, profile update. Unlike [addListener], this includes
  /// events for the same account, which the data stores treat as "refresh your
  /// data" rather than "a different person is here" (they compare ids).
  Stream<User?> get userChanges => _changes.stream;

  /// Reads the session Supabase restored from disk and starts following changes.
  /// Call once, before the stores that listen to [userChanges] call theirs.
  void initialize() {
    _user = _service.currentUser;
    if (_user != null) notifyListeners();
    _subscription = _service.changes.listen((state) {
      final next = state.session?.user;
      final accountChanged = next?.id != _user?.id;
      _user = next;
      // Widgets watching this store care who is signed in, not about the hourly
      // token refresh, so they are told only when the account changes.
      if (accountChanged) notifyListeners();
      _changes.add(next);
    });
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

  Future<void> logOut() => _service.signOut();

  String messageFor(Object e) => AuthService.messageFor(e);
}
