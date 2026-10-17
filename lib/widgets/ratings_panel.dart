import 'package:flutter/material.dart';

import 'package:checkpoint/models/library_stats.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/utils/formatters.dart';
import 'package:checkpoint/widgets/panel.dart';
import 'package:checkpoint/widgets/star_rating.dart';

/// How a member rates their games: the average on the left and, on the right, one
/// bar per rating from half a star to five, as tall as the number of games given
/// that rating.
class RatingsPanel extends StatelessWidget {
  const RatingsPanel({super.key, required this.stats});

  final LibraryStats stats;

  static const double _barAreaHeight = 76;

  @override
  Widget build(BuildContext context) {
    if (stats.ratedCount == 0) {
      return const Panel(
        title: 'Ratings',
        child: Text(
          'No rated games yet.',
          style: TextStyle(color: Palette.muted, fontSize: 13),
        ),
      );
    }
    final steps = LibraryStats.ratingSteps;
    final tallest = steps
        .map((r) => stats.ratingCounts[r] ?? 0)
        .reduce((a, b) => a > b ? a : b);

    return Panel(
      title: 'Ratings',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stats.averageRating.toStringAsFixed(1),
                  style: const TextStyle(
                    fontSize: 34,
                    height: 1.05,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                StarRating(
                  rating: (stats.averageRating * 2).round() / 2,
                  size: 13,
                ),
                const SizedBox(height: 6),
                Text(
                  '${stats.ratedCount} rated',
                  style: const TextStyle(color: Palette.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              children: [
                SizedBox(
                  height: _barAreaHeight + 16,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final r in steps)
                        Expanded(
                          child: _Bar(
                            rating: r,
                            count: stats.ratingCounts[r] ?? 0,
                            tallest: tallest,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [_AxisLabel('½'), _AxisLabel('5')],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "½ ★" / "5 ★" under the ends of the chart. The star is an icon: the ★
/// character is missing from some fonts.
class _AxisLabel extends StatelessWidget {
  const _AxisLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text, style: const TextStyle(color: Palette.muted, fontSize: 11)),
        const SizedBox(width: 1),
        const Icon(Icons.star_rounded, size: 11, color: Palette.muted),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.rating,
    required this.count,
    required this.tallest,
  });

  final double rating;
  final int count;
  final int tallest;

  @override
  Widget build(BuildContext context) {
    final height = count == 0
        ? 3.0
        : 6 + (RatingsPanel._barAreaHeight - 6) * count / tallest;
    return Semantics(
      label:
          '${fmtHours(rating)} stars: $count ${count == 1 ? 'game' : 'games'}',
      excludeSemantics: true,
      child: Tooltip(
        message: '${fmtHours(rating)} stars · $count',
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            SizedBox(
              height: 14,
              child: count == 0
                  ? null
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '$count',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Palette.muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 2),
            Container(
              height: height,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: count == 0
                    ? Colors.white10
                    : Palette.star.withValues(
                        alpha: 0.35 + 0.65 * count / tallest,
                      ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(4),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
