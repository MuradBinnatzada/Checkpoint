import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:checkpoint/models/achievement.dart';
import 'package:checkpoint/models/connected_service.dart';
import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/share_link.dart';
import 'package:checkpoint/screens/game_detail/completion_time_field.dart';
import 'package:checkpoint/screens/game_detail/friends_panel.dart';
import 'package:checkpoint/screens/game_detail/igdb_sections.dart';
import 'package:checkpoint/screens/game_detail/sessions_screen.dart';
import 'package:checkpoint/screens/profile/game_achievements_dialog.dart';
import 'package:checkpoint/sheets/game_backdrop_sheet.dart';
import 'package:checkpoint/sheets/list_sheets.dart';
import 'package:checkpoint/sheets/log_hours_sheet.dart';
import 'package:checkpoint/sheets/review_sheet.dart';
import 'package:checkpoint/state/auth_store.dart';
import 'package:checkpoint/state/game_details_store.dart';
import 'package:checkpoint/state/library_store.dart';
import 'package:checkpoint/state/profile_store.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/app_theme.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/utils/formatters.dart';
import 'package:checkpoint/utils/navigation.dart';
import 'package:checkpoint/widgets/cover_art.dart';
import 'package:checkpoint/widgets/cover_backdrop.dart';
import 'package:checkpoint/widgets/empty_state.dart';
import 'package:checkpoint/widgets/panel.dart';
import 'package:checkpoint/widgets/platform_widgets.dart';
import 'package:checkpoint/widgets/share_link_button.dart';
import 'package:checkpoint/widgets/play_timer_widgets.dart';
import 'package:checkpoint/widgets/star_rating.dart';
import 'package:checkpoint/widgets/status_pill.dart';

class GameDetailScreen extends StatelessWidget {
  const GameDetailScreen({super.key, required this.gameId});
  final String gameId;

  static const double _expanded = 372;

