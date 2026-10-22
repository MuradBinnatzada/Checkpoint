import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import 'package:checkpoint/app/auth_gate.dart';
import 'package:checkpoint/l10n/l10n.dart';
import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/news.dart';
import 'package:checkpoint/state/auth_store.dart';
import 'package:checkpoint/state/library_store.dart';
import 'package:checkpoint/state/load_status.dart';
import 'package:checkpoint/state/news_store.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/widgets/app_choice_chip.dart';
import 'package:checkpoint/widgets/empty_state.dart';
import 'package:checkpoint/widgets/load_more_footer.dart';
import 'package:checkpoint/widgets/news_card.dart';

/// Opens the News screen.
void openNews(BuildContext context) => unawaited(
  Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const NewsScreen())),
);

enum _NewsTab { latest, myGames }

/// Game news. Latest is what the gaming outlets published, from all of them or
/// one, whatever the member plays; My games is what Steam has on the games of
/// their library that came from it. Each article opens on its outlet's own page.
class NewsScreen extends StatefulWidget {
  const NewsScreen({super.key});

  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen> {
  _NewsTab _tab = _NewsTab.latest;

  @override
  void initState() {
    super.initState();
    // After the frame: loading notifies, which isn't allowed during build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(context.read<NewsStore>().loadLatest());
    });
  }

  /// The news of the active tab, asked for again (the screen's pull to refresh).
  Future<void> _refresh() {
    final store = context.read<NewsStore>();
    return _tab == _NewsTab.latest
        ? store.loadLatest(force: true)
        : store.loadMyGames(
            newsAppIds(context.read<LibraryStore>().libraryGames),
            force: true,
          );
  }

  void _select(_NewsTab tab) {
    setState(() => _tab = tab);
    // My games asks for its own news when it is built.
    if (tab == _NewsTab.latest) {
      unawaited(context.read<NewsStore>().loadLatest());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.gameNews)),
      body: !context.watch<AuthStore>().isLoggedIn
          ? EmptyState(
              icon: Icons.lock_outline_rounded,
              title: l10n.logInToReadNews,
              message: l10n.logInToReadNewsMessage,
              actionLabel: l10n.logIn,
              onAction: () => logIn(context),
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                      child: SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<_NewsTab>(
                          showSelectedIcon: false,
                          segments: [
                            ButtonSegment(
                              value: _NewsTab.latest,
                              icon: const Icon(Icons.newspaper_rounded),
                              label: Text(l10n.newsLatest),
                            ),
                            ButtonSegment(
                              value: _NewsTab.myGames,
                              icon: const Icon(Icons.sports_esports_rounded),
                              label: Text(l10n.newsMyGames),
                            ),
                          ],
                          selected: {_tab},
                          onSelectionChanged: (s) => _select(s.first),
                          style: SegmentedButton.styleFrom(
                            backgroundColor: palette.surfaceHigh,
                            foregroundColor: palette.textSoft,
                            selectedBackgroundColor: palette.accent,
                            selectedForegroundColor: palette.onAccent,
                            side: BorderSide(color: palette.outline),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: _tab == _NewsTab.latest
                          ? _Latest(onRefresh: _refresh)
                          : _MyGames(onRefresh: _refresh),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// The outlets' latest articles, with a row of chips to narrow them to one outlet.
class _Latest extends StatelessWidget {
  const _Latest({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final store = context.watch<NewsStore>();
    final articles = store.latest;
    final ready = store.latestStatus == LoadStatus.ready;

    Widget body;
    if (ready && articles.isNotEmpty) {
      body = _ArticleList(
        articles: articles,
        onRefresh: onRefresh,
        hasMore: store.hasMore,
        loadingMore: store.loadingMore,
        loadMoreFailed: store.loadMoreFailed,
        onLoadMore: () => unawaited(store.loadMoreLatest()),
      );
    } else if (ready) {
      body = EmptyState(
        icon: Icons.newspaper_rounded,
        title: l10n.noNewsYet,
        message: l10n.noNewsYetMessage,
      );
    } else if (store.latestStatus == LoadStatus.failed) {
      body = EmptyState(
        icon: Icons.cloud_off_rounded,
        title: l10n.newsLoadFailed,
        message: l10n.checkConnection,
        actionLabel: l10n.tryAgain,
        onAction: () => unawaited(store.loadLatest(force: true)),
      );
    } else {
      body = const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (store.sources.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: AppChoiceChip(
                    label: l10n.newsAllOutlets,
                    selected: store.sourceId == null,
                    onSelected: () => unawaited(store.setSource(null)),
                  ),
                ),
                for (final source in store.sources)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: AppChoiceChip(
                      label: source.name,
                      selected: store.sourceId == source.id,
                      onSelected: () => unawaited(store.setSource(source.id)),
                    ),
                  ),
              ],
            ),
          ),
        Expanded(child: body),
      ],
    );
  }
}

