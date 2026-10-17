import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:checkpoint/app/app_shell.dart';
import 'package:checkpoint/state/app_stores.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/app_theme.dart';

class CheckpointApp extends StatefulWidget {
  const CheckpointApp({super.key});

  @override
  State<CheckpointApp> createState() => _CheckpointAppState();
}

class _CheckpointAppState extends State<CheckpointApp> {
  late final AppStores _stores = AppStores.supabase(Supabase.instance.client);

  @override
  void initState() {
    super.initState();
    unawaited(_stores.initialize());
  }

  @override
  void dispose() {
    _stores.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The scopes sit above MaterialApp so pushed routes and sheets can read them.
    return AppStoresScope(
      stores: _stores,
      child: MaterialApp(
        title: 'Checkpoint',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        builder: (context, child) => MediaQuery.withClampedTextScaling(
          minScaleFactor: 0.9,
          maxScaleFactor: 1.3,
          child: child!,
        ),
        home: const AppShell(),
      ),
    );
  }
}
