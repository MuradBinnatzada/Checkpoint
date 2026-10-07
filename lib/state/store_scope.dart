import 'package:flutter/material.dart';

import 'package:checkpoint/state/checkpoint_store.dart';

class StoreScope extends InheritedNotifier<CheckpointStore> {
  const StoreScope({super.key, required CheckpointStore store, required super.child})
      : super(notifier: store);

  /// Subscribes the caller to changes.
  static CheckpointStore of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StoreScope>()!.notifier!;

  /// No subscription — for event handlers and initState.
  static CheckpointStore read(BuildContext context) =>
      (context.getElementForInheritedWidgetOfExactType<StoreScope>()!.widget as StoreScope)
          .notifier!;
}

extension StoreContext on BuildContext {
  CheckpointStore get store => StoreScope.of(this);
  CheckpointStore get actions => StoreScope.read(this);
}
