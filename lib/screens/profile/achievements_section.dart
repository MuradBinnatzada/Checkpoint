import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:checkpoint/models/achievement.dart';
import 'package:checkpoint/models/achievement_summary.dart';
import 'package:checkpoint/state/load_status.dart';
import 'package:checkpoint/state/public_achievements_store.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/widgets/achievement_tile.dart';
import 'package:checkpoint/widgets/panel.dart';

/// A member's achievements. The count over all their games shows at once (one
/// small row from the database); the games behind it, and each game's
/// achievements, are fetched only when asked for: achievements are large and
/// personal, so they are not part of a profile. The button loads the progress per
/// game; opening a game loads that game's achievements.
class AchievementsSection extends StatefulWidget {
  const AchievementsSection({super.key, required this.userId});

  final String userId;

  @override
  State<AchievementsSection> createState() => _AchievementsSectionState();
}

class _AchievementsSectionState extends State<AchievementsSection> {
  @override
  void initState() {
    super.initState();
    _loadTotalsAfterFrame();
  }

  @override
  void didUpdateWidget(AchievementsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) _loadTotalsAfterFrame();
  }

  /// After the frame: loading notifies, which isn't allowed during build.
  void _loadTotalsAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadTotals());
  }

  void _loadTotals({bool force = false}) {
    if (!mounted) return;
    unawaited(
      context.read<PublicAchievementsStore>().loadTotals(
        widget.userId,
        force: force,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userId = widget.userId;
    final store = context.watch<PublicAchievementsStore>();
    final totalsView = store.totalsOf(userId);
    final summary = store.summaryOf(userId);
    final totals = totalsView.totals;
    final counted = totalsView.status == LoadStatus.ready;
    Future<void> loadSummary({bool force = false}) => context
        .read<PublicAchievementsStore>()
        .loadSummary(userId, force: force);

    final Widget trailing = switch (summary.status) {
      LoadStatus.ready => IconButton(
        tooltip: 'Refresh achievements',
        visualDensity: VisualDensity.compact,
        onPressed: () {
          _loadTotals(force: true);
          unawaited(loadSummary(force: true));
        },
        icon: const Icon(Icons.refresh_rounded, color: Palette.muted),
      ),
      LoadStatus.loading => const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      _ when counted => Icon(
        totals.allUnlocked
            ? Icons.emoji_events_rounded
            : Icons.emoji_events_outlined,
        color: totals.allUnlocked ? Palette.star : Palette.muted,
      ),
      _ => const Icon(Icons.lock_outline_rounded, color: Palette.muted),
    };

    // The per-game part: behind a button until asked for.
    final Widget games = switch (summary.status) {
      LoadStatus.idle => _Locked(onPressed: () => unawaited(loadSummary())),
      LoadStatus.loading => const SizedBox(height: 4),
      LoadStatus.failed => _Failed(onRetry: () => unawaited(loadSummary())),
      LoadStatus.ready =>
        summary.games.isEmpty
            ? const _Empty()
            : Column(
                children: [
                  for (final game in summary.games)
                    _GameAchievements(userId: userId, game: game),
                ],
              ),
    };

    final Widget child = switch (totalsView.status) {
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
      LoadStatus.ready when totals.isEmpty => const _Empty(),
      LoadStatus.ready => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TotalsHeader(totals: totals),
          const SizedBox(height: 14),
          games,
        ],
      ),
      // The count could not be read (offline, or the function is not deployed
      // yet): the button still works.
      LoadStatus.failed => games,
    };

    return Panel(title: 'Achievements', trailing: trailing, child: child);
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'No achievements to show yet.',
      style: TextStyle(color: Palette.muted, fontSize: 12.5, height: 1.35),
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

class _Locked extends StatelessWidget {
  const _Locked({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Achievements are only fetched when you ask for them.',
          style: TextStyle(color: Palette.muted, fontSize: 12.5, height: 1.35),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onPressed,
            icon: const Icon(Icons.emoji_events_rounded, size: 18),
            label: const Text('View Achievements'),
          ),
        ),
      ],
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

/// One game's progress; opens to the game's achievements, fetched on first open.
class _GameAchievements extends StatefulWidget {
  const _GameAchievements({required this.userId, required this.game});

  final String userId;
  final GameAchievementSummary game;

  @override
  State<_GameAchievements> createState() => _GameAchievementsState();
}

class _GameAchievementsState extends State<_GameAchievements> {
  static const int _initialVisible = 8;
  static const int _pageSize = 20;

  bool _open = false;
  int _visible = _initialVisible;

  Future<void> _loadGame({bool force = false}) => context
      .read<PublicAchievementsStore>()
      .loadGame(widget.userId, widget.game.gameId, force: force);

  void _toggle() {
    setState(() => _open = !_open);
    if (_open) unawaited(_loadGame());
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final percent = (game.progress * 100).round();
    // Every achievement of the game is unlocked.
    final complete = game.total > 0 && game.unlocked == game.total;
    final view = context.watch<PublicAchievementsStore>().gameOf(
      widget.userId,
      game.gameId,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _toggle,
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
                Icon(
                  _open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  color: Palette.muted,
                ),
              ],
            ),
          ),
        ),
        if (_open) _details(view),
      ],
    );
  }

  Widget _details(GameAchievementsView view) {
    switch (view.status) {
      case LoadStatus.idle:
      case LoadStatus.loading:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      case LoadStatus.failed:
        return Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => unawaited(_loadGame(force: true)),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Couldn’t load. Tap to retry'),
          ),
        );
      case LoadStatus.ready:
        final all = sortAchievements(
          view.achievements ?? const <Achievement>[],
        );
        if (all.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No achievements stored for this game.',
              style: TextStyle(color: Palette.muted, fontSize: 12.5),
            ),
          );
        }
        final shown = all.take(_visible).toList();
        final remaining = all.length - shown.length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            for (final a in shown) AchievementTile(achievement: a),
            if (remaining > 0 || _visible > _initialVisible)
              Row(
                children: [
                  if (remaining > 0)
                    Flexible(
                      child: TextButton(
                        onPressed: () => setState(() => _visible += _pageSize),
                        child: Text(
                          'Show ${remaining < _pageSize ? remaining : _pageSize} more ($remaining left)',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  if (remaining > 0 && _visible > _initialVisible)
                    const SizedBox(width: 16),
                  if (_visible > _initialVisible)
                    TextButton(
                      onPressed: () =>
                          setState(() => _visible = _initialVisible),
                      child: const Text('Show less'),
                    ),
                ],
              ),
          ],
        );
    }
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
