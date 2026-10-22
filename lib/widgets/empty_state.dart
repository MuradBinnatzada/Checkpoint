import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:checkpoint/theme/palette.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.message, this.actionLabel, this.onAction, this.onRefresh});
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Makes the page pull down to refresh, for an empty state of something that
  /// may have been filled elsewhere in the meantime.
  final Future<void> Function()? onRefresh;

  static const _padding = 32.0;

  @override
  Widget build(BuildContext context) {
    final content = Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(color: context.palette.surfaceHigh, shape: BoxShape.circle),
        child: Icon(icon, color: context.palette.accent, size: 32),
      ),
      const SizedBox(height: 16),
      Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      Text(message, textAlign: TextAlign.center, style: TextStyle(color: context.palette.muted, height: 1.35)),
      if (actionLabel != null) ...[
        const SizedBox(height: 16),
        FilledButton.tonal(onPressed: onAction, child: Text(actionLabel!)),
      ],
    ]);
    final refresh = onRefresh;
    if (refresh == null) {
      return Center(
        child: SingleChildScrollView(padding: const EdgeInsets.all(_padding), child: content),
      );
    }
    // Always scrollable, and as tall as the space, so a pull anywhere on it counts.
    return RefreshIndicator(
      onRefresh: refresh,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(_padding),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: math.max(0, constraints.maxHeight - 2 * _padding)),
            child: Center(child: content),
          ),
        ),
      ),
    );
  }
}
