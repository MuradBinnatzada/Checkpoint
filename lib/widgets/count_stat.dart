import 'package:flutter/material.dart';

import 'package:checkpoint/theme/palette.dart';

/// A number over its label ("248 / Followers"). With [onTap] it is a button.
class CountStat extends StatelessWidget {
  const CountStat({
    super.key,
    required this.value,
    required this.label,
    this.onTap,
  });

  final String value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        Text(
          label,
          style: TextStyle(color: context.palette.muted, fontSize: 12.5),
        ),
      ],
    );
    final tap = onTap;
    if (tap == null) return content;
    return Semantics(
      button: true,
      label: '$value $label',
      excludeSemantics: true,
      onTap: tap,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: tap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 4, 14, 4),
          child: content,
        ),
      ),
    );
  }
}
