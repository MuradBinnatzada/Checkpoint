import 'package:flutter/material.dart';

import 'package:checkpoint/models/activity_entry.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/utils/formatters.dart';
import 'package:checkpoint/utils/navigation.dart';
import 'package:checkpoint/widgets/cover_art.dart';
import 'package:checkpoint/widgets/panel.dart';

/// A member's latest play sessions, one row per game: cover, title, hours and
/// platform, and how long ago. Tapping a row opens the game.
class RecentActivityPanel extends StatelessWidget {
  const RecentActivityPanel({super.key, required this.entries});

  final List<ActivityEntry> entries;

  @override
  Widget build(BuildContext context) {
    return Panel(
      title: 'Recent activity',
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
      child: entries.isEmpty
          ? const Padding(
              padding: EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Text(
                'No sessions logged yet.',
                style: TextStyle(color: Palette.muted, fontSize: 13),
              ),
            )
          : Column(
              children: [
                for (final e in entries)
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => openGame(context, e.game.id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 40,
                            child: CoverArt(game: e.game, radius: 8),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  e.game.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Icon(
                                      e.platform.icon,
                                      size: 13,
                                      color: e.platform.color,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      '${fmtHours(e.hours)} h · ${e.platform.label}',
                                      style: const TextStyle(
                                        color: Palette.muted,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            timeAgo(e.at),
                            style: const TextStyle(
                              color: Palette.muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
