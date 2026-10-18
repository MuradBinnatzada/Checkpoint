import 'dart:async';
import 'package:flutter/material.dart';

import 'package:checkpoint/models/browse.dart';
import 'package:checkpoint/models/filter_options.dart';
import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/social_user.dart';
import 'package:checkpoint/screens/search/browse_results_screen.dart';
import 'package:checkpoint/state/auth_store.dart';
import 'package:checkpoint/state/library_store.dart';
import 'package:checkpoint/state/profile_store.dart';
import 'package:checkpoint/state/search_store.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/utils/formatters.dart';
import 'package:checkpoint/utils/navigation.dart';
import 'package:checkpoint/widgets/cover_art.dart';
import 'package:checkpoint/widgets/empty_state.dart';
import 'package:checkpoint/widgets/filter_sheet.dart';
import 'package:checkpoint/widgets/load_more_footer.dart';
import 'package:checkpoint/widgets/member_tile.dart';
import 'package:checkpoint/widgets/status_pill.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

enum SearchKind { games, users }

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  final _searchFocus = FocusNode();
  String _query = '';
  SearchKind _kind = SearchKind.games;
  Timer? _debounce;
  late final SearchStore _store;
  late int _searchBoxResets;

  @override
  void initState() {
    super.initState();
    // Focus decides between the Recent Searches and Browse By states.
    _searchFocus.addListener(_onFocusChanged);
    _store = context.read<SearchStore>(); // non-subscribing lookup is allowed in initState
    _searchBoxResets = _store.searchBoxResets;
    _store.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    _searchFocus.removeListener(_onFocusChanged);
    _searchFocus.dispose();
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  /// The search was dropped from outside: replaced by a list of games matching
  /// filters (a tag tapped on a game's screen), or the tab was left. Empty the
  /// box, so it shows what the results are for, not text whose results are gone.
  void _onStoreChanged() {
    if (_store.searchBoxResets == _searchBoxResets) return;
    _searchBoxResets = _store.searchBoxResets;
    _debounce?.cancel();
    _controller.clear();
    _searchFocus.unfocus();
    setState(() {
      _query = '';
      _kind = SearchKind.games;
    });
  }

  /// The box was emptied: with filters picked, list the games matching them;
  /// without, drop the previous results so they can't flash back.
  void _onQueryEmptied(SearchStore store) {
    if (store.activeFilters.isEmpty) {
      store.clearSearch();
    } else {
      unawaited(store.searchExternalGames(''));
    }
  }

  void _onQueryChanged(String v) {
    final store = context.read<SearchStore>();
    setState(() => _query = v);
    if (v.trim().isEmpty) _onQueryEmptied(store);
    _debounce?.cancel();
    if (_kind == SearchKind.games) {
      // Results follow the typing, half-typed words included (the server
      // matches the start of title words). Only a finished search is
      // remembered: one submitted, or one whose result was picked.
      _debounce = Timer(const Duration(milliseconds: 400), () {
        final term = v.trim();
        // A space after a word changes nothing to look up.
        if (term.isEmpty || term == store.searchTerm) return;
        unawaited(store.searchExternalGames(term, remember: false));
      });
    } else {
      // Members are searched on the server, so wait for a pause in typing. An
      // emptied box goes back to the "Suggested people" list.
      _debounce = Timer(const Duration(milliseconds: 350), () {
        unawaited(store.findUsers(v));
      });
    }
  }

  /// Keyboard "search" key: don't wait for the debounce.
  void _submitSearch(String v) {
    if (_kind == SearchKind.games && v.trim().isEmpty) return;
    _debounce?.cancel();
    final store = context.read<SearchStore>();
    if (_kind == SearchKind.games) {
      store.searchExternalGames(v);
    } else {
      unawaited(store.findUsers(v));
    }
  }

  /// Clears the box and puts the cursor back in it, which brings up Recent Searches.
  void _clearQuery() {
    _debounce?.cancel();
    _controller.clear();
    setState(() => _query = '');
    final store = context.read<SearchStore>();
    _onQueryEmptied(store);
    if (_kind == SearchKind.users) unawaited(store.findUsers(''));
    _searchFocus.requestFocus();
  }

  /// Opens the filter sheet, and searches again with what it picked.
  Future<void> _openFilters() async {
    _searchFocus.unfocus();
    final picked = await showDiscoverFilterSheet(
      context,
      initial: context.read<SearchStore>().activeFilters,
      searching: _query.trim().isNotEmpty,
    );
    if (picked != null && mounted) _applyFilters(picked);
  }

  /// Narrows the games down by [filters], for what is in the box now: a search
  /// still waiting on the typing pause starts at once.
  void _applyFilters(FilterOptions filters) {
    _debounce?.cancel();
    final store = context.read<SearchStore>();
    final term = _query.trim();
    if (term == store.searchTerm) {
      unawaited(store.setFilter(filters));
    } else {
      unawaited(store.setFilter(filters, triggerSearch: false));
      unawaited(store.searchExternalGames(term, remember: false));
    }
  }

  /// Tapping a recent search fills the box and runs it right away.
  void _runRecentSearch(String query) {
    _debounce?.cancel();
    _controller.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
    setState(() => _query = query);
    _searchFocus.unfocus();
    context.read<SearchStore>().searchExternalGames(query);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<SearchStore>();
    final isUsers = _kind == SearchKind.users;
    final hasQuery = _query.trim().isNotEmpty;
    final filters = store.activeFilters;
    final filtering = !isUsers && !filters.isEmpty;

    final Widget body;
    if (isUsers) {
      // People search shows suggestions until you type. Both are one server-side
      // query, paged as the list is scrolled.
      if (store.userSearchStale) {
        // Nothing loaded for this account yet (first visit, or the account
        // changed under an open tab): load once this frame is done.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final search = context.read<SearchStore>();
          if (mounted && search.userSearchStale) {
            unawaited(search.findUsers(_query));
          }
        });
      }
      final users = store.userResults;
      body = _ResultsPane(
        label: store.userLoading
            ? 'Searching…'
            : hasQuery
                ? _countLabel(users.length, store.userHasMore)
                : 'Suggested people',
        count: users.length,
        empty: store.userLoading || store.userSearchStale
            ? const Center(child: CircularProgressIndicator())
            : EmptyState(
                icon: Icons.person_search_rounded,
                title: 'No users found',
                message: 'Try a different name or @handle.',
              ),
        itemBuilder: (_, i) => _UserTile(user: users[i]),
        hasMore: store.userHasMore,
        loadingMore: store.userLoadingMore,
        loadMoreFailed: store.userLoadMoreFailed,
        onLoadMore: store.loadMoreUsers,
      );
    } else if (hasQuery || (filtering && !_searchFocus.hasFocus)) {
      // State A: active search, or (box empty) the games matching the filters.
      // A result already in the library shows its library state (status pill).
      final library = context.watch<LibraryStore>();
      final games = [for (final g in store.searchResults) library.maybeGame(g.id) ?? g];
      final loading = store.searchLoading;
      body = _ResultsPane(
        label: loading && games.isEmpty
            ? 'Searching…'
            : _countLabel(games.length, store.searchHasMore),
        count: games.length,
        refreshing: loading && games.isNotEmpty,
        empty: loading
            ? const Center(child: CircularProgressIndicator())
            : !context.watch<AuthStore>().isLoggedIn
            // The Edge Function answers signed-in users only.
            ? EmptyState(
                icon: Icons.lock_outline_rounded,
                title: 'Log in to search games',
                message: 'Games come from IGDB, which Checkpoint only reaches for signed-in users.',
                actionLabel: 'Log in',
                onAction: context.read<AuthStore>().logIn,
              )
            : !filtering
            ? EmptyState(
                icon: Icons.search_off_rounded,
                title: 'No games found',
                message: 'Try a different title, studio or genre.',
              )
            : EmptyState(
                icon: Icons.filter_list_off_rounded,
                title: hasQuery ? 'No games found' : 'No games match these filters',
                message: hasQuery
                    ? 'Try a different title, or fewer filters.'
                    : 'Try fewer filters, or a wider range of years.',
                actionLabel: filters.count > 1 ? 'Clear filters' : 'Clear filter',
                onAction: () => _applyFilters(filters.cleared()),
              ),
        itemBuilder: (_, i) => _SearchTile(game: games[i]),
        hasMore: store.searchHasMore,
        loadingMore: store.searchLoadingMore,
        loadMoreFailed: store.searchLoadMoreFailed,
        onLoadMore: store.loadMoreSearchResults,
      );
    } else if (_searchFocus.hasFocus) {
      // State B: empty box, field focused.
      body = _buildRecentSearches(store.recentSearches);
    } else {
      // State C: empty box, field not focused.
      body = _buildBrowseBy();
    }

    return SafeArea(
      bottom: false,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Text('Discover', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(20, 0, isUsers ? 20 : 8, 0),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _searchFocus,
                textInputAction: TextInputAction.search,
                onChanged: _onQueryChanged,
                onSubmitted: _submitSearch,
                onTapOutside: (_) => _searchFocus.unfocus(),
                decoration: fieldDecoration(
                  'Search',
                  hint: isUsers ? 'Names or @handles…' : 'Games, studios, platforms…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: _clearQuery,
                        ),
                ).copyWith(labelText: null),
              ),
            ),
            // Members have nothing to filter by.
            if (!isUsers) ...[
              const SizedBox(width: 2),
              FilterButton(count: filters.count, onPressed: _openFilters),
            ],
          ]),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<SearchKind>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: SearchKind.games, icon: Icon(Icons.sports_esports_rounded), label: Text('Games')),
                ButtonSegment(value: SearchKind.users, icon: Icon(Icons.people_alt_rounded), label: Text('Users')),
              ],
              selected: {_kind},
              onSelectionChanged: (s) {
                setState(() => _kind = s.first);
                _debounce?.cancel();
                final search = context.read<SearchStore>();
                final term = _query.trim();
                // Members are fetched on demand, so (re)load them for whatever is
                // typed in the box. The games were last searched for whatever was
                // typed before switching to Users: catch up with the box.
                if (_kind == SearchKind.users) {
                  unawaited(search.findUsers(_query));
                } else if (term.isNotEmpty && term != search.searchTerm) {
                  unawaited(search.searchExternalGames(term, remember: false));
                }
              },
              style: SegmentedButton.styleFrom(
                backgroundColor: Palette.surfaceHigh,
                foregroundColor: Colors.white70,
                selectedBackgroundColor: Palette.accent,
                selectedForegroundColor: Palette.onAccent,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
              ),
            ),
          ),
        ),
        if (filtering)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: ActiveFilterChips(
              filters: filters,
              onChanged: _applyFilters,
              labelOf: CatalogTags.labelOf,
              padding: const EdgeInsets.symmetric(horizontal: 20),
            ),
          ),
        Expanded(child: body),
      ]),
    );
  }

  Widget _buildRecentSearches(List<String> recents) {
    // TextFieldTapRegion: taps in this pane must not count as "outside" the
    // search field. Otherwise the field would lose focus on pointer-down and
    // this list would be swapped for Browse By before the tap registered.
    return TextFieldTapRegion(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const _SectionLabel('Recent searches'),
        Expanded(
          child: recents.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  child: Text('No recent searches yet.', style: TextStyle(color: Palette.muted)),
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 32),
                  itemCount: recents.length,
                  separatorBuilder: (_, _) => const _RowDivider(),
                  itemBuilder: (_, i) => ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                    leading: const Icon(Icons.history_rounded, color: Palette.muted),
                    title: Text(recents[i], maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => _runRecentSearch(recents[i]),
                  ),
                ),
        ),
      ]),
    );
  }

  Widget _buildBrowseBy() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('Browse by'),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.only(bottom: 32),
            itemCount: BrowseMode.values.length,
            separatorBuilder: (_, _) => const _RowDivider(),
            itemBuilder: (_, i) {
              final mode = BrowseMode.values[i];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                title: Text(
                  mode.label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  color: Palette.muted,
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => BrowseResultsScreen(mode: mode),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Small, uppercase, letter-spaced label above a list ("RECENT SEARCHES", "12 RESULTS").
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(color: Palette.muted, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.0),
        ),
      );
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) => const Divider(height: 1, indent: 20, endIndent: 20, color: Colors.white10);
}

