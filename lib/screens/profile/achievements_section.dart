import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:checkpoint/models/achievement_summary.dart';
import 'package:checkpoint/screens/profile/game_achievements_dialog.dart';
import 'package:checkpoint/state/auth_store.dart';
import 'package:checkpoint/state/load_status.dart';
import 'package:checkpoint/state/public_achievements_store.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/widgets/panel.dart';

/// A member's achievements: the count over all their games, then every game
/// they unlocked anything in with how far they got, most complete first. Both
/// are counts only (their Steam syncs keep them), so they load with the
/// profile; a game's achievements are fetched when it is tapped, in a dialog
/// (see [showGameAchievementsDialog]).
class AchievementsSection extends StatefulWidget {
  const AchievementsSection({super.key, required this.userId});

  final String userId;

  @override
  State<AchievementsSection> createState() => _AchievementsSectionState();
}

class _AchievementsSectionState extends State<AchievementsSection> {
  static const int _initialGames = 5;
  static const int _pageSize = 10;

  int _visible = _initialGames;

  @override
  void initState() {
    super.initState();
    _loadAfterFrame();
  }

  @override
  void didUpdateWidget(AchievementsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _visible = _initialGames;
      _loadAfterFrame();
    }
  }

  /// After the frame: loading notifies, which isn't allowed during build.
  void _loadAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _load({bool force = false}) {
    if (!mounted) return;
    final store = context.read<PublicAchievementsStore>();
    unawaited(store.loadTotals(widget.userId, force: force));
    unawaited(store.loadSummary(widget.userId, force: force));
  }

  @override
  Widget build(BuildContext context) {
    final userId = widget.userId;
    final store = context.watch<PublicAchievementsStore>();
    final totalsView = store.totalsOf(userId);
    final summary = store.summaryOf(userId);
    final totals = totalsView.totals;
    final showTotals =
        totalsView.status == LoadStatus.ready && !totals.isEmpty;
    final own = context.watch<AuthStore>().user?.id == userId;

    final Widget trailing = switch (summary.status) {
      LoadStatus.loading => const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      LoadStatus.ready || LoadStatus.failed => IconButton(
        tooltip: 'Refresh achievements',
        visualDensity: VisualDensity.compact,
        onPressed: () => _load(force: true),
        icon: const Icon(Icons.refresh_rounded, color: Palette.muted),
      ),
      LoadStatus.idle => Icon(
        totals.allUnlocked
            ? Icons.emoji_events_rounded
            : Icons.emoji_events_outlined,
        color: totals.allUnlocked ? Palette.star : Palette.muted,
      ),
    };

    final Widget games = switch (summary.status) {
      LoadStatus.idle || LoadStatus.loading => const SizedBox(
        height: 56,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      LoadStatus.failed => _Failed(onRetry: () => _load(force: true)),
      // The count says it all when the list is somehow empty.
      LoadStatus.ready when summary.games.isEmpty =>
        showTotals ? const SizedBox.shrink() : _Empty(own: own),
      LoadStatus.ready => _gameList(summary.games),
    };

    return Panel(
      title: 'Achievements',
      trailing: trailing,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showTotals) ...[
            _TotalsHeader(totals: totals),
            const SizedBox(height: 10),
          ],
          games,
        ],
      ),
    );
  }

  Widget _gameList(List<GameAchievementSummary> all) {
    final shown = all.take(_visible).toList();
    final remaining = all.length - shown.length;
    final nextPage = remaining < _pageSize ? remaining : _pageSize;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final game in shown)
          _GameAchievements(
            game: game,
            onTap: () => showGameAchievementsDialog(
              context,
              userId: widget.userId,
              game: game,
            ),
          ),
        // "Show less" appears as soon as the list has been expanded past its
        // starting size. The "Show more" label is Flexible so the pair can't
        // overflow on narrow screens.
        if (remaining > 0 || _visible > _initialGames)
          Row(
            children: [
              if (remaining > 0)
                Flexible(
                  child: TextButton(
                    onPressed: () => setState(() => _visible += _pageSize),
                    child: Text(
                      'Show $nextPage more ($remaining left)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              if (remaining > 0 && _visible > _initialGames)
                const SizedBox(width: 16),
              if (_visible > _initialGames)
                TextButton(
                  onPressed: () => setState(() => _visible = _initialGames),
                  child: const Text('Show less'),
                ),
            ],
          ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.own});

  /// The signed-in member's own profile: says how to fill it.
  final bool own;

  @override
  Widget build(BuildContext context) {
    return Text(
      own
          ? 'No achievements yet. Sync your Steam library (Settings > Account) '
                'to list every game you unlocked achievements in.'
          : 'No Steam achievements to show yet.',
      style: const TextStyle(color: Palette.muted, fontSize: 12.5, height: 1.35),
    );
  }
}

/// A gold glow around [child] while [active]: a ring and a soft shadow. Still,
/// not pulsing, so nothing keeps animating on a screen that is just being read.
class _Glow extends StatelessWidget {
  const _Glow({
    required this.active,
    required this.child,
    this.radius = 14,
    this.padding = EdgeInsets.zero,
  });

  final bool active;
  final Widget child;
  final double radius;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        color: active ? Palette.star.withValues(alpha: 0.08) : null,
        border: active
            ? Border.all(color: Palette.star.withValues(alpha: 0.6))
            : null,
        boxShadow: active
            ? [
                BoxShadow(
                  color: Palette.star.withValues(alpha: 0.35),
                  blurRadius: 18,
                ),
              ]
            : const [],
      ),
      child: child,
    );
  }
}

