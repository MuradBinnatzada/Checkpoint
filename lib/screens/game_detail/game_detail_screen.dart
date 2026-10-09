import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
            return Stack(fit: StackFit.expand, children: [
              Opacity(opacity: t, child: _DetailHeaderArt(game: game, topInset: top)),
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
            ]);
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
                  ValueRatioCalculator(game: game),
                  const SizedBox(height: 14),
                  _SessionsPanel(gameId: game.id),
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
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: game.coverColors),
        ),
      ),
      Positioned(right: -40, top: topInset + 30, child: Icon(game.coverIcon, size: 300, color: Colors.white.withValues(alpha: 0.10))),
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x59000000), Color(0x00000000), Palette.background],
            stops: [0, 0.45, 1],
          ),
        ),
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
              child: CoverArt(game: game, radius: 14),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(game.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, height: 1.1)),
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
          stat(game.targetHours > 0 ? '${fmtHours(game.targetHours)} h' : '—', 'Target'),
          stat(game.targetHours > 0 ? '${(game.progress * 100).round()}%' : '—', 'Progress'),
        ]),
        if (game.targetHours > 0) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(value: game.progress, minHeight: 8, color: Palette.accent, backgroundColor: Colors.white12),
          ),
        ],
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

/// Purchase price → cost per hour, with a plain-language verdict.
class ValueRatioCalculator extends StatefulWidget {
  const ValueRatioCalculator({super.key, required this.game});
  final Game game;

  @override
  State<ValueRatioCalculator> createState() => _ValueRatioCalculatorState();
}

class _ValueRatioCalculatorState extends State<ValueRatioCalculator> {
  late final TextEditingController _price = TextEditingController(
    text: widget.game.purchasePrice > 0 ? widget.game.purchasePrice.toStringAsFixed(2) : '',
  );

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  ({String label, Color color}) _verdict(double cph) {
    if (cph <= 1) return (label: 'Bargain', color: Palette.success);
    if (cph <= 3) return (label: 'Great value', color: Palette.success);
    if (cph <= 6) return (label: 'Fair', color: Palette.star);
    return (label: 'Pricey per hour', color: Palette.danger);
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.game;
    final cph = g.costPerHour;
    final verdict = cph == null ? null : _verdict(cph);

    String hint;
    if (g.purchasePrice <= 0) {
      hint = 'Enter what you paid to see your cost per hour.';
    } else if (g.hoursPlayed <= 0) {
      hint = 'Log some hours to calculate cost per hour.';
    } else if (cph! > 1) {
      hint = 'Play ${fmtHours(g.purchasePrice - g.hoursPlayed)} more hours to get under ${fmtMoney(1)}/hr.';
    } else {
      hint = 'Already under ${fmtMoney(1)} per hour. Nice.';
    }

    return Panel(
      title: 'Value ratio',
      trailing: const Icon(Icons.savings_outlined, color: Palette.muted),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          controller: _price,
          keyboardType: decimalKeyboard,
          inputFormatters: [decimalFormatter],
          decoration: fieldDecoration('Purchase price', prefix: '\$ '),
          onChanged: (v) => context.actions.setPurchasePrice(g.id, parseNum(v) ?? 0),
        ),
        const SizedBox(height: 18),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Cost per hour', style: TextStyle(color: Palette.muted, fontSize: 12.5)),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  cph == null ? '—' : '${fmtMoney(cph)}/hr',
                  style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: verdict?.color ?? Colors.white),
                ),
              ),
            ]),
          ),
          if (verdict != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: verdict.color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(20)),
              child: Text(verdict.label, style: TextStyle(color: verdict.color, fontWeight: FontWeight.w700, fontSize: 12.5)),
            ),
        ]),
        const SizedBox(height: 10),
        Text(hint, style: const TextStyle(color: Palette.muted, fontSize: 12.5, height: 1.35)),
      ]),
    );
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