  @override
  Widget build(BuildContext context) {
    final game = context.watch<LibraryStore>().maybeGame(gameId);
    final isLoggedIn = context.watch<AuthStore>().isLoggedIn;
    if (game == null) {
      return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.error_outline_rounded, title: 'Game not found', message: 'It may have been removed.'));
    }
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverAppBar(
          pinned: true,
          expandedHeight: _expanded,
          backgroundColor: context.palette.background,
          surfaceTintColor: Colors.transparent,
          leadingWidth: 68,
          leading: Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Center(
              child: _RoundIconButton(
                icon: Icons.arrow_back_ios_new_rounded,
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onTap: () => Navigator.maybePop(context),
              ),
            ),
          ),
          actions: [
            // Wishlist and favorite are always side by side, whatever the game's
            // status. Favoriting a game that is not in the library adds it. The
            // backdrop is saved on the library row, so it needs one.
            if (isLoggedIn) ...[
              if (canChangeBackdrop(game))
                Padding(
                  padding: const EdgeInsets.only(right: 2),
                  child: Center(
                    child: _RoundIconButton(
                      icon: Icons.wallpaper_rounded,
                      tooltip: 'Change backdrop',
                      onTap: () => showGameBackdropSheet(context, game.id),
                    ),
                  ),
                ),
              if (canShareLinks && game.igdbId != null)
                Padding(
                  padding: const EdgeInsets.only(right: 2),
                  child: Center(
                    child: _RoundIconButton(
                      icon: Icons.share_rounded,
                      tooltip: 'Copy link',
                      // The link finds the game in the catalog, so it goes there first.
                      onTap: () => copyShareLink(
                        context,
                        GameLink(game.igdbId!),
                        before: () => context.read<LibraryStore>().ensureInCatalog(game),
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(right: 2),
                child: Center(
                  child: _RoundIconButton(
                    icon: Icons.playlist_add_rounded,
                    tooltip: 'Add to list',
                    onTap: () => showAddToListSheet(context, game),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 2),
                child: Center(child: _WishlistButton(game: game)),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Center(
                  child: _RoundIconButton(
                    icon: game.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    color: game.isFavorite ? Palette.dark.danger : Colors.white,
                    tooltip: game.isFavorite ? 'Remove from favorites' : 'Add to favorites',
                    onTap: () => context.read<LibraryStore>().toggleFavorite(game.id),
                  ),
                ),
              ),
            ],
          ],
          flexibleSpace: LayoutBuilder(builder: (context, c) {
            final top = MediaQuery.paddingOf(context).top;
            final collapsed = kToolbarHeight + top;
            final t = ((c.maxHeight - collapsed) / (_expanded - kToolbarHeight)).clamp(0.0, 1.0).toDouble();
            // The header art is always laid out at its full expanded size and anchored
            // to the bottom, then clipped. That way the title/year column is never
            // squeezed into the shrinking app bar (the source of the bottom overflow).
            // The status bar's icons are light on the art, and the theme's once
            // the header has collapsed onto the page.
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: systemBarsStyle(t > 0.5 ? Palette.dark : context.palette),
              child: ClipRect(
                child: Stack(fit: StackFit.expand, children: [
                  Opacity(
                    opacity: t,
                    child: OverflowBox(
                      alignment: Alignment.bottomCenter,
                      minHeight: _expanded + top,
                      maxHeight: _expanded + top,
                      // Text on the cover art, under a dark scrim: dark in either theme.
                      child: DarkArtTheme(child: _DetailHeaderArt(game: game, topInset: top)),
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
              ),
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
                        platforms: game.playedOnOptions,
                        selected: game.playedOn,
                        onSelected: (p) => context.read<LibraryStore>().setPlayedOn(game.id, p),
                      ),
                      if (game.playedOn == null) ...[
                        const SizedBox(height: 10),
                        Text('Pick the platform you play this on. It is used in your session log and profile stats.', style: TextStyle(color: context.palette.muted, fontSize: 12.5, height: 1.35)),
                      ],
                    ]),
                  ),
                  const SizedBox(height: 14),
                  Panel(title: 'Update status', child: _StatusActions(game: game)),
                  const SizedBox(height: 14),
                  _SessionsPanel(gameId: game.id),
                  _AchievementsPanel(game: game),
                  FriendsPanel(game: game),
                  AboutPanel(game: game),
                  GameInfoSections(game: game),
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
  const _RoundIconButton({required this.icon, required this.onTap, this.color, this.tooltip});
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;
  final String? tooltip;

  /// A 40 px circle in a 48 px touch target: the space around it is part of the
  /// button, so the row of them keeps its spacing with 2 px between.
  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      iconSize: 18,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        fixedSize: const Size.square(40),
        minimumSize: const Size.square(40),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.padded,
        // Darker on the light theme, where the collapsed header leaves it on a
        // white page: the white icon still reads.
        backgroundColor: Colors.black.withValues(alpha: context.palette.isDark ? 0.38 : 0.55),
        foregroundColor: color ?? Colors.white,
      ),
    );
  }
}

/// The bookmark in the app bar. A game being played or finished has moved past
/// the wishlist, so for it the bookmark is dimmed and tapping it explains why
/// instead of changing the game's status.
class _WishlistButton extends StatelessWidget {
  const _WishlistButton({required this.game});
  final Game game;

  @override
  Widget build(BuildContext context) {
    final wishlisted = game.status == GameStatus.wishlist;
    final movedPast = game.inLibrary && !wishlisted;
    return _RoundIconButton(
      icon: wishlisted ? Icons.bookmark_rounded : Icons.bookmark_add_outlined,
      color: wishlisted
          ? GameStatus.wishlist.color
          : movedPast
              ? Colors.white38
              : Colors.white,
      tooltip: wishlisted
          ? 'Remove from wishlist'
          : movedPast
              ? 'Already in your library'
              : 'Add to wishlist',
      onTap: () => toggleWishlist(context, game),
    );
  }
}

/// How long a snack bar with an Undo stays. Flutter keeps a snack bar that has an
/// action on screen until it is dismissed, unless it says `persist: false`.
const undoSnackBarDuration = Duration(seconds: 5);

/// Puts [game] on the wishlist, or takes it off. A wishlisted game is a library
/// entry with the Wishlist status, so unlike favorites (four at most) there is no
/// limit. The snack bar can undo it. A game already in the library with another
/// status is left alone.
void toggleWishlist(BuildContext context, Game game) {
  final store = context.read<LibraryStore>();
  final messenger = ScaffoldMessenger.of(context);
  final wishlisted = game.status == GameStatus.wishlist;
  if (game.inLibrary && !wishlisted) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('${game.title} is already in your library as ${game.status!.label}')));
    return;
  }
  if (wishlisted) {
    store.removeFromLibrary(game.id);
  } else {
    store.addToLibrary(game.id, GameStatus.wishlist);
  }
  HapticFeedback.mediumImpact();
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(wishlisted ? 'Removed ${game.title} from your wishlist' : 'Added ${game.title} to your wishlist'),
      duration: undoSnackBarDuration,
      persist: false,
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () => wishlisted ? store.addToLibrary(game.id, GameStatus.wishlist) : store.removeFromLibrary(game.id),
      ),
    ));
}

