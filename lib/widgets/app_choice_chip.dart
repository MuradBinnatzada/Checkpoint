import 'package:flutter/material.dart';

import 'package:checkpoint/theme/palette.dart';

/// Pill selector with a high-contrast selected state:
/// solid accent fill + dark text/icon vs. dark surface + light text.
class AppChoiceChip extends StatelessWidget {
  const AppChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.icon,
    this.iconColor,
  });
  final String label;
  final bool selected;
  final VoidCallback onSelected;
  final IconData? icon;
  final Color? iconColor; // icon tint when NOT selected

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      showCheckmark: false,
      selected: selected,
      onSelected: (_) => onSelected(),
      backgroundColor: context.palette.surfaceHigh,
      selectedColor: context.palette.accent,
      shape: const StadiumBorder(),
      side: BorderSide(
        color: selected ? context.palette.accent : context.palette.outline,
        width: selected ? 1.5 : 1,
      ),
      avatar: icon == null
          ? null
          : Icon(icon, size: 18, color: selected ? context.palette.onAccent : (iconColor ?? context.palette.muted)),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          color: selected ? context.palette.onAccent : context.palette.textSoft,
        ),
      ),
    );
  }
}
