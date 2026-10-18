import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart' show ImageRenderMethodForWeb;
import 'package:flutter/material.dart';

import 'package:checkpoint/models/achievement.dart';
import 'package:checkpoint/models/achievement_summary.dart';
import 'package:checkpoint/state/load_status.dart';
import 'package:checkpoint/state/public_achievements_store.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/widgets/achievement_tile.dart';
import 'package:checkpoint/widgets/app_choice_chip.dart';

/// Opens [game]'s achievements for the member [userId] in a dialog over the
/// profile: their progress at the top, then every achievement, unlocked first.
/// The list is fetched as it opens (see [PublicAchievementsStore.loadGame]).
Future<void> showGameAchievementsDialog(
  BuildContext context, {
  required String userId,
  required GameAchievementSummary game,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => GameAchievementsDialog(userId: userId, game: game),
  );
}

enum _Filter { all, unlocked, locked }

class GameAchievementsDialog extends StatefulWidget {
  const GameAchievementsDialog({
    super.key,
    required this.userId,
    required this.game,
  });

  final String userId;

  /// The game as the profile listed it; its counts tell whether the list stored
  /// in the database is current.
  final GameAchievementSummary game;

  @override
  State<GameAchievementsDialog> createState() => _GameAchievementsDialogState();
}

class _GameAchievementsDialogState extends State<GameAchievementsDialog> {
  /// A list this short is laid out whole, so the dialog is only as tall as it.
  static const _shrinkWrapUpTo = 8;