class _DetailHeaderArt extends StatelessWidget {
  const _DetailHeaderArt({required this.game, required this.topInset});
  final Game game;
  final double topInset;

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: [
      // The chosen backdrop, or the blurred cover art (baked in, not a
      // BackdropFilter: see CoverBackdrop).
      CoverBackdrop(game: game),
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
                _PublisherLink(game: game),
                      if (game.hasReleaseYear) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Released ${game.releaseYear}',
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 13,
                          ),
                        ),
                      ],
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

/// The publisher under a game's title. Once IGDB gave its id (with the game's
/// details), tapping it opens the company's page.
class _PublisherLink extends StatelessWidget {
  const _PublisherLink({required this.game});
  final Game game;

  @override
  Widget build(BuildContext context) {
    final details = context.watch<GameDetailsStore>().viewOf(game.id).details;
    final id = details?.companyIds[game.publisher];
    const style = TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600);
    if (id == null) {
      return Text(game.publisher, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
    }
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => openCompany(context, id, name: game.publisher),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Flexible(child: Text(game.publisher, maxLines: 1, overflow: TextOverflow.ellipsis, style: style)),
        const Icon(Icons.chevron_right_rounded, size: 18, color: Colors.white70),
      ]),
    );
  }
}

class _ProgressPanel extends StatelessWidget {
  const _ProgressPanel({required this.game});
  final Game game;

  @override
  Widget build(BuildContext context) {
    Widget stat(String value, String label) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          Text(label, style: TextStyle(fontSize: 12, color: context.palette.muted)),
        ]);

    return Panel(
      // Stretched, so each Wrap spans the panel and its button sits on the right.
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Each row is a Wrap: with large text the button goes under, rather than
        // off the edge.
        Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 10, children: [
          game.status == null
              ? Text('Not in your library', style: TextStyle(color: context.palette.muted))
              : Wrap(spacing: 6, runSpacing: 6, children: [
                  StatusPill(game.status!),
                  if (game.status == GameStatus.completed && game.stillPlaying) const StatusPill(GameStatus.playing),
                ]),
          FilledButton.tonalIcon(
            onPressed: () => showLogHoursSheet(context, game.id),
            icon: const Icon(Icons.timer_outlined, size: 18),
            label: const Text('Log Hours'),
          ),
        ]),
        const SizedBox(height: 16),
        Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 12, runSpacing: 10, children: [
          stat('${fmtHours(game.hoursPlayed)} h', 'Played'),
          if (context.watch<AuthStore>().isLoggedIn) PlayTimerButton(game: game),
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
          ? TextButton(onPressed: () => context.read<LibraryStore>().setRating(game.id, 0), child: const Text('Clear'))
          : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        StarRating(rating: game.rating, size: 44, onChanged: (v) => context.read<LibraryStore>().setRating(game.id, v)),
        const SizedBox(height: 8),
        Text(
          game.rating > 0 ? '${fmtHours(game.rating)} / 5' : 'Tap or drag across the stars (half-stars supported)',
          style: TextStyle(color: game.rating > 0 ? context.palette.star : context.palette.muted, fontWeight: FontWeight.w600, fontSize: 13),
        ),
        if (context.watch<AuthStore>().isLoggedIn) ...[
          const SizedBox(height: 12),
          if (game.review.isEmpty)
            TextButton.icon(
              onPressed: () => showReviewSheet(context, game.id),
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              icon: const Icon(Icons.rate_review_outlined, size: 18),
              label: const Text('Add a short review'),
            )
          else
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => showReviewSheet(context, game.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Icons.format_quote_rounded, size: 18, color: context.palette.muted),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(game.review, style: const TextStyle(height: 1.4))),
                  Icon(Icons.edit_rounded, size: 16, color: context.palette.muted),
                ]),
              ),
            ),
        ],
      ]),
    );
  }
}

