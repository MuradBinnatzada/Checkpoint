import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:checkpoint/models/achievement.dart';
import 'package:checkpoint/models/connected_service.dart';
import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/sheets/log_hours_sheet.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/utils/formatters.dart';
import 'package:checkpoint/widgets/cover_art.dart';
import 'package:checkpoint/widgets/empty_state.dart';
import 'package:checkpoint/widgets/panel.dart';
import 'package:checkpoint/widgets/platform_widgets.dart';
import 'package:checkpoint/widgets/star_rating.dart';
import 'package:checkpoint/widgets/status_pill.dart';

class GameDetailScreen extends StatelessWidget {
  const GameDetailScreen({super.key, required this.gameId});
  final String gameId;

  static const double _expanded = 372;

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final game = store.maybeGame(gameId);
    if (game == null) {
      return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.error_outline_rounded, title: 'Game not found', message: 'It may have been removed.'));
    }
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverAppBar(
          pinned: true,
          expandedHeight: _expanded,
          backgroundColor: Palette.background,
          surfaceTintColor: Colors.transparent,
          leadingWidth: 68,
          leading: Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Center(child: _RoundIconButton(icon: Icons.arrow_back_ios_new_rounded, onTap: () => Navigator.maybePop(context))),
          ),
          actions: [
            if (game.status != null) // Only show heart if it's in the library
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(
                  child: _RoundIconButton(
                    icon: game.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    color: game.isFavorite ? Palette.danger : Colors.white,
                    onTap: () => context.actions.toggleFavorite(game.id),
                  ),
                ),
              ),
          ],
          flexibleSpace: LayoutBuilder(builder: (context, c) {
            final top = MediaQuery.paddingOf(context).top;
            final collapsed = kToolbarHeight + top;
            final t = ((c.maxHeight - collapsed) / (_expanded - kToolbarHeight)).clamp(0.0, 1.0).toDouble();
            // The header art is always laid out at its full expanded size and anchored
            // to the bottom, then clipped. That way the title/year column is never
            // squeezed into the shrinking app bar (the source of the bottom overflow).
            return ClipRect(
              child: Stack(fit: StackFit.expand, children: [
                Opacity(
                  opacity: t,
                  child: OverflowBox(
                    alignment: Alignment.bottomCenter,
                    minHeight: _expanded + top,
                    maxHeight: _expanded + top,
                    child: _DetailHeaderArt(game: game, topInset: top),
                  ),
                ),
                Positioned(
                  left: 68,
                  right: 20,
                  bottom: 0,
                  height: kToolbarHeight,
                  child: Opacity(
                    opacity: 1 - t,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(game.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              ]),
            );
          }),
        ),
        SliverToBoxAdapter(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, bottom + 32),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _ProgressPanel(game: game),
                  const SizedBox(height: 14),
                  _RatingPanel(game: game),
                  const SizedBox(height: 14),
                  Panel(
                    title: 'Played on',
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      PlatformChips(
                        platforms: game.platforms,
                        selected: game.playedOn,
                        onSelected: (p) => context.actions.setPlayedOn(game.id, p),
                      ),
                      if (game.playedOn == null) ...[
                        const SizedBox(height: 10),
                        const Text('Pick the platform you play this on. It is used in your session log and profile stats.', style: TextStyle(color: Palette.muted, fontSize: 12.5, height: 1.35)),
                      ],
                    ]),
                  ),
                  const SizedBox(height: 14),
                  Panel(title: 'Update status', child: _StatusActions(game: game)),
                  const SizedBox(height: 14),
                  _SessionsPanel(gameId: game.id),
                  _AchievementsPanel(game: game),
                  _AboutPanel(game: game),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onTap, this.color});
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: Material(
        color: Colors.black.withValues(alpha: 0.38),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: Icon(icon, size: 18, color: color ?? Colors.white)),
      ),
    );
  }
}

class _DetailHeaderArt extends StatelessWidget {
  const _DetailHeaderArt({required this.game, required this.topInset});
  final Game game;
  final double topInset;

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: [
      // Blurred cover-art backdrop: image, blur, then a dark scrim.
      if (game.coverUrl != null) Positioned.fill(child: Image.network(game.coverUrl!, fit: BoxFit.cover)),
      BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(color: Colors.black.withValues(alpha: 0.6)),
      ),
      Padding(
        padding: EdgeInsets.fromLTRB(20, topInset + kToolbarHeight, 20, 20),
        child: Align(
          alignment: Alignment.bottomLeft,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Container(
              width: 118,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 24, offset: const Offset(0, 10))],
              ),
              child: CoverArt(game: game, radius: 14, showTitle: false),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Flexible lets the title give up lines (with an ellipsis) instead of
                // pushing the rest of the column past the bottom edge.
                Flexible(
                  child: Text(game.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, height: 1.1)),
                ),
                const SizedBox(height: 6),
                Text(game.publisher, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('Released ${game.releaseYear}', style: const TextStyle(color: Colors.white60, fontSize: 13)),
                const SizedBox(height: 10),
                Wrap(spacing: 6, runSpacing: 6, children: [for (final p in game.platforms) PlatformBadge(p, dense: true)]),
              ]),
            ),
          ]),
        ),
      ),
    ]);
  }
}

