import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:checkpoint/models/game.dart';

/// The backdrop behind the Home hero card and the game detail header: the
/// member's chosen backdrop ([Game.customBackdropUrl], an IGDB artwork or
/// screenshot) when they picked one, else the soft, dark, blurred cover art.
///
/// The blur is baked in: the cover is decoded at a tiny size and scaled back up
/// smoothly, so there is no runtime `BackdropFilter` / `ImageFilter.blur`.
/// A BackdropFilter blurs "whatever is already painted behind it", and Android's
/// stretch overscroll (pulling past the top of a list) re-renders the list
/// through a transformed offscreen layer. That left the blur half-applied: a
/// patch of sharp art next to a dark smudge. A plain image has nothing to go wrong
/// there, and it is far cheaper to paint than a sigma-30 blur on every card.
///
/// Fills the space it is given (put it first in a `Stack(fit: StackFit.expand)`).
class CoverBackdrop extends StatelessWidget {
  const CoverBackdrop({super.key, required this.game, this.scrim = 0.6});

  final Game game;

  /// Opacity of the black layer that keeps text drawn on top legible.
  final double scrim;

  /// Decode width in pixels. Deliberately tiny: this *is* the blur.
  static const _decodeWidth = 24;

  /// Widest a chosen backdrop is decoded: a phone screen's width in pixels, and
  /// less than the 1920 px IGDB serves.
  static const _artDecodeWidth = 1280;

  /// IGDB serves every cover in several sizes. The small one is plenty for a
  /// backdrop that is blurred anyway, and a fraction of the download. Any other
  /// URL is used as is.
  static String _smallUrl(String url) =>
      url.replaceFirst('t_cover_big', 't_cover_small');

  @override
  Widget build(BuildContext context) {
    final art = game.customBackdropUrl;
    if (art != null && art.isNotEmpty) return _art(art);

    final url = game.coverUrl;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (url != null && url.isNotEmpty)
          ExcludeSemantics(
            child: CachedNetworkImage(
              imageUrl: _smallUrl(url),
              fit: BoxFit.cover,
              memCacheWidth: _decodeWidth,
              filterQuality: FilterQuality.high, // smooth (bicubic) upscale = the blur
              fadeInDuration: const Duration(milliseconds: 300),
              fadeOutDuration: Duration.zero,
              errorWidget: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        ColoredBox(color: Colors.black.withValues(alpha: scrim)),
      ],
    );
  }

  /// The chosen backdrop, sharp. The scrim is a gradient rather than one flat
  /// layer, so the art shows through in the middle while the buttons at the top
  /// and the text at the bottom stay legible. While it loads (or offline), the
  /// blurred cover stands in.
  Widget _art(String url) {
    return Stack(
      fit: StackFit.expand,
      children: [
        CoverBackdrop(game: game.withBackdrop(null), scrim: scrim),
        ExcludeSemantics(
          child: CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            memCacheWidth: _artDecodeWidth,
            fadeInDuration: const Duration(milliseconds: 300),
            fadeOutDuration: Duration.zero,
            errorWidget: (_, _, _) => const SizedBox.shrink(),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: scrim * 0.8),
                Colors.black.withValues(alpha: scrim * 0.5),
                Colors.black.withValues(alpha: (scrim * 1.4).clamp(0.0, 0.92).toDouble()),
              ],
              stops: const [0, 0.45, 1],
            ),
          ),
        ),
      ],
    );
  }
}
