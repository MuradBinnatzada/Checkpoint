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

/// A member's achievements, behind a button. Nothing is fetched until it is
/// pressed: achievements are large and personal, so they are not part of a
/// profile. Pressing it loads the progress per game; opening a game loads that
/// game's achievements.
class AchievementsSection extends StatelessWidget {
  const AchievementsSection({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PublicAchievementsStore>();
    final summary = store.summaryOf(userId);
    Future<void> load({bool force = false}) => context
        .read<PublicAchievementsStore>()
        .loadSummary(userId, force: force);

    final Widget trailing = switch (summary.status) {
      LoadStatus.ready => IconButton(
        tooltip: 'Refresh achievements',
        visualDensity: VisualDensity.compact,
        onPressed: () => unawaited(load(force: true)),
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
      _ => const Icon(Icons.lock_outline_rounded, color: Palette.muted),
    };

    final Widget child = switch (summary.status) {
      LoadStatus.idle => _Locked(onPressed: () => unawaited(load())),
      LoadStatus.loading => const SizedBox(height: 4),
      LoadStatus.failed => _Failed(onRetry: () => unawaited(load())),
      LoadStatus.ready =>
        summary.games.isEmpty
            ? const Text(
                'No achievements to show yet.',
                style: TextStyle(
                  color: Palette.muted,
                  fontSize: 12.5,
                  height: 1.35,
                ),
              )
            : Column(
                children: [
                  for (final game in summary.games)
                    _GameAchievements(userId: userId, game: game),
                ],
              ),
    };

    return Panel(title: 'Achievements', trailing: trailing, child: child);
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
                _Cover(url: game.coverUrl),
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
                      Text(
                        '${game.unlocked} / ${game.total} · $percent%',
                        style: const TextStyle(
                          color: Palette.muted,
                          fontSize: 12.5,
                        ),
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
