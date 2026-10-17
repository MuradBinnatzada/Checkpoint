import 'package:flutter/material.dart';

import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/utils/formatters.dart';
import 'package:checkpoint/widgets/panel.dart';

/// Hours played per platform as a bar each, most played first. Shared by your own
/// profile and anyone else's.
class HoursByPlatformPanel extends StatelessWidget {
  const HoursByPlatformPanel({
    super.key,
    required this.hours,
    this.emptyText = 'Log a session to see your breakdown.',
  });

  /// Hours per platform, most played first.
  final Map<GamePlatform, double> hours;

  /// Said when there are no hours at all.
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final entries = hours.entries.toList();
    final max = entries.isEmpty ? 1.0 : entries.first.value;
    return Panel(
      title: 'Hours by platform',
      child: entries.isEmpty
          ? Text(emptyText, style: const TextStyle(color: Palette.muted))
          : Column(
              children: [
                for (final e in entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Icon(e.key.icon, size: 18, color: e.key.color),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 82,
                          child: Text(
                            e.key.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(5),
                            child: LinearProgressIndicator(
                              value: e.value / max,
                              minHeight: 9,
                              color: e.key.color,
                              backgroundColor: Colors.white10,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 52,
                          child: Text(
                            '${fmtHours(e.value)} h',
                            textAlign: TextAlign.end,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: Palette.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
