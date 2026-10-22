import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart'
    show ImageRenderMethodForWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart' show LaunchMode, launchUrl;

import 'package:checkpoint/l10n/l10n.dart';
import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/news.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/utils/formatters.dart';
import 'package:checkpoint/widgets/cover_art.dart';

/// One article: where it is from and how old it is, its headline and the start of
/// it, with its picture (or, for news about one of the member's games, that game's
/// cover) beside it. Tapping opens the outlet's own page, where the rest is read.
class NewsCard extends StatelessWidget {
  const NewsCard({super.key, required this.article, this.game});

  final NewsArticle article;

  /// The game the article is about, for the news of the member's games.
  final Game? game;

  static const double _pictureWidth = 104;
  static const double _pictureHeight = 78;

  Future<void> _open(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final message = context.l10n.newsOpenFailed;
    var opened = false;
    try {
      opened = await launchUrl(
        article.url,
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // Falls through to the message.
    }
    if (!opened) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final byline = [
      if (game != null) game!.title,
      if (article.sourceName.isNotEmpty) article.sourceName,
      timeAgo(article.publishedAt.toLocal()),
    ].join(' · ');
    return Semantics(
      button: true,
      link: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _open(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      byline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      article.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    if (article.summary.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        article.summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.textSoft,
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (game != null || article.imageUrl != null) ...[
                const SizedBox(width: 14),
                _Picture(article: article, game: game),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The article's picture, rounded, or the cover of its game.
class _Picture extends StatelessWidget {
  const _Picture({required this.article, required this.game});

  final NewsArticle article;
  final Game? game;

  @override
  Widget build(BuildContext context) {
    final game = this.game;
    if (game != null) {
      return SizedBox(
        width: NewsCard._pictureHeight * 2 / 3,
        child: CoverArt(game: game, radius: 8, showTitle: false),
      );
    }
    final palette = context.palette;
    final fallback = ColoredBox(
      color: palette.surfaceHigh,
      child: Icon(Icons.newspaper_rounded, color: palette.muted),
    );
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: NewsCard._pictureWidth,
          height: NewsCard._pictureHeight,
          child: CachedNetworkImage(
            imageRenderMethodForWeb: ImageRenderMethodForWeb.HttpGet,
            imageUrl: article.imageUrl.toString(),
            fit: BoxFit.cover,
            // The pictures are far bigger than they are drawn.
            memCacheWidth:
                (NewsCard._pictureWidth *
                        MediaQuery.devicePixelRatioOf(context))
                    .round(),
            fadeInDuration: Duration.zero,
            fadeOutDuration: Duration.zero,
            placeholder: (_, _) => fallback,
            errorWidget: (_, _, _) => fallback,
          ),
        ),
      ),
    );
  }
}
