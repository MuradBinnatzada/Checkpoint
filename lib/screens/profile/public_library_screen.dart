import 'dart:async';

import 'package:flutter/material.dart';

import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/state/library_state.dart';
import 'package:checkpoint/state/library_view_store.dart';
import 'package:checkpoint/state/load_status.dart';
import 'package:checkpoint/state/public_library_store.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/app_theme.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/widgets/empty_state.dart';
import 'package:checkpoint/widgets/library_controls.dart';

/// Another member's library, laid out like your own Library tab: a tab per status
/// with how many games it holds, a search box, a platform filter, sorting and a
/// grid or list. The games show the owner's own ratings and hours. Opening one
/// shows it as the catalog knows it, with none of their state.
///
/// [initialStatus] and [sortBy] are what the profile row that was tapped asked for
/// (the Wishlist row opens on the Wishlist tab; "Top rated" sorts by rating).
class PublicLibraryScreen extends StatefulWidget {
  const PublicLibraryScreen({
    super.key,
    required this.userId,
    this.ownerName,
    this.initialStatus,
    this.sortBy,
  });

  final String userId;
  final String? ownerName;
  final GameStatus? initialStatus;
  final SortField? sortBy;

  @override
  State<PublicLibraryScreen> createState() => _PublicLibraryScreenState();
}

