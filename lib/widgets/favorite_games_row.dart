import 'package:flutter/material.dart';

import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/utils/navigation.dart';
import 'package:checkpoint/widgets/cover_art.dart';

/// A member's favorite games as covers in a row. It always lays out four equal
/// slots, so the covers keep the same size whether there is one favorite or four.
class FavoriteGamesRow extends StatelessWidget {
  const FavoriteGamesRow({super.key, required this.games});

  static const int slots = 4;

  final List<Game> games;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < slots; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: i < games.length
                ? Semantics(
                    button: true,
                    label: games[i].title,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => openGame(context, games[i].id),
                      child: CoverArt(game: games[i]),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ],
    );
  }
}