class _ProgressPanel extends StatelessWidget {
  const _ProgressPanel({required this.game});
  final Game game;

  @override
  Widget build(BuildContext context) {
    Widget stat(String value, String label) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
            Text(label, style: const TextStyle(fontSize: 12, color: Palette.muted)),
          ]),
        );

    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (game.status != null) StatusPill(game.status!) else const Text('Not in your library', style: TextStyle(color: Palette.muted)),
          const Spacer(),
          FilledButton.tonalIcon(
            onPressed: () => showLogHoursSheet(context, game.id),
            icon: const Icon(Icons.timer_outlined, size: 18),
            label: const Text('Log Hours'),
          ),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          stat('${fmtHours(game.hoursPlayed)} h', 'Played'),
        ]),
      ]),
    );
  }
}

class _RatingPanel extends StatelessWidget {
  const _RatingPanel({required this.game});
  final Game game;

  @override
  Widget build(BuildContext context) {
    return Panel(
      title: 'Your rating',
      trailing: game.rating > 0
          ? TextButton(onPressed: () => context.actions.setRating(game.id, 0), child: const Text('Clear'))
          : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        StarRating(rating: game.rating, size: 44, onChanged: (v) => context.actions.setRating(game.id, v)),
        const SizedBox(height: 8),
        Text(
          game.rating > 0 ? '${fmtHours(game.rating)} / 5' : 'Tap or drag across the stars (half-stars supported)',
          style: TextStyle(color: game.rating > 0 ? Palette.star : Palette.muted, fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ]),
    );
  }
}

class _StatusActions extends StatelessWidget {
  const _StatusActions({required this.game});
  final Game game;

  @override
  Widget build(BuildContext context) {
    final store = context.actions;
    final messenger = ScaffoldMessenger.of(context);

    void change(GameStatus next, String message) {
      final prev = game.status;
      store.setStatus(game.id, next);
      HapticFeedback.mediumImpact();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(message),
          action: prev == null ? null : SnackBarAction(label: 'Undo', onPressed: () => store.setStatus(game.id, prev)),
        ));
    }

    return Wrap(spacing: 10, runSpacing: 10, children: [
      FilledButton.icon(
        onPressed: game.status == GameStatus.completed ? null : () => change(GameStatus.completed, 'Marked as completed'),
        icon: const Icon(Icons.verified_rounded, size: 18),
        label: const Text('Mark as Completed'),
      ),
      FilledButton.tonalIcon(
        onPressed: game.status == GameStatus.toPlay ? null : () => change(GameStatus.toPlay, 'Moved to To Play'),
        icon: const Icon(Icons.inventory_2_rounded, size: 18),
        label: const Text('Move to To Play'),
      ),
      OutlinedButton.icon(
        onPressed: game.status == GameStatus.dropped ? null : () => change(GameStatus.dropped, 'Dropped'),
        style: OutlinedButton.styleFrom(foregroundColor: Palette.danger, side: BorderSide(color: Palette.danger.withValues(alpha: 0.6))),
        icon: const Icon(Icons.block_rounded, size: 18),
        label: const Text('Drop'),
      ),
      if (game.status != GameStatus.playing)
        TextButton.icon(
          onPressed: () => change(GameStatus.playing, 'Started playing'),
          icon: const Icon(Icons.play_circle_rounded, size: 18),
          label: const Text('Start Playing'),
        ),
      if (game.status != null) ...[
        const SizedBox(width: double.infinity, height: 4),
        TextButton.icon(
          onPressed: () {
            store.removeFromLibrary(game.id);
            Navigator.maybePop(context);
            messenger
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text('Removed ${game.title} from library')));
          },
          style: TextButton.styleFrom(foregroundColor: Palette.danger),
          icon: const Icon(Icons.delete_outline_rounded, size: 18),
          label: const Text('Remove from Library'),
        ),
      ]
    ]);
  }
}

