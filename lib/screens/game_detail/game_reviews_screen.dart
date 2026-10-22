import 'dart:async';

import 'package:flutter/material.dart';

import 'package:checkpoint/l10n/l10n.dart';
import 'package:checkpoint/models/game_reviews.dart';
import 'package:checkpoint/sheets/review_sheet.dart';
import 'package:checkpoint/state/auth_store.dart';
import 'package:checkpoint/state/game_reviews_store.dart';
import 'package:checkpoint/state/library_store.dart';
import 'package:checkpoint/state/load_status.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/widgets/app_choice_chip.dart';
import 'package:checkpoint/widgets/community_rating.dart';
import 'package:checkpoint/widgets/empty_state.dart';
import 'package:checkpoint/widgets/load_more_footer.dart';
import 'package:checkpoint/widgets/review_card.dart';

/// Opens every review of the game [gameId].
void openGameReviews(BuildContext context, String gameId) => unawaited(
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => GameReviewsScreen(gameId: gameId)),
  ),
);

/// All the reviews of a game: the community rating on top, then the reviews,
/// paged as the list is scrolled, in the order picked (friends first, newest,
/// highest or lowest rated), optionally only those of the members you follow.
class GameReviewsScreen extends StatefulWidget {
  const GameReviewsScreen({super.key, required this.gameId});

  final String gameId;

  @override
  State<GameReviewsScreen> createState() => _GameReviewsScreenState();
}

class _GameReviewsScreenState extends State<GameReviewsScreen> {
  @override
  void initState() {
    super.initState();
    // After the frame: loading notifies, which isn't allowed during build. The
    // list starts in the standard order each time the screen opens, and the
    // rating comes with it when the game's screen did not load it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final store = context.read<GameReviewsStore>();
      if (store.viewOf(widget.gameId).status == LoadStatus.ready) {
        unawaited(store.loadList(widget.gameId));
      } else {
        unawaited(store.load(widget.gameId));
      }
    });
  }

  void _setFilter(ReviewFilter filter) => unawaited(
    context.read<GameReviewsStore>().loadList(widget.gameId, filter: filter),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final store = context.watch<GameReviewsStore>();
    final view = store.viewOf(widget.gameId);
    final game = context.watch<LibraryStore>().maybeGame(widget.gameId);
    final isLoggedIn = context.watch<AuthStore>().isLoggedIn;
    final ready = view.listStatus == LoadStatus.ready;
    final reviews = view.reviews;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.reviews,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            if (game != null)
              Text(
                game.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: context.palette.muted),
              ),
          ],
        ),
        actions: [
          if (isLoggedIn)
            IconButton(
              tooltip: l10n.writeReview,
              icon: const Icon(Icons.rate_review_outlined),
              onPressed: () => showReviewSheet(context, widget.gameId),
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: RefreshIndicator(
            onRefresh: () => store.load(widget.gameId),
            child: CustomScrollView(
              // Pulling down refreshes even a list too short to scroll.
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                if (!view.ratings.isEmpty && view.ratings.ratings > 0)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                      child: CommunityRatingSummary(ratings: view.ratings),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: _Filters(filter: view.filter, onChanged: _setFilter),
                ),
                if (ready && reviews.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverList.separated(
                      itemCount: reviews.length,
                      separatorBuilder: (_, _) =>
                          Divider(height: 1, color: context.palette.hairline),
                      itemBuilder: (_, i) => ReviewCard(
                        key: ValueKey(reviews[i].member.id),
                        gameId: widget.gameId,
                        review: reviews[i],
                      ),
                    ),
                  )
                else
                  SliverToBoxAdapter(
                    child: _Placeholder(
                      status: view.listStatus,
                      onlyFollowing: view.filter.onlyFollowing,
                      onRetry: () => _setFilter(view.filter),
                    ),
                  ),
                if (ready &&
                    reviews.isNotEmpty &&
                    (view.hasMore || view.loadingMore || view.loadMoreFailed))
                  SliverToBoxAdapter(
                    child: LoadMoreFooter(
                      loading: view.loadingMore,
                      failed: view.loadMoreFailed,
                      onLoadMore: () =>
                          unawaited(store.loadMore(widget.gameId)),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: MediaQuery.paddingOf(context).bottom + 24,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The order, and "Following only": a row of chips that scrolls sideways.
class _Filters extends StatelessWidget {
  const _Filters({required this.filter, required this.onChanged});

  final ReviewFilter filter;
  final ValueChanged<ReviewFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          for (final sort in ReviewSort.values)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: AppChoiceChip(
                label: sort.label,
                selected: filter.sort == sort,
                onSelected: () => onChanged(filter.withSort(sort)),
              ),
            ),
          AppChoiceChip(
            label: context.l10n.reviewsFollowingOnly,
            icon: Icons.people_alt_rounded,
            selected: filter.onlyFollowing,
            onSelected: () =>
                onChanged(filter.withOnlyFollowing(!filter.onlyFollowing)),
          ),
        ],
      ),
    );
  }
}

/// What stands in for the list: a spinner while it loads, the failure with a way
/// to retry, or that there is nothing to show.
class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.status,
    required this.onlyFollowing,
    required this.onRetry,
  });

  final LoadStatus status;
  final bool onlyFollowing;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final content = switch (status) {
      LoadStatus.failed => EmptyState(
        icon: Icons.cloud_off_rounded,
        title: l10n.reviewsLoadFailed,
        message: l10n.checkConnection,
        actionLabel: l10n.tryAgain,
        onAction: onRetry,
      ),
      LoadStatus.ready => EmptyState(
        icon: Icons.rate_review_outlined,
        title: onlyFollowing ? l10n.noReviewsFollowing : l10n.noReviewsYet,
        message: onlyFollowing
            ? l10n.noReviewsFollowingMessage
            : l10n.noReviewsYetMessage,
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 320),
      child: content,
    );
  }
}
