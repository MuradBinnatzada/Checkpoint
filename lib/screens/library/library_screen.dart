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
import 'package:checkpoint/utils/navigation.dart';
import 'package:checkpoint/widgets/cover_art.dart';
import 'package:checkpoint/widgets/empty_state.dart';
import 'package:checkpoint/widgets/star_rating.dart';

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
    Tab statusTab(String label, int count) => Tab(
      height: 38,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label),
            const SizedBox(width: 6),
            Text(
              '$count',
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
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
                _PlatformFilterButton(selected: view.platformFilter),
                _SortButton(
                  field: view.sortField,
                  descending: view.sortDescending,
                ),
                const SizedBox(width: 4),
                _ViewToggle(view: view.view),
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
          TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            dividerColor: Colors.transparent,
            indicatorSize: TabBarIndicatorSize.tab,
            indicatorPadding: const EdgeInsets.symmetric(vertical: 2),
            splashBorderRadius: BorderRadius.circular(20),
            labelPadding: const EdgeInsets.symmetric(horizontal: 3),
            labelColor: Palette.accent,
            unselectedLabelColor: Palette.muted,
            labelStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
            ),
            unselectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13.5,
            ),
            indicator: BoxDecoration(
              color: Palette.accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Palette.accent.withValues(alpha: 0.5)),
            ),
            tabs: [
              // "All" is injected at index 0, ahead of the per-status tabs.
              statusTab('All', view.count(library.libraryGames, null)),
              for (final s in GameStatus.values)
                statusTab(s.label, view.count(library.libraryGames, s)),
            ],
          ),
          const SizedBox(height: 8),
          _LibrarySearchField(
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

/// Dark rounded search field shown between the tab bar and the game grid/list.
class _LibrarySearchField extends StatelessWidget {
  const _LibrarySearchField({
    required this.controller,
    required this.tabLabel,
    required this.hasText,
    required this.onChanged,
    required this.onClear,
  });
  final TextEditingController controller;
  final String tabLabel;
  final bool hasText;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide.none,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        cursorColor: Palette.accent,
        style: const TextStyle(fontSize: 15),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: Palette.surfaceHigh,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          hintText: 'Search in $tabLabel',
          hintStyle: const TextStyle(color: Palette.muted),
          prefixIcon: const Icon(Icons.search_rounded, color: Palette.muted),
          suffixIcon: hasText
              ? IconButton(
                  tooltip: 'Clear search',
                  icon: const Icon(Icons.close_rounded, color: Palette.muted),
                  onPressed: onClear,
                )
              : null,
          border: border,
          enabledBorder: border,
          focusedBorder: border.copyWith(
            borderSide: BorderSide(
              color: Palette.accent.withValues(alpha: 0.6),
            ),
          ),
        ),
      ),
    );
  }
}

class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.view});
  final LibraryView view;

  @override
  Widget build(BuildContext context) {
    Widget cell(LibraryView v, IconData icon, String tooltip) {
      final active = v == view;
      return Tooltip(
        message: tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => context.read<LibraryViewStore>().setView(v),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 38,
            height: 34,
            decoration: BoxDecoration(
              color: active
                  ? Palette.accent.withValues(alpha: 0.20)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 20,
              color: active ? Palette.accent : Palette.muted,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Palette.surfaceHigh,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          cell(LibraryView.grid, Icons.grid_view_rounded, 'Poster grid'),
          cell(LibraryView.list, Icons.view_list_rounded, 'List'),
        ],
      ),
    );
  }
}

