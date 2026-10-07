import 'package:flutter/material.dart';

import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/utils/navigation.dart';
import 'package:checkpoint/widgets/cover_art.dart';
import 'package:checkpoint/widgets/star_rating.dart';

/// Poster + title + stars (+ optional caption). Used in horizontal carousels.
class GamePosterCard extends StatelessWidget {
  const GamePosterCard({super.key, required this.game, required this.width, this.subtitle, this.subtitleIcon});
  final Game game;
  final double width;
  final String? subtitle;
  final IconData? subtitleIcon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => openGame(context, game.id),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          CoverArt(game: game),
          const SizedBox(height: 8),
          Text(game.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 4),
          game.rating > 0
              ? StarRating(rating: game.rating, size: 14)
              : const Text('Not rated', style: TextStyle(fontSize: 11, color: Palette.muted)),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Row(children: [
              if (subtitleIcon != null) ...[
                Icon(subtitleIcon, size: 12, color: Palette.muted),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Palette.muted)),
              ),
            ]),
          ],
        ]),
      ),
    );
  }
}
