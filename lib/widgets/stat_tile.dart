import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:checkpoint/theme/palette.dart';

/// Summary card. Pass [onTap] to make the whole card tappable (ripple + chevron).
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.icon, required this.value, required this.label, this.onTap});
  final IconData icon;
  final String value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tap = onTap;
    return Material(
      color: context.palette.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: context.palette.hairline),
      ),
      child: InkWell(
        splashColor: context.palette.accent.withValues(alpha: 0.14),
        highlightColor: context.palette.accent.withValues(alpha: 0.06),
        onTap: tap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                tap();
              },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, size: 20, color: context.palette.accent),
              const Spacer(),
              if (tap != null) Icon(Icons.chevron_right_rounded, size: 20, color: context.palette.muted),
            ]),
            const SizedBox(height: 10),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 2),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: context.palette.muted)),
          ]),
        ),
      ),
    );
  }
}
