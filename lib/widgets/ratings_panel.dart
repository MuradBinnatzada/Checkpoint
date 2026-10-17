import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:checkpoint/models/library_stats.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/widgets/panel.dart';
import 'package:checkpoint/widgets/star_rating.dart';

/// How a member rates their games: the average on the left and, on the right, one
/// bar per rating from one star to five, as tall as the number of games given
/// that rating. The counts stay hidden until a bar is tapped; then it lights up
/// and a bubble over it shows the stars and how many games have them.
class RatingsPanel extends StatefulWidget {
  const RatingsPanel({super.key, required this.stats});

  final LibraryStats stats;

  static const double _barAreaHeight = 76;

  /// Room above the bars for the bubble.
  static const double _bubbleHeight = 26;

  /// The bars, lowest first: half-star steps from one star to five. A rating of
  /// half a star is rare, so it shares the first bar instead of getting a sliver
  /// of its own (the axis starts at 1).
  static const List<double> bars = [1, 1.5, 2, 2.5, 3, 3.5, 4, 4.5, 5];

  /// Games with the rating of [bar]; the first bar also holds the half-star ones.
  static int countFor(LibraryStats stats, double bar) {
    final counts = stats.ratingCounts;
    return (counts[bar] ?? 0) + (bar == bars.first ? (counts[0.5] ?? 0) : 0);
  }

  @override
  State<RatingsPanel> createState() => _RatingsPanelState();
}

class _RatingsPanelState extends State<RatingsPanel> {
  /// The bar that was tapped, if any.
  double? _selected;

  void _tap(double bar) {
    HapticFeedback.selectionClick();
    setState(() => _selected = _selected == bar ? null : bar);
  }

  @override
  Widget build(BuildContext context) {
    final stats = widget.stats;
    if (stats.ratedCount == 0) {
      return const Panel(
        title: 'Ratings',
        child: Text(
          'No rated games yet.',
          style: TextStyle(color: Palette.muted, fontSize: 13),
        ),
      );
    }
    const bars = RatingsPanel.bars;
    final tallest = bars
        .map((r) => RatingsPanel.countFor(stats, r))
        .reduce((a, b) => a > b ? a : b);
    final selected = _selected;

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
                  height:
                      RatingsPanel._bubbleHeight + RatingsPanel._barAreaHeight,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            for (final r in bars)
                              Expanded(
                                child: _Bar(
                                  rating: r,
                                  count: RatingsPanel.countFor(stats, r),
                                  tallest: tallest,
                                  selected: selected == r,
                                  onTap: () => _tap(r),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (selected != null)
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          height: RatingsPanel._bubbleHeight,
                          // Centered over its bar, but never out of the chart.
                          child: IgnorePointer(
                            child: Align(
                              alignment: Alignment(
                                2 *
                                        (bars.indexOf(selected) + 0.5) /
                                        bars.length -
                                    1,
                                0,
                              ),
                              child: _Bubble(
                                rating: selected,
                                count: RatingsPanel.countFor(stats, selected),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [_AxisLabel('1'), _AxisLabel('5')],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "1 ★" / "5 ★" under the ends of the chart. The star is an icon: the ★
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

/// What the tapped bar stands for: its stars and how many games have them.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.rating, required this.count});

  final double rating;
  final int count;

  @override
  Widget build(BuildContext context) {
    final orLess = rating == RatingsPanel.bars.first;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Palette.surfaceHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Only the first bar spans two ratings (½ and 1).
            if (orLess)
              const Padding(
                padding: EdgeInsets.only(right: 3),
                child: Text(
                  '≤',
                  style: TextStyle(color: Palette.muted, fontSize: 12),
                ),
              ),
            StarRating(rating: rating, size: 11),
            const SizedBox(width: 6),
            Text(
              '$count ${count == 1 ? 'game' : 'games'}',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.rating,
    required this.count,
    required this.tallest,
    required this.selected,
    required this.onTap,
  });

  final double rating;
  final int count;
  final int tallest;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final height = count == 0
        ? 3.0
        : 6 + (RatingsPanel._barAreaHeight - 6) * count / tallest;
    final Color color;
    if (count == 0) {
      color = selected ? Colors.white38 : Colors.white10;
    } else if (selected) {
      color = Palette.star;
    } else {
      color = Palette.star.withValues(alpha: 0.35 + 0.65 * count / tallest);
    }
    final stars = rating == RatingsPanel.bars.first
        ? '1 star or less'
        : '${rating == rating.roundToDouble() ? rating.toInt() : rating} stars';
    return Semantics(
      button: true,
      selected: selected,
      label: '$stars: $count ${count == 1 ? 'game' : 'games'}',
      excludeSemantics: true,
      onTap: onTap,
      // The whole column is the target, so a one-game bar is as easy to hit as a
      // tall one.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            height: height,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: color,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(4),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
