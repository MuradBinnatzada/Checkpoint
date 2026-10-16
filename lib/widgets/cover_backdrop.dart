import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:checkpoint/models/game.dart';

/// The soft, dark, blurred cover-art backdrop behind the Home hero card and the
/// game detail header.
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

  /// IGDB serves every cover in several sizes. The small one is plenty for a
  /// backdrop that is blurred anyway, and a fraction of the download. Any other
  /// URL is used as is.
  static String _smallUrl(String url) =>
      url.replaceFirst('t_cover_big', 't_cover_small');

  @override
  Widget build(BuildContext context) {
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
}