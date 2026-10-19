import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:checkpoint/app/checkpoint_app.dart';
import 'package:checkpoint/services/session_storage.dart';
import 'package:checkpoint/theme/palette.dart';

const _supabaseUrl = 'https://nmbarqhvcjgyuwreebda.supabase.co';
const _supabasePublishableKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5tYmFycWh2Y2pneXV3cmVlYmRhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTEzODE5OTcsImV4cCI6MjEwNjk1Nzk5N30.tXIvaeJPK1ZEI75U6f-SkD-4iRZBVVE3Cy5OxBCscGQ';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: _supabaseUrl,
    publishableKey: _supabasePublishableKey,
    // Android and iOS keep the session's tokens encrypted; null is
    // supabase_flutter's own storage (the web and desktop apps).
    authOptions: FlutterAuthClientOptions(
      localStorage: EncryptedSessionStorage.supported
          ? EncryptedSessionStorage(sessionKeyFor(_supabaseUrl))
          : null,
    ),
  );

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Palette.navBar,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const CheckpointApp());
}
