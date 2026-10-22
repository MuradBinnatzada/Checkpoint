import 'package:flutter/material.dart';

import 'package:checkpoint/app/auth_gate.dart';
import 'package:checkpoint/l10n/l10n.dart';
import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/screens/game_detail/game_reviews_screen.dart';
import 'package:checkpoint/sheets/review_sheet.dart';
import 'package:checkpoint/state/auth_store.dart';
import 'package:checkpoint/state/game_reviews_store.dart';
import 'package:checkpoint/state/load_status.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/widgets/community_rating.dart';
import 'package:checkpoint/widgets/panel.dart';
import 'package:checkpoint/widgets/review_card.dart';

/// What the members think of the game: their average rating with how the stars
/// are spread, and the first few reviews, the members you follow first. The
/// rest is behind "See all". Asks when the screen opens (see [GameReviewsStore]);
/// until the answer is here, or when it fails, nothing is drawn. Signed out, it
/// asks for a login instead.
class ReviewsPanel extends StatefulWidget {
  const ReviewsPanel({super.key, required this.game});

  final Game game;

  @override
  State<ReviewsPanel> createState() => _ReviewsPanelState();
}

class _ReviewsPanelState extends State<ReviewsPanel> {
  @override
  void initState() {
    super.initState();
    _loadAfterFrame();
  }

  @override
  void didUpdateWidget(ReviewsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.game.id != widget.game.id) _loadAfterFrame();
  }

  /// After the frame: loading notifies, which isn't allowed during build.
  void _loadAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<GameReviewsStore>().load(widget.game.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (!context.watch<AuthStore>().isLoggedIn) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Panel(
          title: l10n.reviews,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.logInToReadReviewsMessage,
                style: TextStyle(color: context.palette.muted, height: 1.4),
              ),
              const SizedBox(height: 10),
              FilledButton.tonal(
                onPressed: () => logIn(context),
                child: Text(l10n.logIn),
              ),
            ],
          ),
        ),
      );
    }

    final view = context.watch<GameReviewsStore>().viewOf(widget.game.id);
    if (view.status != LoadStatus.ready) return const SizedBox.shrink();
    final ratings = view.ratings;
    final more = ratings.reviews > view.preview.length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Panel(
        title: l10n.reviews,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (ratings.ratings > 0) CommunityRatingSummary(ratings: ratings),
            if (view.preview.isEmpty)
              _NoReviews(game: widget.game, hasRatings: ratings.ratings > 0)
            else
              for (var i = 0; i < view.preview.length; i++) ...[
                if (i > 0 || ratings.ratings > 0)
                  Divider(height: 1, color: context.palette.hairline),
                ReviewCard(gameId: widget.game.id, review: view.preview[i]),
              ],
            if (more) ...[
              Divider(height: 1, color: context.palette.hairline),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => openGameReviews(context, widget.game.id),
                  child: Text(l10n.readAllReviews(ratings.reviews)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Nobody wrote a review yet: says so, and asks the member to be the first.
class _NoReviews extends StatelessWidget {
  const _NoReviews({required this.game, required this.hasRatings});

  final Game game;
  final bool hasRatings;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: EdgeInsets.only(top: hasRatings ? 14 : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.noReviewsYet,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            l10n.noReviewsYetMessage,
            style: TextStyle(color: context.palette.muted, height: 1.4),
          ),
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            onPressed: () => showReviewSheet(context, game.id),
            icon: const Icon(Icons.rate_review_outlined, size: 18),
            label: Text(l10n.writeReview),
          ),
        ],
      ),
    );
  }
}