class _SessionsPanel extends StatelessWidget {
  const _SessionsPanel({required this.gameId});
  final String gameId;

  @override
  Widget build(BuildContext context) {
    final logs = context.store.logsFor(gameId);
    if (logs.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Panel(
        title: 'Recent sessions',
        child: Column(children: [
          for (final l in logs.take(5))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(color: l.platform.color.withValues(alpha: 0.16), shape: BoxShape.circle),
                  child: Icon(l.platform.icon, size: 18, color: l.platform.color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('+${fmtHours(l.hours)} h on ${l.platform.label}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (l.note.isNotEmpty) Text(l.note, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Palette.muted)),
                  ]),
                ),
                Text(timeAgo(l.timestamp), style: const TextStyle(fontSize: 12, color: Palette.muted)),
              ]),
            ),
        ]),
      ),
    );
  }
}

/// Unlocked first (most recently unlocked on top), then locked in Steam's own
/// order. `List.sort` isn't stable, so the original index is the tie-break.
List<Achievement> _sortAchievements(List<Achievement> source) {
  final indexed = [for (var i = 0; i < source.length; i++) (index: i, item: source[i])];
  indexed.sort((a, b) {
    final x = a.item, y = b.item;
    if (x.unlocked != y.unlocked) return x.unlocked ? -1 : 1;
    if (x.unlocked) {
      final xt = x.unlockedAt, yt = y.unlockedAt;
      if (xt != null && yt != null) {
        final byTime = yt.compareTo(xt);
        if (byTime != 0) return byTime;
      } else if (xt != null) {
        return -1;
      } else if (yt != null) {
        return 1;
      }
    }
    return a.index.compareTo(b.index);
  });
  return [for (final e in indexed) e.item];
}

/// Steam achievements, loaded on demand: one Steam round trip per game, so
/// they are not part of the bulk library sync.
class _AchievementsPanel extends StatefulWidget {
  const _AchievementsPanel({required this.game});
  final Game game;

  @override
  State<_AchievementsPanel> createState() => _AchievementsPanelState();
}

class _AchievementsPanelState extends State<_AchievementsPanel> {
  static const int _initialVisible = 8;
  static const int _pageSize = 20;

  bool _loading = false;
  bool _checking = false;
  String? _error;
  int _visible = _initialVisible;