class _StatusActions extends StatelessWidget {
  const _StatusActions({required this.game});
  final Game game;

  @override
  Widget build(BuildContext context) {
    final store = context.read<LibraryStore>();
    final messenger = ScaffoldMessenger.of(context);

    void change(GameStatus next, String message) {
      final prev = game.status;
      final prevStillPlaying = game.stillPlaying;
      store.setStatus(game.id, next);
      HapticFeedback.mediumImpact();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(message),
          duration: undoSnackBarDuration,
          persist: false,
          action: prev == null
              ? null
              : SnackBarAction(label: 'Undo', onPressed: () => store.setStatus(game.id, prev, stillPlaying: prevStillPlaying)),
        ));
    }

    void setStillPlaying(bool value) {
      store.setStillPlaying(game.id, value);
      HapticFeedback.selectionClick();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(value ? 'Listed under Playing too' : 'No longer under Playing'),
          duration: undoSnackBarDuration,
          persist: false,
          action: SnackBarAction(label: 'Undo', onPressed: () => store.setStillPlaying(game.id, !value)),
        ));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 10, runSpacing: 10, children: [
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
          style: OutlinedButton.styleFrom(foregroundColor: context.palette.danger, side: BorderSide(color: context.palette.danger.withValues(alpha: 0.6))),
          icon: const Icon(Icons.block_rounded, size: 18),
          label: const Text('Drop'),
        ),
        // A completed game is played on with the switch below instead, so it
        // stays Completed.
        if (game.status != GameStatus.playing && game.status != GameStatus.completed)
          TextButton.icon(
            onPressed: () => change(GameStatus.playing, 'Started playing'),
            icon: const Icon(Icons.play_circle_rounded, size: 18),
            label: const Text('Start Playing'),
          ),
      ]),
      if (game.status == GameStatus.completed) ...[
        const SizedBox(height: 12),
        _StillPlayingSwitch(value: game.stillPlaying, onChanged: setStillPlaying),
      ],
      // Stays in the tree whatever the status, so it sees the game being marked
      // completed (and opens); it draws nothing for any other status.
      CompletionTimeField(game: game),
      if (game.status != null) ...[
        const SizedBox(height: 24),
        TextButton.icon(
          onPressed: () => _confirmRemove(context, game),
          style: TextButton.styleFrom(foregroundColor: context.palette.danger),
          icon: const Icon(Icons.delete_outline_rounded, size: 18),
          label: const Text('Remove from Library'),
        ),
      ]
    ]);
  }
}

