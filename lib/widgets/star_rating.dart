import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:checkpoint/l10n/l10n.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/utils/formatters.dart';

class StarRating extends StatelessWidget {
  const StarRating({super.key, required this.rating, this.size = 16, this.onChanged});
  final double rating;
  final double size;
  final ValueChanged<double>? onChanged; // null → read-only

  double _valueAt(double dx) {
    final raw = (dx / (size * 5)) * 5;
    return ((raw * 2).ceil() / 2).clamp(0.5, 5.0).toDouble();
  }

  void _emit(double dx) {
    final v = _valueAt(dx);
    if (v != rating) {
      HapticFeedback.selectionClick();
      onChanged!(v);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stars = Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final v = rating - i;
        final icon = v >= 1
            ? Icons.star_rounded
            : (v >= 0.5 ? Icons.star_half_rounded : Icons.star_outline_rounded);
        return Icon(icon, size: size, color: v > 0 ? context.palette.star : context.palette.faint);
      }),
    );
    if (onChanged == null) {
      return Semantics(label: context.l10n.outOf5Stars(fmtHours(rating)), child: stars);
    }
    // An adjustable control for screen readers: swiping up or down (or the
    // volume keys) moves it half a star, since they can't drag across it.
    String spoken(double v) => context.l10n.outOf5Stars(fmtHours(v));
    return Semantics(
      slider: true,
      label: context.l10n.sortRating,
      value: rating > 0 ? spoken(rating) : context.l10n.notRated,
      increasedValue: spoken(math.min(5, rating + 0.5)),
      decreasedValue: spoken(math.max(0.5, rating - 0.5)),
      onIncrease: rating < 5 ? () => onChanged!(math.min(5, rating + 0.5)) : null,
      onDecrease: rating > 0.5 ? () => onChanged!(math.max(0.5, rating - 0.5)) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => _emit(d.localPosition.dx),
        onHorizontalDragUpdate: (d) => _emit(d.localPosition.dx),
        // At least 48 px tall to tap, however small the stars.
        child: SizedBox(width: size * 5, height: math.max(size, 48), child: Center(child: stars)),
      ),
    );
  }
}