class _PublicLibraryScreenState extends State<PublicLibraryScreen>
    with SingleTickerProviderStateMixin {
  // This screen's own view state (tab, sort, filter, grid or list), kept apart from
  // the one the Library tab uses: the two libraries are arranged independently.
  final LibraryViewStore _viewStore = LibraryViewStore();
  late final TabController _tabs;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    final status = widget.initialStatus;
    if (status != null) {
      _viewStore.setTabIndex(GameStatus.values.indexOf(status) + 1);
    }
    final sortBy = widget.sortBy;
    if (sortBy != null) _viewStore.setSort(sortBy);

    _tabs = TabController(
      length: GameStatus.values.length + 1, // +1 for the leading "All" tab
      vsync: this,
      initialIndex: _viewStore.currentTabIndex,
    )..addListener(_onTabsChanged);
    _viewStore.addListener(_onViewChanged);
    // After the first frame: loading notifies, which isn't allowed during build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_load());
    });
  }

  @override
  void dispose() {
    _viewStore
      ..removeListener(_onViewChanged)
      ..dispose();
    _tabs
      ..removeListener(_onTabsChanged)
      ..dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onTabsChanged() {
    if (_tabs.index != _viewStore.currentTabIndex) {
      _viewStore.setTabIndex(_tabs.index);
    }
  }

  void _onViewChanged() {
    if (_viewStore.currentTabIndex != _tabs.index) {
      _tabs.index = _viewStore.currentTabIndex;
    }
  }

  Future<void> _load({bool force = false}) =>
      context.read<PublicLibraryStore>().load(widget.userId, force: force);

  void _clearSearch() {
    _searchController.clear();
    setState(() => _searchQuery = '');
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PublicLibraryStore>();
    final library = store.viewOf(widget.userId);
    final name = widget.ownerName;

    final Widget body;
    if (library.status == LoadStatus.failed) {
      body = EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Could not load this library',
        message: 'Check your connection and try again.',
        actionLabel: 'Try again',
        onAction: () => unawaited(_load(force: true)),
      );
    } else if (library.status != LoadStatus.ready) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = ListenableBuilder(
        listenable: _viewStore,
        builder: (context, _) => _content(library.games),
      );
    }

    // The Library widgets read the nearest LibraryViewStore: this screen's own.
    return StoreScope<LibraryViewStore>(
      store: _viewStore,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Library',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              if (name != null)
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: context.palette.muted),
                ),
            ],
          ),
          actions: [
            if (library.status == LoadStatus.ready) ...[
              ListenableBuilder(
                listenable: _viewStore,
                builder: (context, _) => LibraryPlatformFilterButton(
                  selected: _viewStore.platformFilter,
                  options: _viewStore.filterOptions(library.games),
                ),
              ),
              ListenableBuilder(
                listenable: _viewStore,
                builder: (context, _) => LibrarySortButton(
                  field: _viewStore.sortField,
                  descending: _viewStore.sortDescending,
                ),
              ),
              ListenableBuilder(
                listenable: _viewStore,
                builder: (context, _) => Padding(
                  padding: const EdgeInsets.only(left: 4, right: 12),
                  child: LibraryViewToggle(view: _viewStore.view),
                ),
              ),
            ],
          ],
        ),
        body: SafeArea(bottom: false, child: body),
      ),
    );
  }

  Widget _content(List<Game> games) {
    final view = _viewStore;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(
            'Sorted by ${view.sortField.label} · ${view.sortDescending ? 'high to low' : 'low to high'}'
            '${view.platformFilter != null ? ' · ${view.platformFilter!.label}' : ''}',
            style: TextStyle(color: context.palette.muted, fontSize: 12.5),
          ),
        ),
        LibraryStatusTabBar(
          controller: _tabs,
          counts: [
            view.count(games, null),
            for (final s in GameStatus.values) view.count(games, s),
          ],
        ),
        const SizedBox(height: 8),
        LibrarySearchField(
          controller: _searchController,
          tabLabel: view.selectedStatus?.label ?? 'All',
          hasText: _searchQuery.isNotEmpty,
          onChanged: (v) => setState(() => _searchQuery = v),
          onClear: _clearSearch,
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _Collection(
                games: games,
                status: null,
                searchQuery: _searchQuery,
                onClearSearch: _clearSearch,
              ),
              for (final s in GameStatus.values)
                _Collection(
                  games: games,
                  status: s,
                  searchQuery: _searchQuery,
                  onClearSearch: _clearSearch,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The games of one status tab, filtered by the search box and the platform
/// filter, in the chosen order and layout.
class _Collection extends StatelessWidget {
  const _Collection({
    required this.games,
    required this.status,
    required this.searchQuery,
    required this.onClearSearch,
  });

  final List<Game> games;

  /// `null` shows every game ("All").
  final GameStatus? status;
  final String searchQuery;
  final VoidCallback onClearSearch;

  @override
  Widget build(BuildContext context) {
    final view = context.watch<LibraryViewStore>();
    final s = status;
    final query = searchQuery.trim().toLowerCase();
    final shown = view
        .visible(games, s)
        .where((g) => g.title.toLowerCase().contains(query))
        .toList();

    if (shown.isEmpty) {
      final p = view.platformFilter;
      if (query.isNotEmpty) {
        return EmptyState(
          icon: Icons.search_off_rounded,
          title: 'No matches for "${searchQuery.trim()}"',
          message: p != null
              ? 'Try another title, or clear the platform filter.'
              : 'Try a different title.',
          actionLabel: 'Clear search',
          onAction: onClearSearch,
        );
      }
      return EmptyState(
        icon: s?.icon ?? Icons.apps_rounded,
        title: p != null
            ? (s == null
                  ? 'No games on ${p.label}'
                  : 'No ${s.label.toLowerCase()} games on ${p.label}')
            : (s == null ? 'Nothing here yet' : 'Nothing in ${s.label} yet'),
        message: p != null
            ? 'Clear the platform filter to see everything.'
            : 'Games they add show up here.',
        actionLabel: p != null ? 'Clear filter' : null,
        onAction: p != null
            ? () => context.read<LibraryViewStore>().setPlatformFilter(null)
            : null,
      );
    }
    return AnimatedSwitcher(
      duration: motion(context, const Duration(milliseconds: 220)),
      child: view.view == LibraryView.grid
          ? LibraryPosterGrid(
              key: ValueKey('grid-${s?.name ?? 'all'}'),
              games: shown,
            )
          : LibraryGameList(
              key: ValueKey('list-${s?.name ?? 'all'}'),
              games: shown,
            ),
    );
  }
}