/// "Still playing" for a completed game: finished, but played on (online,
/// post-game, DLC), so it is listed under Playing and on Home too while it
/// stays Completed.
class _StillPlayingSwitch extends StatelessWidget {
  const _StillPlayingSwitch({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final color = context.palette.legible(GameStatus.playing.color);
    return Material(
      color: value ? color.withValues(alpha: 0.10) : context.palette.text.withValues(alpha: 0.03),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: value ? color.withValues(alpha: 0.35) : context.palette.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        dense: true,
        contentPadding: const EdgeInsets.only(left: 14, right: 8),
        secondary: Icon(GameStatus.playing.icon, color: value ? color : context.palette.muted),
        title: const Text('Still playing', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        subtitle: Text(
          'Keep it under Playing too, for online, post-game or DLC',
          style: TextStyle(color: context.palette.muted, fontSize: 12, height: 1.3),
        ),
      ),
    );
  }
}

/// Asks before taking [game] out of the library: its play sessions are deleted
/// with it (see `deleteUserGame`), and nothing brings them back.
Future<void> _confirmRemove(BuildContext context, Game game) async {
  final store = context.read<LibraryStore>();
  final messenger = ScaffoldMessenger.of(context);
  final sessions = store.logsFor(game.id).length;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Remove ${game.title}?'),
      content: Text(
        sessions == 0
            ? 'Your status, rating and hours for it are removed. It can\'t be undone.'
            : 'Your status, rating and hours for it are removed, along with '
                '$sessions play session${sessions == 1 ? '' : 's'}. It can\'t be undone.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          style: TextButton.styleFrom(foregroundColor: context.palette.danger),
          child: const Text('Remove'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  store.removeFromLibrary(game.id);
  Navigator.maybePop(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text('Removed ${game.title} from library')));
}

class _SessionsPanel extends StatelessWidget {
  const _SessionsPanel({required this.gameId});
  final String gameId;

  static const _shown = 5;

  @override
  Widget build(BuildContext context) {
    final logs = context.watch<LibraryStore>().logsFor(gameId);
    if (logs.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Panel(
        title: 'Recent sessions',
        trailing: logs.length > _shown
            ? TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => SessionsScreen(gameId: gameId)),
                ),
                child: Text('See all ${logs.length}'),
              )
            : null,
        child: Column(children: [
          for (final l in logs.take(_shown)) SessionTile(session: l),
        ]),
      ),
    );
  }
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
  bool _loading = false;
  bool _checking = false;
  String? _error;

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
    final store = context.read<LibraryStore>();
    await store.ensureAchievementsLoaded(widget.game.id);
    if (mounted) setState(() => _checking = false);
  }

  /// Steam account connected, game in the library and played on PC or Steam
  /// Deck. The game must also be a Steam game: `steamAppId` is set (by Steam
  /// sync) on every game the Edge Function can load achievements for. The
  /// `57e40000-` id prefix covers legacy Steam-keyed rows that sync-steam hasn't
  /// adopted yet; the Edge Function still decodes the app id from those.
  bool _canLoad(BuildContext context) {
    final g = widget.game;
    return context.watch<ProfileStore>().isConnected(ConnectedService.steam) &&
        g.inLibrary &&
        (g.playedOn == GamePlatform.pc || g.playedOn == GamePlatform.steamDeck) &&
        (g.steamAppId != null || g.id.startsWith(legacySteamIdPrefix));
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final error = await context.read<LibraryStore>().syncGameAchievements(widget.game.id);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = error;
    });
  }

  Widget _errorText() => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(_error!, style: TextStyle(color: context.palette.danger, fontSize: 12.5, height: 1.35)),
      );

  Widget _checkingIndicator() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
      );

  Widget _prompt() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        'Pull your unlocked achievements for this game from Steam.',
        style: TextStyle(color: context.palette.muted, fontSize: 12.5, height: 1.35),
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

  /// The progress only; the achievements themselves open in the same dialog
  /// as on a profile, with search and the unlocked / locked filter.
  Widget _summary(List<Achievement> all, {required bool canLoad}) {
    final total = all.length;
    final unlocked = all.where((a) => a.unlocked).length;
    final complete = unlocked >= total;
    // Floor, so 99.6% never reads as 100% while something is still locked.
    final percent = complete ? 100 : (unlocked * 100 / total).floor();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
        Text('$unlocked / $total', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(width: 8),
        Text('($percent%)', style: TextStyle(color: complete ? context.palette.star : context.palette.muted, fontSize: 14, fontWeight: FontWeight.w600)),
      ]),
      const SizedBox(height: 10),
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
          value: unlocked / total,
          minHeight: 8,
          color: context.palette.star,
          backgroundColor: context.palette.track,
        ),
      ),
      const SizedBox(height: 14),
      SizedBox(
        width: double.infinity,
        child: FilledButton.tonalIcon(
          onPressed: () => showOwnGameAchievementsDialog(context, gameId: widget.game.id, canRefresh: canLoad),
          icon: const Icon(Icons.emoji_events_rounded, size: 18),
          label: const Text('Show achievements'),
        ),
      ),
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
              icon: Icon(Icons.refresh_rounded, color: context.palette.muted),
            );
    } else {
      trailing = Icon(Icons.emoji_events_outlined, color: context.palette.muted);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Panel(
        title: 'Achievements',
        trailing: trailing,
        child: achievements == null
            ? (_checking ? _checkingIndicator() : _prompt())
            : achievements.isEmpty
                ? Text(
                    'Steam lists no achievements for this game.',
                    style: TextStyle(color: context.palette.muted, fontSize: 12.5, height: 1.35),
                  )
                : _summary(achievements, canLoad: canLoad),
      ),
    );
  }
}
