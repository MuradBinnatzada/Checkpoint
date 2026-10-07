import 'package:flutter/material.dart';

import 'package:checkpoint/models/game.dart';

class StatusPill extends StatelessWidget {
  const StatusPill(this.status, {super.key});
  final GameStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(status.icon, size: 14, color: status.color),
        const SizedBox(width: 5),
        Text(status.label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: status.color)),
      ]),
    );
  }
}
