import 'package:flutter/foundation.dart';

import 'package:checkpoint/models/game.dart';

/// One piece of game news: a headline, a short summary, a picture and a link to
/// the outlet's own page, which is where the rest is read. From an outlet's feed
/// or, with an [appId], from Steam's news for a game.
@immutable
class NewsArticle {
  const NewsArticle({
    required this.id,
    required this.title,
    required this.url,
    required this.sourceName,
    required this.publishedAt,
    this.summary = '',
    this.imageUrl,
    this.sourceId = '',
    this.appId,
  });

  final String id;
  final String title;

  /// Plain text; empty when the outlet gave none worth showing.
  final String summary;

  /// The article, on the outlet's site.
  final Uri url;
  final Uri? imageUrl;

  /// The outlet's id (what the source filter sends) and its name.
  final String sourceId;
  final String sourceName;
  final DateTime publishedAt;

  /// The Steam app the article is about, for Steam's news.
  final int? appId;

  /// One article of what `game-news` answered, or null when it has no title, no
  /// https link or no date. The other fields are optional.
  static NewsArticle? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = _text(json['id']);
    final title = _text(json['title']);
    final url = _https(json['url']);
    final published = json['published_at'];
    if (id == null || title == null || url == null) return null;
    if (published is! num || !published.isFinite || published <= 0) return null;
    final appId = json['app_id'];
    return NewsArticle(
      id: id,
      title: title,
      summary: _text(json['summary']) ?? '',
      url: url,
      imageUrl: _https(json['image_url']),
      sourceId: _text(json['source_id']) ?? '',
      sourceName: _text(json['source_name']) ?? '',
      publishedAt: DateTime.fromMillisecondsSinceEpoch(
        published.toInt() * 1000,
        isUtc: true,
      ),
      appId: appId is num && appId > 0 ? appId.toInt() : null,
    );
  }
}

/// An outlet the Latest list can be narrowed to.
@immutable
class NewsSource {
  const NewsSource(this.id, this.name);

  final String id;
  final String name;

  static NewsSource? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = _text(json['id']);
    final name = _text(json['name']);
    return id == null || name == null ? null : NewsSource(id, name);
  }
}

/// One page of the Latest list, with the outlets it can be narrowed to.
@immutable
class NewsPage {
  const NewsPage(
    this.articles, {
    this.sources = const [],
    this.hasMore = false,
  });

  final List<NewsArticle> articles;
  final List<NewsSource> sources;

  /// The page was full: another may exist.
  final bool hasMore;

  /// What `game-news` answered in feed mode, or null when it is not an answer
  /// (an `{ "error": ... }`, say). [limit] is what the page asked for.
  static NewsPage? fromResponse(Object? response, {required int limit}) {
    if (response is! Map) return null;
    final articles = response['articles'];
    if (articles is! List) return null;
    final sources = response['sources'];
    return NewsPage(
      [for (final a in articles) ?NewsArticle.fromJson(a)],
      sources: [
        if (sources is List)
          for (final s in sources) ?NewsSource.fromJson(s),
      ],
      hasMore: articles.length >= limit,
    );
  }
}

/// The Steam app ids of the games [News] can follow in a library: the games
/// that have one, the ones being played first and then the most played, at most
/// [limit] (what one `game-news` request takes).
List<int> newsAppIds(Iterable<Game> games, {int limit = 10}) {
  final withApp =
      [
        for (final g in games)
          if (g.steamAppId != null && g.inLibrary) g,
      ]..sort((a, b) {
        final playing =
            (b.status == GameStatus.playing ? 1 : 0) -
            (a.status == GameStatus.playing ? 1 : 0);
        return playing != 0 ? playing : b.hoursPlayed.compareTo(a.hoursPlayed);
      });
  return [
    for (final id in {for (final g in withApp) g.steamAppId!}.take(limit)) id,
  ];
}

String? _text(Object? value) {
  if (value is! String) return null;
  final text = value.trim();
  return text.isEmpty ? null : text;
}

/// [value] as an https address, or null.
Uri? _https(Object? value) {
  final text = _text(value);
  final uri = text == null ? null : Uri.tryParse(text);
  return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty
      ? uri
      : null;
}