  final _search = TextEditingController();
  String _query = '';
  _Filter _filter = _Filter.all;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    // After the frame: loading notifies, which isn't allowed during build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_load());
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool force = false}) =>
      context.read<PublicAchievementsStore>().loadGame(
        widget.userId,
        widget.game.gameId,
        expected: widget.game,
        force: force,
      );

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    await _load(force: true);
    if (mounted) setState(() => _refreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    final view = context.watch<PublicAchievementsStore>().gameOf(
      widget.userId,
      widget.game.gameId,
    );
    final list = view.status == LoadStatus.ready ? view.achievements : null;
    final unlocked =
        list?.where((a) => a.unlocked).length ?? widget.game.unlocked;
    final total = list?.length ?? widget.game.total;
    final size = MediaQuery.sizeOf(context);

    return Dialog(
      backgroundColor: Palette.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: math.min(size.height * 0.85, 820),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              game: widget.game,
              unlocked: unlocked,
              total: total,
              refreshing: _refreshing,
              onRefresh: view.status == LoadStatus.loading ? null : _refresh,
            ),
            if (list != null && list.isNotEmpty) _controls(list),
            Flexible(child: _body(view, list)),
          ],
        ),
      ),
    );
  }

  /// Search and the unlocked / locked filter, for a list long enough to need them.
  Widget _controls(List<Achievement> list) {
    final unlocked = list.where((a) => a.unlocked).length;
    final locked = list.length - unlocked;
    final showSearch = list.length > _shrinkWrapUpTo;
    final showFilter = unlocked > 0 && locked > 0;
    if (!showSearch && !showFilter) return const SizedBox(height: 4);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showSearch)
            TextField(
              controller: _search,
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: Palette.surfaceHigh,
                hintText: 'Search achievements',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () => setState(() {
                          _search.clear();
                          _query = '';
                        }),
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          if (showSearch && showFilter) const SizedBox(height: 10),
          if (showFilter)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (filter, label) in [
                  (_Filter.all, 'All ${list.length}'),
                  (_Filter.unlocked, 'Unlocked $unlocked'),
                  (_Filter.locked, 'Locked $locked'),
                ])
                  AppChoiceChip(
                    label: label,
                    selected: _filter == filter,
                    onSelected: () => setState(() => _filter = filter),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _body(GameAchievementsView view, List<Achievement>? list) {
    switch (view.status) {
      case LoadStatus.idle:
      case LoadStatus.loading:
        return const SizedBox(
          height: 160,
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      case LoadStatus.failed:
        return _Message(
          text: view.error ?? 'Could not load the achievements.',
          error: true,
          action: TextButton.icon(
            onPressed: () => unawaited(_load(force: true)),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Try again'),
          ),
        );
      case LoadStatus.ready:
        break;
    }

    final all = sortAchievements(list ?? const <Achievement>[]);
    if (all.isEmpty) {
      return const _Message(text: 'Steam lists no achievements for this game.');
    }
    final shown = [
      for (final a in all)
        if (_filter == _Filter.all ||
            a.unlocked == (_filter == _Filter.unlocked))
          if (_query.isEmpty ||
              a.name.toLowerCase().contains(_query) ||
              a.description.toLowerCase().contains(_query))
            a,
    ];
    final error = view.error;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Text(
              'Showing the last saved list. $error',
              style: const TextStyle(
                color: Palette.muted,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        Flexible(
          child: shown.isEmpty
              ? const _Message(text: 'No achievements match.')
              : ListView.builder(
                  shrinkWrap: all.length <= _shrinkWrapUpTo,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: shown.length,
                  itemBuilder: (_, i) => AchievementTile(achievement: shown[i]),
                ),
        ),
      ],
    );
  }
}

/// Cover, title, progress, refresh and close. Glows gold once every achievement
/// is unlocked.
class _Header extends StatelessWidget {
  const _Header({
    required this.game,
    required this.unlocked,
    required this.total,
    required this.refreshing,
    required this.onRefresh,
  });

  final GameAchievementSummary game;
  final int unlocked;
  final int total;
  final bool refreshing;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final complete = total > 0 && unlocked >= total;
    // Floor, so 99.6% never reads as 100% while something is still locked.
    final percent = total == 0
        ? 0
        : (complete ? 100 : (unlocked * 100 / total).floor());

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            (complete ? Palette.star : Palette.accent).withValues(alpha: 0.16),
            Palette.surface,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Cover(url: game.coverUrl, glow: complete),
              const SizedBox(width: 14),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    game.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      height: 1.2,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              if (refreshing)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                IconButton(
                  tooltip: 'Refresh from Steam',
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh_rounded, color: Palette.muted),
                ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Semantics(
            container: true,
            label: '$unlocked of $total achievements unlocked',
            excludeSemantics: true,
            child: Row(
              children: [
                if (complete) ...[
                  const Icon(
                    Icons.emoji_events_rounded,
                    size: 18,
                    color: Palette.star,
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    complete
                        ? 'All achievements unlocked · $unlocked / $total'
                        : '$unlocked / $total unlocked',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: complete ? Palette.star : Colors.white,
                    ),
                  ),
                ),
                Text(
                  '$percent%',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: complete ? Palette.star : Palette.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : unlocked / total,
                minHeight: 8,
                color: Palette.star,
                backgroundColor: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.url, required this.glow});

  final String? url;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    const width = 48.0;
    const height = 64.0;
    final fallback = Container(
      color: Palette.surfaceHigh,
      child: const Icon(
        Icons.sports_esports_rounded,
        size: 22,
        color: Palette.muted,
      ),
    );
    final link = url;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: glow
            ? Border.all(color: Palette.star.withValues(alpha: 0.7))
            : null,
        boxShadow: glow
            ? [
                BoxShadow(
                  color: Palette.star.withValues(alpha: 0.35),
                  blurRadius: 16,
                ),
              ]
            : const [],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: width,
          height: height,
          child: link == null || link.isEmpty
              ? fallback
              : CachedNetworkImage(
                  imageRenderMethodForWeb: ImageRenderMethodForWeb.HttpGet,
                  imageUrl: link,
                  fit: BoxFit.cover,
                  memCacheWidth: 144,
                  fadeInDuration: Duration.zero,
                  placeholder: (_, _) => fallback,
                  errorWidget: (_, _, _) => fallback,
                ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.error = false, this.action});

  final String text;
  final bool error;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: TextStyle(
              color: error ? Palette.danger : Palette.muted,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 8), action!],
        ],
      ),
    );
  }
}
