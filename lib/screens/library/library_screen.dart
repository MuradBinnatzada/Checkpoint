import 'package:flutter/material.dart';

import 'package:checkpoint/app/nav_tab.dart';
import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/state/library_state.dart';
import 'package:checkpoint/state/library_store.dart';
import 'package:checkpoint/state/library_view_store.dart';
import 'package:checkpoint/state/nav_store.dart';
import 'package:checkpoint/state/profile_store.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/utils/formatters.dart';
import 'package:checkpoint/widgets/empty_state.dart';
import 'package:checkpoint/widgets/library_controls.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

/// Owns the status-tab `TabController` and keeps it in lock-step with
/// `LibraryViewStore.currentTabIndex` in both directions (tab 0 is "All", then
/// one tab per `GameStatus`; `selectedStatus == null` means All):
///   user taps/swipes a tab  → controller listener → viewStore.setTabIndex
///   viewStore.openTab()     → store listener      → controller.index = …
/// Both sides compare before writing, so the two listeners can never loop.
class _LibraryScreenState extends State<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late final LibraryViewStore _viewStore;
  late final TabController _tabs;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _viewStore = context.read<LibraryViewStore>(); // non-subscribing lookup is allowed in initState
    _tabs = TabController(
      length: GameStatus.values.length + 1, // +1 for the leading "All" tab
      vsync: this,
      initialIndex: _viewStore.currentTabIndex,
    )..addListener(_onTabsChanged);
    _viewStore.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    _viewStore.removeListener(_onStoreChanged);
    _tabs
      ..removeListener(_onTabsChanged)
      ..dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onTabsChanged() {
    final i = _tabs.index;
    if (i != _viewStore.currentTabIndex) _viewStore.setTabIndex(i);
  }

  void _onStoreChanged() {
    final i = _viewStore.currentTabIndex;
    if (i != _tabs.index) _tabs.index = i;
  }

  void _onSearchChanged(String value) => setState(() => _searchQuery = value);

  void _clearSearch() {
    _searchController.clear();
    setState(() => _searchQuery = '');
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryStore>();
    final view = context.watch<LibraryViewStore>();
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'My Library',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                  ),
                ),
                LibraryPlatformFilterButton(
                  selected: view.platformFilter,
                  options: view.filterOptions(library.libraryGames),
                ),
                LibrarySortButton(
                  field: view.sortField,
                  descending: view.sortDescending,
                ),
                const SizedBox(width: 4),
                LibraryViewToggle(view: view.view),
                const SizedBox(width: 8),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 10),
            child: Text(
              'Sorted by ${view.sortField.label} · ${view.sortDescending ? 'high to low' : 'low to high'}'
              '${view.platformFilter != null ? ' · ${view.platformFilter!.label}' : ''}',
              style: const TextStyle(color: Palette.muted, fontSize: 12.5),
            ),
          ),
          const _SyncBanner(),
          LibraryStatusTabBar(
            controller: _tabs,
            // "All" is injected at index 0, ahead of the per-status tabs.
            counts: [
              view.count(library.libraryGames, null),
              for (final s in GameStatus.values)
                view.count(library.libraryGames, s),
            ],
          ),
          const SizedBox(height: 8),
          LibrarySearchField(
            controller: _searchController,
            tabLabel: view.selectedStatus?.label ?? 'All',
            hasText: _searchQuery.isNotEmpty,
            onChanged: _onSearchChanged,
            onClear: _clearSearch,
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                LibraryCollection(
                  status: null, // "All"
                  searchQuery: _searchQuery,
                  onClearSearch: _clearSearch,
                ),
                for (final s in GameStatus.values)
                  LibraryCollection(
                    status: s,
                    searchQuery: _searchQuery,
                    onClearSearch: _clearSearch,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The banner's own scope, so a follow being queued or sent rebuilds only this
/// and not the whole library.
class _SyncBanner extends StatelessWidget {
  const _SyncBanner();

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryStore>();
    final profile = context.watch<ProfileStore>();
    // Follows made while offline wait for the server too, so they count here
    // (this is the one place that says "changes will sync").
    final pending = library.pendingCount + profile.pendingCount;
    if (!library.isOffline && pending == 0) return const SizedBox.shrink();
    return _OfflineBanner(
      offline: library.isOffline,
      pendingCount: pending,
      syncedAt: library.lastSyncedAt,
      retrying: library.isRefreshing,
      onRetry: () {
        library.refresh();
        profile.refresh();
      },
    );
  }
}

/// Shown while the library on screen is the copy saved on this device because
/// the server couldn't be reached, and while edits are waiting to be sent.
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({
    required this.offline,
    required this.pendingCount,
    required this.syncedAt,
    required this.retrying,
    required this.onRetry,
  });
  final bool offline;
  final int pendingCount;
  final DateTime? syncedAt;
  final bool retrying;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final synced = syncedAt;
    final pending = pendingCount == 0
        ? ''
        : ' $pendingCount ${pendingCount == 1 ? 'change' : 'changes'} will sync when you\'re back online.';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        decoration: BoxDecoration(
          color: Palette.surfaceHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.cloud_off_rounded, size: 18, color: Palette.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                !offline
                    ? '$pendingCount ${pendingCount == 1 ? 'change is' : 'changes are'} waiting to sync…'
                    : synced == null
                    ? 'Can\'t reach Checkpoint. Showing your saved library.$pending'
                    : 'Can\'t reach Checkpoint. Showing your saved library, '
                          'updated ${timeAgo(synced)}.$pending',
                style: const TextStyle(color: Palette.muted, fontSize: 12.5),
              ),
            ),
            TextButton(
              onPressed: retrying ? null : onRetry,
              child: Text(retrying ? 'Retrying…' : 'Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class LibraryCollection extends StatelessWidget {
  const LibraryCollection({
    super.key,
    required this.status,
    this.searchQuery = '',
    this.onClearSearch,
  });
  /// Status shown by this tab; `null` shows every game ("All").
  final GameStatus? status;

  /// Free-text title filter, applied only to this tab's games.
  final String searchQuery;
  final VoidCallback? onClearSearch;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryStore>();
    final view = context.watch<LibraryViewStore>();
    if (library.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = library.loadError;
    if (error != null) {
      return EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Could not load library',
        message: error,
        actionLabel: 'Retry',
        onAction: () {
          library.refresh();
          context.read<ProfileStore>().refresh();
        },
      );
    }

    final s = status; // local copy so null checks promote
    final query = searchQuery.trim().toLowerCase();
    final games = view
        .visible(library.libraryGames, s)
        .where((g) => g.title.toLowerCase().contains(query))
        .toList();
    if (games.isEmpty) {
      final p = view.platformFilter;
      if (query.isNotEmpty) {
        return EmptyState(
          icon: Icons.search_off_rounded,
          title: 'No matches for "${searchQuery.trim()}"',
          message: p != null
              ? 'Try another title, or clear the platform filter.'
              : 'Try a different title.',
          actionLabel: 'Clear search',
          onAction: () => onClearSearch?.call(),
        );
      }
      return EmptyState(
        icon: s?.icon ?? Icons.apps_rounded,
        title: p != null
            ? (s == null
                  ? 'No games on ${p.label}'
                  : 'No ${s.label.toLowerCase()} games on ${p.label}')
            : (s == null
                  ? 'Your library is empty'
                  : 'Nothing in ${s.label} yet'),
        message: p != null
            ? 'Clear the platform filter to see everything.'
            : 'Find something new in Discover and add it here.',
        actionLabel: p != null ? 'Clear filter' : 'Discover games',
        onAction: () => p != null
            ? context.read<LibraryViewStore>().setPlatformFilter(null)
            : context.read<NavStore>().select(NavTab.search),
      );
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: view.view == LibraryView.grid
          ? LibraryPosterGrid(key: ValueKey('grid-${s?.name ?? 'all'}'), games: games)
          : LibraryGameList(key: ValueKey('list-${s?.name ?? 'all'}'), games: games),
    );
  }
}

