import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:checkpoint/models/browse.dart';
import 'package:checkpoint/state/auth_store.dart';
import 'package:checkpoint/state/browse_store.dart';
import 'package:checkpoint/state/library_store.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/utils/formatters.dart';
import 'package:checkpoint/widgets/empty_state.dart';
import 'package:checkpoint/widgets/game_poster_card.dart';
import 'package:checkpoint/widgets/load_more_footer.dart';

/// One "Browse by" list as a grid of posters: the games [BrowseStore] holds for
/// [mode], loaded when the screen opens (unless they are already there and fresh)
/// and paged as the grid is scrolled. Pull down to fetch the list again.
class BrowseResultsScreen extends StatefulWidget {
  const BrowseResultsScreen({super.key, required this.mode});

  final BrowseMode mode;

  @override
  State<BrowseResultsScreen> createState() => _BrowseResultsScreenState();
}

class _BrowseResultsScreenState extends State<BrowseResultsScreen> {
  static const _gutter = 20.0;
  static const _spacing = 12.0;

  /// Posters are laid out at about this width, at least 3 to a row.
  static const _targetCellWidth = 140.0;

  @override
  void initState() {
    super.initState();
    // Starting a load notifies listeners, which can't happen while the route is
    // still being built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(context.read<BrowseStore>().load(widget.mode));
    });
  }

  @override
  Widget build(BuildContext context) {
    final mode = widget.mode;
    final store = context.watch<BrowseStore>();
    return Scaffold(
      appBar: AppBar(title: Text(mode.label)),
      body: store.entries(mode).isEmpty ? _buildWithoutGames(store) : _buildGrid(store),
    );
  }

  /// Nothing to show yet: loading, or why there is nothing.
  Widget _buildWithoutGames(BrowseStore store) {
    final mode = widget.mode;
    final loggedIn = context.watch<AuthStore>().isLoggedIn;
    if (store.hasFailed(mode)) {
      // The Edge Function answers signed-in users only, so a retry can't help a guest.
      return loggedIn
          ? EmptyState(
              icon: Icons.cloud_off_rounded,
              title: 'Couldn’t load games',
              message: 'Check your connection and try again.',
              actionLabel: 'Try again',
              onAction: () => unawaited(store.refresh(mode)),
            )
          : EmptyState(
              icon: Icons.lock_outline_rounded,
              title: 'Log in to browse games',
              message: 'Game lists come from IGDB, which Checkpoint only reaches for signed-in users.',
              actionLabel: 'Log in',
              onAction: context.read<AuthStore>().logIn,
            );
    }
    if (store.isLoaded(mode) && !store.isLoading(mode)) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: 'Nothing to show',
        message: 'IGDB returned no games for this list.',
        actionLabel: 'Try again',
        onAction: () => unawaited(store.refresh(mode)),
      );
    }
    return const Center(child: CircularProgressIndicator());
  }

  Widget _buildGrid(BrowseStore store) {
    final mode = widget.mode;
    final entries = store.entries(mode);
    // The user's own copy (status, stars) wins over the catalog's for games in
    // their library.
    final library = context.watch<LibraryStore>();
    final showFooter = store.hasMore(mode) || store.isLoadingMore(mode) || store.loadMoreFailed(mode);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return RefreshIndicator(
      onRefresh: () => store.refresh(mode),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = math.max(3, (constraints.maxWidth / _targetCellWidth).floor());
          final cellWidth = (constraints.maxWidth - 2 * _gutter - (columns - 1) * _spacing) / columns;
          return CustomScrollView(
            // Pull-to-refresh also has to work for a list too short to scroll.
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(_gutter, 12, _gutter, 0),
                sliver: SliverGrid.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: _spacing,
                    mainAxisSpacing: 16,
                    mainAxisExtent: posterCardHeight(context, cellWidth, subtitle: true),
                  ),
                  itemCount: entries.length,
                  itemBuilder: (_, i) {
                    final entry = entries[i];
                    final caption = _caption(entry);
                    return GamePosterCard(
                      game: library.maybeGame(entry.game.id) ?? entry.game,
                      width: cellWidth,
                      subtitle: caption?.text,
                      subtitleIcon: caption?.icon,
                      showUnrated: false,
                    );
                  },
                ),
              ),
              if (showFooter)
                SliverToBoxAdapter(
                  child: LoadMoreFooter(
                    loading: store.isLoadingMore(mode),
                    failed: store.loadMoreFailed(mode),
                    onLoadMore: () => unawaited(store.loadMore(mode)),
                  ),
                ),
              SliverToBoxAdapter(child: SizedBox(height: bottomInset + 24)),
            ],
          );
        },
      ),
    );
  }

  /// The line under a poster: the figure the list is about.
  ({String text, IconData icon})? _caption(BrowseEntry entry) {
    switch (widget.mode) {
      case BrowseMode.popular:
        final genre = entry.game.genres.firstOrNull;
        return genre == null ? null : (text: genre, icon: Icons.category_rounded);
      case BrowseMode.topRated:
        final score = entry.score;
        return score == null ? null : (text: '${score.round()} / 100', icon: Icons.star_rounded);
      case BrowseMode.newReleases:
        final released = entry.releaseDate;
        return released == null ? null : (text: fmtMonthDay(released), icon: Icons.event_rounded);
    }
  }
}
