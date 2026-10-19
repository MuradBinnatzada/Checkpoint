import 'dart:async';
import 'dart:convert';
import 'dart:io' show ContentType, HttpServer, HttpStatus, InternetAddress, SocketException;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Google OAuth client IDs.
///
/// The WEB client ID (the same one configured under Supabase Authentication >
/// Google) is required on every platform: it makes Google issue an ID token that
/// Supabase can verify. The iOS client ID is optional and only read on iOS:
///   flutter run --dart-define=GOOGLE_IOS_CLIENT_ID=yyy.apps.googleusercontent.com
const _googleWebClientId = '920307411259-urq6579e0gukditu4839u7djhs3j3p5e.apps.googleusercontent.com';
const _googleIosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');

/// Desktop (Linux / Windows / macOS) sign-in returns to this localhost address.
/// It must be allowed in Supabase > Authentication > URL Configuration: that is
/// automatic while it equals the project's Site URL (the default is
/// http://localhost:3000). If you change the Site URL, change the port here too,
/// or add this address to the Redirect URLs list.
const _desktopRedirectPort = 3000;
const _desktopRedirectUrl = 'http://localhost:$_desktopRedirectPort';

/// All network/auth calls live here so screens and the store stay SDK-light.
///
/// Auth only: the `profiles` row is created and read by CheckpointRepository.
///
/// Requires `google_sign_in: ^6.x` in pubspec.yaml.
class AuthService {
  AuthService(this._client);
  final SupabaseClient _client;

  GoTrueClient get _auth => _client.auth;

