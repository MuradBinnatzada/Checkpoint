import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:checkpoint/theme/palette.dart';

class SheetFrame extends StatelessWidget {
  const SheetFrame({super.key, required this.title, this.subtitle, required this.child});
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final safe = MediaQuery.paddingOf(context).bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 4, 20, math.max(keyboard, safe) + 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle!, style: const TextStyle(color: Palette.muted)),
        ],
        const SizedBox(height: 18),
        child,
      ]),
    );
  }
}
