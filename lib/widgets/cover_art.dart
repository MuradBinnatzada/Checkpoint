import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart' show ImageRenderMethodForWeb;
import 'package:flutter/material.dart';

import 'package:checkpoint/models/game.dart';

/// Poster art (2:3). Loads the catalog cover when present; the gradient + glyph
/// underneath is the loading / offline fallback.
class CoverArt extends StatelessWidget {
  const CoverArt({super.key, required this.game, this.radius = 12, this.showTitle = true, this.memCacheWidth = 300});
  final Game game;
  final double radius;

  /// Widest the cover is decoded into memory, in pixels. Every poster in the app
  /// is drawn well under 150 logical px wide, so 300 is plenty and keeps a large
  /// source image from being decoded at full size. (IGDB's `t_cover_big` is only
  /// 264 px wide, so today this is a ceiling rather than a saving.)
  final int memCacheWidth;

  /// Whether the title may be drawn over the poster. Even when true, the title
  /// is only a stand-in for missing art: it is never drawn over a game that has
  /// a catalog cover URL.
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 2 / 3,
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth;
        final hasCover = game.coverUrl?.isNotEmpty ?? false;
        final titleAllowed = showTitle && !hasCover;
        final drawTitle = titleAllowed && w >= 84;
        return ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Stack(fit: StackFit.expand, children: [
            // 1 · fallback (visible while loading or offline)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: game.coverColors,
                ),
              ),
            ),
            Positioned(
              right: -w * 0.18,
              top: w * 0.10,
              child: Icon(game.coverIcon, size: w * 0.95, color: Colors.white.withValues(alpha: 0.14)),
            ),
            if (!drawTitle) Center(child: Icon(game.coverIcon, size: w * 0.5, color: Colors.white70)),

            // 2 · network poster, fades in over the fallback. Cached on disk, so
            // covers aren't re-downloaded on every launch.
            if (game.coverUrl case final url? when url.isNotEmpty)
              CachedNetworkImage(
                // Web: download + decode in Flutter. The default <img> path renders blank
                // after scrolling on iOS Safari (GPU textures get dropped).
                imageRenderMethodForWeb: ImageRenderMethodForWeb.HttpGet,
                imageUrl: url,
                fit: BoxFit.cover,
                memCacheWidth: memCacheWidth,
                fadeInDuration: const Duration(milliseconds: 300),
                fadeOutDuration: Duration.zero,
                errorWidget: (_, _, _) => const SizedBox.shrink(), // keep fallback
              ),

            // 3 · scrim + title (the scrim only exists to keep the title legible)
            if (titleAllowed)
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xB3000000)],
                    stops: [0.45, 1],
                  ),
                ),
              ),
            if (drawTitle)
              Positioned(
                left: w * 0.08,
                right: w * 0.08,
                bottom: w * 0.08,
                child: Text(
                  game.title.toUpperCase(),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    height: 1.1,
                    fontSize: (w * 0.105).clamp(8.0, 18.0).toDouble(),
                    shadows: const [Shadow(color: Colors.black87, blurRadius: 6)],
                  ),
                ),
              ),
          ]),
        );
      }),
    );
  }
}