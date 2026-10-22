import 'dart:async';

import 'package:flutter/material.dart';

import 'package:checkpoint/l10n/l10n.dart';
import 'package:checkpoint/models/milestone.dart';
import 'package:checkpoint/models/milestone_progress.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/widgets/milestone_badge.dart';
import 'package:checkpoint/widgets/panel.dart';

/// A member's milestones on their profile: their level and how far to the
/// next, how many of all the milestones they have, and the latest few. "See
/// all" ([onSeeAll]) opens every one.
class MilestonesSection extends StatelessWidget {
  const MilestonesSection({
    super.key,
    required this.earned,
    required this.onSeeAll,
    this.progress,
    this.own = false,
  });

  final EarnedMilestones earned;
  final VoidCallback onSeeAll;

  /// Your own: how far along the locked ones are.
  final MilestoneProgress? progress;
  final bool own;

  /// The latest milestones shown.
  static const recent = 6;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final level = earned.level;
    final latest = earned.list.take(recent).toList();

    return Panel(
      title: context.l10n.milestones,
      trailing: TextButton(onPressed: onSeeAll, child: Text(context.l10n.seeAllShort)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                context.l10n.levelN(level.level),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  context.l10n.earnedOf(earned.count, milestones.length),
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.muted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: level.progress,
              minHeight: 6,
              backgroundColor: palette.track,
              color: palette.accent,
            ),
          ),
          const SizedBox(height: 14),
          if (latest.isEmpty)
            Text(
              own
                  ? context.l10n.noMilestonesOwn
                  : context.l10n.noMilestonesOther,
              style: TextStyle(
                color: palette.muted,
                fontSize: 13,
                height: 1.35,
              ),
            )
          else
            Row(
              children: [
                for (var i = 0; i < recent; i++)
                  Expanded(
                    child: Center(
                      child: i < latest.length
                          ? InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () => unawaited(
                                showMilestoneSheet(
                                  context,
                                  latest[i],
                                  unlockedAt: earned.unlockedAt[latest[i].id],
                                  value: progress?.valueOf(latest[i].metric),
                                ),
                              ),
                              child: MilestoneBadge(
                                milestone: latest[i],
                                size: 40,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
