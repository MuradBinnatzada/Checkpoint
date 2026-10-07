import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/widgets/app_choice_chip.dart';

class PlatformBadge extends StatelessWidget {
  const PlatformBadge(this.platform, {super.key, this.dense = false});
  final GamePlatform platform;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 7 : 9, vertical: dense ? 3 : 4),
      decoration: BoxDecoration(
        color: platform.color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(platform.icon, size: dense ? 12 : 14, color: platform.color),
        const SizedBox(width: 5),
        Text(platform.label,
            style: TextStyle(fontSize: dense ? 11 : 12, fontWeight: FontWeight.w600, color: platform.color)),
      ]),
    );
  }
}

/// "Which platform did you play on?" selector.
class PlatformChips extends StatelessWidget {
  const PlatformChips({super.key, required this.platforms, required this.selected, required this.onSelected});
  final List<GamePlatform> platforms;
  final GamePlatform? selected;
  final ValueChanged<GamePlatform> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final p in platforms)
        AppChoiceChip(
          label: p.label,
          icon: p.icon,
          iconColor: p.color,
          selected: selected == p,
          onSelected: () {
            HapticFeedback.selectionClick();
            onSelected(p);
          },
        ),
    ]);
  }
}
