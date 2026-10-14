import 'dart:async';
import 'package:flutter/material.dart';

import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/social_user.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/utils/formatters.dart';
import 'package:checkpoint/utils/navigation.dart';
import 'package:checkpoint/widgets/cover_art.dart';
import 'package:checkpoint/widgets/empty_state.dart';
import 'package:checkpoint/widgets/profile_avatar.dart';
import 'package:checkpoint/widgets/status_pill.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

enum SearchKind { games, users }

class _SearchScreenState extends State<SearchScreen> {
  // Placeholders until the browse screens exist.
  static const _browseItems = ['Most popular', 'Highest rated', 'New releases'];

  final _controller = TextEditingController();
  final _searchFocus = FocusNode();
  String _query = '';
  SearchKind _kind = SearchKind.games;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    // Focus decides between the Recent Searches and Browse By states.
    _searchFocus.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _searchFocus.removeListener(_onFocusChanged);
    _searchFocus.dispose();
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  void _onQueryChanged(String v) {
    final store = context.store;
    setState(() => _query = v);
    // Emptied the box: drop the previous results so they can't flash back.
    if (v.trim().isEmpty) store.clearSearch();
    if (_kind == SearchKind.games) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 600), () {
        if (v.trim().isNotEmpty) store.searchExternalGames(v);
      });
    }
  }

  /// Keyboard "search" key: don't wait for the debounce.
  void _submitSearch(String v) {
    if (_kind != SearchKind.games || v.trim().isEmpty) return;
    _debounce?.cancel();
    context.store.searchExternalGames(v);
  }

  /// Clears the box and puts the cursor back in it, which brings up Recent Searches.
  void _clearQuery() {
    _debounce?.cancel();
    _controller.clear();
    setState(() => _query = '');
    context.store.clearSearch();
    _searchFocus.requestFocus();
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
    context.store.searchExternalGames(query);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final isUsers = _kind == SearchKind.users;
    final hasQuery = _query.trim().isNotEmpty;

    final Widget body;
    if (isUsers) {
      // People search keeps its original behavior: suggestions until you type.
      final users = store.searchUsers(_query);
      body = _ResultsPane(
        label: hasQuery ? '${users.length} result${users.length == 1 ? '' : 's'}' : 'Suggested people',
        count: users.length,
        empty: EmptyState(
          icon: Icons.person_search_rounded,
          title: 'No users found',
          message: 'Try a different name or @handle.',
        ),
        itemBuilder: (_, i) => _UserTile(user: users[i]),
      );
    } else if (hasQuery) {
      // State A: active search.
      final games = [for (final g in store.searchResults) store.maybeGame(g.id) ?? g];
      body = _ResultsPane(
        label: '${games.length} result${games.length == 1 ? '' : 's'}',
        count: games.length,
        empty: EmptyState(
          icon: Icons.search_off_rounded,
          title: 'No games found',
          message: 'Try a different title, studio or genre.',
        ),
        itemBuilder: (_, i) => _SearchTile(game: games[i]),
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
          padding: const EdgeInsets.symmetric(horizontal: 20),
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
              onSelectionChanged: (s) => setState(() => _kind = s.first),
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
                  separatorBuilder: (_, __) => const _RowDivider(),
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
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _SectionLabel('Browse by'),
      Expanded(
        child: ListView.separated(
          padding: const EdgeInsets.only(bottom: 32),
          itemCount: _browseItems.length,
          separatorBuilder: (_, __) => const _RowDivider(),
          itemBuilder: (_, i) => ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            title: Text(_browseItems[i], style: const TextStyle(fontWeight: FontWeight.w600)),
            trailing: const Icon(Icons.chevron_right_rounded, color: Palette.muted),
            onTap: () => ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text('${_browseItems[i]} is coming soon'))),
          ),
        ),
      ),
    ]);
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

/// A label plus a scrolling list of results (or [empty] when there are none).
class _ResultsPane extends StatelessWidget {
  const _ResultsPane({required this.label, required this.count, required this.empty, required this.itemBuilder});
  final String label;
  final int count;
  final Widget empty;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _SectionLabel(label),
      Expanded(
        child: count == 0
            ? empty
            : ListView.builder(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 32),
                itemCount: count,
                itemBuilder: itemBuilder,
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
    final store = context.store;
    final following = store.isFollowing(user.id);

    void toggle() {
      if (!store.isLoggedIn) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Log in to follow people')));
        return;
      }
      context.actions.toggleFollow(user.id);
    }

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(children: [
        ProfileAvatar(name: user.name, size: 52),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(user.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            Text(user.handle, style: const TextStyle(color: Palette.accent, fontSize: 12.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text('${user.gamesLogged} games · ${fmtCount(user.followers)} followers', style: const TextStyle(color: Palette.muted, fontSize: 12)),
          ]),
        ),
        const SizedBox(width: 8),
        following
            ? OutlinedButton(
                style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                onPressed: toggle,
                child: const Text('Following'),
              )
            : FilledButton(
                style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                onPressed: toggle,
                child: const Text('Follow'),
              ),
      ]),
    );
  }
}

class _SearchTile extends StatelessWidget {
  const _SearchTile({required this.game});
  final Game game;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => openGame(context, game.id),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(children: [
          SizedBox(width: 60, child: CoverArt(game: game, radius: 10)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(game.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text('${game.publisher} · ${game.releaseYear}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Palette.muted, fontSize: 12.5)),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 4, children: [
                for (final p in game.platforms.take(4)) Icon(p.icon, size: 16, color: p.color),
                if (game.platforms.length > 4)
                  Text('+${game.platforms.length - 4}', style: const TextStyle(fontSize: 11, color: Palette.muted)),
              ]),
            ]),
          ),
          const SizedBox(width: 8),
          if (!context.store.isLoggedIn)
            const SizedBox.shrink()
          else if (game.status != null)
            StatusPill(game.status!)
          else
            PopupMenuButton<GameStatus>(
              tooltip: 'Add to library',
              icon: const Icon(Icons.add_circle_outline_rounded, color: Palette.accent, size: 28),
              onSelected: (s) {
                context.actions.addToLibrary(game.id, s);
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