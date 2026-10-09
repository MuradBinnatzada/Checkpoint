import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:checkpoint/data/db_schema.dart';

/// Google OAuth client IDs.
///
/// The WEB client ID (the same one configured under Supabase Authentication >
/// Google) is required on every platform: it makes Google issue an ID token that
/// Supabase can verify. The iOS client ID is optional and only read on iOS:
///   flutter run --dart-define=GOOGLE_IOS_CLIENT_ID=yyy.apps.googleusercontent.com
const _googleWebClientId = '920307411259-urq6579e0gukditu4839u7djhs3j3p5e.apps.googleusercontent.com';
const _googleIosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');

/// All network/auth calls live here so screens and the store stay SDK-light.
///
/// Requires `google_sign_in: ^6.x` in pubspec.yaml.
class AuthService {
  AuthService(this._client);
  final SupabaseClient _client;

  GoTrueClient get _auth => _client.auth;

  /// Google's native account picker only exists on Android and iOS.
  bool get _usesNativeGoogle =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  /// Built on first use and reused, so sign-in and sign-out talk to the same native client.
  late final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: _googleIosClientId.isEmpty ? null : _googleIosClientId,
    serverClientId: _googleWebClientId,
    scopes: ['email', 'profile'],
  );

  /// The user from the session Supabase restored from disk (null = signed out).
  User? get currentUser => _auth.currentUser;

  /// Emits on sign-in, sign-out, token refresh and profile updates.
  Stream<AuthState> get changes => _auth.onAuthStateChange;

  Future<void> signInWithEmail(String email, String password) =>
      _auth.signInWithPassword(email: email.trim(), password: password);

  /// Returns true when a session exists immediately, false when the project
  /// requires the user to confirm their email address first.
  Future<bool> signUpWithEmail(String email, String password, {String? displayName}) async {
    final name = displayName?.trim() ?? '';
    final res = await _auth.signUp(
      email: email.trim(),
      password: password,
      data: {if (name.isNotEmpty) 'full_name': name},
    );
    return res.session != null;
  }

  Future<void> signInWithGoogle() async {
    if (!_usesNativeGoogle) {
      // Web / desktop have no native account picker: use Supabase's browser flow.
      await _auth.signInWithOAuth(OAuthProvider.google);
      return;
    }
    if (_googleWebClientId.isEmpty) {
      throw AuthException("Google sign-in isn't configured. Set _googleWebClientId in services/auth_service.dart.");
    }

    // Native flow: Google account picker → ID token → Supabase session.
    final account = await _googleSignIn.signIn();
    if (account == null) throw AuthException('Google sign-in was cancelled.');

    final googleAuth = await account.authentication;
    final idToken = googleAuth.idToken;
    if (idToken == null) throw AuthException('Google did not return an ID token.');

    await _auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: googleAuth.accessToken,
    );
  }

  Future<void> signOut() async {
    await _auth.signOut();
    if (_usesNativeGoogle) {
      try {
        await _googleSignIn.signOut();
      } catch (e) {
        debugPrint('Google sign-out failed: $e');
      }
    }
  }

  /// The signed-in user's row in `profiles` (null when it doesn't exist yet).
  Future<Map<String, dynamic>?> fetchProfile(String userId) async {
    return await _client.from(Db.profiles).select().eq(Db.id, userId).maybeSingle();
  }

  /// Creates the `profiles` row on first login. Existing rows are left unchanged.
  Future<Map<String, dynamic>?> ensureProfile(User user) async {
    final existing = await fetchProfile(user.id);
    if (existing != null) return existing;

    await _client.from(Db.profiles).upsert({
      Db.id: user.id,
      Db.email: user.email,
      Db.displayName: _displayNameFor(user),
    });
    return fetchProfile(user.id);
  }

  static String _displayNameFor(User user) {
    final meta = user.userMetadata ?? const <String, dynamic>{};
    final local = (user.email ?? '').split('@').first.trim();
    for (final value in [meta['full_name'], meta['name'], meta['display_name'], local]) {
      final text = value?.toString().trim();
      if (text != null && text.isNotEmpty) return text;
    }
    return 'Player';
  }

  /// Text for the UI. Raw exceptions never reach the screen.
  static String messageFor(Object e) {
    if (e is AuthException) return e.message;
    if (e is PlatformException) {
      return switch (e.code) {
        GoogleSignIn.kSignInCanceledError => 'Google sign-in was cancelled.',
        _ => 'Google sign-in failed (${e.code}). Check the OAuth client IDs in Google Cloud.',
      };
    }
    return 'Something went wrong. Please try again.';
  }
}
