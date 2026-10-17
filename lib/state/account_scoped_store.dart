import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:checkpoint/state/auth_store.dart';

/// A store that holds what the app has fetched about other members for the
/// signed-in account, and drops all of it when another account signs in or the
/// user signs out: one person's cache must never be shown to the next.
///
/// Subclasses keep their data in memory only (a profile is a live question, like
/// a search), clear it in [resetForAccount], and guard each request:
///
/// ```dart
/// final epoch = this.epoch;
/// final result = await _repository.fetch(...);
/// if (isStale(epoch)) return; // the account changed while we waited
/// ```
abstract class AccountScopedStore extends ChangeNotifier {
  AccountScopedStore(this._auth);

  final AuthStore _auth;

  StreamSubscription<User?>? _subscription;
  String? _accountId;
  int _epoch = 0;
  bool _disposed = false;

  /// The signed-in account, or null.
  String? get accountId => _accountId;

  /// Changes whenever the account does. See [isStale].
  @protected
  int get epoch => _epoch;

  /// Whether the account changed since [epoch] was read.
  @protected
  bool isStale(int epoch) => epoch != _epoch;

  /// Starts following sign-ins and sign-outs. Call once, after
  /// [AuthStore.initialize].
  void initialize() {
    _accountId = _auth.user?.id;
    _subscription = _auth.userChanges.listen(_onUser);
  }

  // Token refreshes and profile updates re-announce the same account; those are
  // not a reason to forget anything.
  void _onUser(User? user) {
    if (user?.id == _accountId) return;
    _accountId = user?.id;
    _epoch++;
    resetForAccount();
    notifyListeners();
  }

  /// Forgets everything held for the previous account, including requests whose
  /// answers are still on their way (they see [isStale]).
  @protected
  void resetForAccount();

  /// Notifies, unless the store was disposed while a request was in flight.
  @protected
  void notifyIfAlive() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