/// Steam's news for the games of the member's library, each with its game's cover.
class _MyGames extends StatefulWidget {
  const _MyGames({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  State<_MyGames> createState() => _MyGamesState();
}

class _MyGamesState extends State<_MyGames> {
  /// The games the news was last asked for.
  List<int>? _asked;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Runs again when the library changes (it loaded, a game was added): ask for
    // the news of the games it has now. After the frame, as loading notifies.
    final ids = newsAppIds(context.watch<LibraryStore>().libraryGames);
    if (listEquals(ids, _asked)) return;
    _asked = ids;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(context.read<NewsStore>().loadMyGames(ids));
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final store = context.watch<NewsStore>();
    final library = context.watch<LibraryStore>().libraryGames;
    final appIds = newsAppIds(library);
    final byApp = <int, Game>{
      for (final g in library)
        if (g.steamAppId != null) g.steamAppId!: g,
    };

    if (appIds.isEmpty) {
      return EmptyState(
        icon: Icons.sports_esports_rounded,
        title: l10n.noSteamNewsTitle,
        message: l10n.noSteamNewsMessage,
      );
    }
    return switch (store.myGamesStatus) {
      LoadStatus.ready when store.myGames.isEmpty => EmptyState(
        icon: Icons.newspaper_rounded,
        title: l10n.newsMyGamesQuiet,
        message: l10n.newsMyGamesQuietMessage,
      ),
      LoadStatus.ready => _ArticleList(
        articles: store.myGames,
        gameOf: (a) => byApp[a.appId],
        onRefresh: widget.onRefresh,
      ),
      LoadStatus.failed => EmptyState(
        icon: Icons.cloud_off_rounded,
        title: l10n.newsLoadFailed,
        message: l10n.checkConnection,
        actionLabel: l10n.tryAgain,
        onAction: () => unawaited(store.loadMyGames(appIds, force: true)),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

/// A scrolling list of articles, paged when [hasMore], pulled down to refresh.
class _ArticleList extends StatelessWidget {
  const _ArticleList({
    required this.articles,
    required this.onRefresh,
    this.gameOf,
    this.hasMore = false,
    this.loadingMore = false,
    this.loadMoreFailed = false,
    this.onLoadMore,
  });

  final List<NewsArticle> articles;
  final Future<void> Function() onRefresh;
  final Game? Function(NewsArticle article)? gameOf;
  final bool hasMore;
  final bool loadingMore;
  final bool loadMoreFailed;
  final VoidCallback? onLoadMore;

  @override
  Widget build(BuildContext context) {
    final footer = hasMore || loadingMore || loadMoreFailed;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          MediaQuery.paddingOf(context).bottom + 24,
        ),
        itemCount: articles.length + (footer ? 1 : 0),
        separatorBuilder: (_, _) =>
            Divider(height: 1, color: context.palette.hairline),
        itemBuilder: (_, i) {
          if (i < articles.length) {
            return NewsCard(
              key: ValueKey(articles[i].id),
              article: articles[i],
              game: gameOf?.call(articles[i]),
            );
          }
          return LoadMoreFooter(
            loading: loadingMore,
            failed: loadMoreFailed,
            onLoadMore: onLoadMore,
          );
        },
      ),
    );
  }
}
