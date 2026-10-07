import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
        return Icon(icon, size: size, color: v > 0 ? Palette.star : Colors.white24);
      }),
    );
    if (onChanged == null) {
      return Semantics(label: '${fmtHours(rating)} out of 5 stars', child: stars);
    }
    return Semantics(
      label: 'Rating ${fmtHours(rating)} out of 5',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => _emit(d.localPosition.dx),
        onHorizontalDragUpdate: (d) => _emit(d.localPosition.dx),
        child: SizedBox(width: size * 5, height: size, child: stars),
      ),
    );
  }
}