  @override
  void initState() {
    super.initState();
    // Achievements aren't part of the library fetch. If they aren't in memory
    // yet, look for a stored copy in the database before offering the Steam
    // button. `_checking` keeps that button from flashing up in the meantime.
    if (widget.game.achievements == null) {
      _checking = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkStored());
    }
  }

  Future<void> _checkStored() async {
    if (!mounted) return;
    final store = context.actions;
    await store.ensureAchievementsLoaded(widget.game.id);
    if (mounted) setState(() => _checking = false);
  }

  /// Steam account connected, game in the library and played on PC or Steam
  /// Deck. The id prefix check keeps this to games synced from Steam: only
  /// those carry the deterministic id the Edge Function decodes into a Steam
  /// app id.
  bool _canLoad(BuildContext context) {
    final g = widget.game;
    return context.store.isConnected(ConnectedService.steam) &&
        g.inLibrary &&
        (g.playedOn == GamePlatform.pc || g.playedOn == GamePlatform.steamDeck) &&
        g.id.startsWith('57e40000-');
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final error = await context.actions.syncGameAchievements(widget.game.id);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = error;
    });
  }

  Widget _errorText() => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(_error!, style: TextStyle(color: Palette.danger, fontSize: 12.5, height: 1.35)),
      );

  Widget _checkingIndicator() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
      );

  Widget _prompt() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text(
        'Pull your unlocked achievements for this game from Steam.',
        style: TextStyle(color: Palette.muted, fontSize: 12.5, height: 1.35),
      ),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _loading ? null : _load,
          icon: _loading
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.emoji_events_rounded, size: 18),
          label: Text(_loading ? 'Loading achievements…' : 'Load Steam Achievements'),
        ),
      ),
      if (_error != null) _errorText(),
    ]);
  }

  Widget _list(List<Achievement> all) {
    final total = all.length;
    final unlocked = all.where((a) => a.unlocked).length;
    final percent = (unlocked * 100 / total).round();
    final shown = _sortAchievements(all).take(_visible).toList();
    final remaining = total - shown.length;
    final nextPage = remaining < _pageSize ? remaining : _pageSize;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
        Text('$unlocked / $total', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(width: 8),
        Text('($percent%)', style: const TextStyle(color: Palette.muted, fontSize: 14, fontWeight: FontWeight.w600)),
      ]),
      const SizedBox(height: 10),
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
          value: unlocked / total,
          minHeight: 8,
          color: Palette.star,
          backgroundColor: Colors.white.withValues(alpha: 0.08),
        ),
      ),
      const SizedBox(height: 14),
      for (final a in shown) _AchievementTile(achievement: a),
      // "Show less" appears as soon as the list has been expanded past its
      // starting size, not only once everything is visible. The "Show more"
      // label is Flexible so the pair can't overflow on narrow screens.
      if (remaining > 0 || _visible > _initialVisible)
        Row(children: [
          if (remaining > 0)
            Flexible(
              child: TextButton(
                onPressed: () => setState(() => _visible += _pageSize),
                child: Text('Show $nextPage more ($remaining left)', maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
          if (remaining > 0 && _visible > _initialVisible) const SizedBox(width: 16),
          if (_visible > _initialVisible)
            TextButton(
              onPressed: () => setState(() => _visible = _initialVisible),
              child: const Text('Show less'),
            ),
        ]),
      if (_error != null) _errorText(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final achievements = widget.game.achievements;
    final canLoad = _canLoad(context);

    // Never loaded and nothing the user can do about it here: stay out of the way.
    if (achievements == null && !canLoad) return const SizedBox.shrink();

    final Widget trailing;
    if (achievements != null && achievements.isNotEmpty && canLoad) {
      trailing = _loading
          ? const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          : IconButton(
              tooltip: 'Refresh from Steam',
              visualDensity: VisualDensity.compact,
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded, color: Palette.muted),
            );
    } else {
      trailing = const Icon(Icons.emoji_events_outlined, color: Palette.muted);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Panel(
        title: 'Achievements',
        trailing: trailing,
        child: achievements == null
            ? (_checking ? _checkingIndicator() : _prompt())
            : achievements.isEmpty
                ? const Text(
                    'Steam lists no achievements for this game.',
                    style: TextStyle(color: Palette.muted, fontSize: 12.5, height: 1.35),
                  )
                : _list(achievements),
      ),
    );
  }
}

class _AchievementTile extends StatelessWidget {
  const _AchievementTile({required this.achievement});
  final Achievement achievement;

  @override
  Widget build(BuildContext context) {
    final a = achievement;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: a.unlocked ? Palette.star.withValues(alpha: 0.07) : Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: a.unlocked ? Palette.star.withValues(alpha: 0.28) : Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Row(children: [
        _AchievementIcon(achievement: a),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              a.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: a.unlocked ? Colors.white : Colors.white70),
            ),
            if (a.description.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                a.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, height: 1.3, color: Palette.muted),
              ),
            ],
          ]),
        ),
        const SizedBox(width: 8),
        if (a.unlocked)
          Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
            Icon(Icons.emoji_events_rounded, size: 18, color: Palette.star),
            if (a.unlockedAt != null)
              Text(timeAgo(a.unlockedAt!), style: const TextStyle(fontSize: 11, color: Palette.muted)),
          ])
        else
          const Icon(Icons.lock_outline_rounded, size: 18, color: Palette.muted),
      ]),
    );
  }
}

class _AchievementIcon extends StatelessWidget {
  const _AchievementIcon({required this.achievement});
  final Achievement achievement;

  // Steam also ships a grey icon, but desaturating the colour one means we only
  // have to store (and fetch) a single URL per achievement.
  static const ColorFilter _greyscale = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    final a = achievement;
    final Widget fallback = Container(
      color: Colors.white.withValues(alpha: 0.06),
      child: const Icon(Icons.emoji_events_outlined, size: 22, color: Palette.muted),
    );
    Widget image = a.iconUrl.isEmpty
        ? fallback
        : Image.network(
            a.iconUrl,
            fit: BoxFit.cover,
            cacheWidth: 96, // 2x of the 44 px slot; keeps long lists light on memory
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => fallback,
          );
    if (!a.unlocked) {
      image = Opacity(opacity: 0.55, child: ColorFiltered(colorFilter: _greyscale, child: image));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(width: 44, height: 44, child: image),
    );
  }
}

class _AboutPanel extends StatelessWidget {
  const _AboutPanel({required this.game});
  final Game game;

  @override
  Widget build(BuildContext context) {
    return Panel(
      title: 'About',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(game.synopsis, style: const TextStyle(height: 1.45, color: Colors.white70)),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [for (final g in game.genres) Chip(label: Text(g))]),
        const SizedBox(height: 12),
        Text('Developer: ${game.developer}', style: const TextStyle(color: Palette.muted, fontSize: 12.5)),
      ]),
    );
  }
}