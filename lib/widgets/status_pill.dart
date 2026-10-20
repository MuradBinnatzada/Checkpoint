import 'package:flutter/material.dart';

import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/theme/palette.dart';

class StatusPill extends StatelessWidget {
  const StatusPill(this.status, {super.key});
  final GameStatus status;

  @override
  Widget build(BuildContext context) =>
      _Pill(icon: status.icon, label: status.label, color: status.color);
}

/// A game the member marked perfected ([Game.perfected]): its Platinum trophy,
/// every achievement or 100%, named by where they played it.
class PerfectPill extends StatelessWidget {
  const PerfectPill(this.mark, {super.key});
  final PerfectMark mark;

  @override
  Widget build(BuildContext context) =>
      _Pill(icon: mark.icon, label: mark.label, color: mark.color);
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, required this.color});
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final color = context.palette.legible(this.color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
      ]),
    );
  }
}
