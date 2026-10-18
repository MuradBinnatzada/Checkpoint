import 'package:flutter/material.dart';

import 'package:checkpoint/theme/palette.dart';

/// The red box of a destructive action in Settings: what it removes, and the
/// button that starts it (the caller asks first). Used by "Clear library" and
/// "Delete account".
class DangerPanel extends StatelessWidget {
  const DangerPanel({
    super.key,
    required this.title,
    required this.description,
    required this.buttonLabel,
    required this.icon,
    required this.busy,
    required this.onPressed,
    this.disabled = false,
  });

  static const color = Colors.redAccent;

  final String title;
  final String description;
  final String buttonLabel;
  final IconData icon;

  /// The action is running: the button is disabled and shows a spinner.
  final bool busy;
  final VoidCallback onPressed;

  /// The action can't start right now (something else is running): the button
  /// is disabled, without a spinner, since this action isn't what is running.
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: const TextStyle(color: Palette.muted, height: 1.4),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: busy || disabled ? null : onPressed,
            style: OutlinedButton.styleFrom(
              foregroundColor: color,
              side: const BorderSide(color: color),
            ),
            icon: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(icon),
            label: Text(buttonLabel),
          ),
        ],
      ),
    );
  }
}