/// The count that is always there: unlocked out of all, over every game with
/// achievements. Glows once all of them are unlocked.
class _TotalsHeader extends StatelessWidget {
  const _TotalsHeader({required this.totals});

  final AchievementTotals totals;

  @override
  Widget build(BuildContext context) {
    final done = totals.allUnlocked;
    // Floor, so 99.6% never reads as 100% while something is still locked.
    final percent = done ? 100 : (totals.progress * 100).floor();
    final games = '${totals.games} ${totals.games == 1 ? 'game' : 'games'}';
    final detail = done
        ? 'Every achievement unlocked · $games'
        : '$percent% · $games'
              '${totals.completedGames > 0 ? ' · ${totals.completedGames} completed' : ''}';

    return Semantics(
      container: true,
      label:
          '${totals.unlocked} of ${totals.total} achievements unlocked. $detail',
      excludeSemantics: true,
      child: _Glow(
        active: done,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '${totals.unlocked}',
                  style: TextStyle(
                    fontSize: 30,
                    height: 1.05,
                    fontWeight: FontWeight.w800,
                    color: done ? Palette.star : null,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '/ ${totals.total} unlocked',
                  style: const TextStyle(
                    color: Palette.muted,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: totals.progress,
                minHeight: 8,
                color: Palette.star,
                backgroundColor: Colors.white.withValues(alpha: 0.08),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              detail,
              style: TextStyle(
                color: done ? Palette.star : Palette.muted,
                fontSize: 12.5,
                fontWeight: done ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Could not load achievements. Check your connection and try again.',
          style: TextStyle(color: Palette.danger, fontSize: 12.5, height: 1.35),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Try again'),
        ),
      ],
    );
  }
}

/// One game's progress; tapping it opens the game's achievements.
class _GameAchievements extends StatelessWidget {
  const _GameAchievements({required this.game, required this.onTap});

  final GameAchievementSummary game;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final percent = (game.progress * 100).round();
    // Every achievement of the game is unlocked.
    final complete = game.total > 0 && game.unlocked == game.total;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            _Glow(
              active: complete,
              radius: 10,
              child: _Cover(url: game.coverUrl),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    game.title,
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
                      if (complete) ...[
                        const Icon(
                          Icons.emoji_events_rounded,
                          size: 14,
                          color: Palette.star,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        '${game.unlocked} / ${game.total} · $percent%',
                        style: TextStyle(
                          color: complete ? Palette.star : Palette.muted,
                          fontSize: 12.5,
                          fontWeight: complete
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: game.progress,
                      minHeight: 6,
                      color: Palette.star,
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, color: Palette.muted),
          ],
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    const width = 40.0;
    const height = 54.0;
    final fallback = Container(
      color: Palette.surfaceHigh,
      child: const Icon(
        Icons.sports_esports_rounded,
        size: 20,
        color: Palette.muted,
      ),
    );
    final link = url;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: width,
        height: height,
        child: link == null || link.isEmpty
            ? fallback
            : CachedNetworkImage(
                imageUrl: link,
                fit: BoxFit.cover,
                memCacheWidth: 120,
                fadeInDuration: Duration.zero,
                placeholder: (_, _) => fallback,
                errorWidget: (_, _, _) => fallback,
              ),
      ),
    );
  }
}
