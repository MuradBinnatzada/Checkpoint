import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:checkpoint/app/app_shell.dart';
import 'package:checkpoint/state/checkpoint_store.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/app_theme.dart';

class CheckpointApp extends StatefulWidget {
  const CheckpointApp({super.key});

  @override
  State<CheckpointApp> createState() => _CheckpointAppState();
}

class _CheckpointAppState extends State<CheckpointApp> {
  late final CheckpointStore _store = CheckpointStore.supabase(
    Supabase.instance.client,
  );

  @override
  void initState() {
    super.initState();
    unawaited(_store.initialize());
  }

  @override
  void dispose() {
    _store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // StoreScope sits above MaterialApp so pushed routes and sheets can read it.
    return StoreScope(
      store: _store,
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
