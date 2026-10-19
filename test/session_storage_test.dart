import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:checkpoint/services/session_storage.dart';

void main() {
  const key = 'sb-abcdefghijklmnopqrst-auth-token';
  const session = '{"access_token":"a","refresh_token":"r","user":{"id":"u1"}}';

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('the key is the one supabase_flutter uses', () {
    expect(sessionKeyFor('https://abcdefghijklmnopqrst.supabase.co'), key);
  });

  test('a session saved in plain SharedPreferences moves to encrypted storage', () async {
    SharedPreferences.setMockInitialValues({key: session});
    final storage = EncryptedSessionStorage(key);

    await storage.initialize();

    expect(await storage.accessToken(), session);
    expect(await storage.hasAccessToken(), isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(key), isFalse);
  });

  test('a newer encrypted session is not overwritten by an old plain one', () async {
    SharedPreferences.setMockInitialValues({key: 'old'});
    FlutterSecureStorage.setMockInitialValues({key: session});
    final storage = EncryptedSessionStorage(key);

    await storage.initialize();

    expect(await storage.accessToken(), session);
    expect((await SharedPreferences.getInstance()).containsKey(key), isFalse);
  });

  test('sessions are written, read and removed in encrypted storage only', () async {
    final storage = EncryptedSessionStorage(key);
    await storage.initialize();
    expect(await storage.hasAccessToken(), isFalse);

    await storage.persistSession(session);
    expect(await storage.accessToken(), session);
    expect((await SharedPreferences.getInstance()).containsKey(key), isFalse);

    await storage.removePersistedSession();
    expect(await storage.accessToken(), isNull);
  });
}