class _SortButton extends StatelessWidget {
  const _SortButton({required this.field, required this.descending});
  final SortField field;
  final bool descending;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<SortField>(
      tooltip: 'Sort',
      icon: const Icon(Icons.sort_rounded),
      onSelected: context.read<LibraryViewStore>().setSort,
      itemBuilder: (_) => [
        for (final f in SortField.values)
          PopupMenuItem(
            value: f,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    f.label,
                    style: TextStyle(
                      fontWeight: f == field
                          ? FontWeight.w800
                          : FontWeight.w500,
                      color: f == field ? Palette.accent : null,
                    ),
                  ),
                ),
                if (f == field)
                  Icon(
                    descending
                        ? Icons.arrow_downward_rounded
                        : Icons.arrow_upward_rounded,
                    size: 16,
                    color: Palette.accent,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _PlatformFilterButton extends StatelessWidget {
  const _PlatformFilterButton({required this.selected});
  final GamePlatform? selected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<Object>(
      tooltip: 'Filter by platform',
      icon: Icon(
        Icons.filter_list_rounded,
        color: selected != null ? Palette.accent : null,
      ),
      onSelected: (v) =>
          context.read<LibraryViewStore>().setPlatformFilter(
            v is GamePlatform ? v : null,
          ),
      itemBuilder: (_) => [
        PopupMenuItem<Object>(
          value: 'all',
          child: Text(
            'All platforms',
            style: TextStyle(
              fontWeight: selected == null ? FontWeight.w800 : FontWeight.w500,
              color: selected == null ? Palette.accent : null,
            ),
          ),
        ),
        for (final p in GamePlatform.values)
          PopupMenuItem<Object>(
            value: p,
            child: Row(
              children: [
                Icon(p.icon, size: 18, color: p.color),
                const SizedBox(width: 10),
                Text(
                  p.label,
                  style: TextStyle(
                    fontWeight: selected == p
                        ? FontWeight.w800
                        : FontWeight.w500,
                    color: selected == p ? Palette.accent : null,
                  ),
                ),
              ],
            ),
          ),
      ],
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
          ? _PosterGrid(key: ValueKey('grid-${s?.name ?? 'all'}'), games: games)
          : _GameList(key: ValueKey('list-${s?.name ?? 'all'}'), games: games),
    );
  }
}

class _PosterGrid extends StatelessWidget {
  const _PosterGrid({super.key, required this.games});
  final List<Game> games;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 900 ? 6 : (c.maxWidth >= 600 ? 5 : 3);
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 2 / 3,
          ),
          itemCount: games.length,
          itemBuilder: (_, i) => _PosterTile(game: games[i]),
        );
      },
    );
  }
}

class _PosterTile extends StatelessWidget {
  const _PosterTile({required this.game});
  final Game game;

  Widget _badge(Widget child) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.62),
      borderRadius: BorderRadius.circular(8),
    ),
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: CoverArt(game: game)),
        if (game.rating > 0)
          Positioned(
            left: 6,
            top: 6,
            child: _badge(
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.star_rounded, size: 12, color: Palette.star),
                  const SizedBox(width: 2),
                  Text(
                    fmtHours(game.rating),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (game.hoursPlayed > 0)
          Positioned(
            right: 6,
            top: 6,
            child: _badge(
              Text(
                '${fmtHours(game.hoursPlayed)}h',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        Positioned.fill(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => openGame(context, game.id),
            ),
          ),
        ),
      ],
    );
  }
}

class _GameList extends StatelessWidget {
  const _GameList({super.key, required this.games});
  final List<Game> games;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 32),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: games.length,
      separatorBuilder: (context, index) => Divider(
        height: 1,
        indent: 82,
        color: Colors.white.withValues(alpha: 0.06),
      ),
      itemBuilder: (_, i) => _LibraryListTile(game: games[i]),
    );
  }
}

class _LibraryListTile extends StatelessWidget {
  const _LibraryListTile({required this.game});
  final Game game;

  @override
  Widget build(BuildContext context) {
    final platform =
        game.playedOn ??
        (game.platforms.isNotEmpty ? game.platforms.first : null);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => openGame(context, game.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            SizedBox(width: 60, child: CoverArt(game: game, radius: 10)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    game.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (platform != null) ...[
                        Icon(platform.icon, size: 14, color: platform.color),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            platform.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: platform.color,
                            ),
                          ),
                        ),
                        const Text(
                          '  ·  ',
                          style: TextStyle(color: Palette.muted),
                        ),
                      ],
                      Text(
                        '${game.releaseYear}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Palette.muted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      game.rating > 0
                          ? StarRating(rating: game.rating, size: 15)
                          : const Text(
                              'Not rated',
                              style: TextStyle(
                                fontSize: 12,
                                color: Palette.muted,
                              ),
                            ),
                      const Spacer(),
                      const Icon(
                        Icons.schedule_rounded,
                        size: 14,
                        color: Palette.muted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        game.hoursPlayed > 0
                            ? '${fmtHours(game.hoursPlayed)} h'
                            : '—',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, color: Palette.muted),
          ],
        ),
      ),
    );
  }
}