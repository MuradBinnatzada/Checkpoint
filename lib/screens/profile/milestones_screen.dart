import 'dart:async';

import 'package:flutter/material.dart';

import 'package:checkpoint/l10n/l10n.dart';
import 'package:checkpoint/models/milestone.dart';
import 'package:checkpoint/models/milestone_progress.dart';
import 'package:checkpoint/screens/profile/profile_flair_sheet.dart';
import 'package:checkpoint/state/auth_store.dart';
import 'package:checkpoint/state/milestones_store.dart';
import 'package:checkpoint/state/public_profile_store.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/utils/formatters.dart';
import 'package:checkpoint/widgets/milestone_badge.dart';
import 'package:checkpoint/widgets/panel.dart';

/// Every milestone, by category: those [userId] earned with when, and the rest
/// greyed out. On your own page the locked ones show how far along you are, and
/// there is a button to pick your frame, title and showcase.
class MilestonesScreen extends StatelessWidget {
  const MilestonesScreen({super.key, required this.userId, this.ownerName});

  final String userId;

  /// Whose they are, for the title on someone else's; null on your own.
  final String? ownerName;

  @override
  Widget build(BuildContext context) {
    final own = context.watch<AuthStore>().user?.id == userId;
    final EarnedMilestones earned;
    final MilestoneProgress? progress;
    if (own) {
      final store = context.watch<MilestonesStore>();
      earned = store.earned;
      progress = store.progress;
    } else {
      earned = context.watch<PublicProfileStore>().viewOf(userId).milestones;
      progress = null;
    }

    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        MilestonesSummary(earned: earned),
        for (final category in MilestoneCategory.values) ...[
          const SizedBox(height: 22),
          _CategoryTitle(category: category, earned: earned),
          for (final m in milestones)
            if (m.category == category)
              MilestoneTile(
                milestone: m,
                unlockedAt: earned.unlockedAt[m.id],
                value: progress?.valueOf(m.metric),
              ),
        ],
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          own || ownerName == null ? context.l10n.milestones : context.l10n.memberMilestones(ownerName!),
        ),
        actions: [
          if (own)
            IconButton(
              tooltip: context.l10n.flairTooltip,
              onPressed: () => unawaited(showProfileFlairSheet(context)),
              icon: const Icon(Icons.auto_awesome_rounded),
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: own
                ? RefreshIndicator(
                    onRefresh: context.read<MilestonesStore>().refresh,
                    child: list,
                  )
                : list,
          ),
        ),
      ),
    );
  }
}

/// The level, how far to the next one, and how many milestones are earned.
class MilestonesSummary extends StatelessWidget {
  const MilestonesSummary({super.key, required this.earned});

  final EarnedMilestones earned;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final level = earned.level;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                context.l10n.levelN(level.level),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  context.l10n.pointsCount(level.points, fmtThousands(level.points)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${earned.count} / ${milestones.length}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: level.progress,
              minHeight: 8,
              backgroundColor: palette.track,
              color: palette.accent,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            context.l10n.pointsToLevel(
              level.nextLevelAt - level.points,
              fmtThousands(level.nextLevelAt - level.points),
              level.level + 1,
            ),
            style: TextStyle(fontSize: 12.5, color: palette.muted),
          ),
        ],
      ),
    );
  }
}

class _CategoryTitle extends StatelessWidget {
  const _CategoryTitle({required this.category, required this.earned});

  final MilestoneCategory category;
  final EarnedMilestones earned;

  @override
  Widget build(BuildContext context) {
    final inCategory = milestones.where((m) => m.category == category);
    final done = inCategory.where((m) => earned.has(m.id)).length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(category.icon, size: 20, color: context.palette.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              category.label,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
          ),
          Text(
            '$done / ${inCategory.length}',
            style: TextStyle(
              color: context.palette.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// One milestone in a list: its badge, name and what it takes, then when it was
/// earned, or a bar towards it when [value] is known. Tapping it shows it in
/// full.
class MilestoneTile extends StatelessWidget {
  const MilestoneTile({
    super.key,
    required this.milestone,
    this.unlockedAt,
    this.value,
  });

  final Milestone milestone;
  final DateTime? unlockedAt;
  final num? value;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final m = milestone;
    final at = unlockedAt;
    final rewards = milestoneRewards(m);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => unawaited(
            showMilestoneSheet(context, m, unlockedAt: at, value: value),
          ),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: at != null
                    ? m.tier.color.withValues(alpha: 0.35)
                    : palette.hairline,
              ),
            ),
            child: Row(
              children: [
                MilestoneBadge(milestone: m, size: 46, unlocked: at != null),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.title,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                          color: at != null ? palette.text : palette.textSoft,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        m.description,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.3,
                          color: palette.muted,
                        ),
                      ),
                      if (rewards.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          context.l10n.unlocksRewards(rewards.join(' · ')),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: palette.legible(palette.accent),
                          ),
                        ),
                      ],
                      if (at == null && value != null && !m.isYesNo) ...[
                        const SizedBox(height: 8),
                        MilestoneProgressBar(milestone: m, value: value!),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (at != null)
                  Text(
                    fmtDay(at),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: palette.legible(palette.success),
                    ),
                  )
                else
                  Text(
                    context.l10n.pointsShort(m.points),
                    style: TextStyle(fontSize: 12, color: palette.muted),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
