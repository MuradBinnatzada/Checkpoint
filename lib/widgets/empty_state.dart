import 'package:flutter/material.dart';

import 'package:checkpoint/theme/palette.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.message, this.actionLabel, this.onAction});
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(color: Palette.surfaceHigh, shape: BoxShape.circle),
            child: Icon(icon, color: Palette.accent, size: 32),
          ),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Palette.muted, height: 1.35)),
          if (actionLabel != null) ...[
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ]),
      ),
    );
  }
}