/// "12 results", or "20+ results" while more can still be loaded.
String _countLabel(int count, bool hasMore) =>
    hasMore ? '$count+ results' : '$count result${count == 1 ? '' : 's'}';

/// A label plus a scrolling list of results (or [empty] when there are none).
///
/// While [hasMore] the list ends in a footer that asks for the next page as soon
/// as it is built, which happens when the user scrolls close to the end (or the
/// list is too short to fill the screen). A failed page stops that and shows a
/// retry button instead.
class _ResultsPane extends StatelessWidget {
  const _ResultsPane({
    required this.label,
    required this.count,
    required this.empty,
    required this.itemBuilder,
    this.hasMore = false,
    this.loadingMore = false,
    this.loadMoreFailed = false,
    this.onLoadMore,
    this.refreshing = false,
  });
  final String label;
  final int count;
  final Widget empty;

  /// The list on screen is being replaced (the filters changed): a thin bar runs
  /// under the label until it is.
  final bool refreshing;
  final IndexedWidgetBuilder itemBuilder;
  final bool hasMore;
  final bool loadingMore;
  final bool loadMoreFailed;
  final VoidCallback? onLoadMore;

  @override
  Widget build(BuildContext context) {
    final showFooter = hasMore || loadingMore || loadMoreFailed;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _SectionLabel(label),
      SizedBox(
        height: 2,
        child: refreshing ? const LinearProgressIndicator(minHeight: 2) : null,
      ),
      Expanded(
        child: count == 0
            ? empty
            : ListView.builder(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 32),
                itemCount: count + (showFooter ? 1 : 0),
                itemBuilder: (context, i) {
                  if (i < count) return itemBuilder(context, i);
                  return LoadMoreFooter(
                    loading: loadingMore,
                    failed: loadMoreFailed,
                    onLoadMore: onLoadMore,
                  );
                },
              ),
      ),
    ]);
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({required this.user});
  final SocialUser user;

  @override
  Widget build(BuildContext context) {
    final following = context.watch<ProfileStore>().isFollowing(user.id);
    final games = user.gamesLogged;
    final followers = user.followersFor(viewerFollows: following);
    return MemberTile(
      user: user,
      subtitle: '${fmtCount(games)} ${games == 1 ? 'game' : 'games'} · '
          '${fmtCount(followers)} ${followers == 1 ? 'follower' : 'followers'}',
    );
  }
}