  /// Google's native account picker only exists on Android and iOS.
  bool get _usesNativeGoogle =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  /// Desktop has no native picker and no URL scheme registered to catch the
  /// OAuth redirect, so it listens on localhost instead (see [_signInWithGoogleDesktop]).
  bool get _usesLoopbackRedirect =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS);

  /// The temporary localhost listener of an unfinished desktop sign-in, if any.
  HttpServer? _loopback;

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

  /// Where the links in Supabase's emails (confirm address, reset password)
  /// send the browser. Web returns to whichever host served the app, as Google
  /// sign-in does; elsewhere null leaves it to the project's Site URL.
  String? get _emailRedirectUrl => kIsWeb ? Uri.base.origin : null;

  Future<void> signInWithEmail(String email, String password) =>
      _auth.signInWithPassword(email: email.trim(), password: password);

  /// Returns true when a session exists immediately, false when the project
  /// requires the user to confirm their email address first. [displayName]
  /// becomes the new profile's name (see CheckpointRepository.ensureProfile).
  Future<bool> signUpWithEmail(String email, String password, {String? displayName}) async {
    final name = displayName?.trim() ?? '';
    final res = await _auth.signUp(
      email: email.trim(),
      password: password,
      data: {if (name.isNotEmpty) 'full_name': name},
      emailRedirectTo: _emailRedirectUrl,
    );
    // While email confirmation is required, Supabase answers a sign-up for an
    // address that already has an account as if it were new, so the request
    // sends nothing; only the user it returns has no identities.
    final identities = res.user?.identities;
    if (res.session == null && identities != null && identities.isEmpty) {
      throw const AuthException('User already registered', code: 'user_already_exists');
    }
    return res.session != null;
  }

  /// Emails a password reset link. Supabase answers the same whether or not an
  /// account uses [email], so this can't tell who has one.
  Future<void> sendPasswordReset(String email) =>
      _auth.resetPasswordForEmail(email.trim(), redirectTo: _emailRedirectUrl);

  Future<void> signInWithGoogle() async {
    if (_usesLoopbackRedirect) {
      await _signInWithGoogleDesktop();
      return;
    }
    if (!_usesNativeGoogle) {
      // Web has no native account picker: use Supabase's browser flow.
      // Return to whichever host served the app (localhost, Netlify, ...).
      await _auth.signInWithOAuth(OAuthProvider.google, redirectTo: Uri.base.origin);
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

  /// Opens Google sign-in in the system browser and catches the redirect on
  /// localhost: Supabase sends the browser back to [_desktopRedirectUrl] with a
  /// PKCE `code`, which is exchanged for a session here. The code is useless
  /// without the verifier the app kept, so another local program can't use it.
  Future<void> _signInWithGoogleDesktop() async {
    // An earlier attempt that was never finished still holds the port.
    await _loopback?.close(force: true);
    _loopback = null;

    final HttpServer server;
    try {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, _desktopRedirectPort);
    } on SocketException {
      throw AuthException(
        'Port $_desktopRedirectPort is already in use. Close whatever is using it and try again.',
      );
    }
    _loopback = server;

    final callback = Completer<Uri>();
    final subscription = server.listen((request) {
      final params = request.uri.queryParameters;
      final isCallback = params.containsKey('code') || params.containsKey('error');
      final response = request.response;
      if (isCallback) {
        response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.html
          ..write(_callbackPage(ok: !params.containsKey('error')));
      } else {
        response.statusCode = HttpStatus.notFound; // favicon.ico and friends
      }
      unawaited(response.close());
      if (isCallback && !callback.isCompleted) callback.complete(request.uri);
    });

    try {
      final opened = await _auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: _desktopRedirectUrl,
        authScreenLaunchMode: LaunchMode.externalApplication,
      );
      if (!opened) throw AuthException("Couldn't open your browser for Google sign-in.");

      final uri = await callback.future.timeout(
        const Duration(minutes: 3),
        onTimeout: () => throw AuthException('Google sign-in timed out. Please try again.'),
      );

      final error = uri.queryParameters['error_description'] ?? uri.queryParameters['error'];
      if (error != null) throw AuthException(error);
      final code = uri.queryParameters['code'];
      if (code == null) throw AuthException('Google did not return a sign-in code.');

      await _auth.exchangeCodeForSession(code);
    } finally {
      await subscription.cancel();
      await server.close(force: true);
      if (identical(_loopback, server)) _loopback = null;
    }
  }

  /// The page the browser shows after Google sends the user back.
  static String _callbackPage({required bool ok}) {
    final title = ok ? 'Signed in' : 'Sign-in failed';
    final body = ok ? 'You can close this tab and go back to Checkpoint.' : 'Go back to Checkpoint and try again.';
    return '<!doctype html><html><head><meta charset="utf-8"><title>Checkpoint</title>'
        '<style>body{font-family:sans-serif;background:#0b0d12;color:#eee;display:grid;'
        'place-items:center;height:100vh;margin:0;text-align:center}</style></head>'
        '<body><div><h2>$title</h2><p>$body</p></div></body></html>';
  }

  /// Where supabase_flutter keeps the session on disk (see its `Supabase.initialize`).
  String get _persistedSessionKey =>
      'sb-${Uri.parse(_client.rest.url).host.split('.').first}-auth-token';

  Future<String?> _persistedSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_persistedSessionKey);
    } catch (e) {
      debugPrint('Reading the saved session failed: $e');
      return null;
    }
  }

  /// The id of the user whose session is saved on this device, or null. While
  /// [currentUser] is null this is the "signed in, but the session could not be
  /// refreshed yet" state: an expired access token is only dropped from memory
  /// when the refresh fails because the network is down, and the saved session
  /// stays on disk. A real sign-out, or a refresh token the server rejected,
  /// removes it.
  Future<String?> persistedUserId() async {
    final raw = await _persistedSession();
    if (raw == null) return null;
    try {
      final user = (jsonDecode(raw) as Map)['user'];
      final id = user is Map ? user['id'] : null;
      return id is String && id.isNotEmpty ? id : null;
    } catch (_) {
      return null;
    }
  }

  /// Tries to turn the saved session back into a live one (refreshing its
  /// token). Returns whether it worked; on success [changes] announces it.
  Future<bool> restoreSession() async {
    final raw = await _persistedSession();
    if (raw == null) return false;
    try {
      await _auth.recoverSession(raw);
      return _auth.currentUser != null;
    } catch (e) {
      debugPrint('Restoring the session failed: $e');
      return false;
    }
  }

  /// Forgets a saved session that never became live (signing out in that state).
  Future<void> discardPersistedSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_persistedSessionKey);
    } catch (e) {
      debugPrint('Discarding the saved session failed: $e');
    }
  }

  /// Permanently deletes the signed-in user's account through the `delete-account`
  /// Edge Function (their data, uploaded photo and sign-in), then ends the local
  /// session. Nothing is signed out when the function fails, so the user can try
  /// again. The function ignores any body: it deletes the caller and no one else.
  /// Throws the [FunctionException] of a failed call.
  Future<void> deleteAccount() async {
    await _client.functions.invoke('delete-account');
    // The account is gone, so the server may answer the sign-out with a 401/403/404;
    // gotrue ignores those and still ends the local session.
    await signOut();
  }

  /// Ends the sessions of this account on every other device, and keeps this one
  /// signed in. Throws the [AuthException] of a failed call.
  Future<void> signOutOtherDevices() => _auth.signOut(scope: SignOutScope.others);

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

  /// Text for the UI. Raw exceptions never reach the screen.
  static String messageFor(Object e) {
    if (e is AuthRetryableFetchException) return "Can't reach Checkpoint. Check your connection and try again.";
    if (e is AuthException) {
      // The codes Supabase sends for email sign-in and sign-up; anything else
      // (the Google flow's own messages included) is shown as it comes.
      return switch (e.code) {
        'invalid_credentials' => 'Wrong email or password. If you joined with Google, use Continue with Google.',
        'user_already_exists' || 'email_exists' =>
          'That email is already registered. Sign in instead, or use Forgot password? to choose a new password.',
        'weak_password' => 'That password is too weak. ${e.message}'.trim(),
        'email_not_confirmed' => 'Confirm your email first: open the link we sent you, then sign in.',
        'email_address_invalid' => 'Enter a valid email address.',
        'over_email_send_rate_limit' => 'Too many emails were sent. Wait a few minutes and try again.',
        'over_request_rate_limit' => 'Too many attempts. Wait a few minutes and try again.',
        'email_provider_disabled' => "Email sign-in isn't available right now. Use Continue with Google.",
        'signup_disabled' => "New accounts can't be created right now.",
        _ => e.message,
      };
    }
    if (e is PlatformException) {
      return switch (e.code) {
        GoogleSignIn.kSignInCanceledError => 'Google sign-in was cancelled.',
        _ => 'Google sign-in failed (${e.code}). Check the OAuth client IDs in Google Cloud.',
      };
    }
    return 'Something went wrong. Please try again.';
  }
}
