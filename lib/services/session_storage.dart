import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The key supabase_flutter keeps the session under: `sb-<project ref>-auth-token`.
String sessionKeyFor(String supabaseUrl) =>
    'sb-${Uri.parse(supabaseUrl).host.split('.').first}-auth-token';

/// Keeps the signed-in session (its access and refresh tokens) in the
/// platform's encrypted store rather than in SharedPreferences, which is a plain
/// file: on Android encrypted with a key the Android Keystore holds, on iOS in
/// the Keychain, readable once the device has been unlocked after starting and
/// never copied into a backup or onto another phone.
///
/// Only on Android and iOS ([supported]). The web app keeps the session in the
/// browser's localStorage and the desktop apps in SharedPreferences, as
/// supabase_flutter does by default.
class EncryptedSessionStorage extends LocalStorage {
  EncryptedSessionStorage(this.key, {FlutterSecureStorage? store})
    : _store = store ?? _defaultStore;

  static const _defaultStore = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  /// Whether this platform keeps the session here.
  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  final String key;
  final FlutterSecureStorage _store;

  /// Moves a session an earlier version of the app saved in SharedPreferences
  /// in here, so updating signs nobody out. The plain copy is removed only once
  /// the encrypted one is written.
  @override
  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getString(key);
      if (legacy == null) return;
      if (await _store.read(key: key) == null) {
        await _store.write(key: key, value: legacy);
      }
      await prefs.remove(key);
    } catch (e) {
      debugPrint('Moving the saved session to encrypted storage failed: $e');
    }
  }

  @override
  Future<bool> hasAccessToken() async => await accessToken() != null;

  /// The saved session as supabase_flutter wrote it (JSON), or null. An entry
  /// that can't be decrypted counts as none: the user signs in again.
  @override
  Future<String?> accessToken() async {
    try {
      return await _store.read(key: key);
    } catch (e) {
      debugPrint('Reading the saved session failed: $e');
      return null;
    }
  }

  @override
  Future<void> removePersistedSession() async {
    try {
      await _store.delete(key: key);
    } catch (e) {
      debugPrint('Removing the saved session failed: $e');
    }
  }

  /// A failed write leaves the user signed in for now; they sign in again after
  /// the app restarts.
  @override
  Future<void> persistSession(String persistSessionString) async {
    try {
      await _store.write(key: key, value: persistSessionString);
    } catch (e) {
      debugPrint('Saving the session failed: $e');
    }
  }
}