class _SearchTile extends StatelessWidget {
  const _SearchTile({required this.game});
  final Game game;

  @override
  Widget build(BuildContext context) {
    // The search found what was looked for: offer it again under Recent searches.
    void rememberSearch() {
      final search = context.read<SearchStore>();
      unawaited(search.addRecentSearch(search.searchTerm));
    }

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        rememberSearch();
        openGame(context, game.id);
      },
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(children: [
          SizedBox(width: 60, child: CoverArt(game: game, radius: 10)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(game.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(game.hasReleaseYear ? '${game.publisher} · ${game.releaseYear}' : game.publisher, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Palette.muted, fontSize: 12.5)),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 4, children: [
                for (final p in game.platforms.take(4)) Icon(p.icon, size: 16, color: p.color),
                if (game.platforms.length > 4)
                  Text('+${game.platforms.length - 4}', style: const TextStyle(fontSize: 11, color: Palette.muted)),
              ]),
            ]),
          ),
          const SizedBox(width: 8),
          if (!context.watch<AuthStore>().isLoggedIn)
            const SizedBox.shrink()
          else if (game.status != null)
            StatusPill(game.status!)
          else
            PopupMenuButton<GameStatus>(
              tooltip: 'Add to library',
              icon: const Icon(Icons.add_circle_outline_rounded, color: Palette.accent, size: 28),
              onSelected: (s) {
                rememberSearch();
                context.read<LibraryStore>().addToLibrary(game.id, s);
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(SnackBar(content: Text('${game.title} added to ${s.label}')));
              },
              itemBuilder: (_) => [
                for (final s in const [GameStatus.playing, GameStatus.toPlay, GameStatus.wishlist, GameStatus.completed])
                  PopupMenuItem(
                    value: s,
                    child: Row(children: [Icon(s.icon, color: s.color, size: 20), const SizedBox(width: 10), Text(s.label)]),
                  ),
              ],
            ),
        ]),
      ),
    );
  }
